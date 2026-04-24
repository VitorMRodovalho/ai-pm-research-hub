-- =============================================================================
-- get_version_diff — add p_include_content flag for payload optimization
-- =============================================================================
-- Issue: get_version_diff always returned full content_html + content_markdown
--   em version_a + version_b — 50KB+ per call para docs grandes. Com Track H
--   (content_diff_json auto-populated), callers podem pegar apenas stats do
--   pre_computed_diff sem o payload de conteúdo.
--
-- Change: adiciona 3º parâmetro `p_include_content boolean DEFAULT true`.
--   - true (default): comportamento atual (full payload) — backward-compat
--   - false: omite content_html/content_markdown; mantém pre_computed_diff +
--     version metadata + lengths
--
-- Signature change: DROP + CREATE (arg count increased). Exec grant preserved.
-- Rollback: CREATE OR REPLACE with 2-arg signature.
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_version_diff(uuid, uuid);

CREATE OR REPLACE FUNCTION public.get_version_diff(
  p_version_a uuid,
  p_version_b uuid,
  p_include_content boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_member_id uuid;
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

  -- Build version payload — include content if requested
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
$fn$;

COMMENT ON FUNCTION public.get_version_diff(uuid, uuid, boolean) IS
  'Returns content payloads + pre-computed diff stats for two versions of the same document. '
  'p_include_content=false omits content_html/content_markdown (saves bandwidth when host only needs '
  'diff stats from pre_computed_diff). content_diff_json auto-populated via trg_compute_document_version_diff. '
  'Requires authenticated active member. Issue #85 Onda B P0.';

GRANT EXECUTE ON FUNCTION public.get_version_diff(uuid, uuid, boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';
