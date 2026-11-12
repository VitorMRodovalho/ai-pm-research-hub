-- #3048: reuniao de tribo e devida pelo PERIODO do vinculo com aquela tribo, nao pela tribo atual.
-- Corpos de partida conferidos contra o banco vivo em 12/11/2026 (md5 normalizado igual ao da captura
-- mais recente de cada funcao). CREATE OR REPLACE mantem os grants das cinco funcoes existentes.

CREATE OR REPLACE FUNCTION public._member_engaged_on(
  p_member_id uuid, p_initiative_id uuid, p_date date, p_kind text DEFAULT NULL)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- #3048: a pessoa tinha vinculo com a iniciativa NESTA data? Periodo = start_date ate o fim,
  -- e o fim e end_date; para vinculo suspenso sem end_date, o dia anterior ao inicio da pausa
  -- (metadata.pause.since); para encerrado sem end_date, a data da ultima alteracao; senao aberto.
  SELECT EXISTS (
    SELECT 1
    FROM public.members m
    JOIN public.engagements en ON en.person_id = m.person_id
    WHERE m.id = p_member_id
      AND en.initiative_id = p_initiative_id
      AND (p_kind IS NULL OR en.kind = p_kind)
      AND en.status IN ('active', 'suspended', 'offboarded', 'expired')
      AND p_date >= en.start_date
      AND p_date <= COALESCE(
            en.end_date,
            CASE WHEN en.status = 'suspended' THEN (en.metadata -> 'pause' ->> 'since')::date - 1 END,
            CASE WHEN en.status IN ('offboarded', 'expired') THEN en.updated_at::date END,
            'infinity'::date)
  );
$function$;

REVOKE ALL ON FUNCTION public._member_engaged_on(uuid, uuid, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._member_engaged_on(uuid, uuid, date, text) TO authenticated, service_role;

COMMENT ON FUNCTION public._member_engaged_on(uuid, uuid, date, text) IS
  '#3048: vinculo com a iniciativa cobre a data (periodo start_date..fim, pausa e encerramento sem end_date incluidos). Base da elegibilidade de reuniao de tribo.';

CREATE OR REPLACE FUNCTION public._attendance_eligible_events(p_member_id uuid, p_cycle_start date DEFAULT NULL::date)
 RETURNS TABLE(event_id uuid, event_type text, event_date date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH win AS (
    SELECT
      COALESCE(p_cycle_start, (SELECT c.cycle_start FROM public.cycles c WHERE c.is_current = true LIMIT 1)) AS start_date,
      LEAST(COALESCE((SELECT c.cycle_end FROM public.cycles c WHERE c.is_current = true LIMIT 1), CURRENT_DATE), CURRENT_DATE) AS end_date
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
      e.type IN ('geral', 'kickoff')
      -- #3048: reuniao de tribo e devida no PERIODO do vinculo com AQUELA tribo, nao pela tribo
      -- atual. Quem entra no meio do ciclo nao deve as reunioes anteriores; quem troca de tribo
      -- continua devendo (e tendo) as da tribo anterior enquanto estava nela. Presenca registrada
      -- nunca some: cobre vinculo cadastrado com data de inicio posterior a presenca real.
      OR (e.type = 'tribo' AND e.initiative_id IS NOT NULL AND (
            (EXISTS (SELECT 1 FROM public.engagements v3048 JOIN public.members w3048 ON w3048.person_id = v3048.person_id WHERE w3048.id = p_member_id AND v3048.initiative_id = e.initiative_id AND v3048.kind = 'volunteer')
             AND public._member_engaged_on(p_member_id, e.initiative_id, e.date, 'volunteer'))
            OR EXISTS (SELECT 1 FROM public.attendance a3048 WHERE a3048.member_id = p_member_id AND a3048.event_id = e.id AND a3048.present)))
      OR (e.type = 'lideranca' AND public.can_by_member(p_member_id, 'manage_event'))
    );
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
        WHEN ge.type IN ('geral', 'kickoff') THEN true
        -- #3048: so no periodo do vinculo com a tribo; fora dele a celula e 'na', nao falta.
        WHEN ge.type = 'tribo' AND ge.tribe_id = p_tribe_id THEN (
          public._member_engaged_on(m.id, ge.initiative_id, ge.date, 'volunteer')
          OR EXISTS (SELECT 1 FROM public.attendance a3048 WHERE a3048.member_id = m.id AND a3048.event_id = ge.id AND a3048.present))
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
        -- #3048: fora do periodo do vinculo com a iniciativa a celula e 'na' (nem falta, nem
        -- "sem registro"), salvo presenca registrada.
        WHEN NOT (public._member_engaged_on(gm.id, p_initiative_id, ge.date)
                  OR (a.id IS NOT NULL AND a.present = true)) THEN 'na'
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
      'is_cancelled', (ge.status = 'cancelled'),
      -- #1710: a TERCEIRA grade tambem aplica a regra do #1657 (sem linha em evento nao selado e
      -- 'unrecorded') e tambem nao dizia por que. As tres publicam o mesmo carimbo.
      'roster_sealed_at', ge.roster_sealed_at
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

CREATE OR REPLACE FUNCTION public._seal_event_attendance_apply(
  p_event_id uuid, p_actor_id uuid, p_dry_run boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_type      text;
  v_status    text;
  v_date      date;
  v_title     text;
  v_org       uuid;
  v_sealed_at timestamptz;
  v_end       timestamptz;
  v_eligible  int := 0;
  v_recorded  int := 0;
  v_sealed    int := 0;
  v_pre_entry int := 0;
  -- #2426: a janela do ciclo, resolvida UMA vez. Era avaliada por membro, dentro de
  -- `_attendance_eligible_events`, e e a guarda que impede o selo manual de um evento
  -- anterior ao ciclo gravar faltas que hoje nao existem.
  v_win_start date;
  v_win_end   date;
  v_tribe_id  int;
  v_initiative_id uuid;
BEGIN
  SELECT e.type, e.status, e.date, e.title, e.organization_id, e.roster_sealed_at,
         public._event_end_instant(e.date, e.time_start, e.duration_minutes, e.timezone)
    INTO v_type, v_status, v_date, v_title, v_org, v_sealed_at, v_end
  FROM public.events e WHERE e.id = p_event_id;

  IF v_type IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento não encontrado', 'event_id', p_event_id);
  END IF;
  IF v_type NOT IN ('geral','kickoff','tribo','lideranca') THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Tipo de evento não elegível para presença (' || v_type || ')', 'event_id', p_event_id);
  END IF;
  IF v_status = 'cancelled' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento cancelado não pode ser selado', 'event_id', p_event_id);
  END IF;
  -- #1727: comparar DATA em UTC deixava passar a reuniao de hoje a noite, marcando falta de quem
  -- ainda ia comparecer. O corte e por INSTANTE, pela funcao compartilhada.
  IF v_end > now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento ainda não terminou',
      'event_id', p_event_id, 'ends_at', v_end);
  END IF;

  -- #2426: janela do ciclo + tribo do evento, resolvidas uma vez fora de qualquer laco.
  SELECT c.cycle_start, LEAST(COALESCE(c.cycle_end, CURRENT_DATE), CURRENT_DATE)
    INTO v_win_start, v_win_end
  FROM public.cycles c WHERE c.is_current = true LIMIT 1;

  SELECT i.legacy_tribe_id, i.id INTO v_tribe_id, v_initiative_id
  FROM public.initiatives i WHERE i.id = (SELECT e2.initiative_id FROM public.events e2 WHERE e2.id = p_event_id);

  -- Fora da janela do ciclo a coorte e vazia, exatamente como antes (o filtro morava dentro de
  -- `_attendance_eligible_events`). Cai no mesmo desfecho de coorte vazia, logo abaixo.
  IF v_win_start IS NULL OR v_date < v_win_start OR v_date > v_win_end THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Coorte elegível vazia: evento não selado',
      'reason', 'skipped_empty_cohort',
      'event_id', p_event_id, 'event_title', v_title, 'event_date', v_date,
      'eligible_cohort_n', 0, 'roster_sealed_at', v_sealed_at);
  END IF;

  -- A coorte e quantos dela ja tem registro saem da MESMA passagem: assim o numero que o ensaio
  -- publica e o numero que a gravacao produz, e nao duas contas que podem divergir.
  -- #1476 Onda 2: coorte operacional por engagement (junction), nao pelo cache operational_role.
  -- #1948: a coorte NAO muda — quem entrou depois do evento continua nela, e a distincao vai na
  -- COLUNA da linha, nao na presenca dela. Tirar da coorte quebraria "selado => linha existe".
  WITH coorte AS (
    SELECT m.id, (v_date < public._member_operational_since(m.id)) AS pre_entry
    FROM public.members m
    WHERE m.is_active = true AND m.current_cycle_active = true
      AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                  WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
      -- #2426: so o ramo que depende do MEMBRO. O resto ja foi resolvido acima.
      AND (
        v_type IN ('geral','kickoff')
        OR (v_type = 'tribo' AND v_tribe_id IS NOT NULL AND public._member_engaged_on(m.id, v_initiative_id, v_date, 'volunteer'))
        OR (v_type = 'lideranca' AND public.can_by_member(m.id, 'manage_event'))
      )
  )
  SELECT count(*)::int, count(a.member_id)::int,
         count(*) FILTER (WHERE c.pre_entry AND a.member_id IS NULL)::int
    INTO v_eligible, v_recorded, v_pre_entry
  FROM coorte c
  LEFT JOIN public.attendance a ON a.event_id = p_event_id AND a.member_id = c.id;

  -- #1729: coorte vazia NAO e evento a selar. Carimbar aqui marcaria "lista fechada" num evento que
  -- nunca teve lista, e a partir do carimbo a grade passa a ler ausencia de linha como falta.
  IF v_eligible = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Coorte elegível vazia: evento não selado',
      'reason', 'skipped_empty_cohort',
      'event_id', p_event_id,
      'event_title', v_title,
      'event_date', v_date,
      'eligible_cohort_n', 0,
      'roster_sealed_at', v_sealed_at
    );
  END IF;

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'success', true,
      'dry_run', true,
      'event_id', p_event_id,
      'event_title', v_title,
      'event_type', v_type,
      'event_date', v_date,
      'eligible_cohort_n', v_eligible,
      'already_recorded_count', v_recorded,
      'would_write_absent_n', GREATEST(v_eligible - v_recorded - v_pre_entry, 0),
      -- #1948: o ensaio separa as duas naturezas. Sem isto o PM le "N faltas" e algumas nao sao.
      'would_write_excused_pre_entry_n', v_pre_entry,
      'roster_sealed_at', v_sealed_at
    );
  END IF;

  INSERT INTO public.attendance (event_id, member_id, present, excused, excuse_reason, organization_id, notes, registered_by, marked_by, checked_in_at)
  SELECT p_event_id, m.id, false,
         s.pre_entry,
         CASE WHEN s.pre_entry THEN 'Ingresso posterior ao evento (#1948)' END,
         v_org, public._roster_seal_marker(), p_actor_id, p_actor_id, NULL
  FROM public.members m
  CROSS JOIN LATERAL (SELECT (v_date < public._member_operational_since(m.id)) AS pre_entry) s
  WHERE m.is_active = true AND m.current_cycle_active = true
    AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
    -- #2426: MESMA condicao do CTE acima. Os dois caminhos mudam juntos, senao ensaio e ato divergem.
    AND (
      v_type IN ('geral','kickoff')
      OR (v_type = 'tribo' AND v_tribe_id IS NOT NULL AND public._member_engaged_on(m.id, v_initiative_id, v_date, 'volunteer'))
      OR (v_type = 'lideranca' AND public.can_by_member(m.id, 'manage_event'))
    )
  ON CONFLICT (event_id, member_id) DO NOTHING;
  GET DIAGNOSTICS v_sealed = ROW_COUNT;

  UPDATE public.events SET roster_sealed_at = COALESCE(roster_sealed_at, now())
  WHERE id = p_event_id
  RETURNING roster_sealed_at INTO v_sealed_at;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (p_actor_id, 'attendance.roster_sealed', 'event', p_event_id,
    jsonb_build_object(
      'event_title', v_title, 'event_date', v_date, 'event_type', v_type,
      'eligible_cohort_n', v_eligible, 'sealed_absent_count', GREATEST(v_sealed - v_pre_entry, 0),
      'sealed_excused_pre_entry_count', v_pre_entry,
      'roster_sealed_at', v_sealed_at,
      -- Cron e suite de teste tem a MESMA digital (`service_role`, ator nulo). O carimbo e o unico
      -- jeito de o log distinguir um selo automatico de um selo escrito por um teste.
      'source', CASE WHEN p_actor_id IS NULL THEN 'window_cron' ELSE 'manual' END));

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'event_title', v_title,
    'event_type', v_type,
    'event_date', v_date,
    'eligible_cohort_n', v_eligible,
    'sealed_absent_count', GREATEST(v_sealed - v_pre_entry, 0),
    'sealed_excused_pre_entry_count', v_pre_entry,
    'already_recorded_count', GREATEST(v_eligible - v_sealed, 0),
    'roster_sealed_at', v_sealed_at
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
