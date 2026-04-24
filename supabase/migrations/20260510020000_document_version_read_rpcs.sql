-- =============================================================================
-- Document version workflow — read surface (3 RPCs)
-- =============================================================================
-- Issue: #85 Onda B P0 — Document versions workflow (review UX via MCP)
-- Context: p41 shipped write surface (upsert_document_version, lock_document_version,
--   delete_document_version_draft) + governance workflow wrappers (sign_ratification_gate,
--   change requests). Missing: read surface para history / diff / document composition.
--
-- This migration adds:
--   1. list_document_versions(p_document_id) — history + comment counts per version
--   2. get_version_diff(p_version_a, p_version_b) — side-by-side content pair
--   3. get_document_detail(p_document_id) — composite read (doc + current_version +
--      active_chain + signed/pending gates for caller + comment counts)
--
-- Auth: all 3 require authenticated member (auth.uid() → members.id match).
-- Governance documents are shared org-wide; RLS on base tables already gates
-- SELECT to authenticated role. SECURITY DEFINER is used only to bypass RLS on
-- joins (document_comments visibility, approval_signoffs), never to grant new
-- access to non-members.
--
-- No schema changes, no column changes — additive RPC-only migration.
-- Rollback: DROP FUNCTION on all 3.
-- =============================================================================

-- 1. list_document_versions --------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_document_versions(p_document_id uuid)
RETURNS TABLE(
  version_id uuid,
  version_number int,
  version_label text,
  authored_by uuid,
  authored_by_name text,
  authored_at timestamptz,
  locked_at timestamptz,
  locked_by_name text,
  published_at timestamptz,
  notes text,
  is_current boolean,
  content_html_length int,
  has_markdown boolean,
  comments_total bigint,
  comments_unresolved bigint
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_member_id uuid;
  v_current_version_id uuid;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN RETURN; END IF;

  SELECT gd.current_version_id INTO v_current_version_id
  FROM public.governance_documents gd
  WHERE gd.id = p_document_id;
  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    dv.id,
    dv.version_number,
    dv.version_label,
    dv.authored_by,
    am.name,
    dv.authored_at,
    dv.locked_at,
    lm.name,
    dv.published_at,
    dv.notes,
    (dv.id = v_current_version_id),
    COALESCE(length(dv.content_html), 0),
    (dv.content_markdown IS NOT NULL AND length(dv.content_markdown) > 0),
    (SELECT COUNT(*) FROM public.document_comments c
      WHERE c.document_version_id = dv.id),
    (SELECT COUNT(*) FROM public.document_comments c
      WHERE c.document_version_id = dv.id AND c.resolved_at IS NULL)
  FROM public.document_versions dv
  LEFT JOIN public.members am ON am.id = dv.authored_by
  LEFT JOIN public.members lm ON lm.id = dv.locked_by
  WHERE dv.document_id = p_document_id
  ORDER BY dv.version_number DESC;
END;
$fn$;

COMMENT ON FUNCTION public.list_document_versions(uuid) IS
  'Returns full version history of a governance document (all versions, newest first). '
  'Requires authenticated active member. Surfaces comment counts per version for review UX. '
  'Issue #85 Onda B P0 — conversational review workflow.';

GRANT EXECUTE ON FUNCTION public.list_document_versions(uuid) TO authenticated;

-- 2. get_version_diff --------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_version_diff(p_version_a uuid, p_version_b uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_member_id uuid;
  v_a record;
  v_b record;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_version_a IS NULL OR p_version_b IS NULL THEN
    RAISE EXCEPTION 'both version ids are required' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT dv.id, dv.document_id, dv.version_number, dv.version_label,
         dv.authored_at, dv.locked_at, dv.content_html, dv.content_markdown,
         dv.content_diff_json, dv.notes, m.name AS authored_by_name
  INTO v_a
  FROM public.document_versions dv
  LEFT JOIN public.members m ON m.id = dv.authored_by
  WHERE dv.id = p_version_a;

  SELECT dv.id, dv.document_id, dv.version_number, dv.version_label,
         dv.authored_at, dv.locked_at, dv.content_html, dv.content_markdown,
         dv.content_diff_json, dv.notes, m.name AS authored_by_name
  INTO v_b
  FROM public.document_versions dv
  LEFT JOIN public.members m ON m.id = dv.authored_by
  WHERE dv.id = p_version_b;

  IF v_a.id IS NULL OR v_b.id IS NULL THEN
    RETURN jsonb_build_object(
      'both_exist', false,
      'version_a_exists', (v_a.id IS NOT NULL),
      'version_b_exists', (v_b.id IS NOT NULL)
    );
  END IF;

  IF v_a.document_id <> v_b.document_id THEN
    RETURN jsonb_build_object(
      'both_exist', true,
      'same_document', false,
      'document_id_a', v_a.document_id,
      'document_id_b', v_b.document_id
    );
  END IF;

  RETURN jsonb_build_object(
    'both_exist', true,
    'same_document', true,
    'document_id', v_a.document_id,
    'version_a', jsonb_build_object(
      'version_id', v_a.id,
      'version_number', v_a.version_number,
      'version_label', v_a.version_label,
      'authored_by_name', v_a.authored_by_name,
      'authored_at', v_a.authored_at,
      'locked_at', v_a.locked_at,
      'content_html', v_a.content_html,
      'content_markdown', v_a.content_markdown,
      'content_html_length', length(v_a.content_html),
      'notes', v_a.notes
    ),
    'version_b', jsonb_build_object(
      'version_id', v_b.id,
      'version_number', v_b.version_number,
      'version_label', v_b.version_label,
      'authored_by_name', v_b.authored_by_name,
      'authored_at', v_b.authored_at,
      'locked_at', v_b.locked_at,
      'content_html', v_b.content_html,
      'content_markdown', v_b.content_markdown,
      'content_html_length', length(v_b.content_html),
      'notes', v_b.notes
    ),
    'pre_computed_diff', COALESCE(v_b.content_diff_json, v_a.content_diff_json),
    'newer_version_id', CASE WHEN v_a.version_number > v_b.version_number THEN v_a.id ELSE v_b.id END,
    'older_version_id', CASE WHEN v_a.version_number > v_b.version_number THEN v_b.id ELSE v_a.id END
  );
END;
$fn$;

COMMENT ON FUNCTION public.get_version_diff(uuid, uuid) IS
  'Returns both content payloads for two versions of the same document — MCP host computes diff. '
  'Requires authenticated active member. Issue #85 Onda B P0 — review workflow.';

GRANT EXECUTE ON FUNCTION public.get_version_diff(uuid, uuid) TO authenticated;

-- 3. get_document_detail ------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_document_detail(p_document_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_member_id uuid;
  v_doc record;
  v_current_version record;
  v_active_chain record;
  v_signed_gates jsonb;
  v_pending_for_me text[];
  v_comments_total int;
  v_comments_unresolved int;
  v_versions_total int;
  v_draft_versions jsonb;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT gd.id, gd.doc_type, gd.title, gd.description, gd.version, gd.status,
         gd.partner_entity_id, gd.current_version_id, gd.signed_at,
         gd.valid_from, gd.valid_until, gd.exit_notice_days, gd.docusign_envelope_id,
         gd.pdf_url, gd.created_at, gd.updated_at
  INTO v_doc
  FROM public.governance_documents gd
  WHERE gd.id = p_document_id;

  IF v_doc.id IS NULL THEN
    RAISE EXCEPTION 'governance_document not found (id=%)', p_document_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_doc.current_version_id IS NOT NULL THEN
    SELECT dv.id, dv.version_number, dv.version_label, dv.authored_at,
           dv.locked_at, dv.published_at, dv.notes,
           am.name AS authored_by_name, lm.name AS locked_by_name,
           length(dv.content_html) AS content_html_length,
           (dv.content_markdown IS NOT NULL) AS has_markdown
    INTO v_current_version
    FROM public.document_versions dv
    LEFT JOIN public.members am ON am.id = dv.authored_by
    LEFT JOIN public.members lm ON lm.id = dv.locked_by
    WHERE dv.id = v_doc.current_version_id;
  END IF;

  SELECT ac.id, ac.version_id, ac.status, ac.gates, ac.opened_at,
         ac.approved_at, ac.activated_at, ac.closed_at
  INTO v_active_chain
  FROM public.approval_chains ac
  WHERE ac.document_id = p_document_id
    AND ac.status IN ('review','approved')
  ORDER BY ac.opened_at DESC NULLS LAST
  LIMIT 1;

  IF v_active_chain.id IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'gate_kind', s.gate_kind,
      'signer_id', s.signer_id,
      'signer_name', m.name,
      'signed_at', s.signed_at,
      'signoff_type', s.signoff_type,
      'comment_body', s.comment_body
    ) ORDER BY s.signed_at), '[]'::jsonb)
    INTO v_signed_gates
    FROM public.approval_signoffs s
    LEFT JOIN public.members m ON m.id = s.signer_id
    WHERE s.approval_chain_id = v_active_chain.id;

    SELECT COALESCE(array_agg(g->>'kind' ORDER BY (g->>'order')::int), ARRAY[]::text[])
    INTO v_pending_for_me
    FROM jsonb_array_elements(v_active_chain.gates) g
    WHERE public._can_sign_gate(v_member_id, v_active_chain.id, g->>'kind')
      AND NOT EXISTS (
        SELECT 1 FROM public.approval_signoffs s
        WHERE s.approval_chain_id = v_active_chain.id
          AND s.gate_kind = g->>'kind'
          AND s.signer_id = v_member_id
      );
  END IF;

  SELECT COUNT(*)::int INTO v_versions_total
  FROM public.document_versions dv
  WHERE dv.document_id = p_document_id;

  SELECT COUNT(*)::int, COUNT(*) FILTER (WHERE c.resolved_at IS NULL)::int
  INTO v_comments_total, v_comments_unresolved
  FROM public.document_comments c
  JOIN public.document_versions dv ON dv.id = c.document_version_id
  WHERE dv.document_id = p_document_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'version_id', dv.id,
    'version_number', dv.version_number,
    'version_label', dv.version_label,
    'authored_at', dv.authored_at,
    'authored_by_name', m.name
  ) ORDER BY dv.version_number DESC), '[]'::jsonb)
  INTO v_draft_versions
  FROM public.document_versions dv
  LEFT JOIN public.members m ON m.id = dv.authored_by
  WHERE dv.document_id = p_document_id AND dv.locked_at IS NULL;

  RETURN jsonb_build_object(
    'document', jsonb_build_object(
      'id', v_doc.id,
      'doc_type', v_doc.doc_type,
      'title', v_doc.title,
      'description', v_doc.description,
      'version', v_doc.version,
      'status', v_doc.status,
      'partner_entity_id', v_doc.partner_entity_id,
      'current_version_id', v_doc.current_version_id,
      'signed_at', v_doc.signed_at,
      'valid_from', v_doc.valid_from,
      'valid_until', v_doc.valid_until,
      'exit_notice_days', v_doc.exit_notice_days,
      'docusign_envelope_id', v_doc.docusign_envelope_id,
      'pdf_url', v_doc.pdf_url,
      'updated_at', v_doc.updated_at
    ),
    'current_version', CASE WHEN v_current_version.id IS NOT NULL THEN jsonb_build_object(
      'version_id', v_current_version.id,
      'version_number', v_current_version.version_number,
      'version_label', v_current_version.version_label,
      'authored_by_name', v_current_version.authored_by_name,
      'authored_at', v_current_version.authored_at,
      'locked_at', v_current_version.locked_at,
      'locked_by_name', v_current_version.locked_by_name,
      'published_at', v_current_version.published_at,
      'content_html_length', v_current_version.content_html_length,
      'has_markdown', v_current_version.has_markdown,
      'notes', v_current_version.notes
    ) ELSE NULL END,
    'active_chain', CASE WHEN v_active_chain.id IS NOT NULL THEN jsonb_build_object(
      'chain_id', v_active_chain.id,
      'version_id', v_active_chain.version_id,
      'status', v_active_chain.status,
      'gates', v_active_chain.gates,
      'opened_at', v_active_chain.opened_at,
      'approved_at', v_active_chain.approved_at,
      'activated_at', v_active_chain.activated_at,
      'signed_gates', v_signed_gates,
      'pending_gates_for_me', to_jsonb(COALESCE(v_pending_for_me, ARRAY[]::text[]))
    ) ELSE NULL END,
    'draft_versions', v_draft_versions,
    'versions_total', v_versions_total,
    'comments_total', v_comments_total,
    'comments_unresolved', v_comments_unresolved
  );
END;
$fn$;

COMMENT ON FUNCTION public.get_document_detail(uuid) IS
  'Composite read: document + current_version + active_chain + signed/pending gates for caller + '
  'draft versions list + comment counts. Single round-trip for MCP review UX. '
  'Issue #85 Onda B P0 — conversational review workflow.';

GRANT EXECUTE ON FUNCTION public.get_document_detail(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
