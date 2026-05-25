-- WHAT: Wave 1b leaf #312-W4d (p263 — #380 SHIPS reader hardening) — new SECDEF
-- RPC public.get_governance_document_reader(uuid) returning the single-doc reader
-- payload consumed by /governance/document/[id].astro. Replaces the route's two
-- table-direct SELECTs against governance_documents + document_versions with a
-- canonical SECDEF function that enforces visibility_class + status default-exclusion
-- + version locked_at hard-gate in one round-trip.
--
-- WHY: Pre-W4d the reader route relied on RLS gd_read for visibility (added p256 M2)
-- and on no status gate at all — a member who knew a draft UUID could fetch its
-- metadata + content directly. p262 W4c shipped status default-exclusion ONLY at the
-- listing surface (list_governance_library); the per-document reader route remained
-- the last leak vector for default-hidden statuses (draft / pending_proposer_consent
-- / withdrawn / revoked). Pattern matches list_governance_library: member-facing
-- access goes through SECDEF reader, NOT direct SELECT, so the response shape can
-- ALWAYS exclude forbidden columns (file_id / drive_url / pdf_url /
-- docusign_envelope_id / partner_entity_id / content_markdown / content_diff_json /
-- signed_at / signatories) consistently.
--
-- SPEC: SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md §19.5 (Wave 1b W4d) + p262 W4c
-- precedent (default-status exclusion 4-status set) + p256 M2 (gd_read +
-- document_versions_read_published RLS) + p256 M3 (list_governance_library SECDEF
-- pattern + P0-Q8 forbidden-fields forward-defense).
--
-- SCOPE LOCK (per feedback_wave_1a_scope_confine_governance + W4d dispatch scope):
--   IN-SCOPE:  1 new SECDEF RPC (get_governance_document_reader) + GRANT/REVOKE +
--              NOTIFY pgrst. Route rewire ships in companion frontend diff (same PR).
--   OUT-OF-SCOPE: #381 W4e curator draft-read mitigation (dedicated curator surface);
--                 #382 W4f blind-review primitives; #383 W4g content_products ADR;
--                 closing #312/#315/#96; MCP wrappers (Wave 5); Drive/file resolver.
--
-- PAYLOAD CONTRACT (P0-Q8 forward-defense):
--   ALLOWED  : id, title, description, doc_type, status, visibility_class,
--              acknowledgement_mode, effective_from, effective_until, approved_at,
--              current_version_id, current_ratified_version_id, version_id,
--              version_number, version_label, authored_at, locked_at, content_html.
--   FORBIDDEN: file_id, drive_url, pdf_url, docusign_envelope_id,
--              partner_entity_id, content_markdown, content_diff_json, signed_at,
--              signatories, parties, docusign_envelope_id (any Drive/legal/PII handle).
--
-- VISIBILITY GATE (mirror gd_read + list_governance_library):
--   public           → any active member
--   active_members   → any active member
--   legal_scoped     → admin (manage_member) OR signer (mds.is_current=true)
--   admin_only       → admin (manage_member)
--   audit_restricted → platform admin (manage_platform)
--
-- STATUS DEFAULT-EXCLUSION (mirror p262 W4c):
--   member view: status IN ('active','approved','under_review','superseded')
--   admin (manage_member) bypass: all 8 statuses including draft / pending_proposer_consent
--                                 / withdrawn / revoked / Frontiers fixture.
--
-- VERSION LOCKED_AT HARD-GATE (mirror document_versions_read_published RLS):
--   member view : current_version must have locked_at IS NOT NULL
--   admin bypass: also exposes unlocked drafts (curator/reviewer path goes via
--                 get_document_detail; this reader is the member-safe surface)
--
-- PRIVACY-PRESERVING ERROR PARITY: not-found AND visibility-blocked AND status-blocked
-- AND version-not-locked-for-member all return the SAME envelope `{ok:true,
-- document:null, current_version:null}` — the route renders "Documento não
-- encontrado" uniformly. Avoids 404↔403 oracle.
--
-- ROLLBACK (idempotent):
--   DROP FUNCTION public.get_governance_document_reader(uuid);
--
-- INVARIANTS: No change. V'_prime (#315 P0-Q7) untouched. V deferred Wave 1b first
-- leaf. RPC is a read helper that doesn't mutate governed table state.
--
-- CROSS-REF: #312 audit umbrella + #315 Governance Documents v1 + #96 Frontiers +
-- #380 (this child, W4d reader hardening) + #379 (W4c GAP-259.A predecessor) +
-- #378 (W4a 6 gate templates) + #377 (W4b sign_proposer_consent) + p256 M2/M3
-- (RLS + library RPC) + p262 W4c (status default-exclusion). NEXT: #381 W4e
-- curator draft-read mitigation (#380's known regression — curators without
-- manage_member lose direct draft SELECT via DocumentVersionEditor; dedicated
-- surface required).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_governance_document_reader(p_document_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_member_id uuid;
  v_is_admin boolean;
  v_is_platform_admin boolean;
  v_doc record;
  v_visible boolean;
  v_status_allowed boolean;
  -- Scalar version fields (not a record) — when current_version_id IS NULL we skip
  -- the SELECT entirely, and PL/pgSQL forbids referencing a never-assigned record
  -- in the RETURN expression. Scalars default to NULL safely.
  v_ver_id uuid;
  v_ver_number integer;
  v_ver_label text;
  v_ver_authored_at timestamptz;
  v_ver_locked_at timestamptz;
  v_ver_content_html text;
BEGIN
  -- Active membership gate (same envelope as list_governance_library)
  SELECT id INTO v_caller_member_id
  FROM public.members
  WHERE auth_id = auth.uid() AND is_active = true
  LIMIT 1;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no active member record' USING ERRCODE='42501';
  END IF;

  v_is_admin          := public.can_by_member(v_caller_member_id, 'manage_member');
  v_is_platform_admin := public.can_by_member(v_caller_member_id, 'manage_platform');

  -- Fetch doc (SECDEF — bypasses RLS by design; replicates gate inline below).
  SELECT gd.id, gd.title, gd.description, gd.doc_type, gd.status,
         gd.visibility_class, gd.acknowledgement_mode,
         gd.effective_from, gd.effective_until, gd.approved_at,
         gd.current_version_id, gd.current_ratified_version_id
    INTO v_doc
  FROM public.governance_documents gd
  WHERE gd.id = p_document_id;

  IF v_doc.id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'document', NULL, 'current_version', NULL);
  END IF;

  -- Visibility predicate (mirror gd_read RLS + list_governance_library M3).
  v_visible := (
    v_doc.visibility_class = 'public'
    OR v_doc.visibility_class = 'active_members'
    OR (v_doc.visibility_class = 'legal_scoped' AND (
          v_is_admin
          OR EXISTS (
            SELECT 1 FROM public.member_document_signatures mds
            WHERE mds.member_id = v_caller_member_id
              AND mds.document_id = v_doc.id
              AND mds.is_current = true
          )))
    OR (v_doc.visibility_class = 'admin_only' AND v_is_admin)
    OR (v_doc.visibility_class = 'audit_restricted' AND v_is_platform_admin)
  );
  IF NOT v_visible THEN
    RETURN jsonb_build_object('ok', true, 'document', NULL, 'current_version', NULL);
  END IF;

  -- Status default-exclusion (mirror p262 W4c). Admin (manage_member) bypasses.
  v_status_allowed := (
    v_is_admin
    OR v_doc.status IN ('active','approved','under_review','superseded')
  );
  IF NOT v_status_allowed THEN
    RETURN jsonb_build_object('ok', true, 'document', NULL, 'current_version', NULL);
  END IF;

  -- Resolve current version. Member view: locked_at HARD-GATE (mirror
  -- document_versions_read_published RLS). Admin bypass: any current_version_id.
  IF v_doc.current_version_id IS NOT NULL THEN
    SELECT dv.id, dv.version_number, dv.version_label, dv.authored_at,
           dv.locked_at, dv.content_html
      INTO v_ver_id, v_ver_number, v_ver_label, v_ver_authored_at,
           v_ver_locked_at, v_ver_content_html
    FROM public.document_versions dv
    WHERE dv.id = v_doc.current_version_id
      AND (v_is_admin OR dv.locked_at IS NOT NULL);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
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
    'current_version', CASE WHEN v_ver_id IS NOT NULL THEN jsonb_build_object(
      'version_id', v_ver_id,
      'version_number', v_ver_number,
      'version_label', v_ver_label,
      'authored_at', v_ver_authored_at,
      'locked_at', v_ver_locked_at,
      'content_html', v_ver_content_html
    ) ELSE NULL END
  );
END;
$$;

COMMENT ON FUNCTION public.get_governance_document_reader(uuid) IS
  'Single-doc reader (member-safe surface) for /governance/document/[id].astro. '
  'Enforces visibility_class + status default-exclusion (4-status set per W4c) + '
  'version locked_at hard-gate. Returns null-envelope for not-found / blocked / '
  'unlocked-for-member (privacy-preserving error parity). #312-W4d (p263).';

REVOKE EXECUTE ON FUNCTION public.get_governance_document_reader(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_governance_document_reader(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
