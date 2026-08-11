-- #1710 / #1727 / #1729 — o selo passa a enxergar o RELOGIO LOCAL, a recusar coorte vazia, e ganha
-- um ensaio que nao escreve.
--
-- (1) #1727 — o corte da janela era `e.date <= CURRENT_DATE`, uma comparacao de DATA em UTC. Um
-- evento de hoje as 20h ficava elegivel desde o instante em que o dia UTC comecou, ou seja **23
-- horas antes de acontecer** (medido em 11/08 02h12 UTC = 10/08 23h12 no Brasil). A virada de fuso
-- responde por 3 dessas horas; as outras 20 vem de comparar data em vez de instante, entao corrigir
-- so o fuso nao resolveria.
--
-- O instante de termino vira UMA funcao, `_event_end_instant`, em vez de dois predicados
-- equivalentes escritos a mao: a elegibilidade e a guarda do selo tem de responder a MESMA pergunta,
-- e duas copias divergem na primeira manutencao.
--
-- Usa `duration_minutes` (NOT NULL, preenchida em todos os 480 eventos) porque o corte certo e o FIM
-- da reuniao, nao o inicio: selar durante a reuniao marcaria falta de quem ainda esta nela.
--
-- Alcance medido antes de aplicar: `_attendance_eligible_events` e a primitiva canonica (SPEC §3b)
-- com 9 consumidores. Sobre a coorte operacional, neste instante: 524 pares (pessoa, evento) caem
-- para 502. Os 22 removidos sao 4 eventos que ainda nao terminaram, e **0 deles tem presenca
-- registrada** — a mudanca e puramente subtrativa sobre celula sem registro. Se alguem registrar
-- presenca antes da reuniao terminar, o registro sobrevive assim mesmo, porque o #1710 ja deixou
-- `na` condicionado a `a.id IS NULL`.
--
-- (2) #1729 — coorte vazia deixa de ser selavel. `UPDATE ... SET roster_sealed_at` rodava mesmo com
-- `v_eligible = 0`, carimbando "lista fechada" num evento que nunca teve lista (5 casos vivos, todos
-- da tribo 2 arquivada). Agora devolve `skipped_empty_cohort` SEM carimbar, para o chamador listar
-- como evento a revisar em vez de contar como selado.
--
-- (3) `preview_seal_attendance` — o ensaio. So le. Reporta, por evento, o que o selo faria e por que
-- nao faria, incluindo a coorte POR EVENTO: sem ela, um evento de coorte vazia e indistinguivel de
-- um evento em que todo mundo ja estava registrado (os dois dao "sucesso" com zero linhas gravadas).

-- ── 1. o instante de termino, em um lugar so ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._event_end_instant(
  p_date date,
  p_time_start time without time zone,
  p_duration_minutes integer,
  p_timezone text
)
RETURNS timestamptz
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Sem hora de inicio, o evento so termina no FIM do dia local: nao ha como afirmar que ja acabou.
  SELECT CASE
    WHEN p_time_start IS NULL THEN
      ((p_date + interval '1 day') AT TIME ZONE COALESCE(NULLIF(p_timezone, ''), 'America/Sao_Paulo'))
    ELSE
      ((p_date + p_time_start + (COALESCE(p_duration_minutes, 0) || ' minutes')::interval)
         AT TIME ZONE COALESCE(NULLIF(p_timezone, ''), 'America/Sao_Paulo'))
  END;
$function$;

COMMENT ON FUNCTION public._event_end_instant(date, time without time zone, integer, text) IS
  '#1727: instante em que a reuniao termina, em hora LOCAL. Fonte unica para "ja ocorreu" — a elegibilidade e a guarda do selo tem de usar esta, nunca um equivalente reescrito.';

-- ── 2. a elegibilidade passa a exigir que o evento TENHA TERMINADO ──────────────────────────────

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
  ),
  mt AS (
    SELECT public.get_member_tribe(p_member_id) AS tribe_id
  )
  SELECT e.id, e.type, e.date
  FROM public.events e, win, mt
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
      OR (e.type = 'tribo' AND mt.tribe_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.initiatives i
            WHERE i.id = e.initiative_id AND i.legacy_tribe_id = mt.tribe_id))
      OR (e.type = 'lideranca' AND public.can_by_member(p_member_id, 'manage_event'))
    );
$function$;

-- ── 3. o selo: guarda por instante local, e coorte vazia nao carimba ────────────────────────────

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
  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Acesso negado: requer manage_event');
  END IF;

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
         '[roster_seal] no-show materializado (PR11 seal track)', v_caller_id, v_caller_id, NULL
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

-- ── 4. o ensaio: reporta o que o selo faria, sem escrever ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.preview_seal_attendance(p_cycle_start date DEFAULT NULL::date)
 RETURNS TABLE(
   event_id uuid,
   event_date date,
   event_type text,
   event_title text,
   tribe_id integer,
   ends_at timestamptz,
   already_sealed_at timestamptz,
   eligible_cohort_n integer,
   already_recorded_n integer,
   would_write_absent_n integer,
   blocked_reason text
 )
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
  WITH ev AS (
    SELECT e.id, e.date, e.type, e.title, e.status, e.roster_sealed_at,
           public.resolve_tribe_id(e.initiative_id) AS tribe,
           public._event_end_instant(e.date, e.time_start, e.duration_minutes, e.timezone) AS ends
    FROM public.events e
    WHERE e.date >= v_start
      AND e.type IN ('geral','kickoff','tribo','lideranca')
  ),
  coorte AS (
    SELECT ev.id AS eid, m.id AS mid
    FROM ev
    JOIN public.members m
      ON m.is_active = true AND m.current_cycle_active = true
     AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                 WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
     AND EXISTS (SELECT 1 FROM public._attendance_eligible_events(m.id, NULL) ee WHERE ee.event_id = ev.id)
  ),
  agg AS (
    SELECT ev.id AS eid,
           count(c.mid)::int AS cohort_n,
           count(a.member_id)::int AS recorded_n
    FROM ev
    LEFT JOIN coorte c ON c.eid = ev.id
    LEFT JOIN public.attendance a ON a.event_id = ev.id AND a.member_id = c.mid
    GROUP BY ev.id
  )
  SELECT ev.id, ev.date, ev.type, ev.title, ev.tribe, ev.ends, ev.roster_sealed_at,
         agg.cohort_n,
         agg.recorded_n,
         GREATEST(agg.cohort_n - agg.recorded_n, 0),
         CASE
           WHEN ev.status = 'cancelled'        THEN 'cancelled'
           WHEN ev.ends > now()                THEN 'not_ended_yet'
           WHEN agg.cohort_n = 0               THEN 'skipped_empty_cohort'
           WHEN ev.roster_sealed_at IS NOT NULL THEN 'already_sealed'
           ELSE NULL
         END
  FROM ev JOIN agg ON agg.eid = ev.id
  ORDER BY ev.date, ev.title;
END;
$function$;

COMMENT ON FUNCTION public.preview_seal_attendance(date) IS
  '#1710 dry-run: reporta por evento o que seal_event_attendance faria, sem escrever. A coorte POR EVENTO e o ponto — sem ela, coorte vazia e indistinguivel de "todos ja registrados".';

REVOKE ALL ON FUNCTION public.preview_seal_attendance(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.preview_seal_attendance(date) TO authenticated, service_role;
