-- ============================================================================
-- Migration: Phase IP-2 B — advance_approval_gate (FSM) + get_ratification_reminder_targets
-- ADR-0016 D1 (gates como data) + D5 (audit hook em chain lifecycle)
--
-- Nota: sign_ip_ratification (IP-1) já auto-advances chain review→approved
-- quando threshold gates satisfeitos. Este RPC cobre os outros segmentos:
--   draft → review (admin opens chain for signoffs)
--   approved → active (admin activates ratified document)
--   any → withdrawn | superseded (admin closes)
--
-- Rollback:
--   DROP FUNCTION public.advance_approval_gate(uuid, text, text);
--   DROP FUNCTION public.get_ratification_reminder_targets(uuid);
-- ============================================================================

-- ---------------------------------------------------------------------------
-- advance_approval_gate — FSM transition for approval_chains.status
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.advance_approval_gate(
  p_chain_id uuid,
  p_target_status text,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_caller_id uuid;
  v_chain public.approval_chains%ROWTYPE;
  v_now timestamptz := now();
BEGIN
  -- Auth gate (ADR-0011 canonical)
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: requires manage_member' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Load chain
  SELECT * INTO v_chain FROM public.approval_chains WHERE id = p_chain_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'approval_chain not found (id=%)', p_chain_id USING ERRCODE = 'no_data_found';
  END IF;

  -- Validate target
  IF p_target_status NOT IN ('review', 'active', 'withdrawn', 'superseded') THEN
    RAISE EXCEPTION 'Invalid target status: % (allowed: review, active, withdrawn, superseded — review→approved is automatic via sign_ip_ratification)',
      p_target_status USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Legal transitions
  IF v_chain.status = 'draft' AND p_target_status NOT IN ('review', 'withdrawn') THEN
    RAISE EXCEPTION 'Illegal transition: draft -> %', p_target_status USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_chain.status = 'review' AND p_target_status NOT IN ('withdrawn') THEN
    RAISE EXCEPTION 'Illegal transition: review -> % (review→approved is automatic when all gates satisfied; to manually close use withdrawn)',
      p_target_status USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_chain.status = 'approved' AND p_target_status NOT IN ('active', 'withdrawn', 'superseded') THEN
    RAISE EXCEPTION 'Illegal transition: approved -> %', p_target_status USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_chain.status = 'active' AND p_target_status NOT IN ('withdrawn', 'superseded') THEN
    RAISE EXCEPTION 'Illegal transition: active -> %', p_target_status USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_chain.status IN ('withdrawn', 'superseded') THEN
    RAISE EXCEPTION 'Chain is in terminal state %, no transitions allowed', v_chain.status USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Apply transition + timestamps
  UPDATE public.approval_chains SET
    status = p_target_status,
    opened_at = CASE WHEN p_target_status = 'review' AND v_chain.opened_at IS NULL THEN v_now ELSE opened_at END,
    opened_by = CASE WHEN p_target_status = 'review' AND v_chain.opened_by IS NULL THEN v_caller_id ELSE opened_by END,
    activated_at = CASE WHEN p_target_status = 'active' THEN v_now ELSE activated_at END,
    closed_at = CASE WHEN p_target_status IN ('withdrawn', 'superseded') THEN v_now ELSE closed_at END,
    closed_by = CASE WHEN p_target_status IN ('withdrawn', 'superseded') THEN v_caller_id ELSE closed_by END,
    notes = CASE WHEN p_reason IS NOT NULL
                 THEN coalesce(notes || E'\n---\n', '') || '[' || p_target_status || '] ' || p_reason
                 ELSE notes END,
    updated_at = v_now
  WHERE id = p_chain_id;

  -- Audit (ADR-0016 D5 camada 2: chain lifecycle)
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (
    v_caller_id,
    'approval_chain.advanced_to_' || p_target_status,
    'approval_chain',
    p_chain_id,
    jsonb_build_object(
      'document_id', v_chain.document_id,
      'version_id', v_chain.version_id,
      'from_status', v_chain.status,
      'to_status', p_target_status,
      'reason', p_reason
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'chain_id', p_chain_id,
    'from_status', v_chain.status,
    'to_status', p_target_status,
    'advanced_at', v_now,
    'advanced_by', v_caller_id
  );
END;
$function$;

COMMENT ON FUNCTION public.advance_approval_gate(uuid, text, text) IS
  'FSM transitions for approval_chains.status. ADR-0016 D1. draft→review opens chain for signoffs; approved→active activates ratified document; any→withdrawn/superseded closes chain. review→approved is automatic via sign_ip_ratification (IP-1). Auth: manage_member.';

GRANT EXECUTE ON FUNCTION public.advance_approval_gate(uuid, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- get_ratification_reminder_targets — list of members pending signoff for reminder cron
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_ratification_reminder_targets(
  p_document_id uuid
)
RETURNS TABLE (
  target_type text,
  member_id uuid,
  person_id uuid,
  name text,
  email text,
  expected_gate_kind text,
  chain_id uuid,
  version_label text,
  days_since_chain_opened int
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_caller_id uuid;
  v_current_version uuid;
  v_chain_id uuid;
  v_chain_opened_at timestamptz;
  v_chain_gates jsonb;
  v_version_label text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: requires manage_member' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Resolve the governance_documents.current_version_id
  SELECT current_version_id INTO v_current_version
  FROM public.governance_documents WHERE id = p_document_id;
  IF v_current_version IS NULL THEN
    RETURN;
  END IF;

  SELECT dv.version_label INTO v_version_label
  FROM public.document_versions dv WHERE dv.id = v_current_version;

  -- Active chain (in review or approved)
  SELECT ac.id, ac.opened_at, ac.gates
    INTO v_chain_id, v_chain_opened_at, v_chain_gates
  FROM public.approval_chains ac
  WHERE ac.document_id = p_document_id
    AND ac.version_id = v_current_version
    AND ac.status IN ('review', 'approved')
  ORDER BY ac.opened_at DESC NULLS LAST
  LIMIT 1;

  IF v_chain_id IS NULL THEN
    RETURN;
  END IF;

  -- Pending members (active, non-external, missing signature on current version)
  RETURN QUERY
  SELECT
    'member_pending_ratification'::text AS target_type,
    m.id AS member_id,
    m.person_id,
    m.name,
    m.email,
    'member_ratification'::text AS expected_gate_kind,
    v_chain_id AS chain_id,
    v_version_label AS version_label,
    GREATEST(0, EXTRACT(day FROM (now() - v_chain_opened_at))::int) AS days_since_chain_opened
  FROM public.members m
  WHERE m.is_active = true
    AND m.member_status = 'active'
    AND (m.operational_role IS NULL OR m.operational_role <> 'external_signer')
    -- No existing signature on this version
    AND NOT EXISTS (
      SELECT 1 FROM public.member_document_signatures mds
      WHERE mds.member_id = m.id AND mds.signed_version_id = v_current_version
    )
    -- Gate member_ratification exists in chain config
    AND EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_chain_gates) g
      WHERE g->>'kind' = 'member_ratification'
    );

  -- External signers with active auth_engagement, no signoff yet on chain
  RETURN QUERY
  SELECT
    'external_signer_pending'::text AS target_type,
    m.id AS member_id,
    m.person_id,
    m.name,
    m.email,
    COALESCE(ae.role, 'external_signer')::text AS expected_gate_kind,
    v_chain_id AS chain_id,
    v_version_label AS version_label,
    GREATEST(0, EXTRACT(day FROM (now() - v_chain_opened_at))::int) AS days_since_chain_opened
  FROM public.members m
  JOIN public.auth_engagements ae ON ae.person_id = m.person_id
  WHERE m.operational_role = 'external_signer'
    AND ae.kind = 'external_signer'
    AND ae.status = 'active'
    AND ae.is_authoritative = true
    AND NOT EXISTS (
      SELECT 1 FROM public.approval_signoffs s
      WHERE s.approval_chain_id = v_chain_id AND s.signer_id = m.id
    )
    -- Gate kind matching the engagement role exists in chain config
    AND EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_chain_gates) g
      WHERE g->>'kind' = COALESCE(ae.role, 'external_signer')
    );
END;
$function$;

COMMENT ON FUNCTION public.get_ratification_reminder_targets(uuid) IS
  'Returns members (+ external signers) pending signoff on the current version of a governance document. Used by reminder cron. Auth: manage_member. Output fields: target_type, member_id, person_id, name, email, expected_gate_kind, chain_id, version_label, days_since_chain_opened.';

GRANT EXECUTE ON FUNCTION public.get_ratification_reminder_targets(uuid) TO authenticated;
