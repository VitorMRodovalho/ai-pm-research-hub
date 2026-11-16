-- Metricas do ciclo 4: presenca devida so a partir da entrada no Nucleo, e presenca desfeita
-- estorna o credito de XP.
--
-- ── 1. Elegibilidade de reuniao geral, kickoff e lideranca ─────────────────────────────────────
-- `_attendance_eligible_events` contava geral e kickoff para TODA pessoa desde o inicio do ciclo,
-- sem condicao, e lideranca por `can_by_member(..., 'manage_event')` avaliado HOJE. So o ramo de
-- tribo respeitava o periodo do vinculo (#3048).
--
-- O selo (`_seal_event_attendance_apply`, #1948) grava linha justificada "Ingresso posterior" para
-- quem entrou depois do evento, mas cada evento e selado UMA vez. Quem entra depois do selo fica
-- sem linha, e os leitores (LEFT JOIN + excused IS NOT TRUE) contavam a ausencia de linha como
-- falta. Nas grades, "selado + sem linha" vira 'absent' e alimenta o alerta de detrator.
--
-- A data de corte e `_member_operational_since`, e nao uma regra nova: e a SSOT que o #1948 criou
-- para "desde quando esta pessoa podia ser esperada numa reuniao" (min(granted_at) de qualquer
-- engajamento, revogados incluidos; senao members.created_at), e e a data que o selo ja usa. Medido
-- em 16/11/2026 na populacao ativa: para quem entrou no ciclo 4 ela coincide com o menor
-- start_date de engajamento; para quem entrou antes, as duas sao anteriores ao inicio do ciclo e o
-- corte nao muda nada. Nenhuma linha de FALTA real (nao justificada) cai fora da conta: o corte so
-- remove eventos sem linha nenhuma. Presenca registrada antes da data continua contando.
--
-- Leitores afetados (todos pela funcao, nenhum muda de assinatura): get_attendance_panel,
-- get_attendance_engagement_rate, get_attendance_engagement_summary,
-- get_attendance_reliability_summary, get_dropout_risk_members, get_member_detail,
-- get_admin_dashboard (alerta de detrator) e preview_seal_attendance. As duas grades tem copia
-- propria da regra e recebem o mesmo corte aqui, para painel e grade continuarem publicando o
-- mesmo numero (#1656).
--
-- ── 2. get_attendance_panel ignorava p_cycle_end ───────────────────────────────────────────────
-- O parametro existia e nao cortava nada. Nenhum chamador o passa hoje (frontend, MCP), entao o
-- filtro so tem efeito para quem passar a usa-lo.
--
-- ── 3. Presenca desfeita estorna o credito ─────────────────────────────────────────────────────
-- `clear_member_attendance` estorna (#2292), mas os caminhos que trocam presente por falta ou por
-- justificativa sem apagar a linha (mark_member_present(false), mark_member_excused,
-- bulk_mark_excused, admin_bulk_mark_attendance) nao estornavam. O placar continuava contando
-- presenca que a tabela nega, que e o defeito 1 da #2292. Um gatilho cobre os quatro caminhos e os
-- que vierem. O ledger segue append-only (#1087 onda 3): estorno e linha nova, negativa. Se a
-- presenca voltar, o worker de credito re-credita, porque de-duplica por SALDO (#2292c).

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 1. Elegibilidade canonica: geral, kickoff e lideranca a partir da entrada no Nucleo.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._attendance_eligible_events(p_member_id uuid, p_cycle_start date DEFAULT NULL::date)
 RETURNS TABLE(event_id uuid, event_type text, event_date date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH win AS (
    SELECT
      COALESCE(p_cycle_start, (SELECT c.cycle_start FROM public.cycles c WHERE c.is_current = true LIMIT 1)) AS start_date,
      LEAST(COALESCE((SELECT c.cycle_end FROM public.cycles c WHERE c.is_current = true LIMIT 1), CURRENT_DATE), CURRENT_DATE) AS end_date,
      -- Entrada no Nucleo: a MESMA data que o selo usa para gravar "Ingresso posterior" (#1948).
      -- Resolvida uma vez por chamada. Sem data conhecida, nada e cortado (comportamento anterior).
      COALESCE(public._member_operational_since(p_member_id), '-infinity'::date) AS since
  )
  SELECT e.id, e.type, e.date
  FROM public.events e, win
  WHERE win.start_date IS NOT NULL
    AND e.date >= win.start_date
    AND e.date <= win.end_date
    -- #1727: a borda de data e UTC e nao sabe que horas sao. Sem isto, a reuniao de hoje a noite ja
    -- conta como esperada desde a madrugada.
    AND public._event_end_instant(e.date, e.time_start, e.duration_minutes, e.timezone) <= now()
    AND e.status IS DISTINCT FROM 'cancelled'
    AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
    AND (
      -- Reuniao geral, kickoff e lideranca so sao devidas a partir da ENTRADA da pessoa no Nucleo.
      -- O selo grava linha justificada para quem entrou depois, mas sela cada evento UMA vez: quem
      -- entra depois do selo fica sem linha, e o LEFT JOIN dos leitores contava isso como falta.
      -- Presenca registrada nunca some, como no ramo de tribo.
      (e.type IN ('geral', 'kickoff')
       AND (e.date >= win.since
            OR EXISTS (SELECT 1 FROM public.attendance a_ent WHERE a_ent.member_id = p_member_id AND a_ent.event_id = e.id AND a_ent.present)))
      -- #3048: reuniao de tribo e devida no PERIODO do vinculo com AQUELA tribo, nao pela tribo
      -- atual. Quem entra no meio do ciclo nao deve as reunioes anteriores; quem troca de tribo
      -- continua devendo (e tendo) as da tribo anterior enquanto estava nela. Presenca registrada
      -- nunca some: cobre vinculo cadastrado com data de inicio posterior a presenca real.
      OR (e.type = 'tribo' AND e.initiative_id IS NOT NULL AND (
            (EXISTS (SELECT 1 FROM public.engagements v3048 JOIN public.members w3048 ON w3048.person_id = v3048.person_id WHERE w3048.id = p_member_id AND v3048.initiative_id = e.initiative_id AND v3048.kind = 'volunteer')
             AND public._member_engaged_on(p_member_id, e.initiative_id, e.date, 'volunteer'))
            OR EXISTS (SELECT 1 FROM public.attendance a3048 WHERE a3048.member_id = p_member_id AND a3048.event_id = e.id AND a3048.present)))
      OR (e.type = 'lideranca' AND public.can_by_member(p_member_id, 'manage_event')
          AND (e.date >= win.since
               OR EXISTS (SELECT 1 FROM public.attendance a_ent WHERE a_ent.member_id = p_member_id AND a_ent.event_id = e.id AND a_ent.present)))
    );
$function$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 2. Painel: p_cycle_end corta o fim da janela.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_attendance_panel(p_cycle_start date DEFAULT NULL::date, p_cycle_end date DEFAULT NULL::date)
 RETURNS TABLE(member_id uuid, member_name text, tribe_name text, tribe_id integer, operational_role text, general_mandatory integer, general_attended integer, general_pct numeric, tribe_mandatory integer, tribe_attended integer, tribe_pct numeric, combined_pct numeric, last_attendance date, dropout_risk boolean, typology text, cohort_avg_pct numeric, cohort_percentile numeric, cohort_size integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_privileged boolean := false;
BEGIN
  -- D2 gate: require an active member (never serve anon/ghost).
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RETURN; -- anon / ghost / inactive: no rows
  END IF;
  -- Leadership (tribe leaders + GP) see the full nominal ranking + dropout_risk/typology.
  v_privileged := public.can_by_member(v_caller_id, 'manage_event');

  RETURN QUERY
  WITH active AS (
    SELECT m.id, m.name AS m_name, tr.name AS t_name, m.tribe_id AS t_id,
           m.operational_role AS op_role, m.current_cycle_active AS cca,
           (m.designations IS NOT NULL AND m.designations @> ARRAY['curator']::text[]) AS is_curator
    FROM public.members m LEFT JOIN public.tribes tr ON tr.id = m.tribe_id
    WHERE m.is_active = true
  ),
  -- p277 #419 PR7: CANONICAL eligibility (type-based, per-member) — general = non-tribo eligible events
  -- (geral/kickoff/lideranca, mirrors the old general_meeting grouping), tribe = tribo eligible events.
  -- Excused excluded from the mandatory denominator (D1).
  per_member AS (
    SELECT a.id AS mid,
      count(*) FILTER (WHERE el.event_type <> 'tribo' AND att.excused IS NOT TRUE)::int AS g_mand,
      count(*) FILTER (WHERE el.event_type <> 'tribo' AND att.present = true)::int       AS g_att,
      count(*) FILTER (WHERE el.event_type =  'tribo' AND att.excused IS NOT TRUE)::int  AS t_mand,
      count(*) FILTER (WHERE el.event_type =  'tribo' AND att.present = true)::int        AS t_att
    FROM active a
    CROSS JOIN LATERAL public._attendance_eligible_events(a.id, p_cycle_start) el
    LEFT JOIN public.attendance att ON att.member_id = a.id AND att.event_id = el.event_id
    -- p_cycle_end era aceito e ignorado. Nenhum chamador o passa hoje, entao NULL mantem tudo igual.
    WHERE p_cycle_end IS NULL OR el.event_date <= p_cycle_end
    GROUP BY a.id
  ),
  last_att AS (
    SELECT a.member_id, MAX(e.date::date) AS last_date
    FROM public.attendance a JOIN public.events e ON e.id = a.event_id
    WHERE a.present = true GROUP BY a.member_id
  ),
  computed AS (
    SELECT a.id, a.m_name, a.t_name, a.t_id, a.op_role, a.is_curator, a.cca,
      COALESCE(pm.g_mand,0) AS g_mand, COALESCE(pm.g_att,0) AS g_att,
      CASE WHEN COALESCE(pm.g_mand,0)>0 THEN ROUND(pm.g_att::numeric/pm.g_mand*100,1) ELSE 0 END AS g_pct,
      COALESCE(pm.t_mand,0) AS t_mand, COALESCE(pm.t_att,0) AS t_att,
      CASE WHEN COALESCE(pm.t_mand,0)>0 THEN ROUND(pm.t_att::numeric/pm.t_mand*100,1) ELSE 0 END AS t_pct,
      CASE WHEN COALESCE(pm.g_mand,0)+COALESCE(pm.t_mand,0)>0
        THEN ROUND((COALESCE(pm.g_att,0)+COALESCE(pm.t_att,0))::numeric/(COALESCE(pm.g_mand,0)+COALESCE(pm.t_mand,0))*100,1)
        ELSE 0 END AS c_pct,
      la.last_date
    FROM active a
    LEFT JOIN per_member pm ON pm.mid = a.id
    LEFT JOIN last_att la ON la.member_id = a.id
  ),
  -- C+B anonymous aggregate (PR7 review MED): the peer population MUST equal the CANONICAL engagement cohort
  -- (current_cycle_active + operational union {researcher,tribe_leader,manager}, non-curator, with eligible
  -- events) so the non-privileged standing card's cohort_avg_pct == the public home headline 76.2. Using the
  -- looser "any active member with eligible events" set dragged it to 53.7 (50 ppl incl observers / NULL-tribe
  -- researchers outside the cycle) — a cross-surface disagreement on the same metric to the same user. The
  -- NOMINAL ranking (privileged leaders, the final SELECT below) is unaffected — leaders still see ALL active.
  cohort AS (
    SELECT ROUND(AVG(c.c_pct), 1) AS avg_pct, COUNT(*)::int AS sz
    FROM computed c
    WHERE (c.g_mand + c.t_mand) > 0 AND NOT c.is_curator
      AND c.cca = true AND c.op_role IN ('researcher','tribe_leader','manager')
  ),
  caller AS (
    SELECT
      ROUND(100.0 * (
        SELECT COUNT(*) FROM computed c2
        WHERE (c2.g_mand + c2.t_mand) > 0 AND NOT c2.is_curator
          AND c2.cca = true AND c2.op_role IN ('researcher','tribe_leader','manager') AND c2.c_pct < c.c_pct
      ) / NULLIF((SELECT COUNT(*) FROM computed c3 WHERE (c3.g_mand + c3.t_mand) > 0 AND NOT c3.is_curator
          AND c3.cca = true AND c3.op_role IN ('researcher','tribe_leader','manager')), 0), 0) AS ahead_pct
    FROM computed c WHERE c.id = v_caller_id
  )
  SELECT c.id, c.m_name, c.t_name, c.t_id, c.op_role,
    c.g_mand::int, c.g_att::int, c.g_pct, c.t_mand::int, c.t_att::int, c.t_pct,
    c.c_pct, c.last_date,
    CASE WHEN v_privileged OR c.id = v_caller_id
      THEN (NOT c.is_curator AND (c.g_mand + c.t_mand) > 0 AND c.c_pct < 50)
      ELSE NULL END AS dropout_risk,
    CASE WHEN v_privileged OR c.id = v_caller_id THEN
      CASE
        WHEN c.is_curator                               THEN 'curator'
        WHEN c.g_mand + c.t_mand = 0                    THEN 'no-data'
        WHEN c.c_pct >= 70                              THEN 'healthy'
        WHEN c.c_pct >= 50                              THEN 'borderline'
        WHEN c.g_pct < 30 AND c.t_pct >= 50             THEN 'missing-general'
        WHEN c.t_pct < 30 AND c.g_pct >= 50             THEN 'missing-tribe'
        WHEN c.c_pct < 30                               THEN 'missing-both'
        ELSE 'balanced-low'
      END
      ELSE NULL END AS typology,
    CASE WHEN NOT v_privileged AND c.id = v_caller_id THEN (SELECT avg_pct FROM cohort) ELSE NULL END AS cohort_avg_pct,
    CASE WHEN NOT v_privileged AND c.id = v_caller_id THEN (SELECT ahead_pct FROM caller) ELSE NULL END AS cohort_percentile,
    CASE WHEN NOT v_privileged AND c.id = v_caller_id THEN (SELECT sz FROM cohort) ELSE NULL END AS cohort_size
  FROM computed c
  WHERE v_privileged OR c.id = v_caller_id
  ORDER BY c.m_name;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 3. As duas grades com a mesma regra de entrada (painel e grade publicam o mesmo numero, #1656).
-- ─────────────────────────────────────────────────────────────────────────────────────────────
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
           i.legacy_tribe_id AS tribe_id, e.initiative_id,
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
        -- Mesma regra de _attendance_eligible_events: geral, kickoff e lideranca so a partir da
        -- ENTRADA no Nucleo. Sem isto, quem entrou depois do selo aparece com falta ('absent')
        -- em reuniao anterior a entrada, e o alerta de detrator conta essas faltas.
        WHEN ge.type IN ('geral', 'kickoff', 'lideranca') AND ge.date < ent.since
             AND NOT EXISTS (SELECT 1 FROM public.attendance a_ent WHERE a_ent.member_id = m.id AND a_ent.event_id = ge.id AND a_ent.present) THEN false
        WHEN ge.type IN ('geral', 'kickoff') THEN true
        -- #1710: o gestor sem tribo propria NAO e elegivel a reuniao de tribo. A grade dizia
        -- que sim, e a TODAS (93 celulas para 2 pessoas); _attendance_eligible_events diz que
        -- nao, porque exige tribo propria. Era o maior pedaco da divergencia entre as coortes.
        -- #3048: a MESMA regra de _attendance_eligible_events: periodo do vinculo com a tribo do
        -- evento, ou presenca registrada. Antes era a tribo atual, e quem trocou de tribo devia as
        -- reunioes da nova desde o inicio do ciclo.
        WHEN ge.type = 'tribo' AND ge.initiative_id IS NOT NULL THEN (
          (EXISTS (SELECT 1 FROM public.engagements v3048 JOIN public.members w3048 ON w3048.person_id = v3048.person_id WHERE w3048.id = m.id AND v3048.initiative_id = ge.initiative_id AND v3048.kind = 'volunteer')
           AND public._member_engaged_on(m.id, ge.initiative_id, ge.date, 'volunteer'))
          OR EXISTS (SELECT 1 FROM public.attendance a3048 WHERE a3048.member_id = m.id AND a3048.event_id = ge.id AND a3048.present))
        WHEN ge.type = 'lideranca' AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader') THEN true
        WHEN ge.type = 'comms' AND m.designations && ARRAY['comms_team', 'comms_leader', 'comms_member'] THEN true
        ELSE false
      END AS is_eligible
    FROM cohort_members m CROSS JOIN LATERAL (SELECT COALESCE(public._member_operational_since(m.id), '-infinity'::date) AS since) ent CROSS JOIN grid_events ge
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
      'is_cancelled', (ge.status = 'cancelled'),
      -- #1710: o carimbo do selo sai NA GRADE. Sem ele a tela mostra 'unrecorded' e 'absent' lado
      -- a lado sem dizer o que separa os dois, que e exatamente o ato de selar o evento.
      'roster_sealed_at', ge.roster_sealed_at
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
    SELECT e.id, e.date, e.title, e.title_i18n, e.type, e.status, e.roster_sealed_at, i.legacy_tribe_id AS tribe_id, e.initiative_id,
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
    SELECT re.id, re.date, re.title, re.title_i18n, re.type, re.status, re.roster_sealed_at, re.tribe_id, re.initiative_id,
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
        -- Mesma regra de _attendance_eligible_events: geral, kickoff e lideranca so a partir da
        -- ENTRADA no Nucleo. Sem isto, quem entrou depois do selo aparece com falta ('absent')
        -- em reuniao anterior a entrada, e o alerta de detrator conta essas faltas.
        WHEN ge.type IN ('geral', 'kickoff', 'lideranca') AND ge.date < ent.since
             AND NOT EXISTS (SELECT 1 FROM public.attendance a_ent WHERE a_ent.member_id = m.id AND a_ent.event_id = ge.id AND a_ent.present) THEN false
        WHEN ge.type IN ('geral', 'kickoff') THEN true
        -- #3048: so no periodo do vinculo com a tribo; fora dele a celula e 'na', nao falta.
        WHEN ge.type = 'tribo' AND ge.tribe_id = p_tribe_id THEN (
          public._member_engaged_on(m.id, ge.initiative_id, ge.date, 'volunteer')
          OR EXISTS (SELECT 1 FROM public.attendance a3048 WHERE a3048.member_id = m.id AND a3048.event_id = ge.id AND a3048.present))
        WHEN ge.type = 'lideranca' AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader') THEN true
        ELSE false
      END AS is_eligible
    FROM grid_members m CROSS JOIN LATERAL (SELECT COALESCE(public._member_operational_since(m.id), '-infinity'::date) AS since) ent CROSS JOIN grid_events ge
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
      'is_cancelled', (ge.status = 'cancelled'),
      -- #1710: mesmo carimbo da outra grade. As duas leem roster_sealed_at para decidir a celula;
      -- so uma delas o publicava, e nenhuma o mostrava.
      'roster_sealed_at', ge.roster_sealed_at
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

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 4. Presenca desfeita (presente -> falta ou justificativa) estorna o saldo de XP do evento.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._reverse_attendance_credit_on_presence_withdrawn()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  -- O saldo resolve os DOIS formatos historicos de ref_id, como clear_member_attendance. So saldo
  -- POSITIVO e estornado: chamada repetida, ou credito ja estornado, vira no-op.
  INSERT INTO public.gamification_points (member_id, organization_id, points, category, reason, ref_id, granted_by)
  SELECT s.member_id, s.organization_id, -s.pts, 'attendance',
         'Estorno (presença desfeita: o registro passou a falta ou justificativa)', NEW.event_id,
         (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid())
    FROM (
      SELECT gp.member_id, gp.organization_id, SUM(gp.points) AS pts
        FROM public.gamification_points gp
        LEFT JOIN public.attendance a2 ON a2.id = gp.ref_id
       WHERE gp.category = 'attendance'
         AND gp.member_id = NEW.member_id
         AND COALESCE(a2.event_id, gp.ref_id) = NEW.event_id
       GROUP BY gp.member_id, gp.organization_id
      HAVING SUM(gp.points) > 0
    ) s;
  RETURN NULL;
END;
$function$;

COMMENT ON FUNCTION public._reverse_attendance_credit_on_presence_withdrawn() IS
  'Presenca que deixa de ser presenca (UPDATE de present true para false) estorna o saldo de XP '
  'de presenca daquele evento, com linha negativa (ledger append-only, #1087 onda 3). Mesmo molde '
  'do estorno de clear_member_attendance (#2292). Re-marcar presente re-credita pelo worker.';

REVOKE ALL ON FUNCTION public._reverse_attendance_credit_on_presence_withdrawn() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_reverse_attendance_credit_on_presence_withdrawn ON public.attendance;
CREATE TRIGGER trg_reverse_attendance_credit_on_presence_withdrawn
  AFTER UPDATE OF present ON public.attendance
  FOR EACH ROW
  WHEN (OLD.present IS TRUE AND NEW.present IS NOT TRUE)
  EXECUTE FUNCTION public._reverse_attendance_credit_on_presence_withdrawn();
