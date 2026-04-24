-- Migration: LGPD Art. 18 self-service — get_my_signatures RPC
-- Issue: #85 Onda B residual — members should be able to self-query their signature
--        history (approval chain gates signed + document ratifications) via MCP.
-- Design: Unified view across approval_signoffs (per-gate) + member_document_signatures
--         (final doc ratification). Self-scope via auth.uid() → members.id.
-- Rollback: DROP FUNCTION public.get_my_signatures(boolean);

CREATE OR REPLACE FUNCTION public.get_my_signatures(
  p_include_superseded boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_gates jsonb;
  v_ratifications jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Gate signoffs (per-stage approvals on approval_chains)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'signoff_id', s.id,
    'chain_id', s.approval_chain_id,
    'gate_kind', s.gate_kind,
    'signoff_type', s.signoff_type,
    'signed_at', s.signed_at,
    'signature_hash', s.signature_hash,
    'sections_verified', s.sections_verified,
    'comment_body', s.comment_body,
    'document_title', d.title,
    'document_type', d.doc_type,
    'chain_status', ac.status
  ) ORDER BY s.signed_at DESC), '[]'::jsonb)
  INTO v_gates
  FROM public.approval_signoffs s
  LEFT JOIN public.approval_chains ac ON ac.id = s.approval_chain_id
  LEFT JOIN public.governance_documents d ON d.id = ac.document_id
  WHERE s.signer_id = v_caller_id;

  -- Final document ratifications (member_document_signatures)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'signature_id', ms.id,
    'document_id', ms.document_id,
    'document_title', d.title,
    'document_type', d.doc_type,
    'version_id', ms.signed_version_id,
    'signed_at', ms.signed_at,
    'is_current', ms.is_current,
    'superseded_at', ms.superseded_at,
    'superseded_by_version_id', ms.superseded_by_version_id,
    'certificate_id', ms.certificate_id
  ) ORDER BY ms.signed_at DESC), '[]'::jsonb)
  INTO v_ratifications
  FROM public.member_document_signatures ms
  LEFT JOIN public.governance_documents d ON d.id = ms.document_id
  WHERE ms.member_id = v_caller_id
    AND (p_include_superseded OR ms.is_current = true);

  RETURN jsonb_build_object(
    'gate_signoffs', v_gates,
    'document_ratifications', v_ratifications,
    'gate_count', jsonb_array_length(v_gates),
    'ratification_count', jsonb_array_length(v_ratifications)
  );
END;
$function$;

COMMENT ON FUNCTION public.get_my_signatures(boolean) IS
  'LGPD Art. 18 self-service — returns caller''s signature history (approval chain gates + document ratifications). Scoped via auth.uid().';

REVOKE ALL ON FUNCTION public.get_my_signatures(boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_signatures(boolean) TO authenticated, service_role;
