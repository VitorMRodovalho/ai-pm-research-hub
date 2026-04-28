-- ADR-0062: #101 P2 final closure — current_streak_count + points_this_cycle aggregate stats
-- Bulk RPC for leaderboard rows + single-member convenience RPC for profile views.
-- Streak algorithm: window function with run-detection (sort_order + row_number()).
-- Streak alive if last contiguous run reaches current cycle OR previous cycle (1-cycle grace).
-- NULL-safe upper bound: cycle_end IS NULL means cycle is ongoing — points after cycle_start count.
-- Rollback: DROP FUNCTION public.get_member_gamification_stats(uuid[]);
--           DROP FUNCTION public.get_my_gamification_stats();

CREATE OR REPLACE FUNCTION public.get_member_gamification_stats(p_member_ids uuid[])
RETURNS TABLE (
  member_id uuid,
  current_streak_count integer,
  points_this_cycle integer,
  active_cycles_count integer,
  longest_streak_count integer
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_current_sort integer;
  v_cycle_start date;
  v_cycle_end date;
  v_input_size integer;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_member_ids IS NULL THEN
    RETURN;
  END IF;

  v_input_size := COALESCE(array_length(p_member_ids, 1), 0);
  IF v_input_size = 0 THEN
    RETURN;
  END IF;
  IF v_input_size > 200 THEN
    RAISE EXCEPTION 'Too many member_ids (max 200, got %)', v_input_size
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT c.sort_order, c.cycle_start, c.cycle_end
  INTO v_current_sort, v_cycle_start, v_cycle_end
  FROM public.cycles c WHERE c.is_current = true LIMIT 1;

  IF v_current_sort IS NULL THEN
    RETURN QUERY
    SELECT mid, 0::integer, 0::integer, 0::integer, 0::integer
    FROM unnest(p_member_ids) mid;
    RETURN;
  END IF;

  RETURN QUERY
  WITH
  member_cycles AS (
    SELECT
      gp.member_id,
      c.sort_order
    FROM public.gamification_points gp
    JOIN public.cycles c
      ON gp.created_at >= c.cycle_start::timestamp
     AND (c.cycle_end IS NULL OR gp.created_at < (c.cycle_end + interval '1 day')::timestamp)
    WHERE gp.member_id = ANY(p_member_ids)
    GROUP BY gp.member_id, c.sort_order
  ),
  walked AS (
    SELECT
      mc.member_id,
      mc.sort_order,
      mc.sort_order + ROW_NUMBER() OVER (PARTITION BY mc.member_id ORDER BY mc.sort_order DESC) AS run_key
    FROM member_cycles mc
    WHERE mc.sort_order <= v_current_sort
  ),
  runs AS (
    SELECT
      w.member_id,
      w.run_key,
      COUNT(*)::integer AS streak_length,
      MAX(w.sort_order) AS last_sort
    FROM walked w
    GROUP BY w.member_id, w.run_key
  ),
  current_streaks AS (
    SELECT
      r.member_id,
      MAX(r.streak_length) FILTER (WHERE r.last_sort >= v_current_sort - 1) AS current_streak,
      MAX(r.streak_length) AS longest_streak
    FROM runs r
    GROUP BY r.member_id
  ),
  cycle_pts AS (
    SELECT
      gp.member_id,
      SUM(gp.points)::integer AS pts_this_cycle
    FROM public.gamification_points gp
    WHERE gp.member_id = ANY(p_member_ids)
      AND gp.created_at >= v_cycle_start::timestamp
      AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + interval '1 day')::timestamp)
    GROUP BY gp.member_id
  ),
  active_counts AS (
    SELECT mc.member_id, COUNT(*)::integer AS cnt
    FROM member_cycles mc
    GROUP BY mc.member_id
  )
  SELECT
    mid::uuid AS member_id,
    COALESCE(cs.current_streak, 0)::integer AS current_streak_count,
    COALESCE(cp.pts_this_cycle, 0)::integer AS points_this_cycle,
    COALESCE(ac.cnt, 0)::integer AS active_cycles_count,
    COALESCE(cs.longest_streak, 0)::integer AS longest_streak_count
  FROM unnest(p_member_ids) AS mid
  LEFT JOIN current_streaks cs ON cs.member_id = mid
  LEFT JOIN cycle_pts cp ON cp.member_id = mid
  LEFT JOIN active_counts ac ON ac.member_id = mid;
END;
$$;

REVOKE ALL ON FUNCTION public.get_member_gamification_stats(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_member_gamification_stats(uuid[]) TO authenticated;

COMMENT ON FUNCTION public.get_member_gamification_stats(uuid[]) IS
'ADR-0062 (#101 P2 final): Bulk aggregate stats for leaderboard rows. Returns current_streak_count (consecutive cycles with >=1 point ending at current OR previous cycle — 1-cycle grace), points_this_cycle, active_cycles_count, longest_streak_count. Max 200 member_ids per call. Authenticated only — counts only, no PII. Use with frontend-paginated leaderboard.';

CREATE OR REPLACE FUNCTION public.get_my_gamification_stats()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_stats record;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_stats
  FROM public.get_member_gamification_stats(ARRAY[v_caller_id])
  LIMIT 1;

  RETURN jsonb_build_object(
    'member_id', v_stats.member_id,
    'current_streak_count', v_stats.current_streak_count,
    'points_this_cycle', v_stats.points_this_cycle,
    'active_cycles_count', v_stats.active_cycles_count,
    'longest_streak_count', v_stats.longest_streak_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_gamification_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_gamification_stats() TO authenticated;

COMMENT ON FUNCTION public.get_my_gamification_stats() IS
'ADR-0062 (#101 P2 final): Caller-self convenience wrapper around get_member_gamification_stats. Returns single jsonb with current_streak_count + points_this_cycle + active_cycles_count + longest_streak_count for the authenticated member.';
