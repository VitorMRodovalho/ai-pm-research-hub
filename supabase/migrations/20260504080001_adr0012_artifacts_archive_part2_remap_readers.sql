-- ADR-0012 Princípio 4 — artifacts archival part 2: remap 8 readers para publication_submissions
-- 29 rows migradas em part 1 (20260504080000). Dashboard agora lê de publication_submissions
-- (fonte viva). Semantics preserved: get_executive_kpis retorna mesma contagem (6 published).
--
-- Remap applied:
--   (1) exec_funnel_summary       — CTE published_artifacts → published_publications
--   (2) exec_skills_radar         — correlated subquery → publication_submissions
--   (3) get_executive_kpis        — v_total_artifacts → COUNT publication_submissions
--   (4) sync_attendance_points    — artifact INSERT points → publication category
--   (5) platform_activity_summary — 2 refs (snapshot + monthly_activity)
--   (6) list_curation_board       — excise artifacts UNION arm (publication_submissions flow
--                                    usa approval_chains via ReviewChainIsland)
--   (7) list_pending_curation     — excise artifacts branch
--   (8) enqueue_artifact_publication_card — COMMENT deprecated
--
-- Part 3 (DROP TABLE CASCADE + remove I_artifacts_frozen) deferred 48h+ per
-- ADR-0012 Princípio 3 shadow reasoning.

CREATE OR REPLACE FUNCTION public.exec_funnel_summary(p_cycle_code text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer, p_chapter text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.can_read_internal_analytics() THEN
    RAISE EXCEPTION 'Internal analytics access required';
  END IF;

  WITH scoped AS (SELECT * FROM public.analytics_member_scope(p_cycle_code, p_tribe_id, p_chapter)),
  core_total AS (SELECT count(*)::integer AS total_core_courses FROM public.courses WHERE category = 'core'),
  member_core_progress AS (
    SELECT s.member_id, count(DISTINCT cp.course_id) FILTER (WHERE cp.status = 'completed')::integer AS completed_core_courses
    FROM scoped s
    LEFT JOIN public.course_progress cp ON cp.member_id = s.member_id
    LEFT JOIN public.courses c ON c.id = cp.course_id AND c.category = 'core'
    GROUP BY s.member_id
  ),
  published_publications AS (
    -- ADR-0012 archival: ex-artifacts → publication_submissions
    SELECT DISTINCT s.member_id
    FROM scoped s
    JOIN public.publication_submissions ps ON ps.primary_author_id = s.member_id
    WHERE ps.status = 'published'::submission_status
      AND coalesce(ps.acceptance_date, ps.submission_date, ps.created_at::date, now()::date) >= s.cycle_start::date
      AND (s.cycle_end IS NULL OR coalesce(ps.acceptance_date, ps.submission_date, ps.created_at::date, now()::date) < (s.cycle_end + interval '1 day')::date)
  ),
  stage_rollup AS (
    SELECT count(DISTINCT s.member_id)::integer AS total_members,
      count(DISTINCT s.member_id) FILTER (WHERE coalesce(mcp.completed_core_courses, 0) >= coalesce((SELECT total_core_courses FROM core_total), 0))::integer AS members_with_full_core_trail,
      count(DISTINCT s.member_id) FILTER (WHERE s.tribe_id IS NOT NULL)::integer AS members_allocated_to_tribe,
      count(DISTINCT pp.member_id)::integer AS members_with_published_artifact
    FROM scoped s
    LEFT JOIN member_core_progress mcp ON mcp.member_id = s.member_id
    LEFT JOIN published_publications pp ON pp.member_id = s.member_id
  )
  SELECT jsonb_build_object(
    'cycle_code', (SELECT max(cycle_code) FROM scoped),
    'cycle_label', (SELECT max(cycle_label) FROM scoped),
    'filters', jsonb_build_object('cycle_code', p_cycle_code, 'tribe_id', p_tribe_id, 'chapter', p_chapter),
    'stages', jsonb_build_object(
      'total_members', coalesce((SELECT total_members FROM stage_rollup), 0),
      'members_with_full_core_trail', coalesce((SELECT members_with_full_core_trail FROM stage_rollup), 0),
      'members_allocated_to_tribe', coalesce((SELECT members_allocated_to_tribe FROM stage_rollup), 0),
      'members_with_published_artifact', coalesce((SELECT members_with_published_artifact FROM stage_rollup), 0)
    ),
    'breakdown_by_tribe', coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.tribe_id) FROM (
      SELECT s.tribe_id,
        count(DISTINCT s.member_id)::integer AS total_members,
        count(DISTINCT s.member_id) FILTER (WHERE coalesce(mcp.completed_core_courses, 0) >= coalesce((SELECT total_core_courses FROM core_total), 0))::integer AS members_with_full_core_trail,
        count(DISTINCT s.member_id) FILTER (WHERE s.tribe_id IS NOT NULL)::integer AS members_allocated_to_tribe,
        count(DISTINCT pp.member_id)::integer AS members_with_published_artifact
      FROM scoped s
      LEFT JOIN member_core_progress mcp ON mcp.member_id = s.member_id
      LEFT JOIN published_publications pp ON pp.member_id = s.member_id
      WHERE s.tribe_id IS NOT NULL GROUP BY s.tribe_id) t), '[]'::jsonb),
    'breakdown_by_chapter', coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.chapter) FROM (
      SELECT s.chapter,
        count(DISTINCT s.member_id)::integer AS total_members,
        count(DISTINCT s.member_id) FILTER (WHERE coalesce(mcp.completed_core_courses, 0) >= coalesce((SELECT total_core_courses FROM core_total), 0))::integer AS members_with_full_core_trail,
        count(DISTINCT s.member_id) FILTER (WHERE s.tribe_id IS NOT NULL)::integer AS members_allocated_to_tribe,
        count(DISTINCT pp.member_id)::integer AS members_with_published_artifact
      FROM scoped s
      LEFT JOIN member_core_progress mcp ON mcp.member_id = s.member_id
      LEFT JOIN published_publications pp ON pp.member_id = s.member_id
      WHERE s.chapter IS NOT NULL AND trim(s.chapter) <> '' GROUP BY s.chapter) c), '[]'::jsonb)
  ) INTO v_result;

  RETURN coalesce(v_result, jsonb_build_object(
    'cycle_code', p_cycle_code,
    'filters', jsonb_build_object('cycle_code', p_cycle_code, 'tribe_id', p_tribe_id, 'chapter', p_chapter),
    'stages', jsonb_build_object('total_members', 0, 'members_with_full_core_trail', 0, 'members_allocated_to_tribe', 0, 'members_with_published_artifact', 0),
    'breakdown_by_tribe', '[]'::jsonb, 'breakdown_by_chapter', '[]'::jsonb));
END;
$function$;

-- Demais 7 functions (exec_skills_radar, get_executive_kpis, sync_attendance_points,
-- platform_activity_summary, list_curation_board, list_pending_curation, enqueue comment)
-- aplicadas via MCP apply_migration em 20260504080001. Arquivo salvo aqui só para referência
-- da mudança principal (exec_funnel_summary). Bodies completos em git log.

COMMENT ON FUNCTION public.enqueue_artifact_publication_card(uuid, uuid) IS
  '[DEPRECATED — ADR-0012 archival 20260504080001] Reads from frozen public.artifacts. 29 legacy rows migrated to publication_submissions. New curation via approval_chains (ReviewChainIsland). Function preserved for compat but unreachable. Will be DROP CASCADE with artifacts table in migration 20260504090000+ (48h+ shadow window).';

NOTIFY pgrst, 'reload schema';
