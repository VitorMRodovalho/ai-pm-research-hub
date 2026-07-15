-- #1383 PR-D: apply the visibility_class ceiling to get_document_detail, mirroring
-- the canonical reader get_governance_document_reader. This SECDEF composite read
-- bypasses RLS, so the gd_read visibility predicate is replicated inline:
-- legal_scoped docs are visible only to manage_member admins or members who signed
-- the document; admin_only / audit_restricted are authority-scoped. Not-found masking
-- avoids leaking existence. Body otherwise unchanged from the live capture.
CREATE OR REPLACE FUNCTION public.get_document_detail(p_document_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_is_admin boolean;
  v_is_platform_admin boolean;
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
         gd.visibility_class,
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

  -- Visibility ceiling (mirror get_governance_document_reader). SECDEF bypasses RLS;
  -- replicate the gd_read visibility predicate inline. Not-found masking avoids
  -- leaking the existence of a document the caller may not see.
  v_is_admin          := public.can_by_member(v_member_id, 'manage_member');
  v_is_platform_admin := public.can_by_member(v_member_id, 'manage_platform');
  IF NOT (
    v_doc.visibility_class = 'public'
    OR v_doc.visibility_class = 'active_members'
    OR (v_doc.visibility_class = 'legal_scoped' AND (
          v_is_admin
          OR EXISTS (
            SELECT 1 FROM public.member_document_signatures mds
            WHERE mds.member_id = v_member_id
              AND mds.document_id = v_doc.id
              AND mds.is_current = true)))
    OR (v_doc.visibility_class = 'admin_only' AND v_is_admin)
    OR (v_doc.visibility_class = 'audit_restricted' AND v_is_platform_admin)
  ) THEN
    RAISE EXCEPTION 'governance_document not found (id=%)', p_document_id
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Always assign v_current_version (record) so the RETURN's field references are
  -- valid even when current_version_id IS NULL: SELECT INTO on a NULL match assigns
  -- an all-NULL row rather than leaving the record unassigned. Guarding the SELECT
  -- with IF current_version_id IS NOT NULL skipped the assignment and crashed the
  -- RETURN ("record not assigned yet") on docs with no current version (5 such live).
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
      'visibility_class', v_doc.visibility_class,
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
$function$;
