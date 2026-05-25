-- WHAT: Wave 1b leaf #312-W4e (p264 — #381 SHIPS curator draft-read mitigation)
-- — extend get_governance_document_reader (p263 W4d) with a 3rd bypass dimension
-- "assigned curator" — bypass STATUS default-exclusion AND version locked_at
-- HARD-GATE for members eligible as 'curator' (via preview_gate_eligibles_cache
-- primary path or _can_sign_gate fallback for new doc_types) when an OPEN
-- approval_chain exists on the specific document. Visibility predicate
-- UNCHANGED — bypass restricted to status + locked_at; review/audit context
-- preserved; no blanket curate_content grant; no RLS swap.
--
-- WHY: p256 Wave 1a M2 (20260805000036) deliberately swapped
-- document_versions_read_published RLS to require manage_member as the SOLE
-- admin bypass (locked_at IS NOT NULL HARD-GATE outside the OR). Roberto Macêdo
-- (member 49836a70…) and Sarah Faria (19b7ff75…) — both curators with
-- curate_content + participate_in_governance_review but NOT manage_member —
-- lose draft visibility through the W4d reader: status='draft' /
-- 'pending_proposer_consent' / 'withdrawn' / 'revoked' all return null
-- envelope, AND unlocked current_version returns null. The W4d carry note
-- (p263 close handoff) explicitly deferred curator-draft-read to W4e #381.
-- PM dispatch (2026-05-26) ratified Pattern B with assignment scoping:
-- (Q1) extend get_governance_document_reader only — no new sibling SECDEF, no
--      RLS policy, no DocumentVersionEditor change;
-- (Q2) "assigned" = open approval_chain on doc + caller eligible as 'curator'
--      via preview_gate_eligibles_cache;
-- (Q3) scope = all document_versions of the doc while chain open + eligible.
-- IMPLEMENTATION NOTE on Q2: preview_gate_eligibles_cache is populated only
-- for doc_types listed in _cacheable_preview_doc_types() — original 5
-- (cooperation_agreement / cooperation_addendum / volunteer_term_template /
-- volunteer_addendum / policy). The 6 new doc_types shipped in W4a #378
-- (editorial_guide / governance_guideline / manual / executive_summary /
-- framework_reference / project_charter) are NOT in the cache scope yet.
-- To honor PM intent ("curador atribuído com chain ativo") across ALL
-- doc_types, the bypass uses a HYBRID: cache lookup as the primary path
-- (low-latency, matches PM literal ratification) with _can_sign_gate(
-- v_caller_member_id, NULL, 'curator', doc_type, NULL) as fallback for cache
-- misses. _can_sign_gate is the ground-truth function the cache is derived
-- from, so functional equivalence holds; extra cost is one function call on
-- cache-miss path only. Cache scope expansion is tracked as a separate
-- follow-up (OPP-264.A — not in this migration).
--
-- SPEC: SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md §19.5 (Wave 1b carry — curator
-- draft-access mitigation Roberto/Sarah) + §16.5 (QA persona smoke 5 —
-- Roberto/Sarah curatorship paths sem depender de admin) + §11 (smoke matrix
-- entries 3-5). Issue #381 spec Pattern B with PM-ratified refinement.
--
-- SCOPE LOCK (per p236 + p256 + p263 + #381 dispatch):
--   IN-SCOPE:  CREATE OR REPLACE FUNCTION public.get_governance_document_reader(uuid)
--              with same signature (uuid → jsonb); adds v_is_curator_assigned
--              dimension; status + locked_at gates bypass it; visibility
--              ladder + 5-class predicate + 4-status include set + 8 forbidden
--              columns + null-envelope shape ALL preserved byte-identical;
--              comment refreshed to document the W4e third bypass.
--   OUT-OF-SCOPE: visibility predicate bypass (curator still needs visibility
--                 class to pass — preserves legal_scoped / admin_only /
--                 audit_restricted gates exactly as W4d); RLS policy changes
--                 on document_versions / governance_documents (rejected per
--                 dispatch "evitar abrir RLS genérico"); DocumentVersionEditor
--                 changes (admin-only page; admin already bypasses);
--                 ReviewChainIsland changes (already uses SECDEF RPCs, works);
--                 new sibling SECDEF function (PM picked extend over new); cache
--                 scope expansion (tracked OPP-264.A); #382 W4f blind-review
--                 primitives; #383 W4g content_products ADR.
--
-- ASSIGNMENT DEFINITION (W4e bypass predicate, byte-pinned for forward-defense):
--   v_is_curator_assigned := EXISTS open approval_chain on doc_id
--     AND (EXISTS preview_gate_eligibles_cache row with 'curator' in eligible_gates
--          OR _can_sign_gate(member_id, NULL, 'curator', doc_type, NULL))
--   Open chain := approval_chains.closed_at IS NULL (mirrors gate workflow
--   semantics; chain status not directly checked because closed_at is the
--   canonical "still active" signal — superseded/closed chains both have
--   closed_at populated).
--   Cache + fallback combine via OR: cache miss is INVISIBLE to caller; both
--   paths are logically equivalent (cache is computed from _can_sign_gate).
--
-- PAYLOAD CONTRACT (P0-Q8 forward-defense — UNCHANGED from W4d):
--   ALLOWED  : id, title, description, doc_type, status, visibility_class,
--              acknowledgement_mode, effective_from, effective_until,
--              approved_at, current_version_id, current_ratified_version_id,
--              version_id, version_number, version_label, authored_at,
--              locked_at, content_html.
--   FORBIDDEN: file_id, drive_url, pdf_url, docusign_envelope_id,
--              partner_entity_id, content_markdown, content_diff_json,
--              signed_at, signatories, parties.
--
-- VISIBILITY GATE (UNCHANGED from W4d — bypass does NOT widen visibility):
--   public           → any active member
--   active_members   → any active member
--   legal_scoped     → admin (manage_member) OR signer (mds.is_current=true)
--   admin_only       → admin (manage_member)
--   audit_restricted → platform admin (manage_platform)
--
-- STATUS DEFAULT-EXCLUSION (W4e widens admin bypass to include assigned curator):
--   member view (non-admin, non-assigned-curator):
--     status IN ('active','approved','under_review','superseded')
--   admin (manage_member) bypass: all 8 statuses
--   W4e: assigned curator bypass (per assignment predicate above): all 8 statuses
--
-- VERSION LOCKED_AT HARD-GATE (W4e widens admin bypass to include assigned curator):
--   member view (non-admin, non-assigned-curator):
--     current_version requires locked_at IS NOT NULL
--   admin bypass: also exposes unlocked drafts
--   W4e: assigned curator bypass: also exposes unlocked drafts (within review
--        context — open chain on this doc + curator-eligible for this doc_type)
--
-- PRIVACY-PRESERVING ERROR PARITY (UNCHANGED from W4d):
--   not-found / visibility-blocked / status-blocked / version-unlocked-for-member
--   all return `{ok:true, document:null, current_version:null}`. No 404↔403 oracle.
--
-- SEDIMENT REFERENCES:
--   - SEDIMENT-225.B (apply_migration may strip inline -- comments inside $$):
--     comments inside function body are kept; if apply strips them, Phase C
--     body-drift gate flags + minimum-diff fix = strip from file to match live.
--   - SEDIMENT-235.A (no close|fix|resolve+#N adjacency for non-target issues):
--     migration body lists #381 / #312 / #315 / #96 / #382 / #383 as references
--     only — NEVER prefixed with close-keywords.
--   - SEDIMENT-238.C (preserve parameter DEFAULTs on CREATE OR REPLACE):
--     get_governance_document_reader(p_document_id uuid) has NO defaults; safe.
--   - SEDIMENT-239b.A (FK column source assertions for SECDEF INSERTs): this
--     RPC performs NO INSERT — read-only; no FK column source to assert.
--   - SEDIMENT-254.A (shadow row cleanup with exact WHERE version): apply_migration
--     MCP creates a shadow row alongside canonical 20260805000044; cleanup with
--     exact `WHERE version = '<shadow_ts>'` discipline post-apply.
--
-- ROLLBACK (idempotent):
--   Re-apply the W4d body byte-identical (20260805000043) — drops v_is_curator_assigned
--   declaration + assignment block; restores status + locked_at gates to admin-only
--   bypass. Then NOTIFY pgrst, 'reload schema'.
--   Or for surgical revert: CREATE OR REPLACE FUNCTION with same body minus the
--   W4e block (assignment predicate + 2 OR-additions in status/locked_at gates).
--
-- INVARIANTS: 21 → 21 (no new invariant; bypass widens existing reader within
-- pre-existing assignment predicate scope; no schema-level change).
--
-- CROSS-REF: #381 (this child W4e) + #380 (W4d predecessor reader) + #379
-- (W4c default-status exclusion) + #378 (W4a gate templates) + #377 (W4b
-- sign_proposer_consent) + #312 (audit umbrella) + #315 (Governance v1) +
-- #96 (Frontiers) + p256 Wave 1a M2 (RLS swap origin) + p263 W4d (reader
-- hardening) + ADR-0016 (gate eligibility) + ADR-0093 (visibility classes).
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
  v_is_curator_assigned boolean := false;  -- W4e (p264 #381) third bypass dim
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

  -- W4e (p264 #381): assigned-curator bypass dimension.
  -- Predicate: EXISTS open approval_chain on doc_id
  --   AND (cache hit OR _can_sign_gate fallback) curator-eligible for doc_type.
  -- Computed only for non-admins (admins already bypass via v_is_admin).
  IF NOT v_is_admin THEN
    v_is_curator_assigned := EXISTS (
      SELECT 1
      FROM public.approval_chains ac
      WHERE ac.document_id = p_document_id
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

  -- Visibility predicate (mirror gd_read RLS + list_governance_library M3).
  -- UNCHANGED in W4e — assigned-curator does NOT bypass visibility.
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
  -- W4e: assigned curator also bypasses (per assignment predicate above).
  v_status_allowed := (
    v_is_admin
    OR v_is_curator_assigned
    OR v_doc.status IN ('active','approved','under_review','superseded')
  );
  IF NOT v_status_allowed THEN
    RETURN jsonb_build_object('ok', true, 'document', NULL, 'current_version', NULL);
  END IF;

  -- Resolve current version. Member view: locked_at HARD-GATE (mirror
  -- document_versions_read_published RLS). Admin bypass: any current_version_id.
  -- W4e: assigned curator also bypasses locked_at HARD-GATE (review context).
  IF v_doc.current_version_id IS NOT NULL THEN
    SELECT dv.id, dv.version_number, dv.version_label, dv.authored_at,
           dv.locked_at, dv.content_html
      INTO v_ver_id, v_ver_number, v_ver_label, v_ver_authored_at,
           v_ver_locked_at, v_ver_content_html
    FROM public.document_versions dv
    WHERE dv.id = v_doc.current_version_id
      AND (v_is_admin OR v_is_curator_assigned OR dv.locked_at IS NOT NULL);
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
  'version locked_at hard-gate. W4e (p264 #381) adds assigned-curator bypass '
  '(open approval_chain on doc + caller curator-eligible for doc_type via '
  'preview_gate_eligibles_cache or _can_sign_gate fallback) — covers Roberto '
  'Macêdo + Sarah Faria post-p256 M2 RLS swap. Returns null-envelope for '
  'not-found / blocked / unlocked-for-member (privacy-preserving error parity). '
  '#312-W4e (p264).';

REVOKE EXECUTE ON FUNCTION public.get_governance_document_reader(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_governance_document_reader(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
