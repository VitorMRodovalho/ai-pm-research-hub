-- Phase B'' batch 19.1: calculate_rankings V3 sa-bypass → V4 can_by_member('manage_platform')
-- V3 composite gate: committee lead (resource) OR is_superadmin
-- V4: replace is_superadmin IS TRUE with can_by_member('manage_platform')
-- Resource-scoped check (committee role='lead') preserved
-- Impact: V3=2 sa, V4=2 manage_platform (clean match)
CREATE OR REPLACE FUNCTION public.calculate_rankings(p_cycle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_cycle record;
  v_committee record;
  v_median numeric;
  v_cutoff numeric;
  v_p90 numeric;
  v_ranked jsonb;
  v_updated_count int := 0;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Get cycle
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = p_cycle_id;
  IF v_cycle IS NULL THEN
    RAISE EXCEPTION 'Cycle not found';
  END IF;

  -- 3. V4 authorization: committee lead (resource) or platform admin
  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = p_cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or platform admin';
  END IF;

  -- 4. Calculate overall rankings (by final_score DESC)
  WITH scored AS (
    SELECT id, chapter, final_score
    FROM public.selection_applications
    WHERE cycle_id = p_cycle_id
      AND final_score IS NOT NULL
      AND status NOT IN ('withdrawn', 'cancelled')
  ),
  ranked_overall AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY final_score DESC) AS r_overall
    FROM scored
  ),
  ranked_chapter AS (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY chapter ORDER BY final_score DESC) AS r_chapter
    FROM scored
  )
  UPDATE public.selection_applications a
  SET rank_overall = ro.r_overall,
      rank_chapter = rc.r_chapter,
      updated_at = now()
  FROM ranked_overall ro
  JOIN ranked_chapter rc ON rc.id = ro.id
  WHERE a.id = ro.id;

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  -- 5. Calculate median and cutoff for recommendations
  SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY final_score)
  INTO v_median
  FROM public.selection_applications
  WHERE cycle_id = p_cycle_id
    AND final_score IS NOT NULL
    AND status NOT IN ('withdrawn', 'cancelled');

  v_cutoff := ROUND(COALESCE(v_median, 0) * 0.75, 2);

  -- 90th percentile for leader conversion recommendation
  SELECT PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY objective_score_avg)
  INTO v_p90
  FROM public.selection_applications
  WHERE cycle_id = p_cycle_id
    AND objective_score_avg IS NOT NULL
    AND role_applied = 'researcher'
    AND status NOT IN ('withdrawn', 'cancelled');

  -- 6. Build ranked results with recommendations
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'application_id', a.id,
      'applicant_name', a.applicant_name,
      'email', a.email,
      'chapter', a.chapter,
      'role_applied', a.role_applied,
      'objective_score_avg', a.objective_score_avg,
      'interview_score', a.interview_score,
      'final_score', a.final_score,
      'rank_chapter', a.rank_chapter,
      'rank_overall', a.rank_overall,
      'status', a.status,
      'tags', a.tags,
      'recommendation', CASE
        WHEN a.final_score >= v_median THEN 'approve'
        WHEN a.final_score >= v_cutoff THEN 'waitlist'
        ELSE 'reject'
      END,
      'flag_convert_to_leader', CASE
        WHEN a.role_applied = 'researcher'
          AND a.objective_score_avg IS NOT NULL
          AND v_p90 IS NOT NULL
          AND a.objective_score_avg >= v_p90
        THEN true
        ELSE false
      END
    ) ORDER BY a.rank_overall NULLS LAST
  ), '[]'::jsonb)
  INTO v_ranked
  FROM public.selection_applications a
  WHERE a.cycle_id = p_cycle_id
    AND a.status NOT IN ('withdrawn', 'cancelled');

  RETURN jsonb_build_object(
    'cycle_id', p_cycle_id,
    'updated_count', v_updated_count,
    'median_score', v_median,
    'cutoff_75pct', v_cutoff,
    'p90_objective', v_p90,
    'rankings', v_ranked
  );
END;
$function$;
