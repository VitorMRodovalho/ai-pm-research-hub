-- #2461: contagem da iniciativa.
-- (1) Participante EXTERNO conta. Desde a #2400/#2416, kind='observer' significa vinculo externo,
--     nao-voluntario (ADR-0131), e observer x participant existe para quem vem de fora contribuir.
--     Decisao do dono (25/09/2026): dentro da iniciativa ele e participante e entra no roster.
--     Continuam FORA: role='observer' (visitante #2334, acompanhamento) e observer x curator/reviewer
--     (autoridade de revisao, nao participacao). Os dois portoes de autoridade que leem esta view
--     (_can_manage_recurring_rule, _can_sign_gate) exigem role='leader', que o ramo novo nao admite.
-- (2) Presenca: o numerador passa a contar so as pessoas do denominador. Antes, presenca de quem
--     esta fora do roster entrava no numerador e a tela mostrou 140%.
CREATE OR REPLACE VIEW public.v_initiative_roster
WITH (security_invoker = true) AS
 SELECT DISTINCT e.initiative_id,
    i.legacy_tribe_id,
    e.person_id,
    m.id AS member_id,
    m.name,
    e.role,
    e.kind,
    COALESCE(m.gamification_opt_out, false) AS gamification_opt_out
   FROM ((engagements e
     JOIN initiatives i ON ((i.id = e.initiative_id)))
     LEFT JOIN members m ON ((m.person_id = e.person_id)))
  WHERE ((e.status = 'active'::text) AND (e.role <> 'observer'::text)
    AND ((e.kind <> 'observer'::text) OR (e.role = ANY (ARRAY['participant'::text, 'coordinator'::text]))));

CREATE OR REPLACE FUNCTION public.get_initiative_stats(p_initiative_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tribe_id int;
BEGIN
  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RETURN json_build_object('error', 'Initiative not found');
  END IF;

  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_stats(v_tribe_id);
  END IF;

  RETURN (
    WITH cycle AS (SELECT cycle_start FROM cycles WHERE is_current LIMIT 1),
    init_members AS (
      SELECT DISTINCT vir.member_id AS id, vir.name
      FROM v_initiative_roster vir
      WHERE vir.initiative_id = p_initiative_id AND vir.member_id IS NOT NULL
    ),
    init_events AS (
      SELECT e.id, COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes
      FROM events e, cycle c
      WHERE e.initiative_id = p_initiative_id AND e.date >= c.cycle_start AND e.date <= current_date
    ),
    att AS (
      SELECT a.event_id, a.member_id FROM attendance a
      JOIN init_events ie ON ie.id = a.event_id
      WHERE a.present = true AND a.excused IS NOT TRUE
    ),
    -- #2461: a taxa divide por roster x eventos, entao o numerador so conta quem esta no roster.
    -- Quem esteve presente sem estar no roster continua nas horas de impacto (att), nao na taxa.
    att_roster AS (
      SELECT a.event_id, a.member_id FROM att a
      WHERE a.member_id IN (SELECT im.id FROM init_members im)
    ),
    init_boards AS (
      SELECT bi.id, bi.status FROM board_items bi
      JOIN project_boards pb ON pb.id = bi.board_id
      WHERE pb.initiative_id = p_initiative_id
    )
    SELECT json_build_object(
      'member_count', public.get_initiative_roster_count(p_initiative_id),
      'events_held', (SELECT count(*) FROM init_events),
      'attendance_rate', (SELECT round(
        count(a.*)::numeric / NULLIF((SELECT count(*) FROM init_members) * (SELECT count(*) FROM init_events), 0) * 100, 0
      ) FROM att_roster a),
      -- #1656: mesmo valor sob o nome que declara a escala (ja era 0-100).
      'attendance_pct', (SELECT round(
        count(a.*)::numeric / NULLIF((SELECT count(*) FROM init_members) * (SELECT count(*) FROM init_events), 0) * 100, 0
      ) FROM att_roster a),
      'impact_hours', (SELECT coalesce(round(sum(ie.duration_minutes * sub.c)::numeric / 60, 1), 0)
        FROM init_events ie JOIN (SELECT event_id, count(*) c FROM att GROUP BY event_id) sub ON sub.event_id = ie.id),
      'cards_backlog', (SELECT count(*) FROM init_boards WHERE status = 'backlog'),
      'cards_in_progress', (SELECT count(*) FROM init_boards WHERE status = 'in_progress'),
      'cards_review', (SELECT count(*) FROM init_boards WHERE status = 'review'),
      'cards_done', (SELECT count(*) FROM init_boards WHERE status = 'done'),
      'top_contributors', (SELECT coalesce(json_agg(row_to_json(r) ORDER BY r.att_count DESC), '[]')
        FROM (
          SELECT im.name, count(a2.event_id) as att_count,
            round(count(a2.event_id)::numeric / NULLIF((SELECT count(*) FROM init_events), 0) * 100, 0) as rate
          FROM init_members im
          LEFT JOIN att a2 ON a2.member_id = im.id
          GROUP BY im.name
        ) r
      )
    )
  );
END;
$function$;
