-- #646 — Governance draft preview reader.
--
-- Adds a dedicated SECDEF reader for unlocked document_versions so reviewers can
-- inspect/link a legal-review draft before lock/ratification. This deliberately
-- does not broaden the current-version reader and does not expose attachment or
-- source columns.

CREATE OR REPLACE FUNCTION public.get_governance_document_draft_preview(
  p_document_id uuid,
  p_version_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_member_id uuid;
  v_is_admin boolean := false;
  v_is_platform_admin boolean := false;
  v_can_preview boolean := false;
  v_is_curator_assigned boolean := false;
  v_doc record;
  v_ver record;
  v_visible boolean := false;
  v_status_allowed boolean := false;
BEGIN
  SELECT m.id
    INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid()
    AND m.is_active = true
  LIMIT 1;

  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no active member record' USING ERRCODE='42501';
  END IF;

  v_is_admin          := public.can_by_member(v_caller_member_id, 'manage_member');
  v_is_platform_admin := public.can_by_member(v_caller_member_id, 'manage_platform');
  v_can_preview       := (
    v_is_admin
    OR public.can_by_member(v_caller_member_id, 'participate_in_governance_review')
    OR public.can_by_member(v_caller_member_id, 'curate_content')
  );

  SELECT gd.id, gd.title, gd.description, gd.doc_type, gd.status,
         gd.visibility_class, gd.acknowledgement_mode,
         gd.effective_from, gd.effective_until, gd.approved_at,
         gd.current_version_id, gd.current_ratified_version_id
    INTO v_doc
  FROM public.governance_documents gd
  WHERE gd.id = p_document_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'document', NULL, 'draft_version', NULL);
  END IF;

  SELECT dv.id, dv.document_id, dv.version_number, dv.version_label,
         dv.authored_by, dv.authored_at, dv.updated_at, dv.locked_at,
         dv.content_html
    INTO v_ver
  FROM public.document_versions dv
  WHERE dv.id = p_version_id
    AND dv.document_id = p_document_id
    AND dv.locked_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'document', NULL, 'draft_version', NULL);
  END IF;

  IF NOT v_is_admin THEN
    v_is_curator_assigned := EXISTS (
      SELECT 1
      FROM public.approval_chains ac
      WHERE ac.document_id = p_document_id
        AND ac.version_id = p_version_id
        AND ac.closed_at IS NULL
    ) AND (
      EXISTS (
        SELECT 1
        FROM public.preview_gate_eligibles_cache pgec
        WHERE pgec.member_id = v_caller_member_id
          AND pgec.doc_type = v_doc.doc_type
          AND 'curator' = ANY(pgec.eligible_gates)
      )
      OR public._can_sign_gate(v_caller_member_id, NULL, 'curator', v_doc.doc_type, NULL)
    );
  END IF;

  -- Visibility remains stricter than the generic current reader:
  -- legal_scoped drafts are previewable only by admins or current signers.
  v_visible := (
    (v_doc.visibility_class IN ('public', 'active_members') AND (
      v_can_preview OR v_is_curator_assigned OR v_ver.authored_by = v_caller_member_id
    ))
    OR (v_doc.visibility_class = 'legal_scoped' AND (
      v_is_admin
      OR EXISTS (
        SELECT 1
        FROM public.member_document_signatures mds
        WHERE mds.member_id = v_caller_member_id
          AND mds.document_id = v_doc.id
          AND mds.is_current = true
      )
    ))
    OR (v_doc.visibility_class = 'admin_only' AND v_is_admin)
    OR (v_doc.visibility_class = 'audit_restricted' AND v_is_platform_admin)
  );

  IF NOT v_visible THEN
    RETURN jsonb_build_object('ok', true, 'document', NULL, 'draft_version', NULL);
  END IF;

  v_status_allowed := (
    v_is_admin
    OR v_is_curator_assigned
    OR v_ver.authored_by = v_caller_member_id
    OR v_doc.status IN ('active', 'approved', 'under_review', 'draft')
  );

  IF NOT v_status_allowed THEN
    RETURN jsonb_build_object('ok', true, 'document', NULL, 'draft_version', NULL);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'preview', jsonb_build_object(
      'is_draft', true,
      'banner', 'DRAFT - em revisao juridica; nao e a versao vigente'
    ),
    'document', jsonb_build_object(
      'id', v_doc.id,
      'title', v_doc.title,
      'description', v_doc.description,
      'doc_type', v_doc.doc_type,
      'status', v_doc.status,
      'visibility_class', v_doc.visibility_class,
      'acknowledgement_mode', v_doc.acknowledgement_mode,
      'effective_from', v_doc.effective_from,
      'effective_until', v_doc.effective_until,
      'approved_at', v_doc.approved_at,
      'current_version_id', v_doc.current_version_id,
      'current_ratified_version_id', v_doc.current_ratified_version_id
    ),
    'draft_version', jsonb_build_object(
      'version_id', v_ver.id,
      'version_number', v_ver.version_number,
      'version_label', v_ver.version_label,
      'authored_at', v_ver.authored_at,
      'updated_at', v_ver.updated_at,
      'locked_at', v_ver.locked_at,
      'content_html', v_ver.content_html
    )
  );
END;
$$;

COMMENT ON FUNCTION public.get_governance_document_draft_preview(uuid, uuid) IS
  '#646: member-safe governance draft preview for unlocked document_versions. '
  'Requires active member; gates preview to manage_member, governance reviewer, '
  'curator/assigned curator, author, or signatory for legal_scoped documents. '
  'Returns content_html only; attachment/source columns stay server-side.';

REVOKE EXECUTE ON FUNCTION public.get_governance_document_draft_preview(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_governance_document_draft_preview(uuid, uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_governance_document_draft_preview(uuid, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
