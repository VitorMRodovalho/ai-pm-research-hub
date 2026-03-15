-- ============================================================
-- F-02: Migrate exec_funnel_v2 → exec_funnel_summary
-- Date: 2026-03-14
-- ============================================================

-- Step 1: Drop old no-params exec_funnel_summary
DROP FUNCTION IF EXISTS public.exec_funnel_summary();

-- Step 2: Create new exec_funnel_summary with filter params (same body as exec_funnel_v2)
CREATE OR REPLACE FUNCTION public.exec_funnel_summary(
  p_cycle_code text DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL,
  p_chapter text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.can_read_internal_analytics() THEN
    RAISE EXCEPTION 'Internal analytics access required';
  END IF;

  WITH scoped AS (
    SELECT * FROM public.analytics_member_scope(p_cycle_code, p_tribe_id, p_chapter)
  ),
  core_total AS (
    SELECT count(*)::integer AS total_core_courses
    FROM public.courses
    WHERE category = 'core'
  ),
  member_core_progress AS (
    SELECT
      s.member_id,
      count(DISTINCT cp.course_id) FILTER (WHERE cp.status = 'completed')::integer AS completed_core_courses
    FROM scoped s
    LEFT JOIN public.course_progress cp ON cp.member_id = s.member_id
    LEFT JOIN public.courses c ON c.id = cp.course_id AND c.category = 'core'
    GROUP BY s.member_id
  ),
  published_artifacts AS (
    SELECT DISTINCT s.member_id
    FROM scoped s
    JOIN public.artifacts a ON a.member_id = s.member_id
    WHERE a.status = 'published'
      AND coalesce(a.published_at, a.created_at, now()) >= s.cycle_start
      AND (
        s.cycle_end IS NULL
        OR coalesce(a.published_at, a.created_at, now()) < s.cycle_end + interval '1 day'
      )
  ),
  stage_rollup AS (
    SELECT
      count(DISTINCT s.member_id)::integer AS total_members,
      count(DISTINCT s.member_id) FILTER (
        WHERE coalesce(mcp.completed_core_courses, 0) >= coalesce((SELECT total_core_courses FROM core_total), 0)
      )::integer AS members_with_full_core_trail,
      count(DISTINCT s.member_id) FILTER (WHERE s.tribe_id IS NOT NULL)::integer AS members_allocated_to_tribe,
      count(DISTINCT pa.member_id)::integer AS members_with_published_artifact
    FROM scoped s
    LEFT JOIN member_core_progress mcp ON mcp.member_id = s.member_id
    LEFT JOIN published_artifacts pa ON pa.member_id = s.member_id
  )
  SELECT jsonb_build_object(
    'cycle_code', (SELECT max(cycle_code) FROM scoped),
    'cycle_label', (SELECT max(cycle_label) FROM scoped),
    'filters', jsonb_build_object(
      'cycle_code', p_cycle_code,
      'tribe_id', p_tribe_id,
      'chapter', p_chapter
    ),
    'stages', jsonb_build_object(
      'total_members', coalesce((SELECT total_members FROM stage_rollup), 0),
      'members_with_full_core_trail', coalesce((SELECT members_with_full_core_trail FROM stage_rollup), 0),
      'members_allocated_to_tribe', coalesce((SELECT members_allocated_to_tribe FROM stage_rollup), 0),
      'members_with_published_artifact', coalesce((SELECT members_with_published_artifact FROM stage_rollup), 0)
    ),
    'breakdown_by_tribe', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.tribe_id)
      FROM (
        SELECT
          s.tribe_id,
          count(DISTINCT s.member_id)::integer AS total_members,
          count(DISTINCT s.member_id) FILTER (
            WHERE coalesce(mcp.completed_core_courses, 0) >= coalesce((SELECT total_core_courses FROM core_total), 0)
          )::integer AS members_with_full_core_trail,
          count(DISTINCT s.member_id) FILTER (WHERE s.tribe_id IS NOT NULL)::integer AS members_allocated_to_tribe,
          count(DISTINCT pa.member_id)::integer AS members_with_published_artifact
        FROM scoped s
        LEFT JOIN member_core_progress mcp ON mcp.member_id = s.member_id
        LEFT JOIN published_artifacts pa ON pa.member_id = s.member_id
        WHERE s.tribe_id IS NOT NULL
        GROUP BY s.tribe_id
      ) t
    ), '[]'::jsonb),
    'breakdown_by_chapter', coalesce((
      SELECT jsonb_agg(to_jsonb(c) ORDER BY c.chapter)
      FROM (
        SELECT
          s.chapter,
          count(DISTINCT s.member_id)::integer AS total_members,
          count(DISTINCT s.member_id) FILTER (
            WHERE coalesce(mcp.completed_core_courses, 0) >= coalesce((SELECT total_core_courses FROM core_total), 0)
          )::integer AS members_with_full_core_trail,
          count(DISTINCT s.member_id) FILTER (WHERE s.tribe_id IS NOT NULL)::integer AS members_allocated_to_tribe,
          count(DISTINCT pa.member_id)::integer AS members_with_published_artifact
        FROM scoped s
        LEFT JOIN member_core_progress mcp ON mcp.member_id = s.member_id
        LEFT JOIN published_artifacts pa ON pa.member_id = s.member_id
        WHERE s.chapter IS NOT NULL AND trim(s.chapter) <> ''
        GROUP BY s.chapter
      ) c
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN coalesce(v_result, jsonb_build_object(
    'cycle_code', p_cycle_code,
    'filters', jsonb_build_object('cycle_code', p_cycle_code, 'tribe_id', p_tribe_id, 'chapter', p_chapter),
    'stages', jsonb_build_object(
      'total_members', 0,
      'members_with_full_core_trail', 0,
      'members_allocated_to_tribe', 0,
      'members_with_published_artifact', 0
    ),
    'breakdown_by_tribe', '[]'::jsonb,
    'breakdown_by_chapter', '[]'::jsonb
  ));
END;
$$;

GRANT EXECUTE ON FUNCTION public.exec_funnel_summary(text, integer, text) TO authenticated;

-- Step 3: Update exec_analytics_v2_quality to call exec_funnel_summary instead of exec_funnel_v2
CREATE OR REPLACE FUNCTION public.exec_analytics_v2_quality(
  p_cycle_code text DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL,
  p_chapter text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
  v_funnel jsonb;
  v_impact jsonb;
  v_roi jsonb;
  v_stages jsonb;
  v_total integer := 0;
  v_onboarding integer := 0;
  v_allocated integer := 0;
  v_published integer := 0;
  v_before integer := 30;
  v_after integer := 90;
  v_issues text[] := '{}';
  v_warnings text[] := '{}';
BEGIN
  IF NOT public.can_read_internal_analytics() THEN
    RAISE EXCEPTION 'Internal analytics access required';
  END IF;

  v_funnel := public.exec_funnel_summary(p_cycle_code, p_tribe_id, p_chapter);
  v_impact := public.exec_impact_hours_v2(p_cycle_code, p_tribe_id, p_chapter);
  v_roi := public.exec_chapter_roi(p_cycle_code, p_tribe_id, p_chapter);
  v_stages := coalesce(v_funnel -> 'stages', '{}'::jsonb);

  v_total := coalesce((v_stages ->> 'total_members')::integer, 0);
  v_onboarding := coalesce((v_stages ->> 'members_with_full_core_trail')::integer, 0);
  v_allocated := coalesce((v_stages ->> 'members_allocated_to_tribe')::integer, 0);
  v_published := coalesce((v_stages ->> 'members_with_published_artifact')::integer, 0);

  IF v_total < 0 OR v_onboarding < 0 OR v_allocated < 0 OR v_published < 0 THEN
    v_issues := array_append(v_issues, 'negative_stage_values');
  END IF;

  IF v_onboarding > v_total THEN
    v_issues := array_append(v_issues, 'onboarding_exceeds_total');
  END IF;
  IF v_allocated > v_total THEN
    v_issues := array_append(v_issues, 'allocated_exceeds_total');
  END IF;
  IF v_published > v_total THEN
    v_issues := array_append(v_issues, 'published_exceeds_total');
  END IF;

  IF v_published > v_allocated AND v_allocated > 0 THEN
    v_warnings := array_append(v_warnings, 'published_exceeds_allocated');
  END IF;

  IF coalesce((v_impact ->> 'total_impact_hours')::numeric, 0) < 0 THEN
    v_issues := array_append(v_issues, 'negative_impact_hours');
  END IF;

  IF coalesce((v_impact ->> 'percent_of_target')::numeric, 0) > 200 THEN
    v_warnings := array_append(v_warnings, 'impact_percent_above_200');
  END IF;

  IF coalesce((v_roi -> 'attribution_window' ->> 'before_days')::integer, v_before) <> v_before
     OR coalesce((v_roi -> 'attribution_window' ->> 'after_days')::integer, v_after) <> v_after THEN
    v_warnings := array_append(v_warnings, 'unexpected_roi_window');
  END IF;

  RETURN jsonb_build_object(
    'ok', coalesce(array_length(v_issues, 1), 0) = 0,
    'filters', jsonb_build_object(
      'cycle_code', p_cycle_code,
      'tribe_id', p_tribe_id,
      'chapter', p_chapter
    ),
    'attribution_window', jsonb_build_object(
      'before_days', v_before,
      'after_days', v_after
    ),
    'issues', to_jsonb(v_issues),
    'warnings', to_jsonb(v_warnings),
    'snapshot', jsonb_build_object(
      'funnel_stages', v_stages,
      'impact_total_hours', coalesce((v_impact ->> 'total_impact_hours')::numeric, 0),
      'impact_percent_of_target', coalesce((v_impact ->> 'percent_of_target')::numeric, 0),
      'roi_chapters_count', coalesce(jsonb_array_length(v_roi -> 'chapters'), 0)
    )
  );
END;
$$;

-- Step 4: Drop exec_funnel_v2
DROP FUNCTION IF EXISTS public.exec_funnel_v2(text, integer, text) CASCADE;
