-- ADR-0050: gamification_leaderboard RPC v2 + member opt-out
--
-- Closes #101 P0+P1 (P2 chapter/tribe scope filter deferred to ADR-0051):
--   * members.gamification_opt_out (LGPD-compliant member-managed flag)
--   * get_gamification_leaderboard v2 — pagination + cycle filter + total_count + opt-out filter
--   * set_my_gamification_visibility — member self-management RPC
--
-- Backwards compat: get_gamification_leaderboard preserves all 16+ existing return
-- columns. Adds `total_count int` (new column at end). Existing callsites in
-- src/pages/gamification.astro use named columns or *, so adding a column doesn't break.
--
-- Signature change requires DROP + CREATE (not CREATE OR REPLACE) per database rules.
-- Existing callsites pass no args; new params are DEFAULT so call site is unchanged.
--
-- LGPD note: opt-out is fail-closed. Members who set gamification_opt_out=true are
-- excluded from leaderboard rendering. They keep their points (no data deletion);
-- only visibility is suppressed.
--
-- Rollback: see commented section at bottom.

-- =====================================================================
-- 1) Schema: members.gamification_opt_out
-- =====================================================================

ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS gamification_opt_out boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.members.gamification_opt_out IS
  'ADR-0050 #101: LGPD-compliant member-managed flag. When true, member is excluded from gamification leaderboard rendering. Points preserved (no data deletion). Set via set_my_gamification_visibility RPC.';

-- =====================================================================
-- 2) RPC v2: get_gamification_leaderboard (DROP + CREATE)
-- =====================================================================

DROP FUNCTION IF EXISTS public.get_gamification_leaderboard();

CREATE OR REPLACE FUNCTION public.get_gamification_leaderboard(
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_cycle_code text DEFAULT NULL
)
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
  cycle_badge_points integer,
  total_count integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_cycle_start date;
  v_cycle_end date;
  v_total_count int;
  v_effective_limit int;
  v_effective_offset int;
BEGIN
  -- Auth
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Validate pagination params
  v_effective_limit := GREATEST(1, LEAST(COALESCE(p_limit, 50), 200));
  v_effective_offset := GREATEST(0, COALESCE(p_offset, 0));

  -- Resolve cycle window
  IF p_cycle_code IS NOT NULL THEN
    SELECT c.cycle_start, c.cycle_end
    INTO v_cycle_start, v_cycle_end
    FROM public.cycles c WHERE c.cycle_code = p_cycle_code;
    IF v_cycle_start IS NULL THEN
      RAISE EXCEPTION 'cycle_not_found: %', p_cycle_code USING ERRCODE = 'no_data_found';
    END IF;
  ELSE
    -- Default: current cycle
    SELECT c.cycle_start, c.cycle_end
    INTO v_cycle_start, v_cycle_end
    FROM public.cycles c WHERE c.is_current = true LIMIT 1;
  END IF;

  -- Compute total_count once (post-filter)
  SELECT COUNT(*) INTO v_total_count
  FROM public.members m
  WHERE m.current_cycle_active = true
    AND m.gamification_opt_out = false;

  RETURN QUERY
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
    COALESCE(sum(gp.points) FILTER (WHERE gp.created_at >= v_cycle_start
       AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer AS cycle_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = 'attendance'::text
      AND gp.created_at >= v_cycle_start
      AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer AS cycle_attendance_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = ANY (ARRAY['trail'::text, 'course'::text, 'knowledge_ai_pm'::text])
      AND gp.created_at >= v_cycle_start
      AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer AS cycle_course_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = 'artifact'::text
      AND gp.created_at >= v_cycle_start
      AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer AS cycle_artifact_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = 'showcase'::text
      AND gp.created_at >= v_cycle_start
      AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer AS cycle_showcase_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category <> ALL (ARRAY['attendance'::text, 'trail'::text, 'course'::text, 'knowledge_ai_pm'::text, 'cert_pmi_senior'::text, 'cert_cpmai'::text, 'cert_pmi_mid'::text, 'cert_pmi_practitioner'::text, 'cert_pmi_entry'::text, 'badge'::text, 'specialization'::text, 'artifact'::text, 'showcase'::text])
      AND gp.created_at >= v_cycle_start
      AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer AS cycle_bonus_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = ANY (ARRAY['trail'::text, 'course'::text, 'knowledge_ai_pm'::text])
      AND gp.created_at >= v_cycle_start
      AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer AS cycle_learning_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = ANY (ARRAY['cert_pmi_senior'::text, 'cert_cpmai'::text, 'cert_pmi_mid'::text, 'cert_pmi_practitioner'::text, 'cert_pmi_entry'::text])
      AND gp.created_at >= v_cycle_start
      AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer AS cycle_cert_points,
    COALESCE(sum(gp.points) FILTER (WHERE gp.category = ANY (ARRAY['badge'::text, 'specialization'::text])
      AND gp.created_at >= v_cycle_start
      AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer AS cycle_badge_points,
    v_total_count AS total_count
  FROM public.members m
    LEFT JOIN public.gamification_points gp ON gp.member_id = m.id
  WHERE m.current_cycle_active = true
    AND m.gamification_opt_out = false
  GROUP BY m.id, m.name, m.chapter, m.photo_url, m.operational_role, m.designations
  ORDER BY total_points DESC, m.name ASC
  LIMIT v_effective_limit
  OFFSET v_effective_offset;
END;
$$;

COMMENT ON FUNCTION public.get_gamification_leaderboard(integer, integer, text) IS
  'ADR-0050 #101 v2: leaderboard with pagination (limit ∈ [1,200], offset ≥0), cycle filter (NULL=current), opt-out filter (members.gamification_opt_out=false), and total_count column for paginated UI.';

GRANT EXECUTE ON FUNCTION public.get_gamification_leaderboard(integer, integer, text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_gamification_leaderboard(integer, integer, text) FROM PUBLIC, anon;

-- =====================================================================
-- 3) RPC: set_my_gamification_visibility(p_opt_out boolean)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.set_my_gamification_visibility(
  p_opt_out boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_old_value boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT id, gamification_opt_out INTO v_caller_id, v_old_value
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- No-op short-circuit (idempotent)
  IF v_old_value = COALESCE(p_opt_out, false) THEN
    RETURN jsonb_build_object(
      'success', true,
      'member_id', v_caller_id,
      'opt_out', v_old_value,
      'changed', false,
      'updated_at', now()
    );
  END IF;

  UPDATE public.members
  SET gamification_opt_out = COALESCE(p_opt_out, false),
      updated_at = now()
  WHERE id = v_caller_id;

  RETURN jsonb_build_object(
    'success', true,
    'member_id', v_caller_id,
    'opt_out', COALESCE(p_opt_out, false),
    'changed', true,
    'previous_value', v_old_value,
    'updated_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.set_my_gamification_visibility(boolean) IS
  'ADR-0050 #101: member-managed leaderboard visibility. Sets gamification_opt_out for caller. Idempotent (no-op if value unchanged). Authenticated only — caller can only edit own record. LGPD self-management primitive.';

GRANT EXECUTE ON FUNCTION public.set_my_gamification_visibility(boolean) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.set_my_gamification_visibility(boolean) FROM PUBLIC, anon;

-- =====================================================================
-- Reload PostgREST surface
-- =====================================================================

NOTIFY pgrst, 'reload schema';

-- =====================================================================
-- Rollback (commented)
-- =====================================================================
-- DROP FUNCTION IF EXISTS public.set_my_gamification_visibility(boolean);
-- DROP FUNCTION IF EXISTS public.get_gamification_leaderboard(integer, integer, text);
-- ALTER TABLE public.members DROP COLUMN IF EXISTS gamification_opt_out;
-- -- Restore previous get_gamification_leaderboard() (zero-arg) from migration <previous>
