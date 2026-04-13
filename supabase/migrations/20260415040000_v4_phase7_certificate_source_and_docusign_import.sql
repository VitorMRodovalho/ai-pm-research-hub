-- ============================================================================
-- V4 Phase 7b — Certificate source tracking + DocuSign import + requires_agreement
-- ADR: ADR-0008 (Per-Kind Engagement Lifecycle)
-- Depends on: 20260415020000 (volunteer agreement engagement link)
-- Rollback: ALTER TABLE certificates DROP COLUMN IF EXISTS source;
--           DELETE FROM certificates WHERE source = 'docusign_import';
--           UPDATE engagement_kinds SET requires_agreement = false WHERE slug IN ('volunteer','study_group_owner');
-- ============================================================================

-- ═══ 1. Add source column to certificates ═══
ALTER TABLE public.certificates
ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'platform';

COMMENT ON COLUMN public.certificates.source IS
  'Origin of the certificate: platform (signed in-app), docusign_import (imported from DocuSign), admin_attestation (admin-attested external agreement)';

-- ═══ 2. Import DocuSign volunteer agreements ═══
-- 27 active volunteers who signed via DocuSign but have no platform certificate.
-- Each INSERT creates a certificate and links it to the engagement.
-- Matching: DocuSign PDF name → members.name (verified manually).

-- Helper: create cert + link engagement in one shot
CREATE OR REPLACE FUNCTION public._v4_import_docusign_cert(
  p_member_name text,
  p_signed_date date,
  p_pdf_filename text
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_member_id uuid;
  v_engagement_id uuid;
  v_cert_id uuid;
  v_role text;
BEGIN
  -- Find member
  SELECT id INTO v_member_id FROM public.members
  WHERE LOWER(name) = LOWER(p_member_name) AND is_active = true;
  IF v_member_id IS NULL THEN
    RAISE NOTICE 'SKIP: member not found: %', p_member_name;
    RETURN;
  END IF;

  -- Find active volunteer engagement
  SELECT e.id INTO v_engagement_id
  FROM public.engagements e
  JOIN public.persons p ON p.id = e.person_id
  WHERE p.legacy_member_id = v_member_id
    AND e.kind = 'volunteer' AND e.status = 'active'
    AND e.agreement_certificate_id IS NULL;
  IF v_engagement_id IS NULL THEN
    RAISE NOTICE 'SKIP: no unlinked volunteer engagement for: %', p_member_name;
    RETURN;
  END IF;

  -- Get role for certificate
  SELECT operational_role INTO v_role FROM public.members WHERE id = v_member_id;

  -- Create certificate
  v_cert_id := gen_random_uuid();
  INSERT INTO public.certificates (id, member_id, type, title, description, issued_at, function_role, status, source, verification_code)
  VALUES (
    v_cert_id,
    v_member_id,
    'volunteer_agreement',
    'Termo de Compromisso ao Voluntariado 2026',
    'Importado do DocuSign — ' || p_pdf_filename,
    p_signed_date::timestamptz,
    COALESCE(v_role, 'researcher'),
    'active',
    'docusign_import',
    'DSGN-' || SUBSTRING(v_cert_id::text, 1, 8)
  );

  -- Link to engagement
  UPDATE public.engagements SET agreement_certificate_id = v_cert_id WHERE id = v_engagement_id;

  RAISE NOTICE 'OK: % → cert % → engagement %', p_member_name, v_cert_id, v_engagement_id;
END;
$$;

-- Execute imports (27 matched volunteers)
SELECT public._v4_import_docusign_cert('Alexandre Meirelles',      '2026-02-26', 'Alexandre_Augusto_de_Castro_Meirelles_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Andressa Martins',         '2026-02-25', 'Andressa_Rodrigues_Martins_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Antonio Marcos Costa',     '2026-02-25', 'Antonio_Marcos_Moura_Costa_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Cíntia Simões De Oliveira','2026-03-20', 'Cintia_Simoes_de_Oliveira_PMI_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Denis Vasconcelos',        '2026-02-24', 'Denis_Queiroz_Vasconcelos_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Fabricia Maciel',          '2026-02-25', 'Fabricia_Aparecida_Maciel_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Fernando Maquiaveli',      '2026-02-25', 'Fernando_do_Carmo_Maquiaveli_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Gerson Albuquerque Neto',  '2026-02-25', 'Gerson_Vieira_Albuquerque_Neto_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Hayala Curto',             '2026-02-25', 'Hayala_Nepomuceno_Curto_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Italo Soares Nogueira',    '2026-02-18', 'Italo_Soares_Nogueira_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Jefferson Pinto',          '2026-03-05', 'Jefferson_Pinheiro_Pinto_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Leonardo Chaves',          '2026-02-27', 'Leonardo_Grandinetti_Chaves_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Leticia Clemente',         '2026-02-20', 'Leticia_Cristovam_Clemente_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Letícia Rodrigues Vieira', '2026-02-28', 'Leticia_Rodrigues_Vieira_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Lídia Do Vale',            '2026-02-25', 'Lidia_Rakel_Alcantara_do_Vale_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Ligia Costa',              '2026-02-25', 'Ligia_Costa_Ribeiro_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Lorena Almeida',           '2026-02-20', 'Lorena_Rodrigues_de_Almeida_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Luciana Dutra Martins',    '2026-02-18', 'Luciana_Dutra_Martins_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Marcos Antunes Klemz',     '2026-02-25', 'Marcos_Antunes_Klemz_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Mayanna Duarte',           '2026-03-06', 'Mayanna_Fernanda_Aires_Duarte_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Pedro Henrique Rodrigues Mendes', '2026-02-25', 'Pedro_Henrique_Rodrigues_Mendes_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Ricardo Santos',           '2026-02-25', 'Ricardo_Franca_Santos_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Rodrigo Grilo Gomes',      '2026-02-25', 'Rodrigo_Grilo_Gomes_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Stephania Marta De Souza', '2026-03-04', 'Stephania_Marta_de_Souza_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Thiago Freire',            '2026-02-26', 'Thiago_Ribeiro_e_Freire_assinado_assinado.pdf');
SELECT public._v4_import_docusign_cert('Vinicyus Saraiva De Sousa','2026-03-04', 'Vinicyus_Saraiva_de_Sousa_assinado_assinado.pdf');
-- Wellinghton Pereira Barboza — no DocuSign match, moved to admin attestation

-- Drop helper (one-time use)
DROP FUNCTION public._v4_import_docusign_cert(text, date, text);

-- ═══ 3. Admin attestation for remaining volunteers (PMI-CE cycle 2 + edge cases) ═══
-- These members joined under chapter rules that didn't require DocuSign.
-- PM (Vitor) attests their participation is authorized. Audit trail preserved.
-- Members: Ana Carla Cavalcante, Débora Moura, Francisco Jose, João Coelho Jr,
--          Maria Luiza, João Uzejka, Paulo Alves, Wellinghton (if DocuSign didn't match)

CREATE OR REPLACE FUNCTION public._v4_admin_attest_cert(
  p_member_name text,
  p_reason text
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_member_id uuid;
  v_engagement_id uuid;
  v_cert_id uuid;
  v_role text;
  v_pm_id uuid;
BEGIN
  -- PM member ID (Vitor)
  SELECT id INTO v_pm_id FROM public.members WHERE name ILIKE 'Vitor%Rodovalho%' LIMIT 1;

  SELECT id INTO v_member_id FROM public.members
  WHERE LOWER(name) = LOWER(p_member_name) AND is_active = true;
  IF v_member_id IS NULL THEN
    RAISE NOTICE 'SKIP: member not found: %', p_member_name;
    RETURN;
  END IF;

  SELECT e.id INTO v_engagement_id
  FROM public.engagements e
  JOIN public.persons p ON p.id = e.person_id
  WHERE p.legacy_member_id = v_member_id
    AND e.kind = 'volunteer' AND e.status = 'active'
    AND e.agreement_certificate_id IS NULL;
  IF v_engagement_id IS NULL THEN
    RAISE NOTICE 'SKIP: no unlinked volunteer engagement for: %', p_member_name;
    RETURN;
  END IF;

  SELECT operational_role INTO v_role FROM public.members WHERE id = v_member_id;

  v_cert_id := gen_random_uuid();
  INSERT INTO public.certificates (id, member_id, type, title, description, issued_at, issued_by, function_role, status, source, verification_code)
  VALUES (
    v_cert_id,
    v_member_id,
    'volunteer_agreement',
    'Termo de Compromisso ao Voluntariado 2026',
    'Admin attestation: ' || p_reason,
    NOW(),
    v_pm_id,
    COALESCE(v_role, 'researcher'),
    'active',
    'admin_attestation',
    'ATST-' || SUBSTRING(v_cert_id::text, 1, 8)
  );

  UPDATE public.engagements SET agreement_certificate_id = v_cert_id WHERE id = v_engagement_id;
  RAISE NOTICE 'OK (attestation): % → cert % → engagement %', p_member_name, v_cert_id, v_engagement_id;
END;
$$;

-- PMI-CE cycle 2 members (chapter rules didn't require DocuSign)
SELECT public._v4_admin_attest_cert('Ana Carla Cavalcante',                  'PMI-CE ciclo 2 — regra do capítulo não exigia DocuSign');
SELECT public._v4_admin_attest_cert('Débora Moura',                          'PMI-CE ciclo 2 — regra do capítulo não exigia DocuSign');
SELECT public._v4_admin_attest_cert('Francisco Jose Nascimento De Oliveira', 'PMI-CE ciclo 2 — regra do capítulo não exigia DocuSign');
SELECT public._v4_admin_attest_cert('João Coelho Júnior',                    'PMI-CE ciclo 2 — regra do capítulo não exigia DocuSign');
SELECT public._v4_admin_attest_cert('Maria Luiza',                           'PMI-CE ciclo 2 — regra do capítulo não exigia DocuSign');

-- Other chapters — joined before DocuSign was required
SELECT public._v4_admin_attest_cert('João Uzejka Dos Santos',                'PMI-RS — ingressou antes da obrigatoriedade do DocuSign');
SELECT public._v4_admin_attest_cert('Paulo Alves De Oliveira Junior',        'PMI-GO — DocuSign não localizado no arquivo');
SELECT public._v4_admin_attest_cert('Wellinghton Pereira Barboza',          'PMI-GO — DocuSign não localizado no arquivo');

DROP FUNCTION public._v4_admin_attest_cert(text, text);

-- ═══ 4. Mark existing platform certificates ═══
UPDATE public.certificates SET source = 'platform' WHERE source = 'platform' AND type = 'volunteer_agreement';

-- ═══ 5. Enable requires_agreement enforcement ═══
-- Now all active volunteers have a certificate linked. Safe to enforce.
UPDATE public.engagement_kinds
SET requires_agreement = true
WHERE slug IN ('volunteer', 'study_group_owner');

-- ═══ 6. Verification ═══
-- This should return 0 (no active volunteer without cert)
DO $$
DECLARE
  v_missing int;
BEGIN
  SELECT COUNT(*) INTO v_missing
  FROM public.engagements e
  JOIN public.engagement_kinds ek ON ek.slug = e.kind
  WHERE e.status = 'active'
    AND ek.requires_agreement = true
    AND e.agreement_certificate_id IS NULL;
  IF v_missing > 0 THEN
    RAISE EXCEPTION 'ABORT: % active engagements still missing agreement certificate!', v_missing;
  END IF;
  RAISE NOTICE 'VERIFIED: all active engagements with requires_agreement=true have certificates linked';
END;
$$;

NOTIFY pgrst, 'reload schema';
