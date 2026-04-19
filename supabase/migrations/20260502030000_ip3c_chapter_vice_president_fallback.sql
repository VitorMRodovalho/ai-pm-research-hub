-- Phase IP-3c refinement (PM correction 2026-04-18 p33d):
-- * PMI-GO não tem chapter_liaison registrado (Ivan-presidente se envolve direto com o Núcleo).
-- * Regra travada: quando chapter NÃO tem chapter_liaison, vice-presidente do capítulo
--   atua como PREPOSTO de testemunha para governance_documents.
-- * Seed Emanuele Melo (VP PMI-GO) — email vice-presidencia@pmigo.org.br — como member ativo
--   com designation 'chapter_vice_president'. PII complementar (linkedin/phone/photo)
--   via UI admin — não neste migration.
-- * Seed engagements (chapter_board + observer) para satisfazer invariante A3.
-- * Aplica só quando ausência verificada de chapter_liaison no mesmo chapter.

-- ========================================
-- 1. Seed person + member Emanuela (VP PMI-GO)
-- ========================================
DO $$
DECLARE
  v_pmigo_org uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
  v_person_id uuid;
  v_existing_member uuid;
  v_member_id uuid;
BEGIN
  SELECT id INTO v_existing_member FROM public.members WHERE email = 'vice-presidencia@pmigo.org.br';

  IF v_existing_member IS NOT NULL THEN
    UPDATE public.members
    SET designations = array_append(
      CASE WHEN 'chapter_board' = ANY(designations) THEN designations
           ELSE array_append(designations, 'chapter_board'::text) END,
      'chapter_vice_president'::text
    )
    WHERE id = v_existing_member
      AND NOT ('chapter_vice_president' = ANY(designations));
    v_member_id := v_existing_member;
  ELSE
    INSERT INTO public.persons (organization_id, name, email)
    VALUES (v_pmigo_org, 'Emanuele Melo', 'vice-presidencia@pmigo.org.br')
    RETURNING id INTO v_person_id;

    INSERT INTO public.members (
      organization_id, person_id, auth_id, name, email, chapter,
      operational_role, member_status, is_active, designations
    ) VALUES (
      v_pmigo_org, v_person_id, NULL,
      'Emanuele Melo',
      'vice-presidencia@pmigo.org.br',
      'PMI-GO',
      'observer',
      'active',
      true,
      ARRAY['chapter_board', 'chapter_vice_president']::text[]
    )
    RETURNING id INTO v_member_id;
  END IF;

  -- Seed engagements to satisfy invariant A3 (match Lorena/Emanoela pattern)
  IF v_person_id IS NULL THEN
    SELECT person_id INTO v_person_id FROM public.members WHERE id = v_member_id;
  END IF;

  INSERT INTO public.engagements (person_id, organization_id, kind, role, status, start_date)
  SELECT v_person_id, v_pmigo_org, 'chapter_board', 'board_member', 'active', CURRENT_DATE
  WHERE NOT EXISTS (SELECT 1 FROM public.engagements
    WHERE person_id = v_person_id AND kind = 'chapter_board' AND status = 'active');

  INSERT INTO public.engagements (person_id, organization_id, kind, role, status, start_date)
  SELECT v_person_id, v_pmigo_org, 'observer', 'observer', 'active', CURRENT_DATE
  WHERE NOT EXISTS (SELECT 1 FROM public.engagements
    WHERE person_id = v_person_id AND kind = 'observer' AND status = 'active');
END $$;

-- ========================================
-- 2. Update _can_sign_gate: chapter_witness fallback to chapter_vice_president when chapter has no liaison
-- ========================================
DROP FUNCTION IF EXISTS public._can_sign_gate(uuid, uuid, text);
CREATE OR REPLACE FUNCTION public._can_sign_gate(
  p_member_id uuid,
  p_chain_id uuid,
  p_gate_kind text
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member record;
  v_chain record;
  v_doc_type text;
BEGIN
  SELECT m.id, m.operational_role, m.designations, m.chapter, m.is_active, m.member_status
  INTO v_member FROM public.members m WHERE m.id = p_member_id;
  IF v_member.id IS NULL OR v_member.is_active = false THEN RETURN false; END IF;

  SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.opened_by INTO v_chain
  FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL OR v_chain.status NOT IN ('review','approved') THEN RETURN false; END IF;

  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_chain.gates) g WHERE g->>'kind' = p_gate_kind) THEN
    RETURN false;
  END IF;

  SELECT gd.doc_type INTO v_doc_type
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  RETURN CASE p_gate_kind
    WHEN 'curator' THEN 'curator' = ANY(v_member.designations)
    WHEN 'leader' THEN v_member.operational_role IN ('tribe_leader','manager','deputy_manager')
    WHEN 'leader_awareness' THEN
      v_member.operational_role IN ('tribe_leader','manager','deputy_manager')
      OR 'founder' = ANY(v_member.designations)
    WHEN 'submitter_acceptance' THEN
      v_chain.opened_by IS NOT NULL AND v_member.id = v_chain.opened_by
    WHEN 'president_go' THEN
      v_member.chapter = 'PMI-GO'
      AND 'chapter_board' = ANY(v_member.designations)
      AND (
        'legal_signer' = ANY(v_member.designations)
        OR (v_doc_type = 'volunteer_term_template' AND 'voluntariado_director' = ANY(v_member.designations))
      )
    WHEN 'president_others' THEN
      v_member.chapter IN ('PMI-CE','PMI-DF','PMI-MG','PMI-RS')
      AND 'chapter_board' = ANY(v_member.designations)
      AND 'legal_signer' = ANY(v_member.designations)
    WHEN 'chapter_witness' THEN (
      v_member.operational_role = 'chapter_liaison'
      OR 'chapter_liaison' = ANY(v_member.designations)
      OR (
        'chapter_vice_president' = ANY(v_member.designations)
        AND NOT EXISTS (
          SELECT 1 FROM public.members m2
          WHERE m2.is_active = true
            AND m2.chapter = v_member.chapter
            AND (m2.operational_role = 'chapter_liaison' OR 'chapter_liaison' = ANY(m2.designations))
        )
      )
    )
    WHEN 'member_ratification' THEN
      v_member.member_status = 'active'
    WHEN 'external_signer' THEN
      v_member.operational_role = 'external_signer'
    ELSE false
  END;
END;
$$;

NOTIFY pgrst, 'reload schema';
