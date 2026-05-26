-- ============================================================================
-- p268 BUG-268.A — upsert_document_version populates organization_id
--
-- WHAT: CREATE OR REPLACE FUNCTION public.upsert_document_version with the SAME
--       6-arg signature (4 DEFAULTs preserved per SEDIMENT-238.C). Two minimum
--       edits to the body relative to migration 20260503010000_ip3d:
--         1) SELECT v_doc gains `gd.organization_id` (so the org id is available
--            for the INSERT branch).
--         2) INSERT INTO public.document_versions adds `organization_id` column
--            with value `v_doc.organization_id`.
--       Nothing else changes — auth gate (`manage_member`), validations,
--       UPDATE branch, RETURNS jsonb payload, all preserved verbatim.
--
-- WHY: migration `20260805000035_p256_wave1a_315_m1_governance_org_id_backfill`
--      added `document_versions.organization_id NOT NULL` (Wave 1a M1 P0-Q5
--      multi-tenant invariant V) but never touched the canonical writer RPC.
--      The RPC was authored 2026-05-03 (p13-class IP-3d phase), pre-#315 M1
--      (2026-05-25). On p268 smoke for issue #96 v1 (Frontiers editorial guide),
--      INSERT via the RPC raised
--        23502: null value in column "organization_id" of relation
--        "document_versions" violates not-null constraint
--      under JWT-claim impersonation of Vitor — proving the gate ladder reaches
--      the INSERT (auth.uid() resolved correctly via set_config), but the row
--      shape was incomplete.
--
--      Same break path is present in the shipped editor UI at
--      `/admin/governance/documents/[docId]/versions/new.astro` (Tiptap editor
--      → `sb.rpc('upsert_document_version', …)`) — first author to try the UI
--      after p256 would hit this. SEDIMENT-239b.A class (contract tests for
--      SECDEF RPCs that INSERT into FK-constrained tables must assert the
--      source of EVERY column, not just gate ladder); applied here as forward
--      defense.
--
-- HOW (minimum diff vs migration 20260503010000_ip3d):
--      Body lines that change:
--        - line ~20 `SELECT gd.id, gd.title INTO v_doc`
--              becomes
--          `SELECT gd.id, gd.title, gd.organization_id INTO v_doc`
--        - line ~63 INSERT column list and VALUES gain `organization_id`
--      Everything else (auth, validations, UPDATE branch, RETURNS) is verbatim.
--
-- ROLLBACK: re-apply migration 20260503010000_ip3d body (drops org_id) —
--           but rollback re-introduces BUG-268.A, so do NOT rollback unless
--           NOT NULL constraint on document_versions.organization_id is also
--           dropped (which would also rollback p256 M1 invariant V — out of
--           scope here).
--
-- TEST: contract `tests/contracts/p268-bug-268-a-upsert-document-version-org-id.test.mjs`
--       locks 9 static assertions + 2 forward-defense regressions:
--       Forward-defense:
--         (a) INSERT column list must contain `organization_id`.
--         (b) The branch must NOT use `organization_id := NULL` or a default
--             constant (must read from v_doc.organization_id, sourced from
--             governance_documents).
--       Static:
--         file existence + 6-arg signature + 4 DEFAULTs preserved + SECDEF +
--         pinned search_path TO 'public', 'pg_temp' + auth gate
--         (auth.uid() + can_by_member('manage_member')) + RETURNS jsonb shape
--         (success/version_id/document_id/version_number/version_label/
--          authored_by/updated_at) + sanity DO + NOTIFY pgrst.
--       Plus 1 DB-gated assertion (live function prosrc must contain
--       `organization_id` literal).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.upsert_document_version(
  p_document_id uuid,
  p_content_html text,
  p_content_markdown text DEFAULT NULL,
  p_version_label text DEFAULT NULL,
  p_version_id uuid DEFAULT NULL,
  p_notes text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_member record;
  v_version record;
  v_version_id uuid;
  v_version_number int;
  v_version_label text;
  v_doc record;
BEGIN
  -- Auth (preserved verbatim from migration 20260503010000_ip3d)
  SELECT m.id, m.name INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Validate doc (BUG-268.A fix: now also selects organization_id for the INSERT)
  SELECT gd.id, gd.title, gd.organization_id INTO v_doc
  FROM public.governance_documents gd WHERE gd.id = p_document_id;
  IF v_doc.id IS NULL THEN
    RAISE EXCEPTION 'governance_document not found (id=%)', p_document_id USING ERRCODE = 'no_data_found';
  END IF;

  IF length(coalesce(p_content_html,'')) = 0 THEN
    RAISE EXCEPTION 'content_html cannot be empty' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Update branch: existing draft (preserved verbatim — UPDATE doesn't touch org_id)
  IF p_version_id IS NOT NULL THEN
    SELECT dv.id, dv.document_id, dv.version_number, dv.version_label, dv.locked_at, dv.authored_by
    INTO v_version
    FROM public.document_versions dv WHERE dv.id = p_version_id;

    IF v_version.id IS NULL THEN
      RAISE EXCEPTION 'document_version not found (id=%)', p_version_id USING ERRCODE = 'no_data_found';
    END IF;
    IF v_version.document_id <> p_document_id THEN
      RAISE EXCEPTION 'document_version % does not belong to document %', p_version_id, p_document_id
        USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF v_version.locked_at IS NOT NULL THEN
      RAISE EXCEPTION 'document_version % is locked at % — immutable', p_version_id, v_version.locked_at
        USING ERRCODE = 'check_violation';
    END IF;

    UPDATE public.document_versions
      SET content_html = p_content_html,
          content_markdown = coalesce(p_content_markdown, content_markdown),
          version_label = coalesce(p_version_label, version_label),
          notes = coalesce(p_notes, notes),
          updated_at = now()
      WHERE id = p_version_id;

    v_version_id := p_version_id;
    v_version_number := v_version.version_number;
    v_version_label := coalesce(p_version_label, v_version.version_label);
  ELSE
    -- Insert branch: new draft, version_number = MAX+1 per document.
    -- BUG-268.A fix: add `organization_id` to INSERT, sourced from v_doc.organization_id
    -- (FK to organizations(id), inherited from the parent governance_documents row).
    SELECT COALESCE(MAX(version_number), 0) + 1
    INTO v_version_number
    FROM public.document_versions WHERE document_id = p_document_id;

    v_version_label := coalesce(p_version_label, 'Rascunho v' || v_version_number::text);

    INSERT INTO public.document_versions (
      document_id, version_number, version_label, content_html, content_markdown,
      authored_by, authored_at, notes, organization_id
    ) VALUES (
      p_document_id, v_version_number, v_version_label, p_content_html, p_content_markdown,
      v_member.id, now(), p_notes, v_doc.organization_id
    ) RETURNING id INTO v_version_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'version_id', v_version_id,
    'document_id', p_document_id,
    'version_number', v_version_number,
    'version_label', v_version_label,
    'authored_by', v_member.id,
    'updated_at', now()
  );
END;
$function$;

COMMENT ON FUNCTION public.upsert_document_version(uuid, text, text, text, uuid, text) IS
  'Cria ou atualiza draft de document_version (locked_at IS NULL). Se p_version_id provided: UPDATE (erro se locked). Else: INSERT com version_number = MAX+1, organization_id resolvido de governance_documents (p268 BUG-268.A fix). Auth: manage_member. Phase IP-3d + p268 BUG-268.A.';

GRANT EXECUTE ON FUNCTION public.upsert_document_version(uuid, text, text, text, uuid, text) TO authenticated;

-- Sanity (no NOT NULL/check violations should be possible from this RPC anymore).
-- Verify the live body now references organization_id.
DO $sanity$
DECLARE
  v_body text;
BEGIN
  SELECT prosrc INTO v_body
  FROM pg_proc
  WHERE pronamespace = 'public'::regnamespace
    AND proname = 'upsert_document_version'
  LIMIT 1;

  IF v_body IS NULL THEN
    RAISE EXCEPTION 'p268 BUG-268.A sanity: upsert_document_version not found in pg_proc';
  END IF;
  IF position('organization_id' IN v_body) = 0 THEN
    RAISE EXCEPTION 'p268 BUG-268.A sanity: upsert_document_version body must reference organization_id';
  END IF;
END;
$sanity$;

NOTIFY pgrst, 'reload schema';
