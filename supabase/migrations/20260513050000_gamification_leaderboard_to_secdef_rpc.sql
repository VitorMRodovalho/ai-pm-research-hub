-- ADR-0024 follow-up + Issue #82 Onda 2 — gamification_leaderboard view → SECDEF RPC.
--
-- Rationale: Postgres advisor flagged `public.gamification_leaderboard` as
-- `security_definer_view` (Issue #82 Onda 2). Per spec memo
-- (docs/specs/SPEC_ISSUE_82_ONDA_2_3_OPTIONS.md) Option A: convert to a SECDEF
-- function so authority is explicit (`auth.uid()` member check) and the advisor
-- finding closes. PM accepted 2026-04-24.
--
-- Pattern matches `get_public_leaderboard()` (already shipped) — same JOIN graph,
-- same SUM/FILTER aggregation, same `current_cycle_active` filter. RETURNS TABLE
-- preserves the 24-column row shape so the 3 callsites in
-- `src/pages/gamification.astro` (lines 848, 891, 982) refactor to
-- `sb.rpc('get_gamification_leaderboard')` with no client-side reshape.
--
-- Behavior preserved:
--   - Same 24 columns (member_id, name, chapter, photo_url, operational_role,
--     designations, 9 lifetime totals, 9 cycle-scoped totals).
--   - `course_points` and `cycle_course_points` are kept as alias columns of the
--     `learning` aggregation for backward compatibility with the view's API.
--   - Filters `members.current_cycle_active = true` (active members only).
--   - Authority: any authenticated member can read the leaderboard. Anon loses
--     access (was granted to anon via view but no anon-path callsites exist —
--     verified in spec memo).

CREATE OR REPLACE FUNCTION public.get_gamification_leaderboard()
RETURNS TABLE (
  member_id uuid,
  name text,
  chapter text,
  photo_url text,
  operational_role text,
  designations text[],
  total_points integer,
  attendance_points integer,
  learning_points integer,
  cert_points integer,
  badge_points integer,
  artifact_points integer,
  course_points integer,
  showcase_points integer,
  bonus_points integer,
  cycle_points integer,
  cycle_attendance_points integer,
  cycle_course_points integer,
  cycle_artifact_points integer,
  cycle_showcase_points integer,
  cycle_bonus_points integer,
  cycle_learning_points integer,
  cycle_cert_points integer,
  cycle_badge_points integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  -- Auth gate: any active member can read the leaderboard. No role-based
  -- restriction (matches view's prior any-authenticated grant). This is a
  -- baseline-auth-only RPC — ADR-0011 parser correctly does not flag it
  -- because there is no role-list authority pattern.
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN QUERY
  WITH current_cycle AS (
    SELECT cycles.cycle_start
    FROM public.cycles
    WHERE cycles.is_current = true
    LIMIT 1
  )
  SELECT
    m.id AS member_id,
    m.name,
    m.chapter,
    m.photo_url,
    m.operational_role,
    m.designations,
    COALESCE(sum(gp.points), 0::bigint)::integer AS total_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = 'attendance'::text), 0::bigint)::integer AS attendance_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = ANY (ARRAY['trail'::text, 'course'::text, 'knowledge_ai_pm'::text])), 0::bigint)::integer AS learning_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = ANY (ARRAY['cert_pmi_senior'::text, 'cert_cpmai'::text, 'cert_pmi_mid'::text, 'cert_pmi_practitioner'::text, 'cert_pmi_entry'::text])), 0::bigint)::integer AS cert_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = ANY (ARRAY['badge'::text, 'specialization'::text])), 0::bigint)::integer AS badge_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = 'artifact'::text), 0::bigint)::integer AS artifact_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = ANY (ARRAY['trail'::text, 'course'::text, 'knowledge_ai_pm'::text])), 0::bigint)::integer AS course_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = 'showcase'::text), 0::bigint)::integer AS showcase_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category <> ALL (ARRAY['attendance'::text, 'trail'::text, 'course'::text, 'knowledge_ai_pm'::text, 'cert_pmi_senior'::text, 'cert_cpmai'::text, 'cert_pmi_mid'::text, 'cert_pmi_practitioner'::text, 'cert_pmi_entry'::text, 'badge'::text, 'specialization'::text, 'artifact'::text, 'showcase'::text])), 0::bigint)::integer AS bonus_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.created_at >= (SELECT cc.cycle_start FROM current_cycle cc)), 0::bigint)::integer AS cycle_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = 'attendance'::text AND gp.created_at >= (SELECT cc.cycle_start FROM current_cycle cc)), 0::bigint)::integer AS cycle_attendance_points,
    COALESCE(sum(gp.points) FILTER (WHERE (gp.category = ANY (ARRAY['trail'::text, 'course'::text, 'knowledge_ai_pm'::text])) AND gp.created_at >= (SELECT cc.cycle_start FROM current_cycle cc)), 0::bigint)::integer AS cycle_course_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = 'artifact'::text AND gp.created_at >= (SELECT cc.cycle_start FROM current_cycle cc)), 0::bigint)::integer AS cycle_artifact_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = 'showcase'::text AND gp.created_at >= (SELECT cc.cycle_start FROM current_cycle cc)), 0::bigint)::integer AS cycle_showcase_points,
    COALESCE(sum(gp.points) FILTER (WHERE (gp.category <> ALL (ARRAY['attendance'::text, 'trail'::text, 'course'::text, 'knowledge_ai_pm'::text, 'cert_pmi_senior'::text, 'cert_cpmai'::text, 'cert_pmi_mid'::text, 'cert_pmi_practitioner'::text, 'cert_pmi_entry'::text, 'badge'::text, 'specialization'::text, 'artifact'::text, 'showcase'::text])) AND gp.created_at >= (SELECT cc.cycle_start FROM current_cycle cc)), 0::bigint)::integer AS cycle_bonus_points,
    COALESCE(sum(gp.points) FILTER (WHERE (gp.category = ANY (ARRAY['trail'::text, 'course'::text, 'knowledge_ai_pm'::text])) AND gp.created_at >= (SELECT cc.cycle_start FROM current_cycle cc)), 0::bigint)::integer AS cycle_learning_points,
    COALESCE(sum(gp.points) FILTER (WHERE (gp.category = ANY (ARRAY['cert_pmi_senior'::text, 'cert_cpmai'::text, 'cert_pmi_mid'::text, 'cert_pmi_practitioner'::text, 'cert_pmi_entry'::text])) AND gp.created_at >= (SELECT cc.cycle_start FROM current_cycle cc)), 0::bigint)::integer AS cycle_cert_points,
    COALESCE(sum(gp.points) FILTER (WHERE (gp.category = ANY (ARRAY['badge'::text, 'specialization'::text])) AND gp.created_at >= (SELECT cc.cycle_start FROM current_cycle cc)), 0::bigint)::integer AS cycle_badge_points
  FROM public.members m
    LEFT JOIN public.gamification_points gp ON gp.member_id = m.id
  WHERE m.current_cycle_active = true
  GROUP BY m.id, m.name, m.chapter, m.photo_url, m.operational_role, m.designations;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_gamification_leaderboard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_gamification_leaderboard() TO authenticated;

COMMENT ON FUNCTION public.get_gamification_leaderboard() IS
  'Authenticated member leaderboard reader (Issue #82 Onda 2 / ADR-0024 follow-up). Replaces the deprecated public.gamification_leaderboard view (security_definer_view advisor). 24-column row shape preserved for callsite compatibility. Auth gate: any active member.';

DROP VIEW IF EXISTS public.gamification_leaderboard;

NOTIFY pgrst, 'reload schema';
