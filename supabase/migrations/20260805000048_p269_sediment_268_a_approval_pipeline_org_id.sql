-- ============================================================================
-- p269 SEDIMENT-268.A — approval pipeline organization_id remediation
--
-- WHAT: CREATE OR REPLACE FUNCTION for two RPCs that INSERT into the approval
--       pipeline post-W1a M2, but never had their bodies updated to populate
--       `organization_id` (NOT NULL, no default) on the target rows:
--
--         1) public.lock_document_version(p_version_id uuid, p_gates jsonb)
--              v_version SELECT gains `dv.organization_id`.
--              INSERT INTO public.approval_chains adds `organization_id` column
--              sourced from `v_version.organization_id` (FK to organizations).
--
--         2) public.sign_ip_ratification(
--              p_chain_id uuid, p_gate_kind text,
--              p_signoff_type text DEFAULT 'approval',
--              p_sections_verified jsonb DEFAULT NULL,
--              p_comment_body text DEFAULT NULL,
--              p_ue_consent_49_1_a boolean DEFAULT NULL
--            )
--              v_chain SELECT gains `ac.organization_id`.
--              INSERT INTO public.approval_signoffs adds `organization_id` column
--              sourced from `v_chain.organization_id`.
--
--       Both fixes are MINIMUM-DIFF against current live body:
--         - Same identity signature (no DROP+CREATE).
--         - SECURITY DEFINER preserved.
--         - SET search_path = public, pg_temp preserved.
--         - RETURNS jsonb envelope preserved (success/chain_id/notifications_enqueued
--           for lock; success/signoff_id/signature_hash/gates_remaining/... for sign).
--         - Auth gates preserved (can_by_member('manage_member') for lock;
--           _can_sign_gate(...) for sign).
--         - All validations, UPDATE branches, audit log, notification enqueue,
--           certificate issuance, dual EU/non-EU branches, RF-III/RF-V evidence
--           wiring — all verbatim.
--         - All DEFAULTs intact for sign_ip_ratification (SEDIMENT-238.C).
--
-- WHY: migration `20260805000035_p256_wave1a_315_m1_governance_org_id_backfill`
--      added NOT NULL `organization_id` to approval_chains + approval_signoffs
--      (and 11 other governance/intake tables) under p256 Wave 1a M1 — P0-Q5
--      multi-tenant invariant V/V'. The two canonical writers above were never
--      updated to populate the new column. Any caller of lock_document_version
--      would raise 23502 not_null_violation on the INSERT INTO approval_chains,
--      and any subsequent caller of sign_ip_ratification (which depends on a
--      chain existing) would raise the same on INSERT INTO approval_signoffs.
--
--      Bug was MASKED because the Frontiers v1.x guide draft (the next
--      governance_document to be locked into a chain since the W1a M2 constraint
--      landed) is still in `draft`/`locked_at IS NULL` per PM directive — the
--      Gate 0 jurídico (advogada review) holds the chain from opening. We
--      surface the latent bug now via SEDIMENT-268.A audit (p269) — same class
--      as BUG-268.A (migration 20260805000047, p268) which fixed
--      upsert_document_version.
--
--      sign_ratification_gate (MCP tool) is a JS alias in
--      `supabase/functions/nucleo-mcp/index.ts:5337` that wraps
--      `sb.rpc('sign_ip_ratification', …)` — NOT a phantom RPC. Fixing the
--      underlying RPC fixes both invocation paths transparently.
--
-- SCOPE — Tier 1 ONLY (PM decision, Opção A):
--      In scope: lock_document_version + sign_ip_ratification (this migration).
--      Out of scope: confirm_manual_version + link_attachment_to_governance
--                    omit org_id AND visibility_class AND acknowledgement_mode
--                    on INSERT INTO governance_documents — same bug class but
--                    requires semantic decision on default values per doc_type.
--                    Tracked as BUG-268.B follow-up.
--
-- HOW (minimum diff vs live body, both RPCs):
--      lock_document_version:
--        - SELECT into v_version: add `dv.organization_id` after `dv.document_id`.
--        - INSERT INTO public.approval_chains: add `organization_id` column right
--          after `version_id` (FK grouping) + `v_version.organization_id` in VALUES.
--      sign_ip_ratification:
--        - SELECT into v_chain: add `ac.organization_id` after `ac.gates`.
--        - INSERT INTO public.approval_signoffs: add `organization_id` column
--          right after `approval_chain_id` (FK grouping) + `v_chain.organization_id`
--          in VALUES.
--
-- ROLLBACK: re-apply the prior bodies via git history — but rollback re-introduces
--           SEDIMENT-268.A, so do NOT rollback unless NOT NULL on
--           approval_chains.organization_id + approval_signoffs.organization_id
--           is also dropped (which would rollback p256 W1a M1 invariant V/V' —
--           out of scope here).
--
-- TEST: contract `tests/contracts/sediment-268-a-approval-pipeline-org-id.test.mjs`
--       locks 13 static assertions + 2 forward-defense regressions + 2 DB-gated:
--       Static:
--         file existence + 2 CREATE OR REPLACE + SECDEF + pinned search_path (both) +
--         RETURNS jsonb (both) + lock_document_version 2-arg signature + 0 DEFAULTs +
--         sign_ip_ratification 6-arg signature + 4 DEFAULTs preserved (SEDIMENT-238.C) +
--         lock_document_version SELECT v_version extended with dv.organization_id +
--         lock_document_version INSERT approval_chains has organization_id column +
--         lock_document_version VALUES uses v_version.organization_id +
--         sign_ip_ratification SELECT v_chain extended with ac.organization_id +
--         sign_ip_ratification INSERT approval_signoffs has organization_id column +
--         sign_ip_ratification VALUES uses v_chain.organization_id +
--         2 sanity DO blocks + NOTIFY pgrst.
--       Forward-defense (lock the regression class):
--         FD-1. INSERT INTO public.approval_chains in lock_document_version body
--               CANNOT exist without organization_id literal.
--         FD-2. INSERT INTO public.approval_signoffs in sign_ip_ratification body
--               CANNOT exist without organization_id literal.
--       DB-gated:
--         DB-1. Live lock_document_version prosrc contains organization_id.
--         DB-2. Live sign_ip_ratification prosrc contains organization_id.
--       SEDIMENT-239b.A applied: contract test asserts source of every FK column
--       (v_version.organization_id + v_chain.organization_id), not just gate ladder.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- (1/2) lock_document_version — populate approval_chains.organization_id
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.lock_document_version(
  p_version_id uuid,
  p_gates jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_member record;
  v_version record;
  v_chain_id uuid;
  v_existing_chain uuid;
  v_notif_count int;
BEGIN
  SELECT m.id, m.name INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- SEDIMENT-268.A fix: also select dv.organization_id so the INSERT below
  -- can satisfy approval_chains.organization_id NOT NULL (p256 W1a M1).
  SELECT dv.id, dv.document_id, dv.organization_id, dv.version_number, dv.version_label, dv.locked_at
  INTO v_version
  FROM public.document_versions dv WHERE dv.id = p_version_id;

  IF v_version.id IS NULL THEN
    RAISE EXCEPTION 'document_version not found (id=%)', p_version_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_version.locked_at IS NOT NULL THEN
    RAISE EXCEPTION 'document_version already locked at % — create a new version instead', v_version.locked_at
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_gates IS NULL OR jsonb_typeof(p_gates) <> 'array' OR jsonb_array_length(p_gates) = 0 THEN
    RAISE EXCEPTION 'gates must be a non-empty jsonb array' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_gates) g
    WHERE NOT (g ? 'kind' AND g ? 'order' AND g ? 'threshold')
  ) THEN
    RAISE EXCEPTION 'each gate must have kind, order, threshold keys' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT ac.id INTO v_existing_chain
  FROM public.approval_chains ac
  WHERE ac.version_id = p_version_id LIMIT 1;
  IF v_existing_chain IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'chain_already_exists',
      'chain_id', v_existing_chain,
      'version_id', p_version_id
    );
  END IF;

  UPDATE public.document_versions
    SET locked_at = now(),
        locked_by = v_member.id,
        published_at = now(),
        published_by = v_member.id,
        updated_at = now()
    WHERE id = p_version_id;

  -- SEDIMENT-268.A fix: include organization_id (NOT NULL post-W1a M1) sourced
  -- from v_version.organization_id (parent document_versions row), preserving
  -- tenant integrity via FK chain.
  INSERT INTO public.approval_chains (
    document_id, version_id, organization_id, status, gates, opened_at, opened_by
  ) VALUES (
    v_version.document_id, p_version_id, v_version.organization_id, 'review', p_gates, now(), v_member.id
  ) RETURNING id INTO v_chain_id;

  UPDATE public.governance_documents
    SET current_version_id = p_version_id,
        updated_at = now()
    WHERE id = v_version.document_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_member.id, 'document_version.locked', 'document_version', p_version_id,
    jsonb_build_object(
      'document_id', v_version.document_id,
      'version_number', v_version.version_number,
      'version_label', v_version.version_label,
      'chain_id', v_chain_id,
      'gates', p_gates
    )
  );

  v_notif_count := public._enqueue_gate_notifications(v_chain_id, 'chain_opened', NULL);

  RETURN jsonb_build_object(
    'success', true,
    'version_id', p_version_id,
    'chain_id', v_chain_id,
    'notifications_enqueued', v_notif_count,
    'locked_at', now()
  );
END;
$function$;

COMMENT ON FUNCTION public.lock_document_version(uuid, jsonb) IS
  'Locks a document_version and opens an approval_chain (status=review). organization_id sourced from parent document_versions row (SEDIMENT-268.A fix, p269). Auth: manage_member. Phase IP-3d + p269 SEDIMENT-268.A.';

-- Sanity (no NOT NULL/check violations should be possible from this RPC anymore).
DO $sanity_lock$
DECLARE
  v_body text;
BEGIN
  SELECT prosrc INTO v_body
  FROM pg_proc
  WHERE pronamespace = 'public'::regnamespace
    AND proname = 'lock_document_version'
  LIMIT 1;

  IF v_body IS NULL THEN
    RAISE EXCEPTION 'p269 SEDIMENT-268.A sanity: lock_document_version not found in pg_proc';
  END IF;
  IF position('organization_id' IN v_body) = 0 THEN
    RAISE EXCEPTION 'p269 SEDIMENT-268.A sanity: lock_document_version body must reference organization_id';
  END IF;
END;
$sanity_lock$;

-- ----------------------------------------------------------------------------
-- (2/2) sign_ip_ratification — populate approval_signoffs.organization_id
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sign_ip_ratification(
  p_chain_id uuid,
  p_gate_kind text,
  p_signoff_type text DEFAULT 'approval',
  p_sections_verified jsonb DEFAULT NULL,
  p_comment_body text DEFAULT NULL,
  p_ue_consent_49_1_a boolean DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_member record; v_chain record; v_version record; v_doc record;
  v_signoff_id uuid; v_hash text; v_snapshot jsonb; v_existing uuid;
  v_all_satisfied boolean; v_cert_id uuid; v_cert_code text;
  v_gates_remaining int; v_mbr_signature_id uuid;
  v_is_eu boolean := false; v_ue_consent_required boolean := false;
  v_is_member_ratify boolean := false;
  v_policy_version_id uuid;
  v_policy_version_label text;
  v_notif_read_at timestamptz;
  v_notif_created_at timestamptz;
  v_notif_id uuid;
  v_ue_docs text[] := ARRAY[
    'Termo de Compromisso de Voluntário — Núcleo de IA & GP',
    'Adendo Retificativo ao Termo de Compromisso de Voluntario'];
BEGIN
  SELECT m.id, m.name, m.email, m.operational_role, m.pmi_id, m.chapter,
         m.designations, m.member_status, m.person_id
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RETURN jsonb_build_object('error','not_authenticated'); END IF;

  IF NOT public._can_sign_gate(v_member.id, p_chain_id, p_gate_kind) THEN
    RETURN jsonb_build_object('error','access_denied','message','Member not authorized for gate_kind=' || p_gate_kind);
  END IF;

  -- SEDIMENT-268.A fix: also select ac.organization_id so the INSERT below
  -- can satisfy approval_signoffs.organization_id NOT NULL (p256 W1a M1).
  SELECT ac.id, ac.status, ac.document_id, ac.version_id, ac.gates, ac.organization_id
  INTO v_chain FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN RETURN jsonb_build_object('error','chain_not_found'); END IF;

  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html, dv.locked_at
  INTO v_version FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT gd.id, gd.title, gd.doc_type INTO v_doc
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT id INTO v_existing FROM public.approval_signoffs
  WHERE approval_chain_id = p_chain_id AND gate_kind = p_gate_kind AND signer_id = v_member.id;
  IF v_existing IS NOT NULL THEN RETURN jsonb_build_object('error','already_signed','signoff_id',v_existing); END IF;

  v_is_member_ratify := (p_gate_kind IN ('member_ratification','volunteers_in_role_active'));

  IF v_is_member_ratify AND v_doc.title = ANY(v_ue_docs) THEN
    v_is_eu := public.is_eu_resident(v_member.person_id);
    IF v_is_eu THEN
      v_ue_consent_required := true;
      IF p_ue_consent_49_1_a IS NULL OR p_ue_consent_49_1_a = false THEN
        RETURN jsonb_build_object(
          'error', 'ue_consent_required',
          'message', 'EU resident must explicitly consent to Art. 49(1)(a) GDPR data transfer.',
          'document_title', v_doc.title,
          'applicable_clause', CASE
            WHEN v_doc.title = 'Termo de Compromisso de Voluntário — Núcleo de IA & GP' THEN 'Clausula 14'
            ELSE 'Art. 8' END);
      END IF;
    END IF;
  END IF;

  -- RF-III: snapshot Política vigente (current_version_id do doc_type=policy)
  SELECT gd.current_version_id, dv.version_label INTO v_policy_version_id, v_policy_version_label
  FROM public.governance_documents gd
  LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
  WHERE gd.doc_type = 'policy' AND gd.status IN ('active','under_review')
  ORDER BY CASE WHEN gd.status='active' THEN 0 ELSE 1 END LIMIT 1;

  -- RF-V: evidence de ato concludente — read_at da notificação relacionada
  SELECT n.id, n.read_at, n.created_at
    INTO v_notif_id, v_notif_read_at, v_notif_created_at
  FROM public.notifications n
  WHERE n.recipient_id = v_member.id
    AND n.source_type = 'approval_chain'
    AND n.source_id::text = p_chain_id::text
    AND n.type LIKE 'ip_ratification_%'
  ORDER BY n.created_at DESC LIMIT 1;

  v_snapshot := jsonb_build_object(
    'document_id', v_doc.id, 'document_title', v_doc.title, 'doc_type', v_doc.doc_type,
    'version_id', v_version.id, 'version_number', v_version.version_number, 'version_label', v_version.version_label,
    'version_locked_at', v_version.locked_at,
    'signer_id', v_member.id, 'signer_name', v_member.name, 'signer_email', v_member.email,
    'signer_role', v_member.operational_role, 'signer_chapter', v_member.chapter,
    'signer_pmi_id', v_member.pmi_id, 'signer_designations', to_jsonb(v_member.designations),
    'gate_kind', p_gate_kind, 'signoff_type', p_signoff_type, 'signed_at', now(),
    'signer_is_eu_resident', v_is_eu,
    'ue_consent_recorded', COALESCE(p_ue_consent_49_1_a, false),
    'ue_consent_required_by_policy', v_ue_consent_required,
    -- RF-III evidence
    'referenced_policy_version_id', v_policy_version_id,
    'referenced_policy_version_label', v_policy_version_label,
    -- RF-V evidence (ato concludente CC Art. 111)
    'notification_id', v_notif_id,
    'notification_created_at', v_notif_created_at,
    'notification_read_at', v_notif_read_at,
    'notification_read_evidence', CASE WHEN v_notif_read_at IS NOT NULL THEN true ELSE false END
  );

  v_hash := encode(sha256(convert_to(v_snapshot::text || v_member.id::text || now()::text || 'nucleo-ia-ip-ratify-salt', 'UTF8')), 'hex');

  -- SEDIMENT-268.A fix: include organization_id (NOT NULL post-W1a M1) sourced
  -- from v_chain.organization_id (parent approval_chains row), preserving tenant
  -- integrity via FK chain.
  INSERT INTO public.approval_signoffs (
    approval_chain_id, organization_id, gate_kind, signer_id, signoff_type,
    signed_at, signature_hash, content_snapshot, sections_verified, comment_body,
    referenced_policy_version_id
  ) VALUES (
    p_chain_id, v_chain.organization_id, p_gate_kind, v_member.id, p_signoff_type,
    now(), v_hash, v_snapshot, p_sections_verified, p_comment_body,
    v_policy_version_id
  ) RETURNING id INTO v_signoff_id;

  SELECT COUNT(*) INTO v_gates_remaining
  FROM jsonb_array_elements(v_chain.gates) g
  WHERE
    ((g->>'threshold') = 'all'
      AND (SELECT COUNT(*) FROM public.approval_signoffs s
           WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (g->>'kind')
             AND s.signoff_type IN ('approval','acknowledge'))
         < (SELECT COUNT(*) FROM public.members m
            WHERE m.is_active = true
              AND public._can_sign_gate(m.id, p_chain_id, g->>'kind')))
    OR
    ((g->>'threshold') ~ '^[0-9]+$'
      AND (g->>'threshold')::int > 0
      AND (SELECT COUNT(*) FROM public.approval_signoffs s
           WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (g->>'kind')
             AND s.signoff_type IN ('approval','acknowledge')) < (g->>'threshold')::int);

  v_all_satisfied := (v_gates_remaining = 0);

  IF v_is_member_ratify AND p_signoff_type = 'approval' THEN
    v_cert_code := 'IPRAT-' || EXTRACT(YEAR FROM now())::text || '-' || UPPER(SUBSTRING(gen_random_uuid()::text FROM 1 FOR 6));

    INSERT INTO public.certificates (
      member_id, type, title, description, cycle, issued_at, issued_by, verification_code,
      function_role, language, status, signature_hash, content_snapshot, template_id
    ) VALUES (
      v_member.id, 'ip_ratification',
      'Ratificacao IP — ' || v_doc.title,
      'Ratificacao do documento ' || v_doc.title || ' versao ' || v_version.version_label,
      EXTRACT(YEAR FROM now())::int, now(), v_member.id, v_cert_code,
      v_member.operational_role, 'pt-BR', 'issued', v_hash, v_snapshot, v_doc.id::text
    ) RETURNING id INTO v_cert_id;

    INSERT INTO public.member_document_signatures (
      member_id, document_id, signed_version_id, approval_chain_id,
      signoff_id, certificate_id, signed_at, is_current
    ) VALUES (v_member.id, v_doc.id, v_version.id, p_chain_id, v_signoff_id, v_cert_id, now(), true)
    RETURNING id INTO v_mbr_signature_id;
  END IF;

  IF v_all_satisfied AND v_chain.status = 'review' THEN
    UPDATE public.approval_chains SET status = 'approved', approved_at = now(), updated_at = now()
      WHERE id = p_chain_id;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'ip_ratification_signoff', 'approval_signoff', v_signoff_id,
    jsonb_build_object('chain_id', p_chain_id, 'gate_kind', p_gate_kind, 'signoff_type', p_signoff_type,
      'document_id', v_doc.id, 'document_title', v_doc.title, 'version_label', v_version.version_label,
      'chain_satisfied', v_all_satisfied, 'certificate_id', v_cert_id,
      'signer_is_eu_resident', v_is_eu,
      'ue_consent_recorded', COALESCE(p_ue_consent_49_1_a, false),
      'referenced_policy_version_id', v_policy_version_id,
      'notification_read_evidence', (v_notif_read_at IS NOT NULL)));

  RETURN jsonb_build_object('success', true, 'signoff_id', v_signoff_id, 'signature_hash', v_hash,
    'gates_remaining', v_gates_remaining, 'chain_satisfied', v_all_satisfied,
    'certificate_id', v_cert_id, 'certificate_code', v_cert_code,
    'member_signature_id', v_mbr_signature_id, 'signed_at', now(),
    'signer_is_eu_resident', v_is_eu,
    'ue_consent_recorded', COALESCE(p_ue_consent_49_1_a, false),
    'referenced_policy_version_id', v_policy_version_id,
    'notification_read_evidence', (v_notif_read_at IS NOT NULL));
END;
$function$;

COMMENT ON FUNCTION public.sign_ip_ratification(uuid, text, text, jsonb, text, boolean) IS
  'Signs a gate on an IP ratification approval chain. organization_id sourced from parent approval_chains row (SEDIMENT-268.A fix, p269). Auth: _can_sign_gate ladder. ADR-0016 + p269 SEDIMENT-268.A.';

-- Sanity (no NOT NULL/check violations should be possible from this RPC anymore).
DO $sanity_sign$
DECLARE
  v_body text;
BEGIN
  SELECT prosrc INTO v_body
  FROM pg_proc
  WHERE pronamespace = 'public'::regnamespace
    AND proname = 'sign_ip_ratification'
  LIMIT 1;

  IF v_body IS NULL THEN
    RAISE EXCEPTION 'p269 SEDIMENT-268.A sanity: sign_ip_ratification not found in pg_proc';
  END IF;
  IF position('organization_id' IN v_body) = 0 THEN
    RAISE EXCEPTION 'p269 SEDIMENT-268.A sanity: sign_ip_ratification body must reference organization_id';
  END IF;
END;
$sanity_sign$;

NOTIFY pgrst, 'reload schema';
