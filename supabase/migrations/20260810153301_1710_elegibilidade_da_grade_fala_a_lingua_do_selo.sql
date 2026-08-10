-- #1710 (passo 2): a elegibilidade da grade passa a falar a mesma lingua da coorte do selo.
--
-- Decisao do PM em 10/08/2026, sobre duas perguntas de REGRA (nao de codigo):
--   1. sponsor e chapter_liaison fora do tier operacional NAO sao cobrados de presenca em
--      reuniao geral;
--   2. gestor sem tribo propria NAO e elegivel a reuniao de tribo.
--
-- Por que isso e pre-requisito do selo automatico. Medido em 10/08, ciclo corrente:
--   selar os 53 eventos gravaria 121 linhas de falta reais (53 pessoas) E faria 133 celulas
--   virarem 'absent' SEM nenhuma linha (16 pessoas), porque o ramo ELSE da grade infere falta
--   quando roster_sealed_at esta preenchido. Era a acusacao inferida que o #1657 removeu,
--   voltando pela porta do selo. As 133 se decompunham em 93 (gestor x reuniao de tribo, 2
--   pessoas), 25 (chapter_liaison x geral, 9) e 15 (sponsor x geral, 5) — todas sem tribo.
--
-- Nas 12 tribos as duas metricas ja convergiam: simulando o selo, a taxa primitiva (a que
-- alimenta XP e painel) cai de 100,0% para exatamente o avg_rate_pct que a grade ja publica,
-- com delta 0,0 pp em 10 tribos e -0,1 nas outras duas. So o grupo sem tribo divergia, em
-- +64,4 pp. Este ajuste fecha essa divergencia pela restricao, que foi a decisao.
--
-- ⚠️ O predicado e o TIER, nao o operational_role: 2 chapter_liaison ESTAO no tier
-- (researcher/tribe_leader/manager). Sao vocabularios diferentes de autoridade.
--
-- ⚠️ E 'na' passa a exigir AUSENCIA DE REGISTRO. Sem isso, restringir a elegibilidade
-- apagaria da tela 5 presencas reais, e zeraria a coorte historica do #156 (0 de 34
-- ex-membros estao no tier, mas 29 tem presenca registrada).

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
      -- #1655: este filtro derrubava o evento ORG-WIDE que so carrega initiative_id por
      -- proveniencia. Medido em 10/08: 1 evento 'geral' (58 linhas de presenca, todas presentes)
      -- sumia SO desta grade: a de tribo e a de iniciativa ja o mostravam. comms/evento_externo
      -- seguem fora, porque a audiencia deles E a iniciativa.
      AND (e.initiative_id IS NULL OR e.type IN ('tribo', 'geral', 'kickoff', 'lideranca'))
      -- ADR-0105: a contencao de iniciativa confidencial deixa de ser efeito colateral do filtro
      -- acima (que dependia do tipo do evento) e passa a ser o gate canonico, aplicado sempre.
      AND (e.initiative_id IS NULL OR public.rls_can_see_initiative(e.initiative_id))
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
        -- #1710: a elegibilidade da grade passa a falar a MESMA lingua da coorte de
        -- seal_event_attendance, que e o TIER operacional. Medido em 10/08: 14 pessoas
        -- (5 sponsor + 9 chapter_liaison, todas sem tribo) apareciam devendo presenca em
        -- reuniao geral, e o selo nunca as alcancaria: o ELSE 'absent' as acusaria sem
        -- nenhum registro. Filtrar por operational_role seria ERRADO: 2 chapter_liaison
        -- ESTAO no tier. operational_role e operational_tier sao vocabularios distintos.
        WHEN NOT EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                         WHERE vt.member_id = m.id
                           AND vt.operational_tier IN ('researcher', 'tribe_leader', 'manager')) THEN false
        WHEN ge.type IN ('geral', 'kickoff') THEN true
        -- #1710: o gestor sem tribo propria NAO e elegivel a reuniao de tribo. A grade dizia
        -- que sim, e a TODAS (93 celulas para 2 pessoas); _attendance_eligible_events diz que
        -- nao, porque exige tribo propria. Era o maior pedaco da divergencia entre as coortes.
        WHEN ge.type = 'tribo' AND (m.tribe_id = ge.tribe_id OR (p_tribe_id IS NOT NULL AND ge.tribe_id = p_tribe_id)) THEN true
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
        -- #1710: 'na' significa "fora da conta", nunca "apague o que aconteceu". Restringir a
        -- elegibilidade acima tiraria da tela 5 presencas REAIS (2 de quem sai pelo tier, 3 de
        -- gestor em reuniao de tribo) e mantem escondidas outras 3 que ja estavam. E o que deixa a
        -- coorte historica do #156 continuar visivel: 0 de 34 ex-membros estao no tier, mas 29 tem
        -- presenca registrada. Sem registro, fora da conta; COM registro, mostra o registro.
        WHEN NOT el.is_eligible AND a.id IS NULL THEN 'na'
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
    'tribes', (SELECT COALESCE(jsonb_agg(tribe_row ORDER BY sort_key, tribe_row->>'tribe_name'), '[]'::jsonb) FROM (
      SELECT t.sort_key, jsonb_build_object(
        'tribe_id', t.id_json, 'tribe_name', t.name,
        'leader_name', COALESCE((
          SELECT m2.name FROM public.members m2
          WHERE m2.operational_role = 'tribe_leader'
            AND public.get_member_tribe(m2.id) = t.real_id
          LIMIT 1
        ), '—'),
        'avg_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN active_members_scoped am ON am.id = ms.member_id WHERE am.tribe_id IS NOT DISTINCT FROM t.real_id), 0),
        'avg_rate_pct', COALESCE((SELECT ROUND(AVG(ms.rate_pct), 1) FROM member_stats ms JOIN active_members_scoped am ON am.id = ms.member_id WHERE am.tribe_id IS NOT DISTINCT FROM t.real_id), 0),
        'member_count', (SELECT COUNT(*) FROM active_members_scoped am WHERE am.tribe_id IS NOT DISTINCT FROM t.real_id),
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
          WHERE am.tribe_id IS NOT DISTINCT FROM t.real_id)
      ) AS tribe_row
      -- #1655: as tribos reais, mais UM grupo sintetico para quem nao tem tribo. Sem ele a
      -- funcao contava os sem-tribo em 'total_members' e nunca lhes dava linha: medido em 10/08,
      -- o resumo dizia 83 e o corpo renderizava 66. Das 17 pessoas sem linha, 3 estao na coorte de
      -- seal_event_attendance, que gravaria falta em quem nao tem tela onde ser marcado (#1710).
      FROM (
        SELECT to_jsonb(t0.id) AS id_json, t0.name AS name, t0.id AS real_id, 0 AS sort_key
        FROM public.tribes t0
        WHERE t0.is_active = true AND (p_tribe_id IS NULL OR t0.id = p_tribe_id)
        UNION ALL
        SELECT to_jsonb('__cross_functional__'::text), 'Cross-functional', NULL::integer, 1
        WHERE p_tribe_id IS NULL
          AND EXISTS (SELECT 1 FROM active_members_scoped ams WHERE ams.tribe_id IS NULL)
      ) t
    ) sub)
  ) INTO v_result;
  RETURN v_result;
END;
$function$;
