-- WHAT: Wave 1b leaf #312-W4b (p261 — #377 SHIPS) — proposer consent canonical A2 path
--   1) ALTER `governance_documents` ADD COLUMN `proposer_member_id uuid` REFERENCES `members(id)`
--      ON DELETE RESTRICT — preserves history, blocks orphan deletion of named proposer.
--   2) Backfill Frontiers fixture (`18ec4690-…`) with Fabrício Costa member_id `92d26057-…`
--      from p259 fixture payload (which was validated but not persisted by p256 M3 — see p256
--      M3 line 79-85 + p259 evidence doc §1).
--   3) CREATE OR REPLACE `create_governance_document_intake(jsonb)` — minimum-diff extension
--      to persist `proposer_member_id` from payload into the new column (preserves all other
--      behavior byte-identical: validation, status-A2, ack_mode-A1, audit row on offline).
--   4) CREATE new `sign_proposer_consent(p_document_id uuid, p_evidence jsonb DEFAULT NULL)`
--      SECDEF RPC. Gates: caller MUST equal `governance_documents.proposer_member_id`. Transitions
--      `status='pending_proposer_consent' → 'draft'`. Idempotent on already-draft. Captures
--      evidence in `admin_audit_log` (NOT `approval_signoffs` — proposer consent is PRE-chain
--      per A2; chains start later when GP opens workflow via the editor lock).
--
-- WHY: p256 M3 explicitly deferred the real consent flow to Wave 1b. p259 surfaced concretely
-- that Frontiers Editorial Guide is stuck at `pending_proposer_consent` since 2026-05-25 — the
-- canonical A2 path was incomplete. p260 Wave 4 audit identified this as v1 blocker #2 and PM
-- ratified dispatch sequence 1/7 at audit close (audit doc §15.5).
--
-- SPEC: SPEC §10 #312 + §11 persona #2 (Autor/proponente — "ver documento e comentarios
-- permitidos | virar submitter automaticamente"). The proposer is NOT auto-promoted to submitter;
-- they remain a distinct member whose only action on this RPC is consenting to the GP-initiated
-- intake. p260 audit §1.3 D1-D5 ratified (sequence 1/7 = this leaf).
--
-- SCOPE LOCK (per [[feedback-wave-1a-scope-confine-governance]]):
--   IN:  ALTER TABLE proposer_member_id + backfill Frontiers row + CREATE OR REPLACE intake
--        RPC + CREATE sign_proposer_consent RPC + NOTIFY pgrst.
--   OUT: gate templates (separate leaf #378); editor lock flow (Wave 4 implementation); MCP
--        wrapper (Wave 5); evidence bundle (Wave 6).
--
-- PM-RATIFIED CHOICES (p260 close):
--   • PRE-chain evidence path: `admin_audit_log` action='governance.proposer_consent_signed'
--     (NOT approval_signoffs — requires chain_id NOT NULL FK; proposer consent precedes chain).
--   • Caller MUST equal `proposer_member_id` (GP/admin cannot sign on behalf — matches p256 M3
--     guard for canonical A2 path).
--   • Idempotent return when status='draft' already — no double-INSERT, no error.
--
-- ROLLBACK (idempotent):
--   DROP FUNCTION public.sign_proposer_consent(uuid, jsonb);
--   -- restore create_governance_document_intake body to pre-p261 (re-apply 20260805000037 body).
--   ALTER TABLE public.governance_documents DROP COLUMN proposer_member_id;
--
-- INVARIANTS: V'_prime continues to report violation_count=0 post-deploy (Frontiers transitions
-- out of pending_proposer_consent on signing → V' no longer applies). V_status_chain_coherence
-- does NOT yet apply (status=draft, not approved/active). NO new invariant in this leaf.
--
-- CROSS-REF: #312 (audit umbrella) + #315 (Governance Documents v1) + #96 (Frontiers fixture)
-- + #377 (this child) + p256 M3 (deferred this RPC) + p259 (surfaced the gap) + p260 (audit +
-- PM ratification). SEDIMENT-239b.A honored (FK column source for accessor_id, target_id —
-- members.id NOT auth.users.id).
-- ============================================================================

-- p261.1 — ALTER TABLE: add proposer_member_id column (nullable; historical NULL OK)
ALTER TABLE public.governance_documents
  ADD COLUMN proposer_member_id uuid
    REFERENCES public.members(id) ON DELETE RESTRICT;

COMMENT ON COLUMN public.governance_documents.proposer_member_id IS
  'p261 #312-W4b: named proposer member.id (distinct from GP submitter). Required for sign_proposer_consent canonical A2 path; nullable for legacy docs created pre-#377. ON DELETE RESTRICT blocks orphan deletion of the named proposer.';

-- p261.2 — Backfill Frontiers fixture from p259 evidence
UPDATE public.governance_documents
   SET proposer_member_id = '92d26057-5550-4f15-a3bf-b00eed5f32f9'  -- Fabrício Costa
 WHERE id = '18ec4690-4f5a-4cab-904d-451e2c7245bf'  -- Guia Editorial Frontiers in AI & Project Mgmt
   AND status = 'pending_proposer_consent'
   AND proposer_member_id IS NULL;

-- Sanity DO RAISES if backfill missed the Frontiers row (1 expected)
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.governance_documents
  WHERE id = '18ec4690-4f5a-4cab-904d-451e2c7245bf'
    AND proposer_member_id = '92d26057-5550-4f15-a3bf-b00eed5f32f9';
  IF v_count != 1 THEN
    RAISE EXCEPTION 'p261 #312-W4b: Frontiers fixture backfill failed — expected 1 row, got %', v_count;
  END IF;
END $$;

-- p261.3 — Extend create_governance_document_intake to persist proposer_member_id
-- Minimum-diff CREATE OR REPLACE preserving all prior behavior (validation, status A2, ack_mode A1,
-- offline audit row). Only changes the INSERT INTO statement to include proposer_member_id.
CREATE OR REPLACE FUNCTION public.create_governance_document_intake(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_member_id uuid;
  v_caller_org_id uuid;
  v_title text;
  v_doc_type text;
  v_author_label text;
  v_visibility_class text;
  v_description text;
  v_proposer_ack_offline boolean := COALESCE((p_payload->>'proposer_ack_offline')::boolean, false);
  v_proposer_member_id uuid := nullif(p_payload->>'proposer_member_id','')::uuid;
  v_initial_status text;
  v_acknowledgement_mode text;
  v_doc_id uuid;
BEGIN
  -- Resolve caller (active member only)
  SELECT id, organization_id INTO v_caller_member_id, v_caller_org_id
  FROM public.members
  WHERE auth_id = auth.uid() AND is_active = true
  LIMIT 1;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no active member record' USING ERRCODE='42501';
  END IF;

  -- V4 capability gate (per SPEC §19.5 ratificada PM Q2=manage_event)
  IF NOT public.can_by_member(v_caller_member_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event capability' USING ERRCODE='42501';
  END IF;

  -- Validate Tier-1 payload (5 fields per P1-Q6)
  v_title            := nullif(trim(p_payload->>'title'), '');
  v_doc_type         := nullif(trim(p_payload->>'doc_type'), '');
  v_author_label     := nullif(trim(p_payload->>'author_label'), '');
  v_visibility_class := nullif(trim(p_payload->>'visibility_class'), '');
  v_description      := nullif(trim(p_payload->>'description'), '');
  IF v_title IS NULL OR v_doc_type IS NULL OR v_author_label IS NULL
     OR v_visibility_class IS NULL OR v_description IS NULL THEN
    RAISE EXCEPTION 'p256 intake: required fields title/doc_type/author_label/visibility_class/description';
  END IF;
  IF v_visibility_class NOT IN ('public','active_members','legal_scoped','admin_only','audit_restricted') THEN
    RAISE EXCEPTION 'p256 intake: invalid visibility_class';
  END IF;

  -- PM #2: proposer_member_id (optional) must NOT equal caller — GP cannot self-attest
  IF v_proposer_member_id IS NOT NULL AND v_proposer_member_id = v_caller_member_id THEN
    RAISE EXCEPTION 'p256 intake: proposer_member_id must differ from caller (GP cannot self-attest as proposer)';
  END IF;

  -- Default acknowledgement_mode per A1 (intake wizard pre-fills; admin can override later)
  v_acknowledgement_mode := CASE v_doc_type
    WHEN 'manual'                  THEN 'informational'
    WHEN 'editorial_guide'         THEN 'informational'
    WHEN 'governance_guideline'    THEN 'informational'
    WHEN 'executive_summary'       THEN 'informational'
    WHEN 'framework_reference'     THEN 'informational'
    WHEN 'project_charter'         THEN 'informational'
    WHEN 'cooperation_agreement'   THEN 'legal_signature'
    WHEN 'cooperation_addendum'    THEN 'legal_signature'
    WHEN 'volunteer_term_template' THEN 'binding'
    WHEN 'volunteer_addendum'      THEN 'binding'
    WHEN 'policy'                  THEN 'binding'
    ELSE 'informational'
  END;

  -- Status logic per A2
  v_initial_status := CASE WHEN v_proposer_ack_offline THEN 'draft' ELSE 'pending_proposer_consent' END;

  -- INSERT doc. p261 #312-W4b: NOW also persists proposer_member_id when provided in payload
  -- (previously validated but not stored — see p256 M3 line 79-85).
  INSERT INTO public.governance_documents (
    id, doc_type, title, description, status,
    organization_id, visibility_class, acknowledgement_mode,
    proposer_member_id,  -- p261 #312-W4b — new column write
    created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_doc_type, v_title, v_description, v_initial_status,
    v_caller_org_id, v_visibility_class, v_acknowledgement_mode,
    v_proposer_member_id,  -- p261 #312-W4b — already validated above; NULL is allowed
    now(), now()
  ) RETURNING id INTO v_doc_id;

  -- PM #2: when offline, register GP attestation in admin_audit_log
  -- (NOT a proposer_consent signoff — that would falsely attribute consent to GP)
  IF v_proposer_ack_offline THEN
    INSERT INTO public.admin_audit_log (actor_id, target_type, target_id, action, metadata)
    VALUES (
      v_caller_member_id, 'governance_document', v_doc_id,
      'governance.proposer_attestation_offline',
      jsonb_build_object(
        'document_id', v_doc_id,
        'author_label', v_author_label,
        'gp_actor_id', v_caller_member_id,
        'proposer_member_id', v_proposer_member_id,
        'note', 'GP-attested proposer intake (offline) — NOT a proposer_consent signoff. Real consent flow ships Wave 1b (p261 #312-W4b sign_proposer_consent).'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'document_id', v_doc_id,
    'status', v_initial_status,
    'acknowledgement_mode', v_acknowledgement_mode,
    'note', CASE WHEN v_proposer_ack_offline
                 THEN 'Doc in draft. GP attestation registered in admin_audit_log (NOT a proposer_consent signoff — Wave 1b ships real consent flow).'
                 ELSE 'Doc awaiting proposer in-app consent (pending_proposer_consent). Use sign_proposer_consent(document_id) once proposer authenticates.' END
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_governance_document_intake(jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.create_governance_document_intake(jsonb) TO authenticated;

-- p261.4 — sign_proposer_consent RPC
-- Canonical A2 path: named proposer signs in-app, doc transitions pending_proposer_consent → draft.
-- Idempotent on already-draft. Audit log captures evidence.
CREATE OR REPLACE FUNCTION public.sign_proposer_consent(
  p_document_id uuid,
  p_evidence jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_member_id uuid;
  v_doc_proposer_member_id uuid;
  v_doc_status text;
  v_doc_title text;
  v_signed_at timestamptz := now();
BEGIN
  -- Resolve active caller from auth.uid() → members.id (SEDIMENT-239b.A: FK source MUST be members.id)
  SELECT id INTO v_caller_member_id
  FROM public.members
  WHERE auth_id = auth.uid() AND is_active = true
  LIMIT 1;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no active member record' USING ERRCODE='42501';
  END IF;

  -- Load doc + proposer reference
  SELECT proposer_member_id, status, title
    INTO v_doc_proposer_member_id, v_doc_status, v_doc_title
  FROM public.governance_documents
  WHERE id = p_document_id;

  IF v_doc_title IS NULL THEN
    RAISE EXCEPTION 'governance_document % not found', p_document_id USING ERRCODE='42704';
  END IF;

  IF v_doc_proposer_member_id IS NULL THEN
    RAISE EXCEPTION 'governance_document % has no proposer_member_id set; sign_proposer_consent requires a named proposer (was the doc created via Wave 2 intake?)', p_document_id
      USING ERRCODE='22023';
  END IF;

  -- Caller MUST equal proposer (GP/admin cannot sign on behalf — matches p256 M3 self-attest guard)
  IF v_caller_member_id != v_doc_proposer_member_id THEN
    RAISE EXCEPTION 'Unauthorized: only the named proposer can sign proposer_consent for this document'
      USING ERRCODE='42501';
  END IF;

  -- Idempotent: already-signed doc returns ok without double-write
  IF v_doc_status = 'draft' THEN
    RETURN jsonb_build_object(
      'ok', true,
      'already_signed', true,
      'document_id', p_document_id,
      'status', 'draft',
      'proposer_member_id', v_doc_proposer_member_id,
      'note', 'Document already advanced past pending_proposer_consent; consent was signed previously (idempotent path).'
    );
  END IF;

  -- Status guard: only pending_proposer_consent can transition here
  IF v_doc_status != 'pending_proposer_consent' THEN
    RAISE EXCEPTION 'sign_proposer_consent: doc % is in status %; requires pending_proposer_consent', p_document_id, v_doc_status
      USING ERRCODE='22023';
  END IF;

  -- Atomic flip
  UPDATE public.governance_documents
     SET status = 'draft',
         updated_at = v_signed_at
   WHERE id = p_document_id;

  -- Audit row — canonical action, FK source members.id NOT auth.users.id (SEDIMENT-239b.A)
  INSERT INTO public.admin_audit_log (actor_id, target_type, target_id, action, metadata)
  VALUES (
    v_caller_member_id,
    'governance_document',
    p_document_id,
    'governance.proposer_consent_signed',
    jsonb_build_object(
      'document_id', p_document_id,
      'document_title', v_doc_title,
      'proposer_member_id', v_doc_proposer_member_id,
      'signed_at', v_signed_at,
      'evidence', p_evidence,
      'rpc_version', 'p261_312_w4b',
      'note', 'Canonical A2 path: named proposer signed in-app; doc transitioned pending_proposer_consent → draft. Pre-chain capture; approval_chain created later when GP opens workflow.'
    )
  );

  RETURN jsonb_build_object(
    'ok', true,
    'document_id', p_document_id,
    'status', 'draft',
    'signed_at', v_signed_at,
    'proposer_member_id', v_doc_proposer_member_id,
    'note', 'proposer_consent signed; doc transitioned pending_proposer_consent → draft. Next step: GP opens approval chain via editor lock.'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sign_proposer_consent(uuid, jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.sign_proposer_consent(uuid, jsonb) TO authenticated;

NOTIFY pgrst, 'reload schema';
