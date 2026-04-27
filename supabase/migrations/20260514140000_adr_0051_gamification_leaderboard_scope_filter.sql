-- ADR-0051: gamification_leaderboard RPC v3 — scope filter (chapter/tribe)
--
-- Closes #101 P2 (scope filter portion). Aggregate stats (current_streak_count)
-- and UI toggle remain deferred — UI toggle needs browser smoke (out of autonomous
-- scope), streak_count is a future ADR-0052 candidate when first frontend caller
-- demands it.
--
-- Backwards compat: all new params have DEFAULT. Existing 0-arg AND 3-arg
-- callsites work unchanged. Three NEW params added at the END of the signature:
--   p_scope_kind text DEFAULT 'global'  -- 'global' | 'chapter' | 'tribe'
--   p_chapter_code text DEFAULT NULL    -- required if scope_kind='chapter'
--   p_initiative_id uuid DEFAULT NULL   -- required if scope_kind='tribe'
--
-- Signature change requires DROP + CREATE (per database rules).
--
-- Filter semantics:
--   global: no scope filter (current behavior)
--   chapter: WHERE m.chapter = p_chapter_code (e.g. 'PMI-CE', 'PMI-DF')
--   tribe:   WHERE caller has authoritative auth_engagements row for the initiative
--            (uses persons.legacy_member_id ↔ members.id bridge)

DROP FUNCTION IF EXISTS public.get_gamification_leaderboard(integer, integer, text);

CREATE OR REPLACE FUNCTION public.get_gamification_leaderboard(
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_cycle_code text DEFAULT NULL,
  p_scope_kind text DEFAULT 'global',
  p_chapter_code text DEFAULT NULL,
  p_initiative_id uuid DEFAULT NULL
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
  v_scope text;
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

  -- Validate scope_kind
  v_scope := COALESCE(NULLIF(trim(p_scope_kind), ''), 'global');
  IF v_scope NOT IN ('global', 'chapter', 'tribe') THEN
    RAISE EXCEPTION 'invalid_scope_kind: % (allowed: global|chapter|tribe)', v_scope
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_scope = 'chapter' AND (p_chapter_code IS NULL OR trim(p_chapter_code) = '') THEN
    RAISE EXCEPTION 'chapter_code_required: scope_kind=chapter requires p_chapter_code'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_scope = 'tribe' AND p_initiative_id IS NULL THEN
    RAISE EXCEPTION 'initiative_id_required: scope_kind=tribe requires p_initiative_id'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Resolve cycle window
  IF p_cycle_code IS NOT NULL THEN
    SELECT c.cycle_start, c.cycle_end
    INTO v_cycle_start, v_cycle_end
    FROM public.cycles c WHERE c.cycle_code = p_cycle_code;
    IF v_cycle_start IS NULL THEN
      RAISE EXCEPTION 'cycle_not_found: %', p_cycle_code USING ERRCODE = 'no_data_found';
    END IF;
  ELSE
    SELECT c.cycle_start, c.cycle_end
    INTO v_cycle_start, v_cycle_end
    FROM public.cycles c WHERE c.is_current = true LIMIT 1;
  END IF;

  -- Compute total_count once (post-filter, includes scope filter)
  SELECT COUNT(*) INTO v_total_count
  FROM public.members m
  WHERE m.current_cycle_active = true
    AND m.gamification_opt_out = false
    AND (
      v_scope = 'global'
      OR (v_scope = 'chapter' AND m.chapter = p_chapter_code)
      OR (v_scope = 'tribe' AND EXISTS (
        SELECT 1 FROM public.persons p
        JOIN public.auth_engagements ae ON ae.person_id = p.id
        WHERE p.legacy_member_id = m.id
          AND ae.is_authoritative = true
          AND ae.initiative_id = p_initiative_id
      ))
    );

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
    AND (
      v_scope = 'global'
      OR (v_scope = 'chapter' AND m.chapter = p_chapter_code)
      OR (v_scope = 'tribe' AND EXISTS (
        SELECT 1 FROM public.persons p
        JOIN public.auth_engagements ae ON ae.person_id = p.id
        WHERE p.legacy_member_id = m.id
          AND ae.is_authoritative = true
          AND ae.initiative_id = p_initiative_id
      ))
    )
  GROUP BY m.id, m.name, m.chapter, m.photo_url, m.operational_role, m.designations
  ORDER BY total_points DESC, m.name ASC
  LIMIT v_effective_limit
  OFFSET v_effective_offset;
END;
$$;

COMMENT ON FUNCTION public.get_gamification_leaderboard(integer, integer, text, text, text, uuid) IS
  'ADR-0051 #101 v3: leaderboard with pagination, cycle filter, opt-out filter, AND scope filter (global|chapter|tribe). New scope params at end (all DEFAULT). Backwards-compat with v2 (3-arg) and v1 (0-arg) callsites preserved.';

GRANT EXECUTE ON FUNCTION public.get_gamification_leaderboard(integer, integer, text, text, text, uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_gamification_leaderboard(integer, integer, text, text, text, uuid) FROM PUBLIC, anon;

NOTIFY pgrst, 'reload schema';

-- =====================================================================
-- Rollback (commented)
-- =====================================================================
-- DROP FUNCTION IF EXISTS public.get_gamification_leaderboard(integer, integer, text, text, text, uuid);
-- -- Restore v2 from migration 20260514130000 by re-running its CREATE OR REPLACE
