-- Phase IP-3c refinement (PM correction 2026-04-18 p33c):
-- * Chapter witnesses (pontos focais) assinam ANTES dos presidentes — aceleram "tradução" ao pres.
-- * Reusar designation chapter_liaison (já seedada: Roberto CE, Ana DF, Rogério MG, João RS)
-- * threshold=4 (um liaison por capítulo — PMI-GO sem liaison ainda; GP-as-submitter cobre)
-- * Ordem: curator → leader_awareness → submitter_acceptance → chapter_witness → president_go → president_others → member_ratification

-- ========================================
-- 1. Update _can_sign_gate chapter_witness to accept chapter_liaison
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
    WHEN 'chapter_witness' THEN
      v_member.operational_role = 'chapter_liaison'
      OR 'chapter_liaison' = ANY(v_member.designations)
    WHEN 'member_ratification' THEN
      v_member.member_status = 'active'
    WHEN 'external_signer' THEN
      v_member.operational_role = 'external_signer'
    ELSE false
  END;
END;
$$;

-- ========================================
-- 2. Reorder gates of 4 v2.2 chains — chapter_witness BEFORE presidents, threshold=4
-- ========================================
UPDATE public.approval_chains
SET gates = '[
  {"kind": "curator",              "order": 1, "threshold": 1},
  {"kind": "leader_awareness",     "order": 2, "threshold": 0},
  {"kind": "submitter_acceptance", "order": 3, "threshold": 1},
  {"kind": "chapter_witness",      "order": 4, "threshold": 4},
  {"kind": "president_go",         "order": 5, "threshold": 1},
  {"kind": "president_others",     "order": 6, "threshold": 4},
  {"kind": "member_ratification",  "order": 7, "threshold": "all"}
]'::jsonb,
updated_at = now()
WHERE id IN (
  '8b65de6c-b888-468c-892b-8249c8cf0482',
  '47f2d655-6ff2-4cb2-9fe0-97ebd8ba4532',
  '548fd268-0f08-4d90-9518-7bacdc907776'
);

UPDATE public.approval_chains
SET gates = '[
  {"kind": "curator",              "order": 1, "threshold": 1},
  {"kind": "leader_awareness",     "order": 2, "threshold": 0},
  {"kind": "submitter_acceptance", "order": 3, "threshold": 1},
  {"kind": "chapter_witness",      "order": 4, "threshold": 4},
  {"kind": "president_go",         "order": 5, "threshold": 1},
  {"kind": "president_others",     "order": 6, "threshold": 4}
]'::jsonb,
updated_at = now()
WHERE id = '8e7a70c6-f9dd-4c57-b5fa-b548ec965581';

NOTIFY pgrst, 'reload schema';
