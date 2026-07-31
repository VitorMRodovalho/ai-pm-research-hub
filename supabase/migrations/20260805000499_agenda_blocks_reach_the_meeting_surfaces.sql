-- #1548 — a Agenda Viva e a pauta/ata eram superficies DISJUNTAS.
--
-- Medido em 2026-07-31:
--   * `get_meeting_preparation` (= `meeting_minutes action='prepare'` no MCP) lia `events.agenda_text`
--     e NUNCA `event_agenda_blocks`. Pior: `agenda_text` e NULL nas tres ultimas Reunioes Gerais, e
--     TODA Reuniao Geral tem `initiative_id` NULL — como cada bloco do resultado e escopado por
--     `AND v_event.initiative_id IS NOT NULL`, o briefing da reuniao de maior presenca da plataforma
--     voltava com quatro arrays VAZIOS. O lado que o MCP lia era o lado morto.
--   * `meeting_close` nao dizia nada sobre bloco pendente. A Reuniao Geral de 2026-07-30 teve 45
--     presencas, 7 blocos, ZERO confirmados e ZERO XP (02/07 e 18/06: 4/4, 84 e 68 XP). O ritual
--     pos-reuniao e manual e falhou em silencio.
--
-- Esta migration NAO confirma bloco nenhum: conceder XP e veredito humano sobre quem de fato
-- apresentou (mesma regra do #1534/#1537). Ela faz o pendente ficar VISIVEL em tres lugares:
-- no briefing, no fechamento e num alerta diario.
--
-- Partes:
--   1. `_agenda_block_owner_visible` — a regra LGPD PD-5 vira FONTE UNICA, e `get_geral_agenda_viva`
--      passa a chama-la. Duas copias da regra de PII e como um vazamento nasce.
--   2. `get_meeting_preparation` — ganha `agenda_blocks` + contagens.
--   3. `meeting_close` — passa a REPORTAR blocos pendentes ao lado do sinal de drift.
--   4. `detect_agenda_blocks_pending_cron` — alerta diario, sem gate de usuario, ACL apertada.

-- ── 1) A regra de visibilidade do dono, em UM lugar ────────────────────────────
-- LGPD PD-5 (#812): um bloco 'no_show' nao revela o nome do dono ao publico nem ao membro comum;
-- so ao proprio titular e a quem tem manage_event. A regra estava inline em `get_geral_agenda_viva`;
-- `get_meeting_preparation` precisa dela agora, e reimplementar seria criar a segunda copia que um
-- dia diverge. IMMUTABLE porque depende so dos argumentos.
CREATE OR REPLACE FUNCTION public._agenda_block_owner_visible(
  p_status   text,
  p_is_mine  boolean,
  p_is_admin boolean
) RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT NOT (
    p_status = 'no_show'
    AND NOT COALESCE(p_is_admin, false)
    AND NOT COALESCE(p_is_mine, false)
  );
$function$;

COMMENT ON FUNCTION public._agenda_block_owner_visible(text, boolean, boolean) IS
  '#1548 — LGPD PD-5 em um lugar so: o nome do dono de um bloco no_show so aparece para o proprio titular e para manage_event. Consumidores: get_geral_agenda_viva, get_meeting_preparation.';

REVOKE ALL ON FUNCTION public._agenda_block_owner_visible(text, boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._agenda_block_owner_visible(text, boolean, boolean) TO anon, authenticated, service_role;

-- ── 2) get_geral_agenda_viva passa a CHAMAR a regra, em vez de te-la inline ────
-- Unica mudanca no corpo: o CASE de `owner_first_name`. Corpo baseado no VIVO
-- (pg_get_functiondef), nao no arquivo de migration anterior.
CREATE OR REPLACE FUNCTION public.get_geral_agenda_viva(p_limit_events integer DEFAULT 2, p_member_id uuid DEFAULT NULL::uuid, p_window text DEFAULT 'upcoming'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller   uuid;
  v_is_admin boolean := false;
  v_limit    int := LEAST(GREATEST(COALESCE(p_limit_events, 2), 1), 6);
  v_window   text := lower(COALESCE(p_window, 'upcoming'));
  v_result   jsonb;
BEGIN
  IF v_window NOT IN ('upcoming','past_recent','both') THEN
    v_window := 'upcoming';
  END IF;

  -- p_member_id is part of the spec signature, reserved for a future admin "view as member"
  -- mode (slice 3); the caller is always resolved from auth.uid() here (no impersonation yet).
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NOT NULL THEN
    v_is_admin := public.can_by_member(v_caller, 'manage_event');
  END IF;

  WITH all_geral AS (
    SELECT e.id, e.title, e.date, e.time_start, e.timezone,
           (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo') AS start_at
    FROM public.events e
    WHERE e.type = 'geral'
      AND e.status IS DISTINCT FROM 'cancelled'
  ),
  upcoming AS (
    SELECT ag.id, ag.title, ag.date, ag.time_start, ag.timezone, ag.start_at, false AS is_past
    FROM all_geral ag
    WHERE v_window IN ('upcoming','both')
      AND ag.start_at > now()
    ORDER BY ag.start_at
    LIMIT v_limit
  ),
  past AS (
    SELECT ag.id, ag.title, ag.date, ag.time_start, ag.timezone, ag.start_at, true AS is_past
    FROM all_geral ag
    WHERE v_window IN ('past_recent','both')
      AND ag.start_at <= now()
    ORDER BY ag.start_at DESC
    LIMIT 1
  ),
  selected AS (
    SELECT * FROM past
    UNION ALL
    SELECT * FROM upcoming
  ),
  blocks AS (
    SELECT s.is_past, b.event_id, b.id, b.format_slug, b.title, b.duration_min, b.status, b.sort_order,
           b.external_guest, b.owner_member_id, b.guest_name, b.material_url,
           split_part(m.name, ' ', 1) AS owner_first_name,
           m.name AS owner_full_name
    FROM selected s
    JOIN public.event_agenda_blocks b ON b.event_id = s.id
    JOIN public.members m ON m.id = b.owner_member_id
    -- upcoming: reserved+confirmed (futuro reservável); past: confirmed+no_show (realizado/falta).
    -- #1071: past 'reserved' also visible to admins (manage_event) so they can confirm/
    -- no-show a block whose meeting already ended (protagonism never confirmed live).
    WHERE (NOT s.is_past AND b.status IN ('reserved','confirmed'))
       OR (s.is_past     AND b.status IN ('confirmed','no_show'))
       OR (s.is_past AND v_is_admin AND b.status = 'reserved')
  )
  SELECT jsonb_build_object(
    'viewer', jsonb_build_object('is_authenticated', v_caller IS NOT NULL, 'is_admin', v_is_admin),
    'window', v_window,
    'events', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', s.id, 'title', s.title, 'date', s.date, 'time_start', s.time_start,
          'timezone', s.timezone, 'start_at', s.start_at,
          'is_past', s.is_past,
          'capacity_total_min', 90,
          'capacity_used_min', COALESCE((SELECT SUM(duration_min) FROM blocks bk WHERE bk.event_id = s.id), 0),
          'capacity_remaining_min', 90 - COALESCE((SELECT SUM(duration_min) FROM blocks bk WHERE bk.event_id = s.id), 0),
          'blocks', COALESCE((
            SELECT jsonb_agg(
              jsonb_build_object(
                'id', bk.id, 'format_slug', bk.format_slug, 'title', bk.title,
                'duration_min', bk.duration_min, 'status', bk.status, 'sort_order', bk.sort_order,
                'external_guest', bk.external_guest,
                -- LGPD PD-5 (#1548): a regra vive em _agenda_block_owner_visible, nao aqui.
                'owner_first_name', CASE
                  WHEN public._agenda_block_owner_visible(
                         bk.status,
                         (v_caller IS NOT NULL AND bk.owner_member_id = v_caller),
                         v_is_admin)
                    THEN bk.owner_first_name
                  ELSE NULL
                END,
                'is_mine', (v_caller IS NOT NULL AND bk.owner_member_id = v_caller)
              )
              -- authenticated (non-admin) additionally see the material link
              || CASE WHEN v_caller IS NOT NULL
                      THEN jsonb_build_object('material_url', bk.material_url)
                      ELSE '{}'::jsonb END
              -- manage_event sees full detail (owner id + full name + guest PII + raw fields)
              || CASE WHEN v_is_admin
                      THEN jsonb_build_object(
                             'owner_member_id', bk.owner_member_id,
                             'owner_full_name', bk.owner_full_name,
                             'guest_name', bk.guest_name)
                      ELSE '{}'::jsonb END
              ORDER BY bk.sort_order, bk.duration_min DESC
            ) FROM blocks bk WHERE bk.event_id = s.id
          ), '[]'::jsonb)
        ) ORDER BY s.start_at
      ) FROM selected s
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END
$function$;

-- ── 3) get_meeting_preparation passa a enxergar a pauta REAL ───────────────────
-- Antes: so `events.agenda_text`, que e NULL nas tres ultimas Reunioes Gerais. E como todo bloco do
-- resultado e escopado por `initiative_id IS NOT NULL`, e Reuniao Geral e org-wide, o briefing dela
-- voltava vazio. Agora `agenda_blocks` traz a pauta que existe de fato, com a mesma regra de PII
-- (via _agenda_block_owner_visible) e o mesmo recorte por status do #1071.
CREATE OR REPLACE FUNCTION public.get_meeting_preparation(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_is_admin boolean := false;
  v_is_past boolean := false;
  v_event record;
  v_initiative record;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  SELECT e.id, e.title, e.date, e.type, e.duration_minutes, e.meeting_link,
         e.initiative_id, e.agenda_text, e.agenda_url, e.time_start, e.timezone
  INTO v_event FROM public.events e WHERE e.id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  IF NOT public.rls_can_see_initiative(v_event.initiative_id) THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  -- #1548: mesmo calculo de "ja aconteceu" de get_geral_agenda_viva, para os dois nao divergirem.
  v_is_admin := public.can_by_member(v_caller_id, 'manage_event');
  v_is_past := (
    (v_event.date + COALESCE(v_event.time_start,'00:00'::time))
      AT TIME ZONE COALESCE(v_event.timezone,'America/Sao_Paulo')
  ) <= now();

  -- #1383 W3: this SELECT INTO must run UNCONDITIONALLY. It used to be guarded by
  -- `IF v_event.initiative_id IS NOT NULL`, which left v_initiative UNASSIGNED for org-wide
  -- events, and the read of v_initiative.id below then raised instead of yielding NULL.
  -- With no matching row the record is assigned all-NULLs, which is what that read expects.
  SELECT i.id, i.title, i.kind, i.legacy_tribe_id
  INTO v_initiative FROM public.initiatives i WHERE i.id = v_event.initiative_id;

  v_result := jsonb_build_object(
    'event', jsonb_build_object(
      'id', v_event.id,
      'title', v_event.title,
      'date', v_event.date,
      'type', v_event.type,
      'duration_minutes', v_event.duration_minutes,
      'meeting_link', v_event.meeting_link,
      'agenda_text', v_event.agenda_text,
      'agenda_url', v_event.agenda_url,
      'is_past', v_is_past
    ),
    'initiative', CASE WHEN v_initiative.id IS NOT NULL THEN
      jsonb_build_object('id', v_initiative.id, 'title', v_initiative.title,
        'kind', v_initiative.kind, 'legacy_tribe_id', v_initiative.legacy_tribe_id)
    ELSE NULL END,
    -- #1548: a pauta de uma Reuniao Geral SAO os blocos. Recorte por status identico ao
    -- get_geral_agenda_viva (#1071): futuro = reserved+confirmed; passado = confirmed+no_show,
    -- mais reserved quando quem le tem manage_event (e quem pode confirmar).
    'agenda_blocks', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', b.id,
          'sort_order', b.sort_order,
          'format_slug', b.format_slug,
          'title', b.title,
          'duration_min', b.duration_min,
          'status', b.status,
          'external_guest', b.external_guest,
          'material_url', b.material_url,
          'owner_first_name', CASE
            WHEN public._agenda_block_owner_visible(
                   b.status, (b.owner_member_id = v_caller_id), v_is_admin)
              THEN split_part(bm.name, ' ', 1)
            ELSE NULL
          END,
          'is_mine', (b.owner_member_id = v_caller_id)
        )
        || CASE WHEN v_is_admin
                THEN jsonb_build_object(
                       'owner_member_id', b.owner_member_id,
                       'owner_full_name', bm.name,
                       'guest_name', b.guest_name)
                ELSE '{}'::jsonb END
        ORDER BY b.sort_order, b.duration_min DESC)
      FROM public.event_agenda_blocks b
      JOIN public.members bm ON bm.id = b.owner_member_id
      WHERE b.event_id = p_event_id
        AND (
             (NOT v_is_past AND b.status IN ('reserved','confirmed'))
          OR (v_is_past     AND b.status IN ('confirmed','no_show'))
          OR (v_is_past AND v_is_admin AND b.status = 'reserved')
        )
    ), '[]'::jsonb),
    -- `total` e o tamanho da pauta — informacao publica na propria pagina, sem nome de ninguem.
    'agenda_blocks_total', (
      SELECT count(*) FROM public.event_agenda_blocks b WHERE b.event_id = p_event_id
    ),
    -- `pending` NAO: um bloco 'reserved' de reuniao passada e exatamente a linha que o #1071
    -- esconde do membro comum. A contagem nao tem nome, mas denuncia o que a regra de status
    -- oculta, e so quem tem manage_event pode agir sobre ela. NULL = "nao divulgado a voce";
    -- 0 seria mentira. A chave fica sempre presente (envelope estavel).
    'agenda_blocks_pending', CASE WHEN v_is_admin THEN (
      SELECT count(*) FROM public.event_agenda_blocks b
      WHERE b.event_id = p_event_id AND b.status = 'reserved' AND v_is_past
    ) ELSE NULL END,
    'expected_attendees', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', m.id,
        'name', m.name,
        'operational_role', m.operational_role,
        'engagement_kind', ae.kind,
        'engagement_role', ae.role,
        'photo_url', m.photo_url
      ) ORDER BY m.name)
      FROM public.members m
      JOIN public.persons p ON p.legacy_member_id = m.id
      JOIN public.auth_engagements ae ON ae.person_id = p.id
      WHERE m.is_active = true
        AND ae.is_authoritative = true
        AND ae.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
    ), '[]'::jsonb),
    'pending_action_items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', mai.id,
        'event_id', mai.event_id,
        'event_title', e2.title,
        'event_date', e2.date,
        'description', mai.description,
        'kind', mai.kind,
        'assignee_name', mai.assignee_name,
        'assignee_id', mai.assignee_id,
        'due_date', mai.due_date,
        'days_open', GREATEST(0, EXTRACT(DAY FROM (now() - mai.created_at))::int)
      ) ORDER BY mai.due_date NULLS LAST, mai.created_at DESC)
      FROM public.meeting_action_items mai
      JOIN public.events e2 ON e2.id = mai.event_id
      WHERE mai.resolved_at IS NULL
        AND e2.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND e2.id <> p_event_id
        AND e2.date < v_event.date
        AND mai.created_at >= (now() - interval '90 days')
    ), '[]'::jsonb),
    'open_cards', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'curation_status', bi.curation_status,
        'assignee_id', bi.assignee_id,
        'assignee_name', am.name,
        'due_date', bi.due_date,
        'forecast_date', bi.forecast_date,
        'baseline_date', bi.baseline_date,
        'days_since_update', GREATEST(0, EXTRACT(DAY FROM (now() - bi.updated_at))::int),
        'tags', bi.tags,
        'is_at_risk', (
          (bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
            AND bi.forecast_date > bi.baseline_date + INTERVAL '7 days')
          OR (bi.updated_at < now() - interval '14 days' AND bi.status NOT IN ('done', 'archived'))
        )
      ) ORDER BY
        CASE WHEN bi.status NOT IN ('done', 'archived') THEN 0 ELSE 1 END,
        bi.due_date NULLS LAST, bi.updated_at DESC)
      FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.members am ON am.id = bi.assignee_id
      WHERE pb.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND pb.is_active = true
        AND bi.status NOT IN ('archived')
      LIMIT 50
    ), '[]'::jsonb),
    -- #1548: para evento org-wide (toda Reuniao Geral) o escopo por iniciativa devolvia vazio.
    -- Sem iniciativa, "reunioes recentes" sao as do mesmo TIPO — que e o que quem prepara quer ver.
    'recent_meetings', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', e3.id,
        'title', e3.title,
        'date', e3.date,
        'type', e3.type,
        'has_minutes', e3.minutes_text IS NOT NULL,
        'attendance_count', (SELECT COUNT(*) FROM public.attendance a WHERE a.event_id = e3.id),
        'agenda_blocks_pending', CASE WHEN v_is_admin THEN (
          SELECT COUNT(*) FROM public.event_agenda_blocks b2
          WHERE b2.event_id = e3.id AND b2.status = 'reserved'
        ) ELSE NULL END,
        'open_actions_count', (
          SELECT COUNT(*) FROM public.meeting_action_items
          WHERE event_id = e3.id AND resolved_at IS NULL
        )
      ) ORDER BY e3.date DESC)
      FROM public.events e3
      WHERE e3.id <> p_event_id
        AND e3.date < v_event.date
        AND e3.date >= (v_event.date - interval '60 days')
        AND e3.status IS DISTINCT FROM 'cancelled'
        AND CASE
              WHEN v_event.initiative_id IS NOT NULL THEN e3.initiative_id = v_event.initiative_id
              ELSE e3.initiative_id IS NULL AND e3.type = v_event.type
            END
      LIMIT 5
    ), '[]'::jsonb),
    'generated_at', now()
  );

  RETURN v_result;
END;
$function$;

-- ── 4) meeting_close passa a REPORTAR bloco pendente ──────────────────────────
-- Nunca a confirmar: conceder XP e veredito humano sobre quem de fato apresentou. O envelope ja
-- carrega `drift_signal` (ata em markdown vs itens estruturados); `blocks_pending_signal` entra ao
-- lado dele. Fechar reuniao com bloco pendente tem de ser dito em voz alta, nao descoberto um mes
-- depois pela ausencia de XP. meeting_close ja exige manage_event escopado, entao detalhe completo
-- aqui nao amplia superficie de PII.
CREATE OR REPLACE FUNCTION public.meeting_close(p_event_id uuid, p_summary text DEFAULT NULL::text, p_suggested_champion_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_org uuid;
  v_event record;
  v_already_closed boolean;
  v_action_count int;
  v_decision_count int;
  v_unresolved_count int;
  v_markdown_action_count int;
  v_structured_drift int;
  v_links_total int;
  v_showcase_count int;
  v_validated_suggestions uuid[];
  v_invalid_suggestions uuid[];
  v_blocks_total int;
  v_blocks_pending int;
  v_blocks_pending_list jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id, organization_id INTO v_caller_id, v_caller_org
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- #1383: scope manage_event to this event's initiative (was resourceless).
  IF NOT public._manage_event_scope_ok(v_caller_id, p_event_id) THEN
    RAISE EXCEPTION 'Requires manage_event permission for this event';
  END IF;

  SELECT id, title, date, minutes_text, minutes_posted_at
  INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  v_already_closed := v_event.minutes_posted_at IS NOT NULL;

  IF p_suggested_champion_ids IS NOT NULL AND cardinality(p_suggested_champion_ids) > 0 THEN
    IF cardinality(p_suggested_champion_ids) > 10 THEN
      RETURN jsonb_build_object('error', 'too_many_suggestions', 'detail', 'max 10 suggested member ids per meeting_close');
    END IF;

    SELECT array_agg(DISTINCT s ORDER BY s) INTO v_validated_suggestions
    FROM unnest(p_suggested_champion_ids) AS s
    WHERE EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.id = s AND m.organization_id = v_caller_org
    );

    SELECT array_agg(DISTINCT s) INTO v_invalid_suggestions
    FROM unnest(p_suggested_champion_ids) AS s
    WHERE NOT EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.id = s AND m.organization_id = v_caller_org
    );

    IF v_invalid_suggestions IS NOT NULL AND cardinality(v_invalid_suggestions) > 0 THEN
      RETURN jsonb_build_object(
        'error', 'invalid_suggestions',
        'detail', 'unknown or out-of-org member ids: ' || array_to_string(v_invalid_suggestions, ', ')
      );
    END IF;
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE kind = 'action'),
    COUNT(*) FILTER (WHERE kind = 'decision'),
    COUNT(*) FILTER (WHERE kind IN ('action','followup') AND resolved_at IS NULL)
  INTO v_action_count, v_decision_count, v_unresolved_count
  FROM public.meeting_action_items WHERE event_id = p_event_id;

  v_markdown_action_count := COALESCE(
    (SELECT array_length(regexp_split_to_array(v_event.minutes_text, E'(^|\\n)\\s*-\\s*\\[\\s*\\]'), 1) - 1),
    0
  );
  v_markdown_action_count := GREATEST(0, v_markdown_action_count);
  v_structured_drift := GREATEST(0, v_markdown_action_count - v_action_count);

  SELECT COUNT(*) INTO v_links_total
  FROM public.board_item_event_links WHERE event_id = p_event_id;

  SELECT COUNT(*) INTO v_showcase_count
  FROM public.event_showcases WHERE event_id = p_event_id;

  -- #1548: bloco reservado que nunca foi confirmado nem marcado no_show.
  SELECT COUNT(*), COUNT(*) FILTER (WHERE b.status = 'reserved')
  INTO v_blocks_total, v_blocks_pending
  FROM public.event_agenda_blocks b WHERE b.event_id = p_event_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', b.id,
           'sort_order', b.sort_order,
           'title', b.title,
           'format_slug', b.format_slug,
           'duration_min', b.duration_min,
           'owner_member_id', b.owner_member_id,
           'owner_name', bm.name
         ) ORDER BY b.sort_order), '[]'::jsonb)
  INTO v_blocks_pending_list
  FROM public.event_agenda_blocks b
  JOIN public.members bm ON bm.id = b.owner_member_id
  WHERE b.event_id = p_event_id AND b.status = 'reserved';

  IF NOT v_already_closed THEN
    UPDATE public.events
    SET minutes_posted_at = now(),
        minutes_posted_by = v_caller_id,
        notes = CASE
          WHEN p_summary IS NOT NULL AND length(trim(p_summary)) > 0
            THEN COALESCE(notes, '') ||
                 CASE WHEN COALESCE(notes, '') <> '' THEN E'\n\n' ELSE '' END ||
                 '## Meeting close summary (' || to_char(now(), 'YYYY-MM-DD HH24:MI') || ')' ||
                 E'\n' || trim(p_summary)
          ELSE notes
        END,
        suggested_champion_ids = COALESCE(v_validated_suggestions, suggested_champion_ids),
        updated_at = now()
    WHERE id = p_event_id;
  ELSE
    IF v_validated_suggestions IS NOT NULL THEN
      UPDATE public.events
      SET suggested_champion_ids = v_validated_suggestions,
          updated_at = now()
      WHERE id = p_event_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'event_title', v_event.title,
    'already_closed', v_already_closed,
    'closed_at', CASE WHEN v_already_closed THEN v_event.minutes_posted_at ELSE now() END,
    'action_count', v_action_count,
    'decision_count', v_decision_count,
    'unresolved_actions', v_unresolved_count,
    'markdown_action_count', v_markdown_action_count,
    'structured_drift', v_structured_drift,
    'links_total', v_links_total,
    'showcase_count', v_showcase_count,
    'drift_signal', v_structured_drift > 0,
    'agenda_blocks_total', v_blocks_total,
    'agenda_blocks_pending', v_blocks_pending,
    'agenda_blocks_pending_list', v_blocks_pending_list,
    'blocks_pending_signal', v_blocks_pending > 0,
    'summary_appended', p_summary IS NOT NULL AND length(trim(p_summary)) > 0 AND NOT v_already_closed,
    'suggestions_count', COALESCE(cardinality(v_validated_suggestions), 0),
    'suggestions_stored', v_validated_suggestions
  );
END;
$function$;

-- ── 5) Alerta diario: bloco pendente em reuniao ja realizada ───────────────────
-- Funcao `_cron` SEM gate de usuario. Agendar a RPC gateada por auth.uid() rodaria VERDE e VAZIA
-- (medido no #1543: sob pg_cron nao ha JWT, auth.uid() e NULL, o gate nega e o job registra sucesso
-- sem escrever nada). Molde: ratification_window_close_cron.
--
-- REPORTA, nunca confirma. A notificacao aponta para /admin/agenda-viva, onde um humano decide.

-- 5a) O conjunto detectado, isolado numa funcao propria: da para audita-lo por leitura pura, sem
-- disparar o alerta. Espelha _recurrence_stockout_rows. STABLE, sem escrita.
CREATE OR REPLACE FUNCTION public._agenda_blocks_pending_rows(p_horizon_days int DEFAULT 60)
RETURNS TABLE (event_id uuid, title text, event_date date, pending bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT e.id, e.title, e.date, count(b.id)
  FROM public.events e
  JOIN public.event_agenda_blocks b ON b.event_id = e.id AND b.status = 'reserved'
  WHERE e.status IS DISTINCT FROM 'cancelled'
    AND ((e.date + COALESCE(e.time_start,'00:00'::time))
          AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo')) <= now()
    AND e.date >= (CURRENT_DATE - make_interval(days => p_horizon_days))
  GROUP BY e.id, e.title, e.date;
$function$;

REVOKE ALL ON FUNCTION public._agenda_blocks_pending_rows(int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._agenda_blocks_pending_rows(int) FROM anon;
REVOKE ALL ON FUNCTION public._agenda_blocks_pending_rows(int) FROM authenticated;
GRANT EXECUTE ON FUNCTION public._agenda_blocks_pending_rows(int) TO service_role;

CREATE OR REPLACE FUNCTION public.detect_agenda_blocks_pending_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_events int := 0;
  v_blocks int := 0;
  v_inserted int := 0;
BEGIN
  -- Sem TEMP TABLE de proposito: `CREATE TEMP TABLE ... ON COMMIT DROP` quebra com "relation
  -- already exists" se a funcao for chamada DUAS VEZES na mesma transacao (o que um teste faz).
  -- A view abaixo nao existe como objeto; o SELECT e repetido nas duas leituras.
  SELECT count(*), COALESCE(sum(pm.pending), 0) INTO v_events, v_blocks
  FROM public._agenda_blocks_pending_rows(60) pm;

  IF v_events > 0 THEN
    -- Um aviso por (destinatario, reuniao), re-emitido no maximo a cada 6 dias enquanto a pendencia
    -- durar. source_type/source_id dao a idempotencia; sem eles isto viraria spam diario.
    INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode, created_at)
    SELECT m.id,
           'agenda_blocks_pending',
           format('%s bloco(s) sem confirmar em %s', pm.pending, pm.title),
           format('A reuniao de %s tem %s bloco(s) de protagonismo ainda em "reservado". Enquanto nao forem confirmados (ou marcados como nao realizados) os protagonistas nao recebem XP e os blocos nao aparecem publicamente. Confirme em Admin -> Agenda Viva.',
                  to_char(pm.event_date, 'DD/MM/YYYY'), pm.pending),
           '/admin/agenda-viva',
           'event',
           pm.event_id,
           'digest_weekly',
           now()
    FROM public._agenda_blocks_pending_rows(60) pm
    CROSS JOIN public.members m
    WHERE m.is_active = true
      AND public.can_by_member(m.id, 'manage_event')
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = m.id
          AND n.type = 'agenda_blocks_pending'
          AND n.source_id = pm.event_id
          AND n.created_at >= now() - interval '6 days'
      );
    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'cron.detect_agenda_blocks_pending_run', 'system_event', NULL,
      jsonb_build_object('meetings_with_pending', v_events, 'blocks_pending', v_blocks, 'managers_notified', v_inserted, 'horizon_days', 60),
      jsonb_build_object('source', 'cron_detect_agenda_blocks_pending')
    );
  END IF;

  RETURN jsonb_build_object(
    'meetings_with_pending',  v_events,
    'blocks_pending',         v_blocks,
    'notifications_inserted', v_inserted,
    'horizon_days',           60,
    'run_at',                 now()
  );
END;
$function$;

COMMENT ON FUNCTION public.detect_agenda_blocks_pending_cron() IS
  '#1548 — alerta diario de bloco de protagonismo ainda reservado em reuniao ja realizada. REPORTA, nunca confirma (XP e veredito humano). Sem gate de auth.uid(): sob pg_cron nao ha JWT.';

-- ACL apertada — molde do #1543, NAO a do detect_recurrence_stockout_cron (que deixou anon/authenticated
-- com EXECUTE e portanto permite a qualquer um disparar o detector).
REVOKE ALL ON FUNCTION public.detect_agenda_blocks_pending_cron() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.detect_agenda_blocks_pending_cron() FROM anon;
REVOKE ALL ON FUNCTION public.detect_agenda_blocks_pending_cron() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.detect_agenda_blocks_pending_cron() TO service_role;

-- 5b) Agendamento — 09:50 BRT, manha seguinte a uma reuniao da noite. Horario escolhido por
-- ausencia de colisao na grade viva de cron.job (medido 2026-07-31).
SELECT cron.schedule(
  'agenda-blocks-pending-daily',
  '50 12 * * *',
  $cron$SELECT public.detect_agenda_blocks_pending_cron();$cron$
);
