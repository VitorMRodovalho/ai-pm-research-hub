-- #1710 — o selo de presenca ganha ESCOPO, REVERSAO e carimbo na grade.
--
-- Contexto medido em 13/08/2026 (re-medir: os tres se movem sozinhos):
--   510 eventos passados, 0 selados; 55 eventos que o selo alcanca hoje (ciclo 4, desde 09/07);
--   111 faltas materializaveis sobre 44 pessoas, a pior individual com 9.
--
-- Esta migration NAO liga o selo. Ela prepara o terreno para a superficie e fecha uma porta que so
-- nao doia enquanto ninguem podia clicar:
--
-- 1. `_roster_seal_marker()` — o carimbo das linhas do selo passa a ter UMA definicao. Quem grava e
--    quem reverte leem a mesma; duas copias divergem na primeira manutencao e a reversao vira
--    no-op silencioso. (Medido antes de trocar o texto: 0 linhas com o carimbo antigo, entao a
--    troca nao orfana nada.)
--
-- 2. `seal_event_attendance` deixa de usar um gate SEM RECURSO. Medido em 13/08 impersonando os 14
--    portadores de `manage_event`: 622 pares (lider, evento) passavam pelo gate amplo e NAO passam
--    pelo escopado — cada um dos 12 lideres de tribo alcancava de 49 a 55 eventos de outras tribos.
--    Os 2 gestores alcancam os 60, como se espera. Mesma classe do #1728.
--
-- 3. `unseal_event_attendance` — a reversao por evento que o PM exigiu e que nao existia. Reverter
--    passa a ser um ato com nome, gate por recurso e registro de auditoria.
--
-- 4. As duas grades passam a PUBLICAR `roster_sealed_at`. As duas ja o LIAM para decidir a celula
--    entre 'unrecorded' e 'absent', e nenhuma o mostrava: a tela exibia a consequencia do selo sem
--    nunca dizer que o selo existe.
--
-- 5. `preview_seal_attendance` passa a listar so o que o CHAMADOR pode selar. Sem isto o painel
--    mostraria 60 eventos para quem pode selar 8, e cada botao errado seria uma escrita em massa no
--    historico de outra tribo.
--
-- As duas grades foram regeradas a partir do corpo VIVO (a unica mudanca e a chave nova); os quatro
-- primeiros blocos sao autorais. O arquivo inteiro e derivado de `pg_proc` depois de aplicado, para
-- que captura e corpo vivo nao possam divergir.

CREATE OR REPLACE FUNCTION public._roster_seal_marker()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- O prefixo `[roster_seal]` e o contrato durável: e por ele que uma linha nascida do selo se
  -- distingue de uma falta registrada por gente. Quem grava (seal_event_attendance) e quem apaga
  -- (unseal_event_attendance) chamam ESTA funcao, nunca o literal.
  SELECT '[roster_seal] falta materializada pelo selo do evento'::text;
$function$;

CREATE OR REPLACE FUNCTION public.seal_event_attendance(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_type      text;
  v_status    text;
  v_date      date;
  v_title     text;
  v_org       uuid;
  v_sealed_at timestamptz;
  v_end       timestamptz;
  v_eligible  int := 0;
  v_sealed    int := 0;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT e.type, e.status, e.date, e.title, e.organization_id, e.roster_sealed_at,
         public._event_end_instant(e.date, e.time_start, e.duration_minutes, e.timezone)
    INTO v_type, v_status, v_date, v_title, v_org, v_sealed_at, v_end
  FROM public.events e WHERE e.id = p_event_id;

  IF v_type IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento não encontrado', 'event_id', p_event_id);
  END IF;

  -- #1710: era `can_by_member(v_caller_id, 'manage_event')`, um gate SEM recurso — quem podia
  -- gerir algum evento podia selar QUALQUER um. Medido em 13/08/2026 impersonando os 14 portadores
  -- de manage_event: 622 pares (lider, evento) passavam pelo gate amplo e nao pelo escopado; cada
  -- um dos 12 lideres de tribo alcancava de 49 a 55 eventos de OUTRAS tribos, e selar grava falta
  -- em massa. Mesma classe do #1728; aqui o custo subiu porque este ato ganhou botao.
  -- A checagem vem depois do lookup de proposito, para que "não encontrado" continue dizendo isso.
  IF NOT public._can_manage_event(p_event_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Acesso negado: requer manage_event neste evento');
  END IF;

  IF v_type NOT IN ('geral','kickoff','tribo','lideranca') THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Tipo de evento não elegível para presença (' || v_type || ')', 'event_id', p_event_id);
  END IF;
  IF v_status = 'cancelled' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento cancelado não pode ser selado', 'event_id', p_event_id);
  END IF;
  -- #1727: era `v_date > CURRENT_DATE`, comparacao de data em UTC. Uma reuniao de hoje a noite nao
  -- era "futura" para ela, entao selar naquele momento marcava falta de quem ainda ia comparecer.
  IF v_end > now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento ainda não terminou',
      'event_id', p_event_id, 'ends_at', v_end);
  END IF;

  -- eligible operational cohort for THIS event (canonical eligibility only — SPEC §3b)
  -- #1476 Onda 2: coorte operacional por engagement (junction), não pelo cache operational_role.
  SELECT count(*) INTO v_eligible
  FROM public.members m
  WHERE m.is_active = true AND m.current_cycle_active = true
    AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
    AND EXISTS (
      SELECT 1 FROM public._attendance_eligible_events(m.id, NULL) ee WHERE ee.event_id = p_event_id
    );

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

  -- materialize an absent row for every eligible no-show (no existing row) — idempotent, non-destructive
  INSERT INTO public.attendance (event_id, member_id, present, excused, organization_id, notes, registered_by, marked_by, checked_in_at)
  SELECT p_event_id, m.id, false, false, v_org,
         public._roster_seal_marker(), v_caller_id, v_caller_id, NULL
  FROM public.members m
  WHERE m.is_active = true AND m.current_cycle_active = true
    AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
    AND EXISTS (
      SELECT 1 FROM public._attendance_eligible_events(m.id, NULL) ee WHERE ee.event_id = p_event_id
    )
  ON CONFLICT (event_id, member_id) DO NOTHING;
  GET DIAGNOSTICS v_sealed = ROW_COUNT;

  UPDATE public.events SET roster_sealed_at = COALESCE(roster_sealed_at, now())
  WHERE id = p_event_id
  RETURNING roster_sealed_at INTO v_sealed_at;

  -- #1710: escrita em massa no historico de gente real precisa deixar quem, quando e quanto. Sem
  -- isto, a unica evidencia do ato e o proprio dano.
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (v_caller_id, 'attendance.roster_sealed', 'event', p_event_id,
    jsonb_build_object(
      'event_title', v_title, 'event_date', v_date, 'event_type', v_type,
      'eligible_cohort_n', v_eligible, 'sealed_absent_count', v_sealed,
      'roster_sealed_at', v_sealed_at));

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'event_title', v_title,
    'event_type', v_type,
    'event_date', v_date,
    'eligible_cohort_n', v_eligible,
    'sealed_absent_count', v_sealed,
    'already_recorded_count', GREATEST(v_eligible - v_sealed, 0),
    'roster_sealed_at', v_sealed_at
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.unseal_event_attendance(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_title     text;
  v_date      date;
  v_sealed_at timestamptz;
  v_removed   int := 0;
  v_kept      int := 0;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT e.title, e.date, e.roster_sealed_at INTO v_title, v_date, v_sealed_at
  FROM public.events e WHERE e.id = p_event_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento não encontrado', 'event_id', p_event_id);
  END IF;

  IF NOT public._can_manage_event(p_event_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Acesso negado: requer manage_event neste evento');
  END IF;

  IF v_sealed_at IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento não está selado',
      'reason', 'not_sealed', 'event_id', p_event_id, 'event_title', v_title);
  END IF;

  -- O que a reversao NAO toca: linha nascida do selo em que alguem encostou depois (marcou presenca
  -- ou justificou). Desfazer o selo nao pode apagar trabalho humano, entao essas ficam e sao
  -- CONTADAS, para o chamador saber que a reversao nao foi total.
  SELECT count(*) INTO v_kept
  FROM public.attendance a
  WHERE a.event_id = p_event_id
    AND a.notes = public._roster_seal_marker()
    AND (a.present = true OR a.excused = true);

  -- Limite conhecido e aceito: uma falta RE-AFIRMADA por gente sobre a linha do selo
  -- (`mark_member_present(..., false)`) fica indistinguivel da linha original — mesmo carimbo,
  -- mesmo `present=false`. Ela e apagada junto. O caminho para preservar a decisao humana e marcar
  -- presenca ou justificar, que e o que o aviso do #1726 pede ao lider.
  DELETE FROM public.attendance a
  WHERE a.event_id = p_event_id
    AND a.notes = public._roster_seal_marker()
    AND a.present = false
    AND a.excused = false;
  GET DIAGNOSTICS v_removed = ROW_COUNT;

  UPDATE public.events SET roster_sealed_at = NULL WHERE id = p_event_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (v_caller_id, 'attendance.roster_unsealed', 'event', p_event_id,
    jsonb_build_object(
      'event_title', v_title, 'event_date', v_date,
      'removed_absent_count', v_removed, 'kept_touched_count', v_kept,
      'was_sealed_at', v_sealed_at));

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'event_title', v_title,
    'event_date', v_date,
    'removed_absent_count', v_removed,
    'kept_touched_count', v_kept,
    'was_sealed_at', v_sealed_at
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.preview_seal_attendance(p_cycle_start date DEFAULT NULL::date)
 RETURNS TABLE(event_id uuid, event_date date, event_type text, event_title text, tribe_id integer, ends_at timestamp with time zone, already_sealed_at timestamp with time zone, eligible_cohort_n integer, already_recorded_n integer, would_write_absent_n integer, blocked_reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_start date;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Acesso negado: requer manage_event';
  END IF;

  v_start := COALESCE(p_cycle_start, (SELECT c.cycle_start FROM public.cycles c WHERE c.is_current = true LIMIT 1));

  RETURN QUERY
  WITH coorte AS (
    -- UMA chamada por pessoa da coorte operacional, nao uma por par (pessoa, evento).
    SELECT m.id AS mid, ee.event_id AS eid
    FROM public.members m
    CROSS JOIN LATERAL public._attendance_eligible_events(m.id, NULL) ee
    WHERE m.is_active = true AND m.current_cycle_active = true
      AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                  WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
  ),
  ev AS (
    SELECT e.id, e.date, e.type, e.title, e.status, e.roster_sealed_at,
           public.resolve_tribe_id(e.initiative_id) AS tribe,
           public._event_end_instant(e.date, e.time_start, e.duration_minutes, e.timezone) AS ends
    FROM public.events e
    WHERE e.date >= v_start
      AND e.type IN ('geral','kickoff','tribo','lideranca')
      -- #785 (ADR-0105): iniciativa confidencial so aparece para engajado e GP. `manage_event` e
      -- autoridade sobre EVENTO, nao permissao de enxergar iniciativa confidencial.
      AND public.rls_can_see_initiative(e.initiative_id)
      -- #1710: o ensaio tem de ter a MESMA fronteira do ato. O gate acima e por autoridade
      -- generica; este e por RECURSO, o mesmo que seal_event_attendance aplica. Sem ele o painel
      -- listaria 60 eventos para quem pode selar 8, e cada linha a mais seria um botao que erra.
      AND public._can_manage_event(e.id)
  ),
  agg AS (
    SELECT c.eid,
           count(*)::int AS cohort_n,
           count(a.member_id)::int AS recorded_n
    FROM coorte c
    LEFT JOIN public.attendance a ON a.event_id = c.eid AND a.member_id = c.mid
    GROUP BY c.eid
  )
  SELECT ev.id, ev.date, ev.type, ev.title, ev.tribe, ev.ends, ev.roster_sealed_at,
         COALESCE(agg.cohort_n, 0),
         COALESCE(agg.recorded_n, 0),
         GREATEST(COALESCE(agg.cohort_n, 0) - COALESCE(agg.recorded_n, 0), 0),
         CASE
           WHEN ev.status = 'cancelled'         THEN 'cancelled'
           WHEN ev.ends > now()                 THEN 'not_ended_yet'
           WHEN COALESCE(agg.cohort_n, 0) = 0   THEN 'skipped_empty_cohort'
           WHEN ev.roster_sealed_at IS NOT NULL THEN 'already_sealed'
           ELSE NULL
         END
  FROM ev LEFT JOIN agg ON agg.eid = ev.id
  ORDER BY ev.date, ev.title;
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

COMMENT ON FUNCTION public._roster_seal_marker() IS
  '#1710: carimbo unico das linhas de presenca criadas pelo selo. Escrita e reversao leem daqui.';

COMMENT ON FUNCTION public.unseal_event_attendance(uuid) IS
  '#1710: reversao POR EVENTO do selo. Apaga so as linhas ainda com o carimbo de _roster_seal_marker() e intocadas, limpa roster_sealed_at e registra em admin_audit_log.';

NOTIFY pgrst, 'reload schema';
