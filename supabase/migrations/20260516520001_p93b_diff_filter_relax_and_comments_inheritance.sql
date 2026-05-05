-- p93b (2026-05-05): Fix diff "anterior↔atual" + comments inheritance from prior versions
--
-- Bug 1: get_previous_locked_version had restrictive filter chain.status='approved' which
-- blocked the diff tab for docs in pre-ratification state (Round 5/6 case). Replace with
-- NOT EXISTS chain.status='withdrawn' to exclude only IP-1 seeds while still showing prior
-- locked versions.
--
-- Bug 2: 19 unresolved comments from Round 4 (Fabricio+Sarah signed 21-27/04) are tied to
-- v1/v2 — invisible when curator opens new v6 chain. Add p_include_prior_versions param +
-- 3 new return cols to surface inherited comments.

-- =========================================================================
-- 1. get_previous_locked_version: relax filter
-- =========================================================================

CREATE OR REPLACE FUNCTION public.get_previous_locked_version(p_version_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_current record;
  v_prev record;
BEGIN
  SELECT dv.id, dv.document_id, dv.version_number
  INTO v_current FROM public.document_versions dv WHERE dv.id = p_version_id;
  IF v_current.id IS NULL THEN RETURN jsonb_build_object('error','version_not_found'); END IF;

  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html,
         dv.content_markdown, dv.locked_at, dv.published_at
  INTO v_prev
  FROM public.document_versions dv
  WHERE dv.document_id = v_current.document_id
    AND dv.version_number < v_current.version_number
    AND dv.locked_at IS NOT NULL
    -- ADR-0016 Amendment 2 revised p93b: excludes only IP-1 seeds (chain withdrawn).
    -- Previous filter required chain.status='approved' — too restrictive, blocked diff
    -- between revision rounds when docs in pre-ratification state (Round 5/6 case).
    AND NOT EXISTS (
      SELECT 1 FROM public.approval_chains ac
      WHERE ac.version_id = dv.id AND ac.status = 'withdrawn'
    )
  ORDER BY dv.version_number DESC LIMIT 1;

  IF v_prev.id IS NULL THEN RETURN jsonb_build_object('exists', false); END IF;

  RETURN jsonb_build_object(
    'exists', true,
    'version_id', v_prev.id,
    'version_number', v_prev.version_number,
    'version_label', v_prev.version_label,
    'content_html', v_prev.content_html,
    'content_markdown', v_prev.content_markdown,
    'locked_at', v_prev.locked_at,
    'published_at', v_prev.published_at
  );
END;
$function$;

COMMENT ON FUNCTION public.get_previous_locked_version(uuid) IS
  'p93b revised: returns immediate prior locked version of same document. Excludes only seeds with chain.status=withdrawn (IP-1 case). Replaces previous filter that required chain.status=approved (was blocking diff between revision rounds for docs in pre-ratification state).';

-- =========================================================================
-- 2. list_document_comments: add p_include_prior_versions + 3 new return cols
-- =========================================================================

DROP FUNCTION IF EXISTS public.list_document_comments(uuid, boolean);

CREATE OR REPLACE FUNCTION public.list_document_comments(
  p_version_id uuid,
  p_include_resolved boolean DEFAULT false,
  p_include_prior_versions boolean DEFAULT false
)
RETURNS TABLE (
  id uuid,
  clause_anchor text,
  body text,
  visibility text,
  parent_id uuid,
  author_id uuid,
  author_name text,
  author_role text,
  created_at timestamptz,
  resolved_at timestamptz,
  resolved_by_name text,
  resolution_note text,
  from_version_id uuid,
  from_version_label text,
  is_inherited boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_member record;
  v_can_see_all boolean;
  v_document_id uuid;
  v_current_version_number int;
BEGIN
  SELECT m.id, m.operational_role, m.designations, m.is_active
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL OR v_member.is_active = false THEN RETURN; END IF;

  v_can_see_all := public.can_by_member(v_member.id, 'participate_in_governance_review');

  SELECT dv.document_id, dv.version_number
  INTO v_document_id, v_current_version_number
  FROM public.document_versions dv WHERE dv.id = p_version_id;
  IF v_document_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    c.id,
    c.clause_anchor,
    c.body,
    c.visibility,
    c.parent_id,
    c.author_id,
    m.name AS author_name,
    m.operational_role AS author_role,
    c.created_at,
    c.resolved_at,
    (SELECT rm.name FROM public.members rm WHERE rm.id = c.resolved_by) AS resolved_by_name,
    c.resolution_note,
    dv.id AS from_version_id,
    dv.version_label AS from_version_label,
    (dv.id <> p_version_id) AS is_inherited
  FROM public.document_comments c
  JOIN public.members m ON m.id = c.author_id
  JOIN public.document_versions dv ON dv.id = c.document_version_id
  WHERE
    (
      c.document_version_id = p_version_id
      OR (
        p_include_prior_versions
        AND dv.document_id = v_document_id
        AND dv.locked_at IS NOT NULL
        AND dv.version_number < v_current_version_number
      )
    )
    AND (p_include_resolved OR c.resolved_at IS NULL)
    AND (
      v_can_see_all
      OR c.author_id = v_member.id
    )
  ORDER BY (dv.id <> p_version_id), c.clause_anchor NULLS LAST, dv.version_number DESC, c.created_at ASC;
END;
$function$;

COMMENT ON FUNCTION public.list_document_comments(uuid, boolean, boolean) IS
  'p93b revised: now supports p_include_prior_versions=true to surface comments from all prior locked versions of the same document. Returns 3 extra fields (from_version_id, from_version_label, is_inherited) for UI to badge inherited comments. Authority unchanged — participate_in_governance_review or own comment.';

GRANT EXECUTE ON FUNCTION public.list_document_comments(uuid, boolean, boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';
