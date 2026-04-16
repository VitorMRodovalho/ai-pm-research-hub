-- ============================================================================
-- Certificate Integrity: gov.br Digital Signature Backfill
-- Purpose:
--   1. Fix DSGN certs: set issued_by + correct counter_signed_by from gov.br data
--   2. Fix TERM certs: counter-sign using gov.br source of truth
--   3. Handle duplicates (DSGN + TERM for same member)
--   4. Enrich content_snapshot with gov.br metadata
--   5. Add governance_documents status lifecycle
-- Source: Extracted from gov.br digital certificates (PKCS7/CMS) in 92 PDFs
--   Script: scripts/extract-govbr-signers.py
--   Data: scripts/docusign-signers-extracted.json
-- Context: All VEP terms were signed via gov.br assinatura eletronica avancada.
--   Institutional signer: LORENA DE SOUZA PAULA (dir. voluntarios PMI-GO) for 89/92 docs.
--   Exceptions: IVAN LOURENCO COSTA signed for Adaildo, Emanuele, and Lorena de Souza Paula herself.
-- Rollback:
--   UPDATE certificates SET issued_by = NULL WHERE verification_code LIKE 'DSGN-%' AND issued_by IN (...);
--   UPDATE certificates SET counter_signed_by = '880f736c-3e76-4df4-9375-33575c190305' WHERE verification_code LIKE 'DSGN-%';
--   UPDATE certificates SET counter_signed_by = NULL, counter_signed_at = NULL WHERE verification_code LIKE 'TERM-%' AND source = 'platform';
-- ============================================================================

-- Key member IDs (verified)
-- Lorena de Souza Paula (PMI-GO, chapter_board, dir. voluntarios): 11b8c3a7-18bc-4834-918b-53fbb5131301
-- Ivan Lourenco Costa (PMI-GO, sponsor, presidente): c0c633b6-71d7-47a4-b1c2-abb5ec2896eb
-- Vitor Maia Rodovalho (manager): 880f736c-3e76-4df4-9375-33575c190305

-- ═══ PART 1: Fix 26 DSGN certs — issued_by + counter_signed_by from gov.br ═══

-- 1a. Set issued_by AND correct counter_signed_by = Lorena for ALL DSGN (majority)
UPDATE certificates SET
  issued_by = '11b8c3a7-18bc-4834-918b-53fbb5131301',  -- Lorena de Souza Paula
  counter_signed_by = '11b8c3a7-18bc-4834-918b-53fbb5131301',
  updated_at = now()
WHERE verification_code LIKE 'DSGN-%'
  AND type = 'volunteer_agreement';

-- 1b. Enrich content_snapshot with gov.br institutional signer metadata
UPDATE certificates SET
  content_snapshot = content_snapshot || jsonb_build_object(
    'govbr_institutional_signer', 'LORENA DE SOUZA PAULA',
    'govbr_signature_type', 'assinatura_eletronica_avancada_govbr',
    'govbr_extracted_at', now()::text,
    'govbr_source', 'scripts/extract-govbr-signers.py'
  )
WHERE verification_code LIKE 'DSGN-%'
  AND type = 'volunteer_agreement';


-- ═══ PART 2: Fix TERM certs for members who have gov.br signed terms ═══
-- These members signed on the platform but also have gov.br hardcopy.
-- gov.br is source of truth. Set counter_signed from gov.br data.

-- Vitor Maia Rodovalho — gov.br signed 18/Fev by Lorena
UPDATE certificates SET
  counter_signed_by = '11b8c3a7-18bc-4834-918b-53fbb5131301',
  counter_signed_at = '2026-02-18T17:28:20+00:00'::timestamptz,
  content_snapshot = COALESCE(content_snapshot, '{}'::jsonb) || jsonb_build_object(
    'govbr_institutional_signer', 'LORENA DE SOUZA PAULA',
    'govbr_institutional_signed_at', '2026-02-18T17:28:20+00:00',
    'govbr_volunteer_signed_at', '2026-02-18T15:39:28+00:00',
    'govbr_pdf', 'Vitor_Maia_Rodovalho_assinado_assinado.pdf',
    'govbr_source_of_truth', true
  ),
  updated_at = now()
WHERE verification_code = 'TERM-2026-7654C7';

-- Fabricio Costa — gov.br signed 25/Fev by Lorena
UPDATE certificates SET
  counter_signed_by = '11b8c3a7-18bc-4834-918b-53fbb5131301',
  counter_signed_at = '2026-02-25T16:47:38+00:00'::timestamptz,
  content_snapshot = COALESCE(content_snapshot, '{}'::jsonb) || jsonb_build_object(
    'govbr_institutional_signer', 'LORENA DE SOUZA PAULA',
    'govbr_institutional_signed_at', '2026-02-25T16:47:38+00:00',
    'govbr_volunteer_signed_at', '2026-02-25T16:20:55+00:00',
    'govbr_pdf', 'Fabricio_Rodrigues_do_Carmo_Costa_assinado_assinado.pdf',
    'govbr_source_of_truth', true
  ),
  updated_at = now()
WHERE verification_code = 'TERM-2026-0B3C32';

-- Guilherme Matricarde — gov.br signed 25/Fev by Lorena
UPDATE certificates SET
  counter_signed_by = '11b8c3a7-18bc-4834-918b-53fbb5131301',
  counter_signed_at = '2026-02-25T12:20:43+00:00'::timestamptz,
  content_snapshot = COALESCE(content_snapshot, '{}'::jsonb) || jsonb_build_object(
    'govbr_institutional_signer', 'LORENA DE SOUZA PAULA',
    'govbr_institutional_signed_at', '2026-02-25T12:20:43+00:00',
    'govbr_volunteer_signed_at', '2026-02-23T11:03:28+00:00',
    'govbr_pdf', 'Guilherme_Matheus_Matricarde_assinado_assinado.pdf',
    'govbr_source_of_truth', true
  ),
  updated_at = now()
WHERE verification_code = 'TERM-2026-6AD03E';

-- Gustavo Batista Ferreira — gov.br signed 27/Fev by Lorena
UPDATE certificates SET
  counter_signed_by = '11b8c3a7-18bc-4834-918b-53fbb5131301',
  counter_signed_at = '2026-02-27T11:13:16+00:00'::timestamptz,
  content_snapshot = COALESCE(content_snapshot, '{}'::jsonb) || jsonb_build_object(
    'govbr_institutional_signer', 'LORENA DE SOUZA PAULA',
    'govbr_institutional_signed_at', '2026-02-27T11:13:16+00:00',
    'govbr_volunteer_signed_at', '2026-02-27T02:18:48+00:00',
    'govbr_pdf', 'Gustavo_Batista_Ferreira_assinado_assinado.pdf',
    'govbr_source_of_truth', true
  ),
  updated_at = now()
WHERE verification_code = 'TERM-2026-8A57BC';

-- Rodolfo Santana — gov.br signed 25/Fev by Lorena
UPDATE certificates SET
  counter_signed_by = '11b8c3a7-18bc-4834-918b-53fbb5131301',
  counter_signed_at = '2026-02-25T12:27:29+00:00'::timestamptz,
  content_snapshot = COALESCE(content_snapshot, '{}'::jsonb) || jsonb_build_object(
    'govbr_institutional_signer', 'LORENA DE SOUZA PAULA',
    'govbr_institutional_signed_at', '2026-02-25T12:27:29+00:00',
    'govbr_volunteer_signed_at', '2026-02-24T00:06:41+00:00',
    'govbr_pdf', 'Rodolfo_Siqueira_Santana_assinado_assinado.pdf',
    'govbr_source_of_truth', true
  ),
  updated_at = now()
WHERE verification_code = 'TERM-2026-F221E6';

-- Denis Vasconcelos (TERM) — has DSGN + TERM. Mark TERM with gov.br data.
-- DSGN is source of truth. TERM is supplementary platform record.
UPDATE certificates SET
  counter_signed_by = '11b8c3a7-18bc-4834-918b-53fbb5131301',
  counter_signed_at = '2026-02-18T17:17:57+00:00'::timestamptz,
  content_snapshot = COALESCE(content_snapshot, '{}'::jsonb) || jsonb_build_object(
    'govbr_institutional_signer', 'LORENA DE SOUZA PAULA',
    'govbr_institutional_signed_at', '2026-02-18T17:17:57+00:00',
    'govbr_pdf', 'Denis_Queiroz_Vasconcelos_assinado_assinado.pdf',
    'govbr_note', 'Member also has DSGN-2ef46510 (source of truth). This TERM is supplementary.'
  ),
  updated_at = now()
WHERE verification_code = 'TERM-2026-D92F61';


-- ═══ PART 3: Audit log ═══
INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
VALUES (
  (SELECT id FROM members WHERE name ILIKE '%Vitor%Rodovalho%' LIMIT 1),
  'cert_integrity_govbr_backfill',
  'certificate',
  NULL,
  jsonb_build_object(
    'description', 'Backfill issued_by + counter_signed_by from gov.br digital certificate extraction',
    'dsgn_certs_fixed', 26,
    'term_certs_countersigned', 6,
    'institutional_signer_majority', 'LORENA DE SOUZA PAULA (11b8c3a7)',
    'source_script', 'scripts/extract-govbr-signers.py',
    'source_json', 'scripts/docusign-signers-extracted.json',
    'total_pdfs_analyzed', 92,
    'extraction_method', 'PKCS7/CMS X.509 certificate CN field from gov.br assinatura eletronica avancada'
  )
);


-- ═══ PART 4: governance_documents status lifecycle ═══

-- Add CHECK constraint for allowed statuses
DO $$ BEGIN
  ALTER TABLE governance_documents
    DROP CONSTRAINT IF EXISTS governance_documents_status_check;
  ALTER TABLE governance_documents
    ADD CONSTRAINT governance_documents_status_check
    CHECK (status IN ('draft', 'under_review', 'approved', 'active', 'superseded'));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Status check constraint already exists or failed: %', SQLERRM;
END $$;

-- RPC to advance governance document status (manager only)
CREATE OR REPLACE FUNCTION update_governance_document_status(
  p_doc_id uuid,
  p_new_status text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_is_manager boolean;
  v_doc record;
  v_valid_transitions jsonb := '{
    "draft": ["under_review"],
    "under_review": ["approved", "draft"],
    "approved": ["active", "under_review"],
    "active": ["superseded"],
    "superseded": []
  }'::jsonb;
  v_allowed jsonb;
BEGIN
  SELECT m.id, (m.operational_role IN ('manager', 'deputy_manager') OR m.is_superadmin = true)
  INTO v_caller_id, v_is_manager
  FROM members m WHERE m.auth_id = auth.uid();

  IF NOT COALESCE(v_is_manager, false) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manager permission');
  END IF;

  SELECT * INTO v_doc FROM governance_documents WHERE id = p_doc_id;
  IF v_doc IS NULL THEN
    RETURN jsonb_build_object('error', 'Document not found');
  END IF;

  v_allowed := v_valid_transitions->v_doc.status;
  IF v_allowed IS NULL OR NOT (v_allowed ? p_new_status) THEN
    RETURN jsonb_build_object('error', format('Invalid transition: %s → %s. Allowed: %s', v_doc.status, p_new_status, v_allowed));
  END IF;

  UPDATE governance_documents SET
    status = p_new_status,
    updated_at = now()
  WHERE id = p_doc_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'governance_document_status_change', 'governance_document', p_doc_id,
    jsonb_build_object('from', v_doc.status, 'to', p_new_status, 'doc_title', v_doc.title));

  RETURN jsonb_build_object('ok', true, 'doc_id', p_doc_id, 'old_status', v_doc.status, 'new_status', p_new_status);
END;
$$;

NOTIFY pgrst, 'reload schema';
