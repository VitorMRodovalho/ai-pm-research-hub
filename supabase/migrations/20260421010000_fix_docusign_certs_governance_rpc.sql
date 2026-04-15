-- Migration: Fix 34 DocuSign/Attestation imported certificates + update get_governance_documents RPC
-- Rollback: UPDATE certificates SET status='active', template_id=NULL, period_start=NULL, period_end=NULL, cycle=NULL, content_snapshot=NULL, signature_hash=NULL WHERE type='volunteer_agreement' AND verification_code LIKE 'DSGN-%' OR verification_code LIKE 'ATST-%';
--           Then re-create the old get_governance_documents RPC (active-only filter, no content field)

-- ============================================================
-- WS1: Fix 34 imported volunteer agreement certificates
-- ============================================================

-- 1. Set template_id, period, cycle, status for all 34 imported certs
UPDATE certificates
SET
  status = 'issued',
  template_id = 'a78311fd-cf87-4bee-b0f1-e117a36095c5',  -- R3-C3 active template
  period_start = '2026-01-20',
  period_end = '2026-12-19',
  cycle = 2026,
  updated_at = now()
WHERE type = 'volunteer_agreement'
  AND status = 'active'
  AND (verification_code LIKE 'DSGN-%' OR verification_code LIKE 'ATST-%');

-- 2. Populate content_snapshot from member data + chapter_registry
UPDATE certificates c
SET
  content_snapshot = jsonb_build_object(
    'member_name', m.name,
    'member_email', m.email,
    'member_chapter', m.chapter,
    'member_pmi_id', m.pmi_id,
    'member_phone', m.phone,
    'member_address', m.address,
    'member_city', m.city,
    'member_state', m.state,
    'member_country', m.country,
    'member_birth_date', m.birth_date,
    'chapter_cnpj', cr.cnpj,
    'chapter_name', cr.legal_name,
    'signed_via', CASE WHEN c.verification_code LIKE 'DSGN-%' THEN 'docusign' ELSE 'attestation' END,
    'template_version', 'R3-C3',
    'signed_at', c.issued_at
  ),
  signature_hash = encode(
    sha256(
      convert_to(
        m.name || '|' || m.email || '|' || COALESCE(m.chapter,'') || '|' || c.issued_at::text,
        'UTF8'
      )
    ),
    'hex'
  )
FROM members m
LEFT JOIN chapter_registry cr ON cr.chapter_code = REPLACE(m.chapter, 'PMI-', '')
WHERE c.member_id = m.id
  AND c.type = 'volunteer_agreement'
  AND c.content_snapshot IS NULL
  AND (c.verification_code LIKE 'DSGN-%' OR c.verification_code LIKE 'ATST-%');

-- ============================================================
-- WS2: Update get_governance_documents RPC
-- Show draft docs to GP (manager/deputy_manager/superadmin)
-- Add content field to response
-- ============================================================

CREATE OR REPLACE FUNCTION get_governance_documents(p_doc_type text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE v_caller record; v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'id', gd.id,
    'doc_type', gd.doc_type,
    'title', gd.title,
    'description', gd.description,
    'content', gd.content,
    'version', gd.version,
    'parties', gd.parties,
    'docusign_envelope_id', gd.docusign_envelope_id,
    'signed_at', gd.signed_at,
    'status', gd.status,
    'valid_from', gd.valid_from,
    'exit_notice_days', gd.exit_notice_days,
    'signatories', CASE
      WHEN v_caller.is_superadmin OR v_caller.operational_role IN ('manager', 'sponsor', 'chapter_liaison')
      THEN gd.signatories ELSE NULL
    END
  ) ORDER BY gd.status ASC, gd.signed_at DESC) INTO v_result
  FROM governance_documents gd
  WHERE (p_doc_type IS NULL OR gd.doc_type = p_doc_type)
    AND (
      gd.status = 'active'
      OR (gd.status = 'draft' AND (v_caller.is_superadmin OR v_caller.operational_role IN ('manager', 'deputy_manager')))
    );

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;
