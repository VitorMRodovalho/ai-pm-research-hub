-- WHAT: Wave 1a M3 — two SECDEF RPCs for governance doc intake + member library.
--   1) create_governance_document_intake(jsonb) — Tier-1 intake (P1-Q6 5 fields)
--      + optional proposer_ack_offline (A2) + optional proposer_member_id (PM #2).
--   2) list_governance_library(jsonb) — class-aware reader with file_id forward-defense.
--
-- WHY: M2 swapped gd_read to class-aware RLS. Member-facing library must go through
-- a SECDEF reader (not direct SELECT) so the visibility predicate is enforced consistently
-- and the response shape can ALWAYS exclude file_id / drive_url / content (P0-Q8).
-- Intake is the canonical write surface (Wave 2 admin UI consumes it; Wave 5 MCP wrapper
-- consumes it). Wave 1a ships the intake-only happy path — full chain workflow stays on
-- existing RPCs.
--
-- SPEC: §19.5 Wave 1a M3. PM corrections applied (rev2 plan):
--   #1 — closing_gate_signoff_id FK = RESTRICT (lands in M2; no impact on M3).
--   #2 — Intake does NOT create proposer_consent signoff via GP. proposer_ack_offline
--        = true → status=draft + INSERT admin_audit_log row (action=
--        governance.proposer_attestation_offline). proposer_member_id (optional) MUST
--        differ from caller — GP cannot self-attest. Real sign_proposer_consent flow
--        ships Wave 1b (in-app proposer-authenticated path).
--   (#3/#4/#5 lands in M2 or test plan; unchanged here.)
--
-- SCOPE LOCK: Wave 1a M3 is ONLY these 2 RPCs. Wave 5 MCP wrappers, Wave 2 admin UI,
-- Wave 3 member-facing biblioteca route, and Wave 1b dependent tables (artifacts,
-- dependencies, content_products) are all OUT-OF-SCOPE.
--
-- ROLLBACK (idempotent):
--   DROP FUNCTION public.create_governance_document_intake(jsonb);
--   DROP FUNCTION public.list_governance_library(jsonb);
--
-- INVARIANTS: no invariant change in M3 (V' shipped in M2; V deferred Wave 1b).
-- CROSS-REF: #315 Wave 0; SPEC §19.5; ADR-0007 V4 authority; session p256.
-- ============================================================================

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

  -- INSERT doc. PM #2: NO chain/signoff created — real consent flow ships Wave 1b.
  INSERT INTO public.governance_documents (
    id, doc_type, title, description, status,
    organization_id, visibility_class, acknowledgement_mode,
    created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_doc_type, v_title, v_description, v_initial_status,
    v_caller_org_id, v_visibility_class, v_acknowledgement_mode,
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
        'note', 'GP-attested proposer intake (offline) — NOT a proposer_consent signoff. Real consent flow ships Wave 1b.'
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
                 ELSE 'Doc awaiting proposer in-app consent (pending_proposer_consent). Wave 1b will ship sign_proposer_consent RPC.' END
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_governance_document_intake(jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.create_governance_document_intake(jsonb) TO authenticated;

-- ============================================================================

CREATE OR REPLACE FUNCTION public.list_governance_library(p_filters jsonb DEFAULT '{}'::jsonb)
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
  v_filter_doc_type text;
  v_filter_status text;
  v_result jsonb;
BEGIN
  -- Active membership gate
  SELECT id INTO v_caller_member_id
  FROM public.members
  WHERE auth_id = auth.uid() AND is_active = true
  LIMIT 1;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no active member record' USING ERRCODE='42501';
  END IF;

  v_is_admin          := public.can_by_member(v_caller_member_id, 'manage_member');
  v_is_platform_admin := public.can_by_member(v_caller_member_id, 'manage_platform');

  v_filter_doc_type := nullif(p_filters->>'doc_type', '');
  v_filter_status   := nullif(p_filters->>'status', '');

  -- Build result jsonb. P0-Q8 FORWARD-DEFENSE: response shape NEVER includes
  -- file_id, drive_url, content, or pdf_url — those go through a separate
  -- artifact-handle resolver (Wave 5).
  SELECT jsonb_build_object(
    'documents', COALESCE(jsonb_agg(d ORDER BY d->>'title'), '[]'::jsonb),
    'total', count(*)
  )
  INTO v_result
  FROM (
    SELECT jsonb_build_object(
      'id', gd.id,
      'title', gd.title,
      'description', gd.description,
      'doc_type', gd.doc_type,
      'status', gd.status,
      'visibility_class', gd.visibility_class,
      'acknowledgement_mode', gd.acknowledgement_mode,
      'effective_from', gd.effective_from,
      'effective_until', gd.effective_until,
      'approved_at', gd.approved_at,
      'current_ratified_version_id', gd.current_ratified_version_id,
      'current_version_id', gd.current_version_id
    ) AS d
    FROM public.governance_documents gd
    WHERE
      (v_filter_doc_type IS NULL OR gd.doc_type = v_filter_doc_type)
      AND (v_filter_status IS NULL OR gd.status = v_filter_status)
      AND gd.visibility_class IS NOT NULL
      AND (
        gd.visibility_class = 'public'
        OR gd.visibility_class = 'active_members'  -- caller already gated as active member above
        OR (gd.visibility_class = 'legal_scoped' AND (
            v_is_admin
            OR EXISTS (
              SELECT 1 FROM public.member_document_signatures mds
              WHERE mds.member_id = v_caller_member_id
                AND mds.document_id = gd.id
                AND mds.is_current = true
            )))
        OR (gd.visibility_class = 'admin_only' AND v_is_admin)
        OR (gd.visibility_class = 'audit_restricted' AND v_is_platform_admin)
      )
  ) sub;

  RETURN COALESCE(v_result, jsonb_build_object('documents', '[]'::jsonb, 'total', 0));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.list_governance_library(jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_governance_library(jsonb) TO authenticated;

NOTIFY pgrst, 'reload schema';
