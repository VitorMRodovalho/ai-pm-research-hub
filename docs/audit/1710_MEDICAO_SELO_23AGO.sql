-- #1710 — medicao do selo de presenca, caminho (b): replicacao do predicado do cron.
--
-- POR QUE ESTE ARQUIVO EXISTE
-- `seal_attendance_window_cron(true)` (o ensaio oficial) devolve `skipped: before_floor`
-- enquanto a data local for menor que o `floor_date`. Antes de 24/08 ele nao mede nada.
-- Esta consulta replica o MESMO predicado para permitir medir na vespera.
--
-- FRONTEIRA (medido em 19/08/2026): esta consulta replica o CRON, que NAO tem gate de
-- chamador. `preview_seal_attendance` tem dois (`_can_manage_event` + `rls_can_see_initiative`)
-- e portanto mede outra coisa: o que UM chamador alcanca. Divergencia entre os dois caminhos
-- e ESPERADA e do tamanho da grade fora do alcance do lider. Nao trate como erro.
--
-- Fonte do predicado: corpos vivos de `seal_attendance_window_cron`,
-- `_seal_event_attendance_apply` e `_attendance_eligible_events`, lidos em 19/08/2026 22:1x UTC.
-- Se qualquer um mudar, esta replicacao caduca: releia antes de confiar.
--
-- COMO USAR EM 23/08: rode como esta (cenario A = agora). O cenario B projeta o instante do
-- cron no piso. Depois de 24/08 11:40 UTC, o numero que vale e o do ensaio oficial:
--   SELECT public.seal_attendance_window_cron(true);

WITH cyc AS (SELECT cycle_start FROM public.cycles WHERE is_current = true LIMIT 1),
-- coorte operacional: UMA chamada por pessoa, como o preview faz (nao uma por par).
coorte AS (
  SELECT m.id AS mid, ee.event_id AS eid
  FROM public.members m
  CROSS JOIN LATERAL public._attendance_eligible_events(m.id, NULL) ee
  WHERE m.is_active = true AND m.current_cycle_active = true
    AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
),
-- o laco do cron, sem o corte de graca (aplicado por cenario abaixo).
due AS (
  SELECT e.id,
         public._event_end_instant(e.date, e.time_start, e.duration_minutes, e.timezone) AS ends
  FROM public.events e, cyc
  WHERE e.roster_sealed_at IS NULL
    AND e.status IS DISTINCT FROM 'cancelled'
    AND e.type IN ('geral','kickoff','tribo','lideranca')
    AND e.date >= cyc.cycle_start
),
agg AS (
  SELECT d.id, d.ends,
         count(c.mid)::int      AS cohort_n,
         count(a.member_id)::int AS recorded_n
  FROM due d
  LEFT JOIN coorte c ON c.eid = d.id
  LEFT JOIN public.attendance a ON a.event_id = d.id AND a.member_id = c.mid
  GROUP BY d.id, d.ends
),
-- grace_days sai da config, nao de literal: se o PM mexer, a conta acompanha.
cfg AS (
  SELECT COALESCE((value->>'grace_days')::int, 14) AS grace,
         (value->>'floor_date')::date              AS floor_date
  FROM public.platform_settings WHERE key = 'attendance.seal_window'
),
sc AS (
  SELECT 'A_agora'::text AS cenario, now() - (SELECT grace FROM cfg) * interval '1 day' AS cutoff
  UNION ALL
  -- o cron roda 40 11 * * * UTC; no dia do piso o corte e esse instante menos a graca.
  SELECT 'B_piso_1140utc',
         (((SELECT floor_date FROM cfg) + time '11:40') AT TIME ZONE 'UTC')
           - (SELECT grace FROM cfg) * interval '1 day'
)
SELECT sc.cenario,
       to_char(sc.cutoff, 'YYYY-MM-DD HH24:MI')                              AS corte_fim_evento,
       count(*) FILTER (WHERE agg.ends <= sc.cutoff)                         AS events_due,
       count(*) FILTER (WHERE agg.ends <= sc.cutoff AND agg.cohort_n > 0)    AS events_would_seal,
       count(*) FILTER (WHERE agg.ends <= sc.cutoff AND agg.cohort_n = 0)    AS events_skipped_empty,
       COALESCE(sum(GREATEST(agg.cohort_n - agg.recorded_n, 0))
                FILTER (WHERE agg.ends <= sc.cutoff AND agg.cohort_n > 0), 0) AS absences_would_write
FROM sc CROSS JOIN agg
GROUP BY sc.cenario, sc.cutoff
ORDER BY sc.cenario;
