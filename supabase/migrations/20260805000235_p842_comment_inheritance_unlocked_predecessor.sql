-- #842 (2026-06-22): governance comment inheritance must reach UNLOCKED predecessors.
--
-- Gap: comment inheritance (p93b) and the "anterior↔atual" diff both gated the prior
-- version on `dv.locked_at IS NOT NULL`. A version that is superseded WITHOUT ever being
-- locked (real case: TAP CPMAI doc d7447a94 — R00 chain=superseded, locked=false, carries
-- 4 unresolved comments; R01 current/locked shows 0) escapes that gate, so the curator
-- reviewing R01 never sees R00's open comments and the diff tab is empty.
--
-- Fix (signal-only, PM-approved 2026-06-22): relax the predecessor predicate to the same
-- "exclude only chain.status='withdrawn'" model p93b already adopted for get_previous_locked_version.
-- This is read-only/additive — NO comment rows are mutated or re-anchored. Inherited comments
-- keep their provenance badge (is_inherited / from_version_label) so the UI shows "↩ R00".
--
-- NOTE: list_document_comments relied SOLELY on locked_at to exclude IP-1 seeds (it had no
-- withdrawn check), so here we REPLACE locked_at with NOT EXISTS(chain withdrawn) — not just drop it.

-- =========================================================================
-- 1. get_previous_locked_version: drop the locked_at gate (withdrawn-exclusion stays)
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
    -- #842: locked_at gate removed — a superseded-but-unlocked round is still a real
    -- predecessor. The withdrawn-exclusion below already drops IP-1 seeds / abandoned chains.
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
  '#842 revised (was p93b): returns immediate prior version of same document for the diff baseline. Excludes only chains with status=withdrawn (IP-1 seeds / abandoned). NOTE: name kept for caller stability but the version may be UNLOCKED (a superseded-but-not-locked round still counts as a predecessor).';

-- =========================================================================
-- 2. list_document_comments: replace locked_at gate with withdrawn-exclusion
-- =========================================================================

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
        AND dv.version_number < v_current_version_number
        -- #842: was `dv.locked_at IS NOT NULL` (the sole seed-exclusion here). Replaced with
        -- withdrawn-exclusion so superseded-but-unlocked rounds (R00 case) inherit too, while
        -- IP-1 seeds / abandoned chains stay hidden.
        AND NOT EXISTS (
          SELECT 1 FROM public.approval_chains ac
          WHERE ac.version_id = dv.id AND ac.status = 'withdrawn'
        )
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
  '#842 revised (was p93b): p_include_prior_versions=true surfaces comments from all prior versions of the same document whose chain is NOT withdrawn (includes superseded-but-unlocked rounds — locked_at gate removed). Returns from_version_id/from_version_label/is_inherited for the UI badge. Authority unchanged — participate_in_governance_review or own comment.';

GRANT EXECUTE ON FUNCTION public.list_document_comments(uuid, boolean, boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';
