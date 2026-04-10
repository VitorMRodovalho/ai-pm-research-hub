-- ============================================================
-- Pre-onboarding Sprint 2: leaderboard RPC + onboarding % in selection dashboard
-- ============================================================

-- 1. Leaderboard: ranking of candidates by pre-onboarding XP
CREATE OR REPLACE FUNCTION public.get_pre_onboarding_leaderboard()
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result json;
BEGIN
  -- Any authenticated member can see the leaderboard (motivational)
  IF auth.uid() IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  SELECT coalesce(json_agg(row_to_json(t) ORDER BY t.xp_earned DESC, t.name), '[]'::json)
  INTO v_result
  FROM (
    SELECT
      m.name,
      m.photo_url,
      count(*) FILTER (WHERE op.status = 'completed') as completed,
      count(*) as total,
      coalesce(sum((op.metadata->>'xp')::int) FILTER (WHERE op.status = 'completed'), 0) as xp_earned,
      coalesce(sum((op.metadata->>'xp')::int), 0) as xp_total,
      CASE WHEN count(*) > 0 THEN round(100.0 * count(*) FILTER (WHERE op.status = 'completed') / count(*)) ELSE 0 END as pct
    FROM onboarding_progress op
    JOIN members m ON m.id = op.member_id
    WHERE op.metadata->>'phase' = 'pre_onboarding'
    GROUP BY m.id, m.name, m.photo_url
  ) t;

  RETURN json_build_object('leaderboard', v_result);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_pre_onboarding_leaderboard() TO authenticated;

-- 2. View for selection dashboard to include onboarding % per application
-- We add a helper function that the selection dashboard can call
CREATE OR REPLACE FUNCTION public.get_application_onboarding_pct(p_application_id uuid)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN count(*) = 0 THEN -1  -- no onboarding data
    ELSE round(100.0 * count(*) FILTER (WHERE status = 'completed') / count(*))::int
  END
  FROM onboarding_progress
  WHERE application_id = p_application_id
  AND metadata->>'phase' = 'pre_onboarding';
$$;

GRANT EXECUTE ON FUNCTION public.get_application_onboarding_pct(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
