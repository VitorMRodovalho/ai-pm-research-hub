-- #1239 (option A): retention headline = last CLOSED cohort transition.
-- The homepage "Taxa de Retenção" reads get_member_retention_canonical()->headline, which picked the
-- LAST transition unconditionally (ORDER BY rn DESC LIMIT 1). Once C4 opened (2026-07-09) that headline
-- became C3->C4 (47.6%) -- retention measured INTO the current, still-forming cohort, which understates
-- it (denominator complete, numerator incomplete). The function's own definition already said "last
-- closed transition"; this makes the code match it by excluding the current open cycle as the target.
-- The in-progress transition stays in `transitions` (full history). Falls back to the latest transition
-- if every transition targets the current cycle (edge case at a brand-new program).
CREATE OR REPLACE FUNCTION public.get_member_retention_canonical()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH cyc AS (
    SELECT cycle_code, min(cycle_start) AS cstart, min(cycle_label) AS clabel
    FROM public.member_cycle_history
    GROUP BY cycle_code
  ),
  ordered AS (
    SELECT cycle_code, clabel, cstart, row_number() OVER (ORDER BY cstart) AS rn FROM cyc
  ),
  pairs AS (
    SELECT a.cycle_code AS from_code, a.clabel AS from_label,
           b.cycle_code AS to_code, b.clabel AS to_label, a.rn AS rn
    FROM ordered a JOIN ordered b ON b.rn = a.rn + 1
  ),
  computed AS (
    SELECT p.rn, p.from_code, p.from_label, p.to_code, p.to_label,
      (SELECT count(DISTINCT member_id) FROM public.member_cycle_history WHERE cycle_code = p.from_code) AS cohort_n,
      (SELECT count(DISTINCT mh1.member_id) FROM public.member_cycle_history mh1
         WHERE mh1.cycle_code = p.from_code
           AND EXISTS (SELECT 1 FROM public.member_cycle_history mh2
                       WHERE mh2.member_id = mh1.member_id AND mh2.cycle_code = p.to_code)) AS survived
    FROM pairs p
  ),
  withpct AS (
    SELECT *, ROUND(survived::numeric * 100 / NULLIF(cohort_n, 0), 1) AS survival_pct FROM computed
  )
  SELECT jsonb_build_object(
    'metric', 'cohort_survival',
    'definition', 'Share of cycle N members (distinct member_id in member_cycle_history) who return in cycle N+1. Headline = last CLOSED transition (excludes the current open cycle as target; the in-progress transition stays in transitions).',
    'transitions', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'from_code', from_code, 'from_label', from_label, 'to_code', to_code, 'to_label', to_label,
        'cohort_n', cohort_n, 'survived', survived, 'survival_pct', survival_pct) ORDER BY rn) FROM withpct), '[]'::jsonb),
    'headline', COALESCE(
      (SELECT jsonb_build_object(
        'from_code', from_code, 'from_label', from_label, 'to_code', to_code, 'to_label', to_label,
        'cohort_n', cohort_n, 'survived', survived, 'survival_pct', survival_pct,
        'basis', replace(from_code, 'cycle_', 'C') || '->' || replace(to_code, 'cycle_', 'C')
      ) FROM withpct
      WHERE to_code IS DISTINCT FROM (SELECT cycle_code FROM public.cycles WHERE is_current LIMIT 1)
      ORDER BY rn DESC LIMIT 1),
      (SELECT jsonb_build_object(
        'from_code', from_code, 'from_label', from_label, 'to_code', to_code, 'to_label', to_label,
        'cohort_n', cohort_n, 'survived', survived, 'survival_pct', survival_pct,
        'basis', replace(from_code, 'cycle_', 'C') || '->' || replace(to_code, 'cycle_', 'C')
      ) FROM withpct ORDER BY rn DESC LIMIT 1)
    ),
    'computed_at', now()
  );
$function$;
