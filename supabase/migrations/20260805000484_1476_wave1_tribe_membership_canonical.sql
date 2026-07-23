-- #1476 Onda 1 — pertencimento de tribo por engagement (canonical set), não pelo cache operational_role.
--
-- Bug: ~16 funções usam `operational_role NOT IN ('sponsor','chapter_liaison','guest','none')` como
-- proxy de pertencimento. Quem acumula ponto focal de capítulo + pesquisador de tribo tem o cache
-- resolvido para 'chapter_liaison' (escada "governança vence") e é apagado dos grids/contagens da
-- própria tribo, apesar de engagement volunteer ativo. Fonte de verdade = engagement, não o rótulo.
--
-- Onda 1 (tribe-scoped, sem entanglement com #1437/ADR-0126 v_operational_members): centraliza o
-- conjunto canônico numa view (`v_tribe_active_members`) e reescreve as 6 funções tribe-scoped para
-- consumi-la. Deltas aterrados 2026-07-24: 2 afetados / tribos 1 e 7; bridge ⊆ engagement (0 linhas
-- só-bridge); grid leg1 fallback `initiative_id` cobre 0 membros; view = 68 linhas.
--
-- Class B (LEAVE, gate de autoridade legítimo): get_org_chart, get_portfolio_planned_vs_actual,
-- review_change_request. Org-wide/write-path (seal_event_attendance, summaries, dropout, cohort-health)
-- e a view #1437 canonical → Onda 2 (decisão de owner p/ o canonical amplo). NÃO nesta migration.

-- ============================================================================
-- 1) Conjunto canônico: membros ativos de tribo por engagement (SSOT único)
-- ============================================================================
-- Consumido SOMENTE dentro de funções SECURITY DEFINER (owner=postgres, rolbypassrls). security_invoker=on
-- + REVOKE de anon/authenticated é LOAD-BEARING: pg_default_acl auto-concede DML a anon/authenticated em
-- toda relação nova (lição #1422). Dependência de owner: se um futuro consumidor NÃO for owned by postgres,
-- precisará de GRANT SELECT explícito nesta view (senão "permission denied for view" em runtime).
CREATE OR REPLACE VIEW public.v_tribe_active_members AS
SELECT DISTINCT
  e.person_id,
  m.id            AS member_id,
  i.legacy_tribe_id,
  i.id            AS initiative_id
FROM public.engagements e
JOIN public.initiatives i ON i.id = e.initiative_id
JOIN public.members m     ON m.person_id = e.person_id
WHERE e.kind = 'volunteer'
  AND e.status = 'active'
  AND i.kind = 'research_tribe'
  AND i.legacy_tribe_id IS NOT NULL;

ALTER VIEW public.v_tribe_active_members SET (security_invoker = on);
REVOKE ALL ON public.v_tribe_active_members FROM PUBLIC, anon, authenticated;

COMMENT ON VIEW public.v_tribe_active_members IS
  'Canonical set of active tribe members by engagement (SSOT for tribe belonging; #1476). '
  'One row per (person, tribe). Consumed only by SECURITY DEFINER functions owned by postgres. '
  'security_invoker=on + REVOKE from anon/authenticated is load-bearing (#1422 pg_default_acl auto-grant).';

-- ============================================================================
-- 2) count_tribe_slots — capacidade por engagement (era tribe_id + rótulo)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.count_tribe_slots()
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(
    json_object_agg(legacy_tribe_id, cnt),
    '{}'::json
  )
  FROM (
    SELECT legacy_tribe_id, count(*)::int as cnt
    FROM public.v_tribe_active_members
    GROUP BY legacy_tribe_id
  ) sub;
$function$;

-- ============================================================================
-- 3) get_tribe_attendance_grid — leg1 já engagement-gated; remove filtro de rótulo (o sintoma)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_tribe_attendance_grid(p_tribe_id integer, p_event_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member_id uuid;
  v_caller_tribe_id integer;
  v_is_admin boolean;
  v_is_stakeholder boolean;
  v_cycle_start date;
  v_tribe_initiative_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  v_caller_tribe_id := public.get_member_tribe(v_member_id);

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  v_is_stakeholder := public.can_by_member(v_member_id, 'view_partner');

  IF NOT v_is_admin AND NOT v_is_stakeholder
     AND COALESCE(v_caller_tribe_id, -1) <> p_tribe_id THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM public.cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  SELECT id INTO v_tribe_initiative_id
  FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id AND kind = 'research_tribe'
  LIMIT 1;

  WITH
  raw_events AS (
    SELECT e.id, e.date, e.title, e.title_i18n, e.type, e.status, i.legacy_tribe_id AS tribe_id,
           i.title AS tribe_name,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date)::int AS week_number,
           EXTRACT(ISOYEAR FROM e.date)::int AS iso_year,
           EXTRACT(WEEK FROM e.date)::int AS iso_week
    FROM public.events e LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_cycle_start
      AND (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff') OR e.type = 'lideranca')
      AND (p_event_type IS NULL OR e.type = p_event_type)
      AND (e.initiative_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
  ),
  cancelled_with_replan AS (
    SELECT re_cancelled.id AS cancelled_event_id
    FROM raw_events re_cancelled
    WHERE re_cancelled.status = 'cancelled'
      AND re_cancelled.tribe_id = p_tribe_id
      AND EXISTS (
        SELECT 1 FROM raw_events re_sibling
        WHERE re_sibling.id <> re_cancelled.id
          AND re_sibling.tribe_id = p_tribe_id
          AND re_sibling.status = 'scheduled'
          AND re_sibling.iso_year = re_cancelled.iso_year
          AND re_sibling.iso_week = re_cancelled.iso_week
      )
  ),
  grid_events AS (
    SELECT re.id, re.date, re.title, re.title_i18n, re.type, re.status, re.tribe_id,
           re.tribe_name, re.duration_minutes, re.week_number
    FROM raw_events re
    LEFT JOIN cancelled_with_replan cr ON cr.cancelled_event_id = re.id
    WHERE cr.cancelled_event_id IS NULL
    ORDER BY re.date
  ),
  event_row_counts AS (
    SELECT a.event_id, COUNT(*) AS row_count
    FROM public.attendance a
    WHERE a.event_id IN (SELECT id FROM grid_events)
    GROUP BY a.event_id
  ),
  grid_members AS (
    SELECT m.id, m.name,
           public.get_member_tribe(m.id) AS tribe_id,
           m.chapter, m.operational_role, m.designations, m.member_status
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.id IN (
        SELECT member_id FROM public.v_tribe_active_members
        WHERE initiative_id = v_tribe_initiative_id
      )
    UNION
    SELECT DISTINCT m.id, m.name,
           public.get_member_tribe(m.id) AS tribe_id,
           m.chapter, m.operational_role, m.designations, m.member_status
    FROM public.members m
    JOIN public.attendance a ON a.member_id = m.id
    JOIN grid_events ge ON ge.id = a.event_id
    WHERE m.member_status IN ('observer', 'alumni', 'inactive')
      AND ge.tribe_id = p_tribe_id
  ),
  eligibility AS (
    SELECT m.id AS member_id, ge.id AS event_id,
      CASE
        WHEN ge.type IN ('geral', 'kickoff') THEN true
        WHEN ge.type = 'tribo' AND ge.tribe_id = p_tribe_id THEN true
        WHEN ge.type = 'lideranca' AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader') THEN true
        ELSE false
      END AS is_eligible
    FROM grid_members m CROSS JOIN grid_events ge
  ),
  cell_status AS (
    SELECT el.member_id, el.event_id, el.is_eligible,
      CASE
        WHEN ge.status = 'cancelled' THEN 'na'
        WHEN NOT el.is_eligible THEN 'na'
        WHEN ge.date > CURRENT_DATE THEN CASE WHEN gm.member_status != 'active' THEN 'na' ELSE 'scheduled' END
        WHEN a.id IS NOT NULL AND a.excused = true THEN 'excused'
        WHEN a.id IS NOT NULL AND a.present = true THEN 'present'
        WHEN a.id IS NOT NULL AND a.present = false THEN 'absent'
        ELSE CASE
          WHEN gm.member_status != 'active' AND (gm.offboarded_at IS NULL OR gm.offboarded_at::date > ge.date) THEN 'absent'
          WHEN gm.member_status != 'active' AND gm.offboarded_at IS NOT NULL AND gm.offboarded_at::date <= ge.date THEN 'na'
          ELSE 'absent' END
      END AS status
    FROM eligibility el JOIN grid_events ge ON ge.id = el.event_id
    JOIN (SELECT id, member_status, offboarded_at FROM public.members) gm ON gm.id = el.member_id
    LEFT JOIN public.attendance a ON a.member_id = el.member_id AND a.event_id = el.event_id
    LEFT JOIN event_row_counts erc ON erc.event_id = ge.id
  ),
  member_stats AS (
    SELECT cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      ROUND(COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent')), 0), 2) AS rate,
      ROUND(SUM(CASE WHEN cs.status = 'present' THEN ge.duration_minutes ELSE 0 END)::numeric / 60, 1) AS hours
    FROM cell_status cs JOIN grid_events ge ON ge.id = cs.event_id GROUP BY cs.member_id
  ),
  detractor_calc AS (
    SELECT cs.member_id,
      (SELECT COUNT(*) FROM (
        SELECT cs2.status AS cell_status, ROW_NUMBER() OVER (ORDER BY ge2.date DESC) AS rn
        FROM cell_status cs2 JOIN grid_events ge2 ON ge2.id = cs2.event_id
        WHERE cs2.member_id = cs.member_id AND cs2.status IN ('present', 'absent')
        ORDER BY ge2.date DESC
      ) sub WHERE sub.cell_status = 'absent' AND sub.rn <= COALESCE((
        SELECT MIN(rn2) FROM (
          SELECT cs3.status AS cell_status, ROW_NUMBER() OVER (ORDER BY ge3.date DESC) AS rn2
          FROM cell_status cs3 JOIN grid_events ge3 ON ge3.id = cs3.event_id
          WHERE cs3.member_id = cs.member_id AND cs3.status IN ('present', 'absent')
          ORDER BY ge3.date DESC
        ) sub2 WHERE sub2.cell_status = 'present'), 999)) AS consecutive_absences
    FROM cell_status cs GROUP BY cs.member_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT COUNT(DISTINCT id) FROM grid_members WHERE member_status = 'active'),
      'overall_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
      'perfect_attendance', (SELECT COUNT(*) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active' AND ms.rate >= 1.0),
      'below_50', (SELECT COUNT(*) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active' AND ms.rate < 0.5 AND ms.rate > 0),
      'total_events', (SELECT COUNT(*) FROM grid_events),
      'past_events', (SELECT COUNT(*) FROM grid_events WHERE date <= CURRENT_DATE),
      'cancelled_events', (SELECT COUNT(*) FROM grid_events ge_c WHERE ge_c.status = 'cancelled'),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0),
      'detractors_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN grid_members gm ON gm.id = dc.member_id WHERE gm.member_status = 'active' AND dc.consecutive_absences >= 3),
      'at_risk_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN grid_members gm ON gm.id = dc.member_id WHERE gm.member_status = 'active' AND dc.consecutive_absences = 2)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'title_i18n', ge.title_i18n, 'type', ge.type,
      'status', ge.status,
      'tribe_id', ge.tribe_id, 'tribe_name', ge.tribe_name,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_tribe_event', (ge.tribe_id = p_tribe_id), 'is_future', (ge.date > CURRENT_DATE),
      'is_cancelled', (ge.status = 'cancelled')
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'members', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', am.id, 'name', am.name, 'chapter', am.chapter, 'member_status', am.member_status,
      'rate', COALESCE(ms.rate, 0), 'hours', COALESCE(ms.hours, 0),
      'eligible_count', COALESCE(ms.eligible_count, 0), 'present_count', COALESCE(ms.present_count, 0),
      'detractor_status', CASE
        WHEN am.member_status != 'active' THEN 'inactive'
        WHEN COALESCE(dc.consecutive_absences, 0) >= 3 THEN 'detractor'
        WHEN COALESCE(dc.consecutive_absences, 0) = 2 THEN 'at_risk'
        ELSE 'regular' END,
      'consecutive_absences', COALESCE(dc.consecutive_absences, 0),
      'attendance', (SELECT COALESCE(jsonb_object_agg(cs.event_id::text, cs.status), '{}'::jsonb)
        FROM cell_status cs WHERE cs.member_id = am.id)
    ) ORDER BY CASE WHEN am.member_status = 'active' THEN 0 ELSE 1 END, COALESCE(ms.rate, 0) ASC), '[]'::jsonb)
      FROM grid_members am
      LEFT JOIN member_stats ms ON ms.member_id = am.id
      LEFT JOIN detractor_calc dc ON dc.member_id = am.id)
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- ============================================================================
-- 4) get_tribe_events_timeline — v_tribe_member_count via set canônico
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_tribe_events_timeline(p_tribe_id integer, p_upcoming_limit integer DEFAULT 3, p_past_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_upcoming jsonb;
  v_past jsonb;
  v_next_recurring jsonb;
  v_tribe_member_count int;
  v_tribe_initiative_id uuid;
  v_now_brt timestamptz := NOW() AT TIME ZONE 'America/Sao_Paulo';
  v_today_brt date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT id INTO v_tribe_initiative_id
  FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id AND kind = 'research_tribe'
  LIMIT 1;

  SELECT count(*) INTO v_tribe_member_count
  FROM public.v_tribe_active_members v
  WHERE v.initiative_id = v_tribe_initiative_id;

  SELECT COALESCE(jsonb_agg(row_data ORDER BY row_data->>'date', row_data->>'title'), '[]'::jsonb)
  INTO v_upcoming
  FROM (
    SELECT jsonb_build_object(
      'id', e.id,
      'title', e.title,
      'title_i18n', e.title_i18n,
      'date', e.date,
      'type', e.type,
      'nature', e.nature,
      'duration_minutes', COALESCE(e.duration_minutes, 60),
      'meeting_link', e.meeting_link,
      'audience_level', e.audience_level,
      'tribe_id', i.legacy_tribe_id,
      'is_tribe_event', (i.legacy_tribe_id = p_tribe_id),
      'agenda_text', e.agenda_text,
      'eligible_count', CASE
        WHEN e.type IN ('geral', 'kickoff') THEN (SELECT count(*) FROM members WHERE is_active AND current_cycle_active)
        WHEN i.legacy_tribe_id = p_tribe_id THEN v_tribe_member_count
        ELSE 0
      END
    ) as row_data
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff', 'lideranca'))
      AND COALESCE(e.visibility, 'all') != 'gp_only'
      AND (
        e.date > v_today_brt
        OR (
          e.date = v_today_brt
          AND (
            e.date::timestamp
            + COALESCE(
                (SELECT tms.time_start FROM tribe_meeting_slots tms
                 WHERE tms.tribe_id = i.legacy_tribe_id AND tms.is_active LIMIT 1),
                '19:30'::time
              )
            + (COALESCE(e.duration_minutes, 60) || ' minutes')::interval
          )::timestamp > v_now_brt::timestamp
        )
      )
    ORDER BY e.date ASC
    LIMIT p_upcoming_limit
  ) sub;

  SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'date') DESC), '[]'::jsonb)
  INTO v_past
  FROM (
    SELECT jsonb_build_object(
      'id', e.id,
      'title', e.title,
      'title_i18n', e.title_i18n,
      'date', e.date,
      'type', e.type,
      'nature', e.nature,
      'duration_minutes', COALESCE(e.duration_actual, e.duration_minutes, 60),
      'tribe_id', i.legacy_tribe_id,
      'is_tribe_event', (i.legacy_tribe_id = p_tribe_id),
      'youtube_url', e.youtube_url,
      'recording_url', e.recording_url,
      'recording_type', e.recording_type,
      'has_recording', (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL),
      'attendee_count', (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true),
      'eligible_count', CASE
        WHEN e.type IN ('geral', 'kickoff') THEN (SELECT count(*) FROM members WHERE is_active AND current_cycle_active)
        WHEN i.legacy_tribe_id = p_tribe_id THEN v_tribe_member_count
        ELSE 0
      END,
      'agenda_text', e.agenda_text,
      'minutes_text', e.minutes_text
    ) as row_data
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE e.date <= v_today_brt
      AND (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff'))
      AND COALESCE(e.visibility, 'all') != 'gp_only'
    ORDER BY e.date DESC
    LIMIT p_past_limit
  ) sub;

  SELECT jsonb_build_object(
    'day_of_week', tms.day_of_week,
    'time_start', tms.time_start,
    'time_end', tms.time_end,
    'day_name_pt', CASE tms.day_of_week
      WHEN 0 THEN 'Domingo' WHEN 1 THEN 'Segunda' WHEN 2 THEN 'Terça'
      WHEN 3 THEN 'Quarta' WHEN 4 THEN 'Quinta' WHEN 5 THEN 'Sexta' WHEN 6 THEN 'Sábado'
    END,
    'day_name_en', CASE tms.day_of_week
      WHEN 0 THEN 'Sunday' WHEN 1 THEN 'Monday' WHEN 2 THEN 'Tuesday'
      WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday' WHEN 6 THEN 'Saturday'
    END
  ) INTO v_next_recurring
  FROM tribe_meeting_slots tms
  WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true
  LIMIT 1;

  RETURN jsonb_build_object(
    'upcoming', v_upcoming,
    'past', v_past,
    'next_recurring', COALESCE(v_next_recurring, 'null'::jsonb),
    'tribe_member_count', v_tribe_member_count
  );
END;
$function$;

-- ============================================================================
-- 5) request_tribe_assignment — gate de vaga via set canônico
-- ============================================================================
CREATE OR REPLACE FUNCTION public.request_tribe_assignment(p_tribe_id integer, p_message text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_person_id uuid;
  v_member_status text;
  v_is_active boolean;
  v_initiative record;
  v_invitation_id uuid;
  v_deadline timestamptz;
  v_slot_count integer;
  v_max_slots integer := public.tribe_capacity_limit();
BEGIN
  SELECT m.id, m.person_id, m.member_status, m.is_active
    INTO v_member_id, v_person_id, v_member_status, v_is_active
    FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_is_active IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Membro inativo' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Deadline gate: block NEW tribe requests once the configured deadline has passed. SSOT setting;
  -- absent/null = open window (no enforcement). This is the real gate (the FE hides the picker too).
  v_deadline := (SELECT (value #>> '{}')::timestamptz FROM public.platform_settings WHERE key = 'tribe_request_deadline');
  IF v_deadline IS NOT NULL AND now() > v_deadline THEN
    RAISE EXCEPTION 'O prazo para pedir uma tribo encerrou. Fale com a coordenacao do Nucleo para entrar ou trocar de tribo.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF length(coalesce(p_message, '')) < 50 THEN
    RAISE EXCEPTION 'A mensagem deve ter ao menos 50 caracteres descrevendo sua motivação (atual: %)', length(coalesce(p_message, ''))
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- WS-A3 parity with select_tribe: tribe entry requires the signed volunteer term.
  -- Fail closed if no person row (member_is_pre_onboarding(NULL,...) would return false).
  IF v_person_id IS NULL OR public.member_is_pre_onboarding(v_person_id, v_member_status) THEN
    RAISE EXCEPTION 'Assine o termo de voluntário antes de pedir uma tribo'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_initiative
  FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id AND kind = 'research_tribe';

  IF v_initiative.id IS NULL THEN
    RAISE EXCEPTION 'Tribo não encontrada' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_initiative.status <> 'active' THEN
    RAISE EXCEPTION 'Esta tribo não está ativa' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- block if already in ANY tribe (self-service is "join your first tribe"; moves are GP-mediated
  -- via admin force-move). This keeps the AH single-active-engagement invariant intact on approval.
  IF EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.initiatives i3 ON i3.id = e.initiative_id AND i3.kind = 'research_tribe'
    WHERE e.person_id = v_person_id
      AND e.kind = 'volunteer'
      AND e.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Você já participa de uma tribo' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- one pending tribe request at a time (across all research_tribe initiatives)
  IF EXISTS (
    SELECT 1
    FROM public.initiative_invitations ii
    JOIN public.initiatives i2 ON i2.id = ii.initiative_id AND i2.kind = 'research_tribe'
    WHERE ii.invitee_member_id = v_member_id
      AND ii.status = 'pending'
  ) THEN
    RAISE EXCEPTION 'Você já tem um pedido de tribo pendente' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- #1350: capacity gate at REQUEST time (was only on approve/select_tribe). Same slot formula as
  -- review_tribe_request (p_tribe_id IS the legacy_tribe_id = members.tribe_id). Blocking here means
  -- no un-approvable pending is ever created against a full tribe. Cap SSOT = tribe_capacity_limit().
  SELECT count(*) INTO v_slot_count
  FROM public.v_tribe_active_members v
  WHERE v.legacy_tribe_id = p_tribe_id;
  IF v_slot_count >= v_max_slots THEN
    RAISE EXCEPTION 'Tribo lotada (%/%): escolha outra tribo', v_slot_count, v_max_slots
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- #1257 (Wave 3, D2): TTL 7 dias EXPLÍCITO — revisão feita por líder voluntário precisa de mais
  -- folga que as 72h do default da tabela. Só o caminho de tribo seta 7d; o default (now()+72h)
  -- permanece para convites líder→pesquisador legítimos.
  INSERT INTO public.initiative_invitations
    (initiative_id, invitee_member_id, inviter_member_id, kind_scope, message, expires_at)
  VALUES
    (v_initiative.id, v_member_id, v_member_id, 'volunteer', p_message, now() + interval '7 days')
  RETURNING id INTO v_invitation_id;

  -- notify the tribe leader(s) — no PII in the body (LGPD minimisation).
  -- #1139 Item 2: link deep-links to the Membros tab (where the approval queue renders).
  INSERT INTO public.notifications
    (recipient_id, type, title, body, link, source_type, source_id, actor_id, delivery_mode)
  SELECT m2.id, 'tribe_request',
         'Novo pedido de entrada na tribo',
         'Um pesquisador pediu para entrar na tribo ' || v_initiative.title || '. Revise em /tribe/' || p_tribe_id::text || '.',
         '/tribe/' || p_tribe_id::text || '?tab=members',
         'initiative_invitation', v_invitation_id, v_member_id, 'transactional_immediate'
  FROM public.engagements e
  JOIN public.members m2 ON m2.person_id = e.person_id
  WHERE e.initiative_id = v_initiative.id
    AND e.kind = 'volunteer' AND e.role = 'leader' AND e.status = 'active';

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', v_invitation_id,
    'tribe_id', p_tribe_id,
    'initiative_id', v_initiative.id,
    'expires_at', (now() + interval '7 days'),
    'note', 'O líder da tribo vai revisar seu pedido. Acompanhe por list_my_initiative_invitations.'
  );
END;
$function$;

-- ============================================================================
-- 6) review_tribe_request — gate de vaga via set canônico
-- ============================================================================
CREATE OR REPLACE FUNCTION public.review_tribe_request(p_invitation_id uuid, p_decision text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_is_admin boolean;
  v_is_leader boolean;
  v_invitation record;
  v_initiative record;
  v_invitee_person_id uuid;
  v_engagement_id uuid;
  v_org_id uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
  v_slot_count integer;
  v_max_slots integer := public.tribe_capacity_limit();
BEGIN
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_decision NOT IN ('approve', 'decline') THEN
    RAISE EXCEPTION 'Decisão deve ser \"approve\" ou \"decline\" (recebido: %)', p_decision
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- cap the note (it lands verbatim in the requester's notification body)
  IF length(coalesce(p_note, '')) > 500 THEN
    RAISE EXCEPTION 'Nota muito longa (máx 500 caracteres)' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT * INTO v_invitation FROM public.initiative_invitations WHERE id = p_invitation_id;
  IF v_invitation.id IS NULL THEN
    RAISE EXCEPTION 'Pedido não encontrado' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT * INTO v_initiative FROM public.initiatives WHERE id = v_invitation.initiative_id;
  IF v_initiative.kind <> 'research_tribe' THEN
    RAISE EXCEPTION 'review_tribe_request só revisa pedidos de tribo (use review_initiative_request)'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF v_invitation.status <> 'pending' THEN
    RAISE EXCEPTION 'Pedido não está pendente (status=%)', v_invitation.status
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_invitation.expires_at < now() THEN
    -- do NOT UPDATE here: a RAISE rolls back the same statement, so the write is a no-op.
    -- The cron expire_stale_initiative_invitations commits the 'expired' state.
    RAISE EXCEPTION 'Pedido expirou' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- self-service request invariant (invitee == inviter)
  IF v_invitation.invitee_member_id <> v_invitation.inviter_member_id THEN
    RAISE EXCEPTION 'Não é um pedido self-service — o convidado deve responder via respond_to_initiative_invitation'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Authority: GP (manage_member) OR leader of THIS tribe (Caminho-3 inline-scope, no shared gate)
  v_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');
  IF NOT v_is_admin THEN
    v_is_leader := EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = v_caller_person_id
        AND e.initiative_id = v_invitation.initiative_id
        AND e.kind = 'volunteer'
        AND e.role = 'leader'
        AND e.status = 'active'
    );
    IF NOT v_is_leader THEN
      RAISE EXCEPTION 'Não autorizado: apenas o líder desta tribo ou o GP podem revisar'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Capacidade (SSOT tribe_capacity_limit): só bloqueia o approve — decline sempre passa.
  -- Conta como count_tribe_slots(): membros ativos já na tribo, excluindo papéis sem vaga.
  IF p_decision = 'approve' THEN
    SELECT count(*) INTO v_slot_count
    FROM public.v_tribe_active_members v
    WHERE v.legacy_tribe_id = v_initiative.legacy_tribe_id;
    IF v_slot_count >= v_max_slots THEN
      RAISE EXCEPTION 'Tribo lotada (%/%): peça ao GP para ajustar a capacidade ou escolha outra tribo', v_slot_count, v_max_slots
        USING ERRCODE = 'invalid_parameter_value';
    END IF;
  END IF;

  UPDATE public.initiative_invitations
  SET status = CASE WHEN p_decision = 'approve' THEN 'accepted' ELSE 'declined' END,
      reviewed_by = v_caller_member_id,
      reviewed_at = now(),
      reviewed_note = p_note,
      responded_at = now()
  WHERE id = p_invitation_id;

  IF p_decision = 'approve' THEN
    SELECT m.person_id INTO v_invitee_person_id
    FROM public.members m WHERE m.id = v_invitation.invitee_member_id;

    -- #1263 (Wave 3): atomic tribe switch. request_tribe_assignment blocks a member who already has
    -- a tribe, so this only bites the edge where a pending request predated a tribe join (or a GP
    -- force-move): the researcher holds an ACTIVE volunteer engagement in ANOTHER research_tribe.
    -- Demote it here — BEFORE inserting the new one — so the bridge trigger
    -- trg_sync_tribe_id_from_engagement never sees two active tribe engagements for this person, and
    -- AH (single active tribe engagement) + AG (members.tribe_id matches) stay at baseline 0.
    -- Use 'offboarded' (valid engagements_status_check value) — NEVER 'revoked' (not in the CHECK).
    UPDATE public.engagements e
       SET status = 'offboarded',
           revoked_at = now(),
           revoked_by = v_caller_person_id,   -- engagements.revoked_by FK -> persons(id), NOT members(id)
           revoke_reason = 'tribe_switch_on_approval',
           metadata = e.metadata || jsonb_build_object(
             'offboarded_via', 'tribe_switch_on_approval',
             'superseding_invitation_id', p_invitation_id,
             'reviewed_by_member_id', v_caller_member_id
           ),
           updated_at = now()
      FROM public.initiatives i
     WHERE e.initiative_id = i.id
       AND i.kind = 'research_tribe'
       AND e.person_id = v_invitee_person_id
       AND e.kind = 'volunteer'
       AND e.status = 'active'
       AND e.initiative_id <> v_invitation.initiative_id;

    -- #1280 idempotência: se já existe engagement do mesmo kind ativa nesta MESMA tribo, reusar
    -- (no-op) em vez de inserir uma segunda — que violaria AH_research_tribe_single_active_engagement.
    -- Bite: um pedido pendente materializado após um stub retroativo (backfill #1247) para a mesma tribo.
    SELECT e.id INTO v_engagement_id
    FROM public.engagements e
    WHERE e.person_id = v_invitee_person_id
      AND e.initiative_id = v_invitation.initiative_id
      AND e.kind = v_invitation.kind_scope
      AND e.status = 'active'
    ORDER BY e.created_at
    LIMIT 1;

    IF v_engagement_id IS NULL THEN
      INSERT INTO public.engagements
        (person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id)
      VALUES (
        v_invitee_person_id,
        v_invitation.initiative_id,
        v_invitation.kind_scope,
        -- #1325: membresia numa research_tribe é papel de pesquisador. 'participant' mapeava para
        -- operational_role='guest' (fallback do sync_operational_role_cache) e derrubava o joiner do
        -- ranking a menos que tivesse um segundo vínculo researcher. Alinha com approve_selection_application.
        'researcher',
        'active',
        'consent',
        v_caller_person_id,  -- engagements.granted_by FK -> persons(id), NOT members(id)
        jsonb_build_object(
          'source', 'tribe_request_approved',
          'invitation_id', p_invitation_id,
          'reviewed_by', v_caller_member_id,
          'review_authority', CASE WHEN v_is_admin THEN 'admin' ELSE 'tribe_leader' END,
          'requested_at', v_invitation.created_at
        ),
        v_org_id
      )
      RETURNING id INTO v_engagement_id;
    END IF;
  END IF;

  -- notify the requester of the outcome. #1352: on decline, route to the picker (/workspace) and name
  -- the next step; on approve, route to the (now their) tribe.
  INSERT INTO public.notifications
    (recipient_id, type, title, body, link, source_type, source_id, actor_id, delivery_mode)
  VALUES (
    v_invitation.invitee_member_id,
    'tribe_request_reviewed',
    CASE WHEN p_decision = 'approve' THEN 'Pedido de tribo aprovado' ELSE 'Pedido de tribo recusado' END,
    CASE WHEN p_decision = 'approve'
         THEN 'Seu pedido para entrar na tribo ' || v_initiative.title || ' foi aprovado.'
         ELSE 'Seu pedido para entrar na tribo ' || v_initiative.title || ' foi recusado.'
              || coalesce(' Nota: ' || p_note, '')
              || ' Você pode escolher outra tribo no seu painel.'
    END,
    CASE WHEN p_decision = 'approve'
         THEN '/tribe/' || v_initiative.legacy_tribe_id::text
         ELSE '/workspace'
    END,
    'initiative_invitation', p_invitation_id, v_caller_member_id, 'transactional_immediate'
  );

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', p_invitation_id,
    'decision', p_decision,
    'engagement_id', v_engagement_id,
    'review_authority', CASE WHEN v_is_admin THEN 'admin' ELSE 'tribe_leader' END,
    'reviewed_at', now()
  );
END;
$function$;

-- ============================================================================
-- 7) exec_cycle_report — AMBOS member_count (v_tribes overcount + v_att_by_tribe undercount) via set canônico
-- ============================================================================
CREATE OR REPLACE FUNCTION public.exec_cycle_report(p_cycle_code text DEFAULT 'cycle3-2026'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb; v_kpis jsonb; v_members jsonb; v_tribes jsonb;
  v_production jsonb; v_engagement jsonb; v_curation jsonb; v_cycle jsonb; v_attendance jsonb; v_att_by_tribe jsonb;
  v_total_members int; v_active_members int;
  v_start date := '2026-01-01';
  v_end date := '2026-06-30';
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  -- ADR-0042: V4 catalog (manage_platform writes; view_chapter_dashboards reads)
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  SELECT jsonb_build_object(
    'code', COALESCE(c.cycle_code, p_cycle_code),
    'name', COALESCE(c.cycle_label, 'Ciclo 3 — 2026/1'),
    'start_date', c.cycle_start, 'end_date', c.cycle_end
  ) INTO v_cycle FROM public.cycles c WHERE c.cycle_code = p_cycle_code OR c.is_current = true LIMIT 1;
  IF v_cycle IS NULL THEN v_cycle := jsonb_build_object('code', p_cycle_code, 'name', 'Ciclo 3', 'start_date', v_start, 'end_date', v_end); END IF;

  v_kpis := public.get_kpi_dashboard(v_start, v_end);

  SELECT COUNT(*) INTO v_total_members FROM public.members;
  SELECT COUNT(*) INTO v_active_members FROM public.members WHERE current_cycle_active = true;

  SELECT jsonb_build_object(
    'total', v_total_members, 'active', v_active_members,
    'by_chapter', COALESCE((SELECT jsonb_agg(jsonb_build_object('chapter', chapter, 'count', cnt) ORDER BY cnt DESC) FROM (SELECT chapter, count(*) AS cnt FROM public.members WHERE current_cycle_active = true AND chapter IS NOT NULL GROUP BY chapter) sub), '[]'::jsonb),
    'by_role', COALESCE((SELECT jsonb_agg(jsonb_build_object('role', operational_role, 'count', cnt) ORDER BY cnt DESC) FROM (SELECT COALESCE(operational_role, 'none') AS operational_role, count(*) AS cnt FROM public.members WHERE current_cycle_active = true GROUP BY operational_role) sub), '[]'::jsonb),
    -- #692: this is RECURRING members (active members who have been in >1 cycle), NOT retention.
    -- Renamed from retention_rate; the canonical cohort-survival retention ships alongside.
    'recurring_members_pct', ROUND(COALESCE((SELECT COUNT(*) FILTER (WHERE COALESCE(array_length(cycles, 1), 0) > 1)::numeric * 100 / NULLIF(COUNT(*), 0) FROM public.members WHERE current_cycle_active = true AND cycles IS NOT NULL), 0)),
    'retention_cohort_survival_pct', (public.get_member_retention_canonical() -> 'headline' ->> 'survival_pct')::numeric,
    'retention_basis', (public.get_member_retention_canonical() -> 'headline' ->> 'basis'),
    'new_this_cycle', (SELECT COUNT(*) FROM public.members WHERE current_cycle_active = true AND (cycles IS NULL OR COALESCE(array_length(cycles, 1), 0) <= 1))
  ) INTO v_members;

  SELECT COALESCE(jsonb_agg(tribe_data ORDER BY tribe_data->>'name'), '[]'::jsonb) INTO v_tribes
  FROM (SELECT jsonb_build_object('id', t.id, 'name', t.name,
    'leader', COALESCE((SELECT m.name FROM public.members m WHERE m.tribe_id = t.id AND m.operational_role = 'tribe_leader' LIMIT 1), '—'),
    'member_count', (SELECT count(*) FROM public.v_tribe_active_members v WHERE v.legacy_tribe_id = t.id),
    'board_items_total', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived'), 0),
    'board_items_completed', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status = 'done'), 0),
    'completion_pct', COALESCE((SELECT ROUND(COUNT(*) FILTER (WHERE bi.status = 'done')::numeric * 100 / NULLIF(COUNT(*), 0)) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived'), 0),
    'articles_produced', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status IN ('done', 'published') AND (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')), 0)
  ) AS tribe_data FROM public.tribes t WHERE t.is_active = true) sub;

  SELECT jsonb_build_object(
    'articles_submitted', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')), 0),
    'articles_published', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%') AND bi.status IN ('done', 'published')), 0),
    'articles_in_review', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%') AND bi.status IN ('review', 'in_progress')), 0),
    'webinars_completed', public.get_webinars_count(NULL, NULL, 'realized'),
    'webinars_planned', public.get_webinars_count(NULL, NULL, 'planned')
  ) INTO v_production;

  SELECT jsonb_build_object(
    'total_events', (SELECT COUNT(*) FROM public.events WHERE date BETWEEN v_start AND v_end),
    'total_attendance_hours', COALESCE((SELECT round(sum(COALESCE(e.duration_actual, e.duration_minutes, 60)::numeric * (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present)) / 60) FROM events e WHERE e.date BETWEEN v_start AND v_end), 0),
    'avg_attendance_per_event', COALESCE((SELECT ROUND(AVG(ac)) FROM (SELECT COUNT(*) AS ac FROM public.attendance a JOIN events e ON e.id = a.event_id WHERE a.present = true AND e.date BETWEEN v_start AND v_end GROUP BY a.event_id) sub), 0),
    'total_attendance_records', (SELECT COUNT(*) FROM public.attendance WHERE present = true),
    'certification_completion_rate', ROUND(COALESCE((SELECT COUNT(*) FILTER (WHERE cpmai_certified = true)::numeric * 100 / NULLIF(COUNT(*), 0) FROM public.members WHERE current_cycle_active = true), 0))
  ) INTO v_engagement;

  SELECT jsonb_build_object(
    'items_submitted', COALESCE((SELECT COUNT(*) FROM public.curation_review_log), 0),
    'items_approved', COALESCE((SELECT COUNT(*) FROM public.curation_review_log WHERE decision = 'approved'), 0),
    'items_in_review', COALESCE((SELECT COUNT(*) FROM public.board_items WHERE status = 'review'), 0),
    'avg_review_days', COALESCE((SELECT ROUND(AVG(EXTRACT(EPOCH FROM (completed_at - created_at)) / 86400)::numeric, 1) FROM public.curation_review_log), 0),
    'sla_compliance_rate', COALESCE((SELECT ROUND(COUNT(*) FILTER (WHERE completed_at <= due_date)::numeric * 100 / NULLIF(COUNT(*) FILTER (WHERE due_date IS NOT NULL), 0)) FROM public.curation_review_log), 0)
  ) INTO v_curation;

  -- p277 #419 m3 PR5a: attendance DECOUPLED from get_attendance_summary (D9 — drop the hidden 0.4/0.6
  -- combined_pct weighting). Per-tribe headline = ENGAGEMENT (present/eligible, cycles.is_current window);
  -- the RELIABILITY diagnostic ships alongside WITH raw present/absent/excused counts. at_risk_count now
  -- counts engagement < 0.50 (genuine no-show), not the old combined_pct band.
  SELECT COALESCE(jsonb_agg(att_row ORDER BY att_row->>'tribe_name'), '[]'::jsonb) INTO v_att_by_tribe
  FROM (SELECT jsonb_build_object('tribe_id', t.id, 'tribe_name', t.name,
    'members_count', (SELECT count(*) FROM public.v_tribe_active_members v WHERE v.legacy_tribe_id = t.id),
    'engagement_pct', ROUND(COALESCE((eng.j ->> 'avg_rate')::numeric, 0) * 100, 1),
    'reliability_pct', ROUND(COALESCE((rel.j ->> 'avg_rate')::numeric, 0) * 100, 1),
    'present_total', COALESCE((rel.j ->> 'present_total')::int, 0),
    'absent_total', COALESCE((rel.j ->> 'absent_total')::int, 0),
    'excused_total', COALESCE((rel.j ->> 'excused_total')::int, 0),
    'at_risk_count', COALESCE((eng.j ->> 'at_risk_count')::int, 0)
  ) AS att_row
  FROM tribes t
  CROSS JOIN LATERAL (SELECT public.get_attendance_engagement_summary('tribe', t.id) AS j) eng
  CROSS JOIN LATERAL (SELECT public.get_attendance_reliability_summary('tribe', t.id) AS j) rel
  WHERE t.is_active = true) sub;

  v_attendance := jsonb_build_object(
    'engagement', public.get_attendance_engagement_summary('global'),
    'reliability', public.get_attendance_reliability_summary('global'),
    'by_tribe', v_att_by_tribe
  );

  v_result := jsonb_build_object('cycle', v_cycle, 'kpis', v_kpis, 'members', v_members, 'tribes', v_tribes, 'production', v_production, 'engagement', v_engagement, 'curation', v_curation, 'attendance', v_attendance);
  RETURN v_result;
END; $function$;
