-- ============================================================================
-- ADR-0015 Phase 1 — publication_submissions reader cutover (2nd C3 table)
--
-- Scope: 3 reader RPCs refactored to JOIN initiatives instead of tribes.
-- Output shape preserved identically (frontend/MCP contract intact).
--
-- Dual-write integrity: 8/8 rows both tribe_id + initiative_id (lossless).
--
-- Changed RPCs:
--   1. get_publication_submissions       — LEFT JOIN tribes → initiatives
--   2. get_publication_submission_detail — LEFT JOIN tribes → initiatives
--   3. get_publication_pipeline_summary  — GROUP BY tribe_id → initiative_id
--
-- NOT changed (writes still valid; triggers sync until Phase 2/3):
--   - create_publication_submission (writes tribe_id, dual-write handles sync)
--
-- ADR: ADR-0015 Phase 1, ADR-0005
-- Rollback: restore prior bodies (see bottom of file).
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. get_publication_submissions — SETOF TABLE return, JOIN initiatives
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_publication_submissions(
  p_status submission_status DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  title text,
  abstract text,
  target_type submission_target_type,
  target_name text,
  status submission_status,
  submission_date date,
  presentation_date date,
  primary_author_name text,
  tribe_name text,
  estimated_cost_brl numeric,
  actual_cost_brl numeric,
  created_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ps.id, ps.title, ps.abstract, ps.target_type, ps.target_name,
    ps.status, ps.submission_date, ps.presentation_date,
    m.name AS primary_author_name,
    i.title AS tribe_name,  -- ADR-0015 Phase 1: derive from initiative
    ps.estimated_cost_brl, ps.actual_cost_brl, ps.created_at
  FROM public.publication_submissions ps
  LEFT JOIN public.members m ON m.id = ps.primary_author_id
  LEFT JOIN public.initiatives i ON i.id = ps.initiative_id  -- ADR-0015 Phase 1
  WHERE (p_status IS NULL OR ps.status = p_status)
    AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)  -- ADR-0015 Phase 1
  ORDER BY ps.created_at DESC;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. get_publication_submission_detail — JSONB single-row, JOIN initiatives
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_publication_submission_detail(
  p_submission_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'submission', jsonb_build_object(
      'id', ps.id,
      'title', ps.title,
      'abstract', ps.abstract,
      'target_type', ps.target_type::text,
      'target_name', ps.target_name,
      'target_url', ps.target_url,
      'status', ps.status::text,
      'submission_date', ps.submission_date,
      'review_deadline', ps.review_deadline,
      'acceptance_date', ps.acceptance_date,
      'presentation_date', ps.presentation_date,
      'primary_author_id', ps.primary_author_id,
      'primary_author_name', m.name,
      'estimated_cost_brl', ps.estimated_cost_brl,
      'actual_cost_brl', ps.actual_cost_brl,
      'cost_paid_by', ps.cost_paid_by,
      'reviewer_feedback', ps.reviewer_feedback,
      'doi_or_url', ps.doi_or_url,
      'tribe_id', ps.tribe_id,
      'tribe_name', i.title,  -- ADR-0015 Phase 1
      'board_item_id', ps.board_item_id,
      'created_by', ps.created_by,
      'created_at', ps.created_at,
      'updated_at', ps.updated_at
    ),
    'authors', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', psa.id,
        'member_id', psa.member_id,
        'member_name', am.name,
        'author_order', psa.author_order,
        'is_corresponding', psa.is_corresponding
      ) ORDER BY psa.author_order), '[]'::jsonb)
      FROM public.publication_submission_authors psa
      JOIN public.members am ON am.id = psa.member_id
      WHERE psa.submission_id = ps.id
    )
  )
  INTO v_result
  FROM public.publication_submissions ps
  LEFT JOIN public.members m ON m.id = ps.primary_author_id
  LEFT JOIN public.initiatives i ON i.id = ps.initiative_id  -- ADR-0015 Phase 1
  WHERE ps.id = p_submission_id;

  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. get_publication_pipeline_summary — GROUP BY initiative_id
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_publication_pipeline_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM public.publication_submissions),
    'by_status', (
      SELECT COALESCE(jsonb_object_agg(s, c), '{}'::jsonb)
      FROM (SELECT status::text as s, count(*) as c FROM public.publication_submissions GROUP BY status) x
    ),
    'by_target_type', (
      SELECT COALESCE(jsonb_object_agg(tt, c), '{}'::jsonb)
      FROM (SELECT target_type::text as tt, count(*) as c FROM public.publication_submissions GROUP BY target_type) x
    ),
    'by_tribe', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'tribe_name', i.title,  -- ADR-0015 Phase 1: use initiatives.title
        'count', sub.cnt
      )), '[]'::jsonb)
      FROM (
        SELECT initiative_id, count(*) as cnt
        FROM public.publication_submissions
        WHERE initiative_id IS NOT NULL
        GROUP BY initiative_id
      ) sub
      JOIN public.initiatives i ON i.id = sub.initiative_id  -- ADR-0015 Phase 1
    ),
    'estimated_total_cost', (SELECT COALESCE(SUM(estimated_cost_brl), 0) FROM public.publication_submissions),
    'actual_total_cost', (SELECT COALESCE(SUM(actual_cost_brl), 0) FROM public.publication_submissions)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- ROLLBACK: prior bodies joined `tribes t ON t.id = ps.tribe_id` + t.name.
-- Restore requires swapping `initiatives i`/`i.title`/`i.legacy_tribe_id`
-- back to `tribes t`/`t.name`/`ps.tribe_id` and using tribe_id for GROUP BY
-- + SUB JOIN.
-- ═══════════════════════════════════════════════════════════════════════════
