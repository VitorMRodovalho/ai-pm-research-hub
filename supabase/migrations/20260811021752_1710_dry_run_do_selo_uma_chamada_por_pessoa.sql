-- #1710 — o ensaio do selo, agora com custo linear na coorte.
--
-- A primeira versao chamava `_attendance_eligible_events` uma vez por PAR (pessoa, evento), dentro
-- de um EXISTS correlacionado: ~86 pessoas x ~300 eventos = ~26 mil chamadas de uma funcao que ela
-- mesma varre `events`. Estourou o timeout do statement e nunca respondeu.
--
-- A funcao ja devolve TODOS os eventos elegiveis de uma pessoa numa chamada so. Chamar uma vez por
-- pessoa e materializar o resultado troca ~26 mil chamadas por ~86, e o resto vira agregacao comum.
--
-- (Este e o mesmo erro que a propria funcao induz em quem a le como predicado booleano: ela nao e
-- "esta pessoa pode neste evento?", e sim "quais eventos desta pessoa" — usar como EXISTS por par
-- funciona e custa caro.)

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

COMMENT ON FUNCTION public.preview_seal_attendance(date) IS
  '#1710 dry-run: reporta por evento o que seal_event_attendance faria, sem escrever. A coorte POR EVENTO e o ponto — sem ela, coorte vazia e indistinguivel de "todos ja registrados". Elegibilidade resolvida UMA vez por pessoa (a versao por par estourava o timeout).';
