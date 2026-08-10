-- #1656 - uma escala no contrato de exibicao de presenca (0-100 sob nome *_pct)
--
-- Decisao do PM em 10/08/2026: a chave de EXIBICAO passa a ser percentual 0-100 e o nome
-- declara a escala (*_pct). As primitivas continuam fracao 0-1 (get_attendance_rate,
-- get_attendance_engagement_rate, avg_rate) - contrato ja afirmado por
-- tests/contracts/p277-419-m3b-get-attendance-rate-canonical.test.mjs.
--
-- Migracao ADITIVA: cada funcao publica a chave nova AO LADO da velha. O front ja deployado
-- continua lendo a chave velha, entao a janela entre este DDL e o deploy nao mostra numero
-- errado (a licao do #1611). A chave velha sai na filha de limpeza.
--
-- Junto, e pela mesma razao de escopo (as duas funcoes ja seriam tocadas): o contrato do #1657
-- ("sem registro nao e falta") chega as OUTRAS DUAS grades. Ele so existia em
-- get_tribe_attendance_grid. Medido em 10/08 antes de aplicar: get_attendance_grid acusava 97
-- celulas (50 membros) e get_initiative_attendance_grid 33 (5 membros), NENHUMA com linha real
-- de falta. A taxa nao muda: essas celulas ja estavam no denominador como 'absent' e passam a
-- 'unrecorded', que o denominador decidido (opcao (a)) mantem.
--
-- Base: capturas vivas em supabase/migrations, com md5 conferido contra
-- _audit_list_public_function_bodies() antes de substituir. Substituicoes ancoradas por script.

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
    SELECT e.id, e.date, e.title, e.title_i18n, e.type, e.status, e.roster_sealed_at, i.legacy_tribe_id AS tribe_id,
           i.title AS tribe_name,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date)::int AS week_number,
           EXTRACT(ISOYEAR FROM e.date)::int AS iso_year,
           EXTRACT(WEEK FROM e.date)::int AS iso_week
    FROM public.events e LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_cycle_start
      AND (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff') OR e.type = 'lideranca')
      AND (p_event_type IS NULL OR e.type = p_event_type)
      AND (e.type <> 'tribo' OR i.legacy_tribe_id = p_tribe_id)
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
    SELECT re.id, re.date, re.title, re.title_i18n, re.type, re.status, re.roster_sealed_at, re.tribe_id,
           re.tribe_name, re.duration_minutes, re.week_number
    FROM raw_events re
    LEFT JOIN cancelled_with_replan cr ON cr.cancelled_event_id = re.id
    WHERE cr.cancelled_event_id IS NULL
    ORDER BY re.date
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
          WHEN gm.member_status != 'active' AND gm.offboarded_at IS NOT NULL AND gm.offboarded_at::date <= ge.date THEN 'na'
          -- #1657: sem linha num evento NAO SELADO e ausencia de REGISTRO, nao falta. Quem nao
          -- clicou deixa de ser indistinguivel de quem faltou. seal_event_attendance() materializa
          -- a linha de no-show, entao "selado + sem linha" nao ocorre; o ELSE cobre so o residuo.
          WHEN ge.roster_sealed_at IS NULL THEN 'unrecorded'
          ELSE 'absent' END
      END AS status
    FROM eligibility el JOIN grid_events ge ON ge.id = el.event_id
    JOIN (SELECT id, member_status, offboarded_at FROM public.members) gm ON gm.id = el.member_id
    LEFT JOIN public.attendance a ON a.member_id = el.member_id AND a.event_id = el.event_id
  ),
  member_stats AS (
    SELECT cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused', 'unrecorded')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      COUNT(*) FILTER (WHERE cs.status = 'unrecorded') AS unrecorded_count,
      -- #1657: 'unrecorded' PERMANECE no denominador. Tirar a celula da acusacao nao pode inflar a
      -- metrica: medido em 09/08, com o denominador colapsado 65 de 66 iriam a 100% e a media
      -- saltaria de 0,779 para 0,985. Quem decide o denominador definitivo e o #1656.
      ROUND(COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'unrecorded')), 0), 2) AS rate,
      -- #1656: rate_pct e a UNICA escala do contrato de exibicao (0-100, 1 casa). Mesma formula
      -- do combined_pct do get_attendance_panel, para que painel e grade publiquem o MESMO numero.
      -- 'rate' (0-1, 2 casas) fica so ate o front migrar; a limpeza e a filha desta issue.
      ROUND(COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'unrecorded')), 0) * 100, 1) AS rate_pct,
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
      'overall_rate_pct', COALESCE((SELECT ROUND(AVG(ms.rate_pct), 1) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
      'perfect_attendance', (SELECT COUNT(*) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active' AND ms.rate >= 1.0),
      'below_50', (SELECT COUNT(*) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active' AND ms.rate < 0.5 AND ms.rate > 0),
      'total_events', (SELECT COUNT(*) FROM grid_events),
      'past_events', (SELECT COUNT(*) FROM grid_events WHERE date <= CURRENT_DATE),
      'cancelled_events', (SELECT COUNT(*) FROM grid_events ge_c WHERE ge_c.status = 'cancelled'),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0),
      'unrecorded_cells', COALESCE((SELECT SUM(ms.unrecorded_count) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
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
      'rate', COALESCE(ms.rate, 0), 'rate_pct', COALESCE(ms.rate_pct, 0), 'hours', COALESCE(ms.hours, 0),
      'eligible_count', COALESCE(ms.eligible_count, 0), 'present_count', COALESCE(ms.present_count, 0),
      'unrecorded_count', COALESCE(ms.unrecorded_count, 0),
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

CREATE OR REPLACE FUNCTION public.get_attendance_grid(p_tribe_id integer DEFAULT NULL::integer, p_event_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_caller_tribe_id integer;
  v_is_admin boolean;
  v_is_stakeholder boolean;
  v_cycle_start date;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  v_caller_tribe_id := public.get_member_tribe(v_member_id);

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  v_is_stakeholder := public.can_by_member(v_member_id, 'view_partner');

  IF NOT v_is_admin AND NOT v_is_stakeholder THEN
    IF v_caller_tribe_id IS NOT NULL THEN
      p_tribe_id := v_caller_tribe_id;
    ELSE
      RETURN jsonb_build_object('error', 'No tribe assigned');
    END IF;
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM public.cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  WITH
  grid_events AS (
    SELECT e.id, e.date, e.title, e.type, e.nature, e.status, e.roster_sealed_at,
           i.legacy_tribe_id AS tribe_id,
           i.title AS tribe_name,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date) AS week_number
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_cycle_start
      AND e.type IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms', 'evento_externo')
      AND (p_event_type IS NULL OR e.type = p_event_type)
      AND (e.initiative_id IS NULL OR e.type = 'tribo')
    ORDER BY e.date
  ),
  active_members AS MATERIALIZED (
    SELECT m.id, m.name,
           public.get_member_tribe(m.id) AS tribe_id,
           m.chapter, m.operational_role, m.designations,
           m.member_status, m.offboarded_at
    FROM public.members m
    WHERE m.is_active = true
      AND m.operational_role NOT IN ('guest', 'none')
  ),
  active_members_scoped AS (
    SELECT * FROM active_members
    WHERE p_tribe_id IS NULL OR tribe_id = p_tribe_id
  ),
  historical_members AS (
    SELECT DISTINCT m.id, m.name,
           p_tribe_id AS tribe_id,
           m.chapter, m.operational_role, m.designations,
           m.member_status, m.offboarded_at
    FROM public.members m
    JOIN public.attendance a ON a.member_id = m.id
    JOIN grid_events ge ON ge.id = a.event_id
    WHERE p_tribe_id IS NOT NULL
      AND m.member_status IN ('observer', 'alumni', 'inactive')
      AND ge.tribe_id = p_tribe_id
  ),
  cohort_members AS (
    SELECT * FROM active_members_scoped
    UNION
    SELECT * FROM historical_members
  ),
  eligibility AS (
    SELECT m.id AS member_id, ge.id AS event_id,
      CASE
        WHEN ge.type IN ('geral', 'kickoff') THEN true
        WHEN ge.type = 'tribo' AND (m.tribe_id = ge.tribe_id OR m.operational_role IN ('manager', 'deputy_manager') OR (p_tribe_id IS NOT NULL AND ge.tribe_id = p_tribe_id)) THEN true
        WHEN ge.type = 'lideranca' AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader') THEN true
        WHEN ge.type = 'comms' AND m.designations && ARRAY['comms_team', 'comms_leader', 'comms_member'] THEN true
        ELSE false
      END AS is_eligible
    FROM cohort_members m CROSS JOIN grid_events ge
  ),
  cell_status AS (
    SELECT el.member_id, el.event_id, el.is_eligible,
      CASE
        WHEN ge.status = 'cancelled' THEN 'na'
        WHEN NOT el.is_eligible THEN 'na'
        WHEN ge.date > CURRENT_DATE THEN CASE WHEN cm.member_status != 'active' THEN 'na' ELSE 'scheduled' END
        WHEN a.id IS NOT NULL AND a.excused = true THEN 'excused'
        WHEN a.id IS NOT NULL AND a.present = true THEN 'present'
        WHEN a.id IS NOT NULL THEN 'absent'
        ELSE CASE
          WHEN cm.member_status != 'active' AND cm.offboarded_at IS NOT NULL AND cm.offboarded_at::date <= ge.date THEN 'na'
          -- #1656: mesmo contrato do #1657 na grade de tribo, que era a UNICA das tres a te-lo.
          -- Sem linha em evento NAO SELADO e ausencia de REGISTRO, nao falta. 'unrecorded' PERMANECE
          -- no denominador (denominador decidido, opcao (a)), entao a taxa NAO muda: muda so a
          -- acusacao na celula. Medido em 10/08: 97 celulas, 50 membros, 0 com linha real de falta.
          WHEN ge.roster_sealed_at IS NULL THEN 'unrecorded'
          ELSE 'absent' END
      END AS status
    FROM eligibility el JOIN grid_events ge ON ge.id = el.event_id
    JOIN cohort_members cm ON cm.id = el.member_id
    LEFT JOIN public.attendance a ON a.member_id = el.member_id AND a.event_id = el.event_id
  ),
  member_stats AS (
    SELECT cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused', 'unrecorded')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      COUNT(*) FILTER (WHERE cs.status = 'unrecorded') AS unrecorded_count,
      ROUND(COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'unrecorded')), 0), 2) AS rate,
      ROUND(COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'unrecorded')), 0) * 100, 1) AS rate_pct,
      ROUND(SUM(CASE WHEN cs.status = 'present' THEN ge.duration_minutes ELSE 0 END)::numeric / 60, 1) AS hours
    FROM cell_status cs JOIN grid_events ge ON ge.id = cs.event_id
    GROUP BY cs.member_id
  ),
  detractor_calc AS (
    SELECT cs.member_id,
      (SELECT COUNT(*) FROM (
        SELECT cs2.status, ROW_NUMBER() OVER (ORDER BY ge2.date DESC) AS rn
        FROM cell_status cs2 JOIN grid_events ge2 ON ge2.id = cs2.event_id
        WHERE cs2.member_id = cs.member_id AND cs2.status IN ('present', 'absent')
        ORDER BY ge2.date DESC
      ) sub WHERE sub.status = 'absent' AND sub.rn <= (
        SELECT MIN(rn2) FROM (
          SELECT cs3.status, ROW_NUMBER() OVER (ORDER BY ge3.date DESC) AS rn2
          FROM cell_status cs3 JOIN grid_events ge3 ON ge3.id = cs3.event_id
          WHERE cs3.member_id = cs.member_id AND cs3.status IN ('present', 'absent')
          ORDER BY ge3.date DESC
        ) sub2 WHERE sub2.status = 'present'
      )) AS consecutive_absences
    FROM cell_status cs GROUP BY cs.member_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT COUNT(DISTINCT id) FROM active_members_scoped),
      'overall_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN active_members_scoped am ON am.id = ms.member_id), 0),
      'overall_rate_pct', COALESCE((SELECT ROUND(AVG(ms.rate_pct), 1) FROM member_stats ms JOIN active_members_scoped am ON am.id = ms.member_id), 0),
      'unrecorded_cells', COALESCE((SELECT SUM(ms.unrecorded_count) FROM member_stats ms JOIN active_members_scoped am ON am.id = ms.member_id), 0),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms JOIN active_members_scoped am ON am.id = ms.member_id), 0),
      'detractors_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN active_members_scoped am ON am.id = dc.member_id WHERE dc.consecutive_absences >= 3),
      'at_risk_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN active_members_scoped am ON am.id = dc.member_id WHERE dc.consecutive_absences = 2)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'type', ge.type, 'nature', ge.nature,
      'status', ge.status,
      'tribe_id', ge.tribe_id, 'tribe_name', ge.tribe_name,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_future', (ge.date > CURRENT_DATE),
      'is_cancelled', (ge.status = 'cancelled')
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'tribes', (SELECT COALESCE(jsonb_agg(tribe_row ORDER BY tribe_row->>'tribe_name'), '[]'::jsonb) FROM (
      SELECT jsonb_build_object(
        'tribe_id', t.id, 'tribe_name', t.name,
        'leader_name', COALESCE((
          SELECT m2.name FROM public.members m2
          WHERE m2.operational_role = 'tribe_leader'
            AND public.get_member_tribe(m2.id) = t.id
          LIMIT 1
        ), '—'),
        'avg_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN active_members_scoped am ON am.id = ms.member_id WHERE am.tribe_id = t.id), 0),
        'avg_rate_pct', COALESCE((SELECT ROUND(AVG(ms.rate_pct), 1) FROM member_stats ms JOIN active_members_scoped am ON am.id = ms.member_id WHERE am.tribe_id = t.id), 0),
        'member_count', (SELECT COUNT(*) FROM active_members_scoped am WHERE am.tribe_id = t.id),
        'members', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', am.id, 'name', am.name, 'chapter', am.chapter,
          'member_status', am.member_status,
          'rate', COALESCE(ms.rate, 0), 'rate_pct', COALESCE(ms.rate_pct, 0), 'hours', COALESCE(ms.hours, 0),
          'eligible_count', COALESCE(ms.eligible_count, 0), 'present_count', COALESCE(ms.present_count, 0),
          'unrecorded_count', COALESCE(ms.unrecorded_count, 0),
          'detractor_status', CASE
            WHEN am.member_status != 'active' THEN 'inactive'
            WHEN COALESCE(dc.consecutive_absences, 0) >= 3 THEN 'detractor'
            WHEN COALESCE(dc.consecutive_absences, 0) = 2 THEN 'at_risk'
            ELSE 'regular' END,
          'consecutive_absences', COALESCE(dc.consecutive_absences, 0),
          'attendance', (SELECT COALESCE(jsonb_object_agg(cs.event_id::text, cs.status), '{}'::jsonb)
            FROM cell_status cs WHERE cs.member_id = am.id)
        ) ORDER BY CASE WHEN am.member_status = 'active' THEN 0 ELSE 1 END, COALESCE(ms.rate, 0) ASC), '[]'::jsonb)
          FROM cohort_members am
          LEFT JOIN member_stats ms ON ms.member_id = am.id
          LEFT JOIN detractor_calc dc ON dc.member_id = am.id
          WHERE am.tribe_id = t.id)
      ) AS tribe_row
      FROM public.tribes t WHERE t.is_active = true AND (p_tribe_id IS NULL OR t.id = p_tribe_id)
    ) sub)
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_initiative_attendance_grid(p_initiative_id uuid, p_event_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_tribe_id int;
  v_cycle_start date;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_attendance_grid(v_tribe_id, p_event_type);
  END IF;

  -- D3: native (non-tribe) path had no scope check — any authenticated member could read any
  -- initiative's grid. Mirror get_tribe_attendance_grid: admin (manage_member) OR stakeholder
  -- (manage_partner) OR active engagement on the initiative.
  IF NOT public.can_by_member(v_caller.id, 'manage_member')
     AND NOT public.can_by_member(v_caller.id, 'view_partner')
     AND NOT EXISTS (
       SELECT 1 FROM engagements e
       WHERE e.person_id = v_caller.person_id
         AND e.initiative_id = p_initiative_id
         AND e.status = 'active'
     ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  WITH
  grid_events AS (
    SELECT e.id, e.date, e.title, e.type, e.status, e.roster_sealed_at,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date)::int AS week_number
    FROM events e
    WHERE e.initiative_id = p_initiative_id
      AND e.date >= v_cycle_start
      AND (p_event_type IS NULL OR e.type = p_event_type)
    ORDER BY e.date
  ),
  grid_members AS (
    SELECT DISTINCT m.id, m.name, m.chapter, m.operational_role, m.designations, m.member_status
    FROM engagements eng
    JOIN members m ON m.person_id = eng.person_id
    WHERE eng.initiative_id = p_initiative_id AND eng.status = 'active'
    UNION
    SELECT DISTINCT m.id, m.name, m.chapter, m.operational_role, m.designations, m.member_status
    FROM members m
    JOIN attendance a ON a.member_id = m.id
    JOIN grid_events ge ON ge.id = a.event_id
  ),
  cell_status AS (
    SELECT
      gm.id AS member_id, ge.id AS event_id,
      CASE
        WHEN ge.status = 'cancelled' THEN 'na'
        WHEN ge.date > CURRENT_DATE THEN
          CASE WHEN gm.member_status != 'active' THEN 'na' ELSE 'scheduled' END
        WHEN a.id IS NOT NULL AND a.excused = true THEN 'excused'
        WHEN a.id IS NOT NULL AND a.present = true THEN 'present'
        WHEN a.id IS NOT NULL THEN 'absent'
        -- #1656: mesmo contrato do #1657 na grade de tribo (ver get_attendance_grid).
        -- Medido em 10/08: 33 celulas, 5 membros, 0 com linha real de falta.
        WHEN ge.roster_sealed_at IS NULL THEN 'unrecorded'
        ELSE 'absent'
      END AS status
    FROM grid_members gm
    CROSS JOIN grid_events ge
    LEFT JOIN attendance a ON a.member_id = gm.id AND a.event_id = ge.id
  ),
  member_stats AS (
    SELECT
      cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused', 'unrecorded')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      COUNT(*) FILTER (WHERE cs.status = 'unrecorded') AS unrecorded_count,
      ROUND(
        COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'unrecorded')), 0), 2
      ) AS rate,
      ROUND(
        COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'unrecorded')), 0) * 100, 1
      ) AS rate_pct,
      ROUND(
        SUM(CASE WHEN cs.status = 'present' THEN ge.duration_minutes ELSE 0 END)::numeric / 60, 1
      ) AS hours
    FROM cell_status cs
    JOIN grid_events ge ON ge.id = cs.event_id
    GROUP BY cs.member_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT COUNT(DISTINCT id) FROM grid_members WHERE member_status = 'active'),
      'overall_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
      'overall_rate_pct', COALESCE((SELECT ROUND(AVG(ms.rate_pct), 1) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
      'unrecorded_cells', COALESCE((SELECT SUM(ms.unrecorded_count) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
      'total_events', (SELECT COUNT(*) FROM grid_events),
      'past_events', (SELECT COUNT(*) FROM grid_events WHERE date <= CURRENT_DATE),
      'cancelled_events', (SELECT COUNT(*) FROM grid_events WHERE status = 'cancelled'),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'type', ge.type,
      'status', ge.status,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_tribe_event', false,
      'is_future', (ge.date > CURRENT_DATE),
      'is_cancelled', (ge.status = 'cancelled')
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'members', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', gm.id, 'name', gm.name, 'chapter', gm.chapter,
        'member_status', gm.member_status,
        'rate', COALESCE(ms.rate, 0),
        'rate_pct', COALESCE(ms.rate_pct, 0),
        'hours', COALESCE(ms.hours, 0),
        'eligible_count', COALESCE(ms.eligible_count, 0),
        'present_count', COALESCE(ms.present_count, 0),
        'unrecorded_count', COALESCE(ms.unrecorded_count, 0),
        'detractor_status', 'regular',
        'consecutive_absences', 0,
        'attendance', (
          SELECT COALESCE(jsonb_object_agg(cs.event_id::text, cs.status), '{}'::jsonb)
          FROM cell_status cs WHERE cs.member_id = gm.id
        )
      ) ORDER BY COALESCE(ms.rate, 0) ASC), '[]'::jsonb)
      FROM grid_members gm
      LEFT JOIN member_stats ms ON ms.member_id = gm.id
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.exec_tribe_dashboard(p_tribe_id integer, p_cycle text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record; v_caller_tribe_id integer;
  v_tribe record; v_leader record; v_cycle_start date; v_result jsonb;
  v_tribe_initiative_id uuid;
  v_members_total int; v_members_active int; v_members_by_role jsonb; v_members_by_chapter jsonb; v_members_list jsonb;
  v_board record; v_prod_total int := 0; v_prod_by_status jsonb := '{}'::jsonb;
  v_articles_submitted int := 0; v_articles_approved int := 0; v_articles_published int := 0;
  v_curation_pending int := 0; v_avg_days_to_approval numeric := 0;
  v_attendance_rate numeric := 0; v_total_meetings int := 0; v_total_hours numeric := 0;
  v_avg_attendance numeric := 0; v_members_with_streak int := 0; v_members_inactive_30d int := 0;
  v_last_meeting_date date; v_next_meeting jsonb := '{}'::jsonb;
  v_tribe_total_xp int := 0; v_tribe_avg_xp numeric := 0;
  v_top_contributors jsonb := '[]'::jsonb; v_cpmai_certified int := 0;
  v_attendance_by_month jsonb := '[]'::jsonb; v_production_by_month jsonb := '[]'::jsonb;
  v_meeting_slots jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;
  v_caller_tribe_id := public.get_member_tribe(v_caller.id);

  IF v_caller_tribe_id IS DISTINCT FROM p_tribe_id
     AND NOT public.can_by_member(v_caller.id, 'manage_platform')
     AND NOT public.can_by_member(v_caller.id, 'view_chapter_dashboards') THEN
    RAISE EXCEPTION 'Unauthorized: cross-tribe view requires manage_platform or view_chapter_dashboards permission';
  END IF;

  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN RAISE EXCEPTION 'Tribe not found'; END IF;

  SELECT id INTO v_tribe_initiative_id
  FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id AND kind = 'research_tribe'
  LIMIT 1;

  v_cycle_start := (SELECT cycle_start FROM public.cycles WHERE is_current = true LIMIT 1);
  SELECT id, name, photo_url INTO v_leader FROM public.members WHERE id = v_tribe.leader_member_id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('day_of_week', tms.day_of_week, 'time_start', tms.time_start, 'time_end', tms.time_end)), '[]'::jsonb)
  INTO v_meeting_slots
  FROM public.tribe_meeting_slots tms WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true;

  -- #419 metric 4 (PR4-C): member_count = the canonical roster primitive (DISTINCT person with an active,
  -- non-observer-role engagement). Was COUNT(is_active AND EXISTS(kind='volunteer')) = 5 for tribe 8 (the
  -- kind filter dropped curator Roberto). Now the canonical 6. 'active' converges onto the same roster (the
  -- current_cycle_active gate retired in PR4-B; total == active == roster for every tribe today).
  v_members_total := COALESCE(public.get_initiative_roster_count(v_tribe_initiative_id), 0);
  v_members_active := v_members_total;

  SELECT COALESCE(jsonb_object_agg(role, cnt), '{}'::jsonb) INTO v_members_by_role
  FROM (
    SELECT m.operational_role AS role, COUNT(*) AS cnt
    FROM public.members m
    WHERE m.id IN (
      SELECT member_id FROM public.v_initiative_roster WHERE initiative_id = v_tribe_initiative_id
    )
    GROUP BY m.operational_role
  ) sub;

  SELECT COALESCE(jsonb_object_agg(ch, cnt), '{}'::jsonb) INTO v_members_by_chapter
  FROM (
    SELECT COALESCE(m.chapter, 'N/A') AS ch, COUNT(*) AS cnt
    FROM public.members m
    WHERE m.id IN (
      SELECT member_id FROM public.v_initiative_roster WHERE initiative_id = v_tribe_initiative_id
    )
    GROUP BY m.chapter
  ) sub;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', m.id, 'name', m.name, 'chapter', m.chapter, 'operational_role', m.operational_role,
      'xp_total', COALESCE((SELECT SUM(points) FROM public.gamification_points WHERE member_id = m.id), 0),
      'attendance_rate', COALESCE(public.get_attendance_engagement_rate(m.id), 0),
      'attendance_pct', ROUND(COALESCE(public.get_attendance_engagement_rate(m.id), 0) * 100, 1),
      'cpmai_certified', COALESCE(m.cpmai_certified, false),
      'last_activity_at', GREATEST(m.updated_at, (SELECT MAX(a2.created_at) FROM public.attendance a2 WHERE a2.member_id = m.id))
    ) ORDER BY COALESCE((SELECT SUM(points) FROM public.gamification_points WHERE member_id = m.id), 0) DESC
  ), '[]'::jsonb) INTO v_members_list
  FROM public.members m
  WHERE m.id IN (
    SELECT member_id FROM public.v_initiative_roster WHERE initiative_id = v_tribe_initiative_id
  );

  SELECT pb.* INTO v_board
  FROM public.project_boards pb
  JOIN public.initiatives i ON i.id = pb.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id AND pb.domain_key = 'research_delivery' AND pb.is_active = true
  LIMIT 1;

  IF v_board.id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_prod_total FROM public.board_items WHERE board_id = v_board.id;
    SELECT COALESCE(jsonb_object_agg(status, cnt), '{}'::jsonb) INTO v_prod_by_status
    FROM (SELECT status, COUNT(*) AS cnt FROM public.board_items WHERE board_id = v_board.id GROUP BY status) sub;
    SELECT COUNT(*) FILTER (WHERE curation_status IN ('submitted', 'under_review', 'approved', 'published')) INTO v_articles_submitted
    FROM public.board_items WHERE board_id = v_board.id;
    SELECT COUNT(*) FILTER (WHERE curation_status = 'approved') INTO v_articles_approved FROM public.board_items WHERE board_id = v_board.id;
    SELECT COUNT(*) FILTER (WHERE curation_status = 'published') INTO v_articles_published FROM public.board_items WHERE board_id = v_board.id;
    SELECT COUNT(*) FILTER (WHERE curation_status IN ('submitted', 'under_review')) INTO v_curation_pending FROM public.board_items WHERE board_id = v_board.id;
  END IF;

  SELECT COUNT(DISTINCT e.id), COALESCE(SUM(COALESCE(e.duration_actual, e.duration_minutes, 60)) / 60.0, 0)
  INTO v_total_meetings, v_total_hours
  FROM public.events e
  JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE;

  IF v_total_meetings > 0 AND v_members_active > 0 THEN
    v_attendance_rate := COALESCE((public.get_attendance_engagement_summary('tribe', p_tribe_id) ->> 'avg_rate')::numeric, 0);

    SELECT ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(v_total_meetings, 0), 1)
    INTO v_avg_attendance
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE;
  END IF;

  SELECT MAX(e.date) INTO v_last_meeting_date
  FROM public.events e
  JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id AND e.date <= CURRENT_DATE;

  SELECT COUNT(*) INTO v_members_inactive_30d
  FROM public.members m
  WHERE m.id IN (
      SELECT member_id FROM public.v_initiative_roster WHERE initiative_id = v_tribe_initiative_id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.attendance a JOIN public.events e2 ON e2.id = a.event_id
      WHERE a.member_id = m.id AND a.present = true AND e2.date >= (CURRENT_DATE - INTERVAL '30 days')
    );

  SELECT jsonb_build_object('day_of_week', tms.day_of_week, 'time_start', tms.time_start) INTO v_next_meeting
  FROM public.tribe_meeting_slots tms WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true LIMIT 1;

  SELECT COALESCE(SUM(gp.points), 0) INTO v_tribe_total_xp
  FROM public.gamification_points gp
  WHERE gp.member_id IN (
    SELECT member_id FROM public.v_initiative_roster WHERE initiative_id = v_tribe_initiative_id
  );

  v_tribe_avg_xp := CASE WHEN v_members_active > 0 THEN ROUND(v_tribe_total_xp::numeric / v_members_active, 1) ELSE 0 END;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', sub.name, 'xp', sub.xp, 'rank', sub.rn)), '[]'::jsonb) INTO v_top_contributors
  FROM (
    SELECT m.name, SUM(gp.points) AS xp, ROW_NUMBER() OVER (ORDER BY SUM(gp.points) DESC) AS rn
    FROM public.gamification_points gp
    JOIN public.members m ON m.id = gp.member_id
    WHERE m.id IN (
        SELECT member_id FROM public.v_initiative_roster WHERE initiative_id = v_tribe_initiative_id
      )
    GROUP BY m.id, m.name
    ORDER BY xp DESC LIMIT 5
  ) sub;

  SELECT COUNT(*) INTO v_cpmai_certified
  FROM public.members m
  WHERE m.cpmai_certified = true
    AND m.id IN (
      SELECT member_id FROM public.v_initiative_roster WHERE initiative_id = v_tribe_initiative_id
    );

  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', sub.month, 'rate', sub.rate,
    'rate_pct', ROUND(sub.rate * 100, 1)) ORDER BY sub.month), '[]'::jsonb) INTO v_attendance_by_month
  FROM (SELECT TO_CHAR(e.date, 'YYYY-MM') AS month,
      LEAST(ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(COUNT(*), 0), 2), 1.0) AS rate
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
    GROUP BY TO_CHAR(e.date, 'YYYY-MM')) sub;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', sub.month, 'cards_created', sub.created, 'cards_completed', sub.completed) ORDER BY sub.month), '[]'::jsonb) INTO v_production_by_month
  FROM (SELECT TO_CHAR(bi.created_at, 'YYYY-MM') AS month, COUNT(*) AS created,
      COUNT(*) FILTER (WHERE bi.status = 'done') AS completed
    FROM public.board_items bi WHERE bi.board_id = v_board.id AND bi.created_at >= v_cycle_start
    GROUP BY TO_CHAR(bi.created_at, 'YYYY-MM')) sub;

  v_result := jsonb_build_object(
    'tribe', jsonb_build_object('id', v_tribe.id, 'name', v_tribe.name,
      'quadrant', v_tribe.quadrant, 'quadrant_name', v_tribe.quadrant_name,
      'leader', CASE WHEN v_leader.id IS NOT NULL THEN jsonb_build_object('id', v_leader.id, 'name', v_leader.name, 'avatar_url', v_leader.photo_url) ELSE NULL END,
      'meeting_slots', v_meeting_slots, 'drive_url', v_tribe.drive_url),
    'members', jsonb_build_object('total', v_members_total, 'active', v_members_active,
      'by_role', v_members_by_role, 'by_chapter', v_members_by_chapter, 'list', v_members_list),
    'production', jsonb_build_object('total_cards', v_prod_total, 'by_status', v_prod_by_status,
      'articles_submitted', v_articles_submitted, 'articles_approved', v_articles_approved,
      'articles_published', v_articles_published, 'curation_pending', v_curation_pending,
      'avg_days_to_approval', v_avg_days_to_approval),
    'engagement', jsonb_build_object('attendance_rate', v_attendance_rate,
      'attendance_pct', ROUND(v_attendance_rate * 100, 1), 'total_meetings', v_total_meetings,
      'total_hours', ROUND(v_total_hours, 1), 'avg_attendance_per_meeting', v_avg_attendance,
      'members_inactive_30d', v_members_inactive_30d, 'last_meeting_date', v_last_meeting_date, 'next_meeting', v_next_meeting),
    'gamification', jsonb_build_object('tribe_total_xp', v_tribe_total_xp, 'tribe_avg_xp', v_tribe_avg_xp,
      'top_contributors', v_top_contributors,
      'certification_progress', jsonb_build_object('cpmai_certified', v_cpmai_certified)),
    'trends', jsonb_build_object('attendance_by_month', v_attendance_by_month, 'production_by_month', v_production_by_month)
  );
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.exec_cross_initiative_comparison(p_kind text DEFAULT 'research_tribe'::text, p_cycle text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_cycle_start date := (SELECT cycle_start FROM public.cycles WHERE is_current = true LIMIT 1);
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  SELECT jsonb_build_object(
    'initiatives', (
      SELECT jsonb_agg(row_obj ORDER BY sort_kind, sort_tribe, sort_title)
      FROM (
        SELECT
          i.kind AS sort_kind,
          COALESCE(t.id, 9999) AS sort_tribe,
          i.title AS sort_title,
          jsonb_build_object(
            'initiative_id', i.id,
            'initiative_kind', i.kind,
            'initiative_title', i.title,
            'tribe_id', t.id,
            'tribe_name', t.name,
            'quadrant', t.quadrant_name,
            'leader', (
              SELECT m.name FROM public.members m
              WHERE m.id = COALESCE(
                t.leader_member_id,
                (SELECT em.id
                 FROM public.engagements en
                 JOIN public.members em ON em.person_id = en.person_id
                 WHERE en.initiative_id = i.id
                   AND en.status = 'active'
                   AND en.kind ~ '(coordinator|owner|leader|manager)'
                 ORDER BY en.created_at ASC
                 LIMIT 1)
              )
            ),
            'member_count', public.get_initiative_roster_count(i.id),
            'members_inactive_30d', (
              SELECT COUNT(*) FROM public.members m
              WHERE m.id IN (
                  SELECT member_id FROM public.v_initiative_roster
                  WHERE initiative_id = i.id AND member_id IS NOT NULL
                )
                AND m.id NOT IN (
                  SELECT DISTINCT a.member_id FROM public.attendance a
                  JOIN public.events ev ON ev.id = a.event_id
                  WHERE ev.date >= (current_date - 30) AND ev.date <= CURRENT_DATE
                    AND ev.initiative_id = i.id  -- p194 GAP-194.A: strict scope (PM Option A)
                )
            ),
            'total_cards', (
              SELECT COUNT(*) FROM public.board_items bi
              JOIN public.project_boards pb ON pb.id = bi.board_id
              WHERE pb.initiative_id = i.id
            ),
            'cards_completed', (
              SELECT COUNT(*) FROM public.board_items bi
              JOIN public.project_boards pb ON pb.id = bi.board_id
              WHERE pb.initiative_id = i.id
                AND bi.status IN ('done','approved','published')
            ),
            'articles_submitted', (
              SELECT COUNT(*) FROM public.board_lifecycle_events ble
              JOIN public.board_items bi ON bi.id = ble.item_id
              JOIN public.project_boards pb ON pb.id = bi.board_id
              WHERE pb.initiative_id = i.id
                AND ble.action = 'submission'
            ),
            'attendance_rate', CASE WHEN t.id IS NOT NULL THEN COALESCE((public.get_attendance_engagement_summary('tribe', t.id) ->> 'avg_rate')::numeric, 0) ELSE NULL END,
            'attendance_pct', CASE WHEN t.id IS NOT NULL THEN ROUND(COALESCE((public.get_attendance_engagement_summary('tribe', t.id) ->> 'avg_rate')::numeric, 0) * 100, 1) ELSE NULL END,
            'total_hours', (
              SELECT COALESCE(SUM(ev.duration_minutes / 60.0), 0)
              FROM public.attendance a JOIN public.events ev ON ev.id = a.event_id
              WHERE a.member_id IN (
                SELECT member_id FROM public.v_initiative_roster
                WHERE initiative_id = i.id AND member_id IS NOT NULL
              )
              AND ev.date >= v_cycle_start AND ev.date <= CURRENT_DATE
              AND ev.initiative_id = i.id  -- p194 GAP-192.C: strict scope (PM Option B)
            ),
            'meetings_count', (
              SELECT COUNT(*) FROM public.events ev
              WHERE ev.initiative_id = i.id
                AND ev.date >= v_cycle_start AND ev.date <= CURRENT_DATE
            ),
            'total_xp', (
              SELECT COALESCE(SUM(gp.points), 0) FROM public.gamification_points gp
              WHERE gp.member_id IN (
                SELECT member_id FROM public.v_initiative_roster
                WHERE initiative_id = i.id AND member_id IS NOT NULL
              )
            ),
            'avg_xp', (
              SELECT COALESCE(ROUND(AVG(sub.total)::numeric, 1), 0)
              FROM (
                SELECT SUM(gp.points) AS total
                FROM public.gamification_points gp
                WHERE gp.member_id IN (
                  SELECT member_id FROM public.v_initiative_roster
                  WHERE initiative_id = i.id AND member_id IS NOT NULL
                )
                GROUP BY gp.member_id
              ) sub
            ),
            'last_meeting_date', (
              SELECT MAX(ev.date) FROM public.events ev
              WHERE ev.initiative_id = i.id AND ev.date <= CURRENT_DATE
            ),
            'days_since_last_meeting', (
              SELECT EXTRACT(DAY FROM now() - MAX(ev.date)::timestamp)::int
              FROM public.events ev
              WHERE ev.initiative_id = i.id AND ev.date <= CURRENT_DATE
            )
          ) AS row_obj
        FROM public.initiatives i
        LEFT JOIN public.tribes t ON t.id = i.legacy_tribe_id
        WHERE (p_kind IS NULL OR i.kind = p_kind)
          AND i.visibility <> 'confidential'  -- #932: exclude confidential initiative from cross-initiative list
      ) src
    ),
    'kinds_present', (
      SELECT array_to_json(ARRAY(SELECT DISTINCT i.kind FROM public.initiatives i WHERE i.visibility <> 'confidential' ORDER BY i.kind))::jsonb
    ),
    'generated_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.exec_all_tribes_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_cycle_start date;
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

  v_cycle_start := COALESCE(
    (SELECT MIN(date) FROM public.events
     WHERE title ILIKE '%kick%off%' AND date >= '2026-01-01'),
    '2026-03-05'::date
  );

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'tribe_id', t.id,
      'name', t.name,
      'quadrant', t.quadrant,
      'member_count', (SELECT COUNT(*) FROM public.members WHERE tribe_id = t.id AND is_active = true),
      'attendance_pct', COALESCE(
        (SELECT ROUND(
          COUNT(*) FILTER (WHERE a.present = true)::numeric /
          NULLIF(COUNT(*), 0) * 100, 1
        ) FROM public.attendance a
        JOIN public.events e ON e.id = a.event_id
        JOIN public.initiatives i2 ON i2.id = e.initiative_id
        WHERE i2.legacy_tribe_id = t.id AND e.date >= v_cycle_start),
        0
      ),
      'attendance_rate', COALESCE(
        (SELECT ROUND(
          COUNT(*) FILTER (WHERE a.present = true)::numeric /
          NULLIF(COUNT(*), 0), 2
        ) FROM public.attendance a
        JOIN public.events e ON e.id = a.event_id
        JOIN public.initiatives i2 ON i2.id = e.initiative_id
        WHERE i2.legacy_tribe_id = t.id AND e.date >= v_cycle_start),
        0
      ),
      'articles_count', COALESCE(
        (SELECT COUNT(*) FROM public.board_items bi
         JOIN public.project_boards pb ON pb.id = bi.board_id
         JOIN public.initiatives i3 ON i3.id = pb.initiative_id
         WHERE i3.legacy_tribe_id = t.id AND bi.curation_status IN ('submitted', 'approved', 'published')),
        0
      ),
      'xp_total', COALESCE(
        (SELECT SUM(gp.points) FROM public.gamification_points gp
         WHERE gp.member_id IN (SELECT id FROM public.members WHERE tribe_id = t.id AND is_active = true)),
        0
      ),
      'leader_name', (SELECT name FROM public.members WHERE id = t.leader_member_id)
    ) ORDER BY t.id
  ), '[]'::jsonb) INTO v_result
  FROM public.tribes t
  WHERE t.is_active = true AND t.workstream_type = 'research';

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_cycle_attendance_overview(p_cycle_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_is_service boolean;
  v_cycle record;
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

  SELECT cycle_code, cycle_label, cycle_start,
         COALESCE(cycle_end, CURRENT_DATE) AS cycle_end_eff, is_current
  INTO v_cycle
  FROM public.cycles
  WHERE cycle_code = COALESCE(p_cycle_code,
    (SELECT cycle_code FROM public.cycles WHERE is_current = true ORDER BY cycle_start DESC LIMIT 1));

  IF v_cycle.cycle_code IS NULL THEN
    RETURN jsonb_build_object('error', 'Cycle not found: ' || COALESCE(p_cycle_code, '(current)'));
  END IF;

  -- coorte: ciclo corrente -> membros ativos; ciclo passado -> snapshot em member_cycle_history
  -- (#1104 governa o roll-forward). attendance espelha a janela/tipos do get_tribe_gamification:
  -- eventos nao-cancelados em ('geral','kickoff','tribo','lideranca'); denominador exclui excused.
  -- #1476 Onda 2: coorte do ciclo corrente por engagement (junction {researcher,tribe_leader}), nao pelo cache.
  WITH cohort AS (
    SELECT m.id AS member_id, m.name, m.chapter, m.tribe_id
    FROM public.members m
    WHERE v_cycle.is_current AND m.member_status = 'active'
      AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                  WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader'))
    UNION
    SELECT mch.member_id, mch.member_name_snapshot, mch.chapter, mch.tribe_id
    FROM public.member_cycle_history mch
    WHERE NOT v_cycle.is_current AND mch.cycle_code = v_cycle.cycle_code AND mch.is_active
  ),
  att AS (
    SELECT a.member_id,
      count(*) FILTER (WHERE a.present = true) AS present_count,
      count(*) FILTER (WHERE a.present IS NOT TRUE AND a.excused IS NOT TRUE) AS absent_count,
      count(*) FILTER (WHERE a.excused = true) AS excused_count,
      count(*) FILTER (WHERE a.excused IS NOT TRUE) AS eligible_count
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    WHERE e.date >= v_cycle.cycle_start AND e.date <= v_cycle.cycle_end_eff
      AND e.status IS DISTINCT FROM 'cancelled'
      AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
    GROUP BY a.member_id
  )
  SELECT jsonb_build_object(
    'cycle', jsonb_build_object('code', v_cycle.cycle_code, 'label', v_cycle.cycle_label,
       'start', v_cycle.cycle_start, 'end', v_cycle.cycle_end_eff, 'is_current', v_cycle.is_current),
    'total_members', (SELECT count(*) FROM cohort),
    'members', coalesce(jsonb_agg(jsonb_build_object(
       'member_id', c.member_id, 'name', c.name, 'chapter', c.chapter, 'tribe_id', c.tribe_id,
       'present', coalesce(att.present_count, 0),
       'absent', coalesce(att.absent_count, 0),
       'excused', coalesce(att.excused_count, 0),
       'eligible', coalesce(att.eligible_count, 0),
       'attendance_rate', CASE WHEN coalesce(att.eligible_count, 0) > 0
          THEN round(att.present_count::numeric / att.eligible_count, 2) ELSE NULL END,
       'attendance_pct', CASE WHEN coalesce(att.eligible_count, 0) > 0
          THEN round(att.present_count::numeric / att.eligible_count * 100, 1) ELSE NULL END
     ) ORDER BY coalesce(att.present_count, 0) ASC, c.name), '[]'::jsonb),
    'generated_at', now()
  ) INTO v_result
  FROM cohort c
  LEFT JOIN att ON att.member_id = c.member_id;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_tribe_gamification(p_tribe_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_summary jsonb;
  v_members jsonb;
  v_ranking jsonb;
  v_trend jsonb;
  v_total_xp bigint;
  v_member_count int;
  v_cycle_start date;
  v_initiative_id uuid;
  v_member_ids uuid[];
  v_stats jsonb := '{}'::jsonb;
  v_attendance jsonb := '{}'::jsonb;
  v_trail_total int;
  v_trail_completion numeric;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF NOT (
    v_caller.tribe_id = p_tribe_id
    OR public.can_by_member(v_caller.id, 'view_internal_analytics')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;

  -- M4: canonical member cohort (participants-only roster), single source of truth.
  v_initiative_id := public.resolve_initiative_id(p_tribe_id);
  v_member_count := public.get_initiative_roster_count(v_initiative_id);

  -- #425: roster member ids for the batched coaching-stats call.
  SELECT array_agg(member_id) INTO v_member_ids
  FROM v_initiative_roster WHERE initiative_id = v_initiative_id;

  -- #425: streak / active-cycle coaching signals from the canonical RPC (SSOT).
  -- get_member_gamification_stats RAISEs if the caller is not an active member;
  -- a non-active viewer should still get the table, just with zeroed streaks.
  IF v_member_ids IS NOT NULL THEN
    BEGIN
      SELECT COALESCE(jsonb_object_agg(s.member_id::text, jsonb_build_object(
               'current_streak', s.current_streak_count,
               'longest_streak', s.longest_streak_count,
               'active_cycles', s.active_cycles_count
             )), '{}'::jsonb)
      INTO v_stats
      FROM public.get_member_gamification_stats(v_member_ids) s;
    EXCEPTION WHEN insufficient_privilege OR invalid_parameter_value THEN
      -- non-active viewer (insufficient_privilege) or >200-member cap
      -- (invalid_parameter_value): degrade gracefully to zeroed streaks. Any
      -- OTHER error propagates (schema drift / programming bugs must surface).
      v_stats := '{}'::jsonb;
    END;

    -- #576: batch attendance_rate for the whole roster in ONE grouped scan
    -- (was public.get_attendance_rate(member, cycle) per member = N+1). Mirrors
    -- get_attendance_rate's numerator/denominator/event-window; v_cycle_start is
    -- already resolved above (so the fn's COALESCE-to-current-cycle fallback is
    -- unneeded here). Per-member values (incl. the NULL case) are identical.
    SELECT COALESCE(jsonb_object_agg(ar.member_id::text, ar.rate), '{}'::jsonb)
    INTO v_attendance
    FROM (
      SELECT a.member_id,
        ROUND(
          count(*) FILTER (WHERE a.present = true)::numeric
          / NULLIF(count(*) FILTER (WHERE a.excused IS NOT TRUE), 0), 2) AS rate
      FROM attendance a
      JOIN events e ON e.id = a.event_id
      WHERE a.member_id = ANY(v_member_ids)
        AND e.date >= v_cycle_start
        AND e.date <= CURRENT_DATE
        AND e.status IS DISTINCT FROM 'cancelled'
        AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
      GROUP BY a.member_id
    ) ar;
  END IF;

  -- #425: dynamic trail denominator (no hardcoded 6).
  v_trail_total := (SELECT count(*) FROM courses WHERE is_trail = true);

  WITH points_per_member AS (
    SELECT
      gp.member_id,
      SUM(gp.points)::int AS total_points,
      COALESCE(SUM(gp.points) FILTER (WHERE COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start), 0)::int AS cycle_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'presenca'), 0)::int AS attendance_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%'), 0)::int AS cert_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.slug = 'badge'), 0)::int AS badge_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'trilha'), 0)::int AS learning_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'producao'), 0)::int AS producao_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'curadoria'), 0)::int AS curadoria_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'champions'), 0)::int AS champions_points,
      MAX(gp.created_at) AS last_activity_ts
    FROM gamification_points gp
    LEFT JOIN gamification_rules gr
      ON gr.organization_id = gp.organization_id
     AND gr.slug = gp.category
    WHERE gp.member_id = ANY(v_member_ids)
    GROUP BY gp.member_id
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', m.id, 'name', m.name,
    'total_points', COALESCE(p.total_points, 0),
    'cycle_points', COALESCE(p.cycle_points, 0),
    'attendance_points', COALESCE(p.attendance_points, 0),
    'cert_points', COALESCE(p.cert_points, 0),
    'badge_points', COALESCE(p.badge_points, 0),
    'learning_points', COALESCE(p.learning_points, 0),
    'producao_points', COALESCE(p.producao_points, 0),
    'curadoria_points', COALESCE(p.curadoria_points, 0),
    'champions_points', COALESCE(p.champions_points, 0),
    'credly_badge_count', COALESCE(jsonb_array_length(m.credly_badges), 0),
    'has_cpmai', COALESCE(m.cpmai_certified, false),
    -- #425: trail_progress = completed trail COURSES (course_progress, canonical).
    'trail_progress', (
      SELECT count(*) FROM course_progress cp
      WHERE cp.member_id = m.id AND cp.status = 'completed'
        AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)
    ),
    -- #576: attendance_rate served from the pre-batched map (value identical to
    -- the prior per-member public.get_attendance_rate(m.id, v_cycle_start) call).
    'attendance_rate', (v_attendance -> m.id::text),
    'attendance_pct', CASE WHEN (v_attendance ->> m.id::text) IS NULL THEN NULL
      ELSE ROUND((v_attendance ->> m.id::text)::numeric * 100, 1) END,
    'current_streak', COALESCE((v_stats -> m.id::text ->> 'current_streak')::int, 0),
    'longest_streak', COALESCE((v_stats -> m.id::text ->> 'longest_streak')::int, 0),
    'active_cycles', COALESCE((v_stats -> m.id::text ->> 'active_cycles')::int, 0),
    -- #576: last_activity folded into points_per_member's MAX(created_at) — same
    -- value as the prior per-member correlated MAX subquery. last VOLUNTARY
    -- gamification activity (NOT members.last_seen_at — login presence to peers
    -- would be an LGPD Art. 9 minimisation issue).
    'last_activity', to_char(p.last_activity_ts, 'YYYY-MM-DD'),
    'trail_courses', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'course_id', c.id, 'code', c.code, 'name', c.name, 'tier', c.tier,
        'status', COALESCE(cp.status, 'missing')
      ) ORDER BY c.sort_order), '[]'::jsonb)
      FROM courses c
      LEFT JOIN course_progress cp ON cp.course_id = c.id AND cp.member_id = m.id
      WHERE c.is_trail = true
    )
  ) ORDER BY COALESCE(p.total_points, 0) DESC), '[]'::jsonb)
  INTO v_members
  FROM members m
  LEFT JOIN points_per_member p ON p.member_id = m.id
  WHERE m.id = ANY(v_member_ids);

  SELECT COALESCE(SUM((elem->>'total_points')::bigint), 0)
  INTO v_total_xp
  FROM jsonb_array_elements(v_members) elem;

  -- #425: real trail completion = AVG over roster of (completed/total), fraction 0..1.
  SELECT ROUND(AVG(member_pct), 2) INTO v_trail_completion
  FROM (
    SELECT (
      SELECT count(*) FROM course_progress cp
      WHERE cp.member_id = rm.member_id AND cp.status = 'completed'
        AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)
    )::numeric / NULLIF(v_trail_total, 0) AS member_pct
    FROM (SELECT DISTINCT u AS member_id FROM unnest(v_member_ids) u) rm
  ) sub;

  v_summary := jsonb_build_object(
    'total_xp', v_total_xp,
    'avg_xp', CASE WHEN v_member_count > 0 THEN ROUND(v_total_xp::numeric / v_member_count) ELSE 0 END,
    'tribe_rank', (
      WITH tribe_totals AS (
        SELECT t.id AS tid, COALESCE(SUM(gp.points), 0) AS txp
        FROM tribes t
        LEFT JOIN (SELECT DISTINCT legacy_tribe_id, member_id FROM v_initiative_roster) m2 ON m2.legacy_tribe_id = t.id
        LEFT JOIN gamification_points gp ON gp.member_id = m2.member_id
        WHERE t.is_active = true
        GROUP BY t.id
      ),
      ranked AS (
        SELECT tid, RANK() OVER (ORDER BY txp DESC) AS rk FROM tribe_totals
      )
      SELECT rk FROM ranked WHERE tid = p_tribe_id
    ),
    'cert_coverage', CASE WHEN v_member_count > 0 THEN ROUND(
      (SELECT count(*) FROM members
        WHERE id = ANY(v_member_ids)
        AND (cpmai_certified = true OR jsonb_array_length(COALESCE(credly_badges, '[]'::jsonb)) > 0)
      )::numeric / v_member_count, 2
    ) ELSE 0 END,
    'trail_completion', COALESCE(v_trail_completion, 0)
  );

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'tribe_id', sub.tid,
      'tribe_name', sub.tname,
      'tribe_name_i18n', sub.tname_i18n,
      'total_xp', sub.txp
    )
    ORDER BY sub.txp DESC
  ), '[]'::jsonb)
  INTO v_ranking
  FROM (
    SELECT t.id AS tid, t.name AS tname, t.name_i18n AS tname_i18n, COALESCE(SUM(gp.points), 0) AS txp
    FROM tribes t
    LEFT JOIN (SELECT DISTINCT legacy_tribe_id, member_id FROM v_initiative_roster) m4 ON m4.legacy_tribe_id = t.id
    LEFT JOIN gamification_points gp ON gp.member_id = m4.member_id
    WHERE t.is_active = true
    GROUP BY t.id, t.name, t.name_i18n
  ) sub;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'xp', month_xp) ORDER BY month), '[]'::jsonb)
  INTO v_trend
  FROM (
    SELECT date_trunc('month', gp.created_at) AS month, SUM(gp.points) AS month_xp
    FROM gamification_points gp
    WHERE gp.member_id = ANY(v_member_ids)
      AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start
    GROUP BY date_trunc('month', gp.created_at)
  ) sub;

  RETURN jsonb_build_object('summary', v_summary, 'members', v_members, 'tribe_ranking', v_ranking, 'monthly_trend', v_trend);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_initiative_gamification(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_tribe_id int;
  v_result jsonb;
  v_cycle_start date;
  v_member_ids uuid[];
  v_stats jsonb := '{}'::jsonb;
  v_attendance jsonb := '{}'::jsonb;
  v_trail_total int;
BEGIN
  -- #785 PR-3: confidential gate (covers both the tribe-delegated and standalone paths)
  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- #576 (item 5): resolve routing FIRST so tribe-backed initiatives delegate to
  -- get_tribe_gamification (which runs its own auth gate) without a redundant
  -- members-by-auth_id fetch here. The standalone path authenticates below.
  -- Output is identical: a non-member still gets 'Unauthorized' either way.
  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_gamification(v_tribe_id);
  END IF;

  -- standalone (non-tribe) initiative path: authenticate the caller.
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  -- #600 (#419 M4 residual, sibling of #465/#468): initiative-scoped authority gate —
  -- mirrors get_tribe_gamification's gate (tribe member OR view_internal_analytics).
  -- Without it ANY authenticated member could read ANY standalone initiative's roster
  -- (names + per-pillar XP). Membership = any ACTIVE engagement on the initiative
  -- (observers included — they are initiative insiders; the participants-only filter
  -- applies to who is LISTED, not who may view). Fail-closed default per ADR-0007.
  IF NOT (
    EXISTS (
      SELECT 1 FROM engagements e
      WHERE e.initiative_id = p_initiative_id
        AND e.status = 'active'
        AND e.person_id = v_caller.person_id
    )
    OR public.can_by_member(v_caller.id, 'view_internal_analytics')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;

  SELECT array_agg(DISTINCT m.id) INTO v_member_ids
  FROM v_initiative_roster vir JOIN members m ON m.id = vir.member_id
  WHERE vir.initiative_id = p_initiative_id;

  -- #425: streak / active-cycle coaching signals (SSOT), guarded for non-active viewers.
  IF v_member_ids IS NOT NULL THEN
    BEGIN
      SELECT COALESCE(jsonb_object_agg(s.member_id::text, jsonb_build_object(
               'current_streak', s.current_streak_count,
               'longest_streak', s.longest_streak_count,
               'active_cycles', s.active_cycles_count
             )), '{}'::jsonb)
      INTO v_stats
      FROM public.get_member_gamification_stats(v_member_ids) s;
    EXCEPTION WHEN insufficient_privilege OR invalid_parameter_value THEN
      -- non-active viewer (insufficient_privilege) or >200-member cap
      -- (invalid_parameter_value): degrade gracefully to zeroed streaks. Any
      -- OTHER error propagates (schema drift / programming bugs must surface).
      v_stats := '{}'::jsonb;
    END;

    -- #576: batch attendance_rate (was get_attendance_rate per member = N+1).
    SELECT COALESCE(jsonb_object_agg(ar.member_id::text, ar.rate), '{}'::jsonb)
    INTO v_attendance
    FROM (
      SELECT a.member_id,
        ROUND(
          count(*) FILTER (WHERE a.present = true)::numeric
          / NULLIF(count(*) FILTER (WHERE a.excused IS NOT TRUE), 0), 2) AS rate
      FROM attendance a
      JOIN events e ON e.id = a.event_id
      WHERE a.member_id = ANY(v_member_ids)
        AND e.date >= v_cycle_start
        AND e.date <= CURRENT_DATE
        AND e.status IS DISTINCT FROM 'cancelled'
        AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
      GROUP BY a.member_id
    ) ar;
  END IF;

  v_trail_total := (SELECT count(*) FROM courses WHERE is_trail = true);

  WITH init_members AS MATERIALIZED (
    SELECT DISTINCT m.id, m.name, m.cpmai_certified, m.credly_badges
    FROM v_initiative_roster vir
    JOIN members m ON m.id = vir.member_id
    WHERE vir.initiative_id = p_initiative_id
  ),
  points_per_member AS (
    SELECT
      gp.member_id,
      SUM(gp.points)::int AS total_points,
      COALESCE(SUM(gp.points) FILTER (WHERE COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start), 0)::int AS cycle_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'presenca'), 0)::int AS attendance_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%'), 0)::int AS cert_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.slug = 'badge'), 0)::int AS badge_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'trilha'), 0)::int AS learning_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'producao'), 0)::int AS producao_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'curadoria'), 0)::int AS curadoria_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'champions'), 0)::int AS champions_points,
      MAX(gp.created_at) AS last_activity_ts
    FROM gamification_points gp
    JOIN init_members im ON im.id = gp.member_id
    LEFT JOIN gamification_rules gr
      ON gr.organization_id = gp.organization_id
     AND gr.slug = gp.category
    GROUP BY gp.member_id
  ),
  member_data AS MATERIALIZED (
    SELECT im.id, im.name,
           COALESCE(p.total_points, 0) AS total_points,
           COALESCE(p.cycle_points, 0) AS cycle_points,
           COALESCE(p.attendance_points, 0) AS attendance_points,
           COALESCE(p.cert_points, 0) AS cert_points,
           COALESCE(p.badge_points, 0) AS badge_points,
           COALESCE(p.learning_points, 0) AS learning_points,
           COALESCE(p.producao_points, 0) AS producao_points,
           COALESCE(p.curadoria_points, 0) AS curadoria_points,
           COALESCE(p.champions_points, 0) AS champions_points,
           COALESCE(jsonb_array_length(im.credly_badges), 0) AS credly_badge_count,
           COALESCE(im.cpmai_certified, false) AS has_cpmai,
           p.last_activity_ts AS last_activity_ts,
           (SELECT count(*) FROM course_progress cp
             WHERE cp.member_id = im.id AND cp.status = 'completed'
               AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)) AS trail_progress
    FROM init_members im
    LEFT JOIN points_per_member p ON p.member_id = im.id
  ),
  v_members AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', md.id, 'name', md.name,
      'total_points', md.total_points, 'cycle_points', md.cycle_points,
      'attendance_points', md.attendance_points, 'cert_points', md.cert_points,
      'badge_points', md.badge_points, 'learning_points', md.learning_points,
      'producao_points', md.producao_points, 'curadoria_points', md.curadoria_points,
      'champions_points', md.champions_points,
      'credly_badge_count', md.credly_badge_count,
      'has_cpmai', md.has_cpmai,
      'trail_progress', md.trail_progress,
      -- #576: attendance_rate from the pre-batched map (value identical to the
      -- prior per-member public.get_attendance_rate(md.id, v_cycle_start) call).
      'attendance_rate', (v_attendance -> md.id::text),
      'attendance_pct', CASE WHEN (v_attendance ->> md.id::text) IS NULL THEN NULL
        ELSE ROUND((v_attendance ->> md.id::text)::numeric * 100, 1) END,
      'current_streak', COALESCE((v_stats -> md.id::text ->> 'current_streak')::int, 0),
      'longest_streak', COALESCE((v_stats -> md.id::text ->> 'longest_streak')::int, 0),
      'active_cycles', COALESCE((v_stats -> md.id::text ->> 'active_cycles')::int, 0),
      -- #576: last_activity folded into points_per_member's MAX(created_at).
      'last_activity', to_char(md.last_activity_ts, 'YYYY-MM-DD'),
      'trail_courses', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'course_id', c.id, 'code', c.code, 'name', c.name, 'tier', c.tier,
          'status', COALESCE(cp.status, 'missing')
        ) ORDER BY c.sort_order), '[]'::jsonb)
        FROM courses c
        LEFT JOIN course_progress cp ON cp.course_id = c.id AND cp.member_id = md.id
        WHERE c.is_trail = true
      )
    ) ORDER BY md.total_points DESC), '[]'::jsonb) AS members_json
    FROM member_data md
  ),
  v_trend AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'xp', month_xp) ORDER BY month), '[]'::jsonb) AS trend_json
    FROM (
      SELECT date_trunc('month', gp.created_at) AS month, SUM(gp.points) AS month_xp
      FROM gamification_points gp
      JOIN init_members im ON im.id = gp.member_id
      WHERE COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start
      GROUP BY date_trunc('month', gp.created_at)
    ) sub
  ),
  v_trail AS (
    SELECT ROUND(AVG(member_pct), 2) AS pct FROM (
      SELECT (
        SELECT count(*) FROM course_progress cp
        WHERE cp.member_id = im.id AND cp.status = 'completed'
          AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)
      )::numeric / NULLIF(v_trail_total, 0) AS member_pct
      FROM init_members im
    ) s
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_xp', COALESCE((SELECT SUM(total_points) FROM member_data), 0),
      'avg_xp', CASE WHEN (SELECT count(*) FROM member_data) > 0
                THEN ROUND((SELECT SUM(total_points) FROM member_data)::numeric / (SELECT count(*) FROM member_data))
                ELSE 0 END,
      'tribe_rank', NULL,
      'cert_coverage', CASE WHEN (SELECT count(*) FROM member_data) > 0
                       THEN ROUND((SELECT count(*) FROM member_data WHERE has_cpmai OR credly_badge_count > 0)::numeric / (SELECT count(*) FROM member_data), 2)
                       ELSE 0 END,
      'trail_completion', COALESCE((SELECT pct FROM v_trail), 0)
    ),
    'members', (SELECT members_json FROM v_members),
    'tribe_ranking', '[]'::jsonb,
    'monthly_trend', (SELECT trend_json FROM v_trend)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_attendance_engagement_summary(p_scope text DEFAULT 'global'::text, p_scope_id integer DEFAULT NULL::integer, p_cycle_start date DEFAULT NULL::date, p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH cohort AS (
    SELECT m.id
    FROM public.members m
    WHERE CASE
      WHEN p_scope = 'chapter' THEN (m.member_status = 'active' AND m.chapter = p_chapter)
      ELSE (
        m.is_active = true AND m.current_cycle_active = true
        AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                    WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
        AND (
          p_scope = 'global'
          OR (p_scope = 'tribe' AND public.get_member_tribe(m.id) = p_scope_id)
        )
      )
    END
  ),
  rates AS (
    SELECT c.id, public.get_attendance_engagement_rate(c.id, p_cycle_start) AS rate
    FROM cohort c
  ),
  totals AS (
    SELECT
      count(*) FILTER (WHERE att.present = true)        AS present_total,
      count(*) FILTER (WHERE att.excused IS NOT TRUE)   AS expected_total,
      count(*) FILTER (WHERE att.excused = true)        AS excused_total
    FROM cohort c
    CROSS JOIN LATERAL public._attendance_eligible_events(c.id, p_cycle_start) el
    LEFT JOIN public.attendance att ON att.member_id = c.id AND att.event_id = el.event_id
  )
  SELECT jsonb_build_object(
    'scope', p_scope,
    'scope_id', p_scope_id,
    'cohort_n', (SELECT count(*) FROM rates WHERE rate IS NOT NULL),
    'avg_rate', (SELECT ROUND(AVG(rate), 4) FROM rates WHERE rate IS NOT NULL),
    'avg_pct', (SELECT ROUND(AVG(rate) * 100, 1) FROM rates WHERE rate IS NOT NULL),
    'at_risk_count', (SELECT count(*) FROM rates WHERE rate IS NOT NULL AND rate < 0.50),
    'present_total', (SELECT present_total FROM totals),
    'expected_total', (SELECT expected_total FROM totals),
    'excused_total', (SELECT excused_total FROM totals),
    'coverage_flag', CASE WHEN (SELECT count(*) FROM rates WHERE rate IS NOT NULL) = 0 THEN 'no_data' ELSE 'ok' END
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_attendance_reliability_summary(p_scope text DEFAULT 'global'::text, p_scope_id integer DEFAULT NULL::integer, p_cycle_start date DEFAULT NULL::date, p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH cohort AS (
    SELECT m.id
    FROM public.members m
    WHERE CASE
      WHEN p_scope = 'chapter' THEN (m.member_status = 'active' AND m.chapter = p_chapter)
      ELSE (
        m.is_active = true AND m.current_cycle_active = true
        AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                    WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
        AND (
          p_scope = 'global'
          OR (p_scope = 'tribe' AND public.get_member_tribe(m.id) = p_scope_id)
        )
      )
    END
  ),
  rates AS (
    SELECT c.id, public.get_attendance_rate(c.id, p_cycle_start) AS rate
    FROM cohort c
  ),
  recorded AS (
    SELECT
      count(*) FILTER (WHERE att.present = true)                          AS present_total,
      count(*) FILTER (WHERE att.present = false AND att.excused IS NOT TRUE) AS absent_total,
      count(*) FILTER (WHERE att.excused = true)                          AS excused_total
    FROM cohort c
    JOIN public.attendance att ON att.member_id = c.id
    JOIN public.events e ON e.id = att.event_id
    WHERE e.date >= COALESCE(p_cycle_start, (SELECT cy.cycle_start FROM public.cycles cy WHERE cy.is_current = true LIMIT 1))
      AND e.date <= CURRENT_DATE
      AND e.status IS DISTINCT FROM 'cancelled'
      AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
  ),
  elig AS (
    SELECT count(*) AS eligible_total
    FROM cohort c
    CROSS JOIN LATERAL public._attendance_eligible_events(c.id, p_cycle_start) el
  )
  SELECT jsonb_build_object(
    'scope', p_scope,
    'scope_id', p_scope_id,
    'cohort_n', (SELECT count(*) FROM rates WHERE rate IS NOT NULL),
    'avg_rate', (SELECT ROUND(AVG(rate), 4) FROM rates WHERE rate IS NOT NULL),
    'avg_pct', (SELECT ROUND(AVG(rate) * 100, 1) FROM rates WHERE rate IS NOT NULL),
    'present_total', (SELECT present_total FROM recorded),
    'absent_total', (SELECT absent_total FROM recorded),
    'excused_total', (SELECT excused_total FROM recorded),
    'eligible_total', (SELECT eligible_total FROM elig),
    'coverage_flag', CASE
      WHEN (SELECT eligible_total FROM elig) = 0 THEN 'no_data'
      WHEN ((SELECT present_total + absent_total + excused_total FROM recorded))::numeric / NULLIF((SELECT eligible_total FROM elig), 0) >= 0.90 THEN 'complete'
      WHEN ((SELECT present_total + absent_total + excused_total FROM recorded))::numeric / NULLIF((SELECT eligible_total FROM elig), 0) >= 0.50 THEN 'partial'
      ELSE 'sparse'
    END
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_tribe_stats(p_tribe_id integer)
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH cycle AS (SELECT cycle_start FROM cycles WHERE is_current LIMIT 1),
  tribe_members AS (
    SELECT DISTINCT vir.member_id AS id
    FROM v_initiative_roster vir
    WHERE vir.legacy_tribe_id = p_tribe_id AND vir.member_id IS NOT NULL
  ),
  tribe_events AS (
    SELECT e.id, e.duration_minutes
    FROM events e
    JOIN initiatives i ON i.id = e.initiative_id
    CROSS JOIN cycle c
    WHERE i.legacy_tribe_id = p_tribe_id AND e.type = 'tribo'
      AND e.date >= c.cycle_start AND e.date <= current_date
  ),
  att AS (
    SELECT a.event_id, a.member_id FROM attendance a
    JOIN tribe_events te ON te.id = a.event_id
    WHERE a.excused IS NOT TRUE
  ),
  tribe_boards AS (
    SELECT bi.id, bi.status FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    JOIN initiatives i ON i.id = pb.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id
  )
  SELECT json_build_object(
    'member_count', public.get_initiative_roster_count(public.resolve_initiative_id(p_tribe_id)),
    'events_held', (SELECT count(*) FROM tribe_events),
    'attendance_rate', ROUND((public.get_attendance_engagement_summary('tribe', p_tribe_id) ->> 'avg_rate')::numeric * 100, 1),
    -- #1656: mesmo valor sob o nome que declara a escala. 'attendance_rate' aqui SEMPRE foi 0-100,
    -- contra a convencao; e o par que sustentava o coalesce 'rate <= 1' no front.
    'attendance_pct', ROUND((public.get_attendance_engagement_summary('tribe', p_tribe_id) ->> 'avg_rate')::numeric * 100, 1),
    'impact_hours', (SELECT coalesce(round(sum(te.duration_minutes * sub.c)::numeric / 60, 1), 0)
      FROM tribe_events te JOIN (SELECT event_id, count(*) c FROM att GROUP BY event_id) sub ON sub.event_id = te.id),
    'cards_backlog', (SELECT count(*) FROM tribe_boards WHERE status = 'backlog'),
    'cards_in_progress', (SELECT count(*) FROM tribe_boards WHERE status = 'in_progress'),
    'cards_review', (SELECT count(*) FROM tribe_boards WHERE status = 'review'),
    'cards_done', (SELECT count(*) FROM tribe_boards WHERE status = 'done'),
    'top_contributors', (SELECT coalesce(json_agg(row_to_json(r) ORDER BY r.att_count DESC), '[]')
      FROM (
        SELECT m.name, count(a2.event_id) as att_count,
          round(count(a2.event_id)::numeric / NULLIF((SELECT count(*) FROM tribe_events), 0) * 100, 0) as rate
        FROM tribe_members tm
        JOIN members m ON m.id = tm.id
        LEFT JOIN att a2 ON a2.member_id = tm.id
        GROUP BY m.name
      ) r
    )
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_initiative_stats(p_initiative_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
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
      ) FROM att a),
      -- #1656: mesmo valor sob o nome que declara a escala (ja era 0-100).
      'attendance_pct', (SELECT round(
        count(a.*)::numeric / NULLIF((SELECT count(*) FROM init_members) * (SELECT count(*) FROM init_events), 0) * 100, 0
      ) FROM att a),
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
$$;
