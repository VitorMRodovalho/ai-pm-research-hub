-- #1383 PR-D: apply the visibility_class ceiling + draft (locked_at) hard-gate to
-- get_version_diff, mirroring the canonical reader get_governance_document_reader.
-- This SECDEF diff returns full version content, so it must not expose a document the
-- caller cannot see, nor unpublished (unlocked) draft versions to non-admins. Both
-- versions belong to the same document (checked before the gate). Not-found masking
-- avoids leaking existence. Body otherwise unchanged from the live capture.
CREATE OR REPLACE FUNCTION public.get_version_diff(p_version_a uuid, p_version_b uuid, p_include_content boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_is_admin boolean;
  v_is_platform_admin boolean;
  v_visibility_class text;
  v_a record;
  v_b record;
  v_payload_a jsonb;
  v_payload_b jsonb;
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

  -- Visibility ceiling (mirror get_governance_document_reader). Both versions share
  -- v_a.document_id (checked above). Not-found masking avoids leaking existence.
  v_is_admin          := public.can_by_member(v_member_id, 'manage_member');
  v_is_platform_admin := public.can_by_member(v_member_id, 'manage_platform');

  SELECT gd.visibility_class INTO v_visibility_class
  FROM public.governance_documents gd
  WHERE gd.id = v_a.document_id;

  IF NOT (
    v_visibility_class = 'public'
    OR v_visibility_class = 'active_members'
    OR (v_visibility_class = 'legal_scoped' AND (
          v_is_admin
          OR EXISTS (
            SELECT 1 FROM public.member_document_signatures mds
            WHERE mds.member_id = v_member_id
              AND mds.document_id = v_a.document_id
              AND mds.is_current = true)))
    OR (v_visibility_class = 'admin_only' AND v_is_admin)
    OR (v_visibility_class = 'audit_restricted' AND v_is_platform_admin)
  ) THEN
    RETURN jsonb_build_object(
      'both_exist', false,
      'version_a_exists', false,
      'version_b_exists', false
    );
  END IF;

  -- Draft (unlocked) versions are visible only to manage_member admins (mirror the
  -- reader's locked_at HARD-GATE). A non-admin cannot diff an unpublished draft.
  IF NOT v_is_admin AND (v_a.locked_at IS NULL OR v_b.locked_at IS NULL) THEN
    RETURN jsonb_build_object(
      'both_exist', false,
      'version_a_exists', (v_a.locked_at IS NOT NULL),
      'version_b_exists', (v_b.locked_at IS NOT NULL)
    );
  END IF;

  v_payload_a := jsonb_build_object(
    'version_id', v_a.id,
    'version_number', v_a.version_number,
    'version_label', v_a.version_label,
    'authored_by_name', v_a.authored_by_name,
    'authored_at', v_a.authored_at,
    'locked_at', v_a.locked_at,
    'content_html_length', length(v_a.content_html),
    'content_markdown_length', length(v_a.content_markdown),
    'notes', v_a.notes
  );
  IF p_include_content THEN
    v_payload_a := v_payload_a
      || jsonb_build_object('content_html', v_a.content_html)
      || jsonb_build_object('content_markdown', v_a.content_markdown);
  END IF;

  v_payload_b := jsonb_build_object(
    'version_id', v_b.id,
    'version_number', v_b.version_number,
    'version_label', v_b.version_label,
    'authored_by_name', v_b.authored_by_name,
    'authored_at', v_b.authored_at,
    'locked_at', v_b.locked_at,
    'content_html_length', length(v_b.content_html),
    'content_markdown_length', length(v_b.content_markdown),
    'notes', v_b.notes
  );
  IF p_include_content THEN
    v_payload_b := v_payload_b
      || jsonb_build_object('content_html', v_b.content_html)
      || jsonb_build_object('content_markdown', v_b.content_markdown);
  END IF;

  RETURN jsonb_build_object(
    'both_exist', true,
    'same_document', true,
    'document_id', v_a.document_id,
    'include_content', p_include_content,
    'version_a', v_payload_a,
    'version_b', v_payload_b,
    'pre_computed_diff', COALESCE(v_b.content_diff_json, v_a.content_diff_json),
    'newer_version_id', CASE WHEN v_a.version_number > v_b.version_number THEN v_a.id ELSE v_b.id END,
    'older_version_id', CASE WHEN v_a.version_number > v_b.version_number THEN v_b.id ELSE v_a.id END
  );
END;
$function$;
