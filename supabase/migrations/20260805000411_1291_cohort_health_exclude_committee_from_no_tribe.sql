-- #1291 refinamento (feedback owner 2026-07-11): curador / membro de comite NAO e "sem tribo em risco".
-- Sarah e Roberto sao curadores (engagement committee_coordinator no Comite de Curadoria). Para um
-- curador/membro de comite, NAO ter tribo de pesquisa e o estado normal — nao um risco. O sinal SSOT
-- hoje e um engagement ATIVO numa iniciativa kind='committee' (Comite de Curadoria / Governanca).
-- Fix: placed := has_tribe OR is_committee; no_tribe risk so dispara para quem nao tem NENHUM dos dois.
-- (VEP formalizara essas posicoes; ate la o engagement de comite e a fonte de verdade.)
CREATE OR REPLACE FUNCTION public.get_gp_cohort_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_is_service boolean;
  v_cycle record;
  v_kickoff uuid;
  v_result jsonb;
BEGIN
  v_is_service := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  ) = 'service_role';
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT coalesce(v_is_service, false)
     AND (v_caller IS NULL
          OR NOT (public.can_by_member(v_caller, 'manage_member')
                  OR public.can_by_member(v_caller, 'view_internal_analytics'))) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member or view_internal_analytics');
  END IF;

  SELECT cycle_code, cycle_label, cycle_start INTO v_cycle
  FROM public.cycles WHERE is_current = true ORDER BY cycle_start DESC LIMIT 1;

  -- kickoff da coorte corrente: derivado (NAO hardcoded) — type='kickoff' OU titulo ILIKE '%kick%',
  -- primeiro evento nao-cancelado dentro da janela do ciclo. Em C4 o kickoff foi registrado como
  -- type='geral' com "Kick-off" no titulo, dai o OR por titulo.
  SELECT id INTO v_kickoff
  FROM public.events
  WHERE (type = 'kickoff' OR title ILIKE '%kick%')
    AND date >= v_cycle.cycle_start
    AND status IS DISTINCT FROM 'cancelled'
  ORDER BY date ASC LIMIT 1;

  WITH cohort AS (
    SELECT m.id, m.name, m.chapter,
      EXISTS (SELECT 1 FROM public.v_initiative_roster r
              JOIN public.initiatives i2 ON i2.id = r.initiative_id
              WHERE r.member_id = m.id AND i2.kind = 'research_tribe') AS has_tribe,
      -- #1291: curador / membro de comite (engagement ativo em iniciativa kind='committee') —
      -- tribelessness legitima, nao conta como "sem tribo em risco".
      EXISTS (SELECT 1 FROM public.engagements e
              JOIN public.initiatives ic ON ic.id = e.initiative_id
              WHERE e.person_id = m.person_id AND e.status = 'active' AND ic.kind = 'committee') AS is_committee,
      EXISTS (SELECT 1 FROM public.attendance a
              WHERE a.member_id = m.id AND a.event_id = v_kickoff AND a.present = true) AS at_kickoff,
      EXISTS (SELECT 1 FROM public.gamification_points gp
              WHERE gp.member_id = m.id AND gp.created_at >= v_cycle.cycle_start) AS has_activity
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.operational_role IN ('researcher', 'tribe_leader')
  ),
  cohort_p AS (
    SELECT c.*, (c.has_tribe OR c.is_committee) AS placed FROM cohort c
  )
  SELECT jsonb_build_object(
    'cycle', jsonb_build_object('code', v_cycle.cycle_code, 'label', v_cycle.cycle_label),
    'kickoff_event_id', v_kickoff,
    'cohort_summary', jsonb_build_object(
      'total',            (SELECT count(*) FROM cohort_p),
      'with_tribe',       (SELECT count(*) FROM cohort_p WHERE has_tribe),
      'committee_members',(SELECT count(*) FROM cohort_p WHERE is_committee),
      'without_tribe',    (SELECT count(*) FROM cohort_p WHERE NOT placed),
      'at_kickoff',       (SELECT count(*) FROM cohort_p WHERE at_kickoff),
      'no_kickoff',       (SELECT count(*) FROM cohort_p WHERE NOT at_kickoff),
      'no_activity',      (SELECT count(*) FROM cohort_p WHERE NOT has_activity)
    ),
    'at_risk_members', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'member_id', c.id, 'name', c.name, 'chapter', c.chapter,
        'is_committee', c.is_committee,
        'no_tribe', NOT c.placed,
        'no_kickoff', NOT c.at_kickoff,
        'no_activity', NOT c.has_activity,
        'risk_count', (CASE WHEN NOT c.placed THEN 1 ELSE 0 END
                     + CASE WHEN NOT c.at_kickoff THEN 1 ELSE 0 END
                     + CASE WHEN NOT c.has_activity THEN 1 ELSE 0 END)
      ) ORDER BY (CASE WHEN NOT c.placed THEN 1 ELSE 0 END
                + CASE WHEN NOT c.at_kickoff THEN 1 ELSE 0 END
                + CASE WHEN NOT c.has_activity THEN 1 ELSE 0 END) DESC, c.name), '[]'::jsonb)
      FROM cohort_p c
      WHERE NOT c.placed OR NOT c.at_kickoff OR NOT c.has_activity
    ),
    'pending_leader_approvals', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'invitation_id', ii.id,
        'requester_member_id', ii.invitee_member_id,
        'requester_name', rm.name,
        'tribe', init.title,
        'legacy_tribe_id', init.legacy_tribe_id,
        'requested_at', ii.created_at,
        'expires_at', ii.expires_at,
        'days_waiting', EXTRACT(day FROM now() - ii.created_at)::int
      ) ORDER BY ii.created_at), '[]'::jsonb)
      FROM public.initiative_invitations ii
      JOIN public.initiatives init ON init.id = ii.initiative_id
      JOIN public.members rm ON rm.id = ii.invitee_member_id
      WHERE ii.status = 'pending' AND init.kind = 'research_tribe'
        AND ii.invitee_member_id = ii.inviter_member_id
        AND ii.expires_at > now()
    ),
    'generated_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$function$;
