-- p95 #120: _can_sign_gate V4 conversion (Path A híbrido)
-- ====================================================================
-- 3 V3 paths converted: leader, leader_awareness (via Path A) + external_signer (via Path B inline).
-- chapter_witness keeps partial V3 (operational_role=chapter_liaison fallback) — out of scope this PR.
--
-- Path A (leader/leader_awareness): new action sign_chain_leader + 5 seed rows scope=organization.
--   Seed covers all (kind, role) pairs that sync_operational_role_cache() maps to
--   operational_role IN ('tribe_leader', 'manager', 'deputy_manager').
--
-- Path B (external_signer): inline auth_engagements EXISTS check (kind='external_signer').
--   0 active engagements today; simpler than Path A seed for unused vocabulary.
--
-- Smoke baseline (pre-migration): leader=8, leader_awareness=8, external_signer=0.
-- Smoke must equal post-migration. Validated p95 2026-05-05: 8/8/0 preserved (same 8 names).
--
-- RISK: HIGH (5 active chains use leader_awareness gate). Rollback: restore previous
-- function body (preserved in migration history pre-2026-05-05).

-- 1. Seed engagement_kind_permissions
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description) VALUES
  ('volunteer', 'manager',         'sign_chain_leader', 'organization', 'p95 #120 V4: substitui operational_role IN (manager) em _can_sign_gate'),
  ('volunteer', 'deputy_manager',  'sign_chain_leader', 'organization', 'p95 #120 V4: substitui operational_role IN (deputy_manager)'),
  ('volunteer', 'leader',          'sign_chain_leader', 'organization', 'p95 #120 V4: substitui operational_role IN (tribe_leader)'),
  ('volunteer', 'co_gp',           'sign_chain_leader', 'organization', 'p95 #120 V4: cache mapeia co_gp→manager (sync_operational_role_cache)'),
  ('volunteer', 'comms_leader',    'sign_chain_leader', 'organization', 'p95 #120 V4: cache mapeia comms_leader→tribe_leader')
ON CONFLICT (kind, role, action) DO NOTHING;

-- 2. Refactor _can_sign_gate (signature unchanged)
CREATE OR REPLACE FUNCTION public._can_sign_gate(
  p_member_id uuid,
  p_chain_id uuid,
  p_gate_kind text,
  p_doc_type text DEFAULT NULL::text,
  p_submitter_id uuid DEFAULT NULL::uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record; v_chain record; v_doc_type text; v_submitter_id uuid;
BEGIN
  SELECT m.id, m.operational_role, m.designations, m.chapter, m.is_active,
         m.member_status, m.person_id
  INTO v_member FROM public.members m WHERE m.id = p_member_id;
  IF v_member.id IS NULL OR v_member.is_active = false THEN RETURN false; END IF;

  IF p_chain_id IS NOT NULL THEN
    SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.opened_by INTO v_chain
    FROM public.approval_chains ac WHERE ac.id = p_chain_id;
    IF v_chain.id IS NULL OR v_chain.status NOT IN ('review','approved') THEN RETURN false; END IF;
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_chain.gates) g WHERE g->>'kind' = p_gate_kind) THEN
      RETURN false;
    END IF;
    SELECT gd.doc_type INTO v_doc_type FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;
    v_submitter_id := v_chain.opened_by;
  ELSE
    IF p_doc_type IS NULL THEN RETURN false; END IF;
    v_doc_type := p_doc_type;
    v_submitter_id := p_submitter_id;
  END IF;

  RETURN CASE p_gate_kind
    WHEN 'curator' THEN 'curator' = ANY(v_member.designations)
    WHEN 'leader' THEN public.can_by_member(v_member.id, 'sign_chain_leader')
    WHEN 'leader_awareness' THEN public.can_by_member(v_member.id, 'sign_chain_leader')
    WHEN 'submitter_acceptance' THEN v_submitter_id IS NOT NULL AND v_member.id = v_submitter_id
    WHEN 'president_go' THEN
      v_member.chapter = 'PMI-GO' AND 'chapter_board' = ANY(v_member.designations)
      AND ('legal_signer' = ANY(v_member.designations)
        OR (v_doc_type = 'volunteer_term_template' AND 'voluntariado_director' = ANY(v_member.designations)))
    WHEN 'president_others' THEN
      v_member.chapter IN ('PMI-CE','PMI-DF','PMI-MG','PMI-RS')
      AND 'chapter_board' = ANY(v_member.designations)
      AND 'legal_signer' = ANY(v_member.designations)
    WHEN 'chapter_witness' THEN (
      v_member.operational_role = 'chapter_liaison'
      OR 'chapter_liaison' = ANY(v_member.designations)
      OR ('chapter_vice_president' = ANY(v_member.designations) AND NOT EXISTS (
          SELECT 1 FROM public.members m2 WHERE m2.is_active = true
            AND m2.chapter = v_member.chapter
            AND (m2.operational_role = 'chapter_liaison' OR 'chapter_liaison' = ANY(m2.designations))))
      OR ('chapter_board' = ANY(v_member.designations) AND EXISTS (
          SELECT 1 FROM public.governance_documents gd
          WHERE gd.doc_type = 'cooperation_agreement'
            AND gd.status = 'active'
            AND v_member.chapter = ANY(gd.parties)
            AND gd.signed_at IS NOT NULL
            AND gd.signed_at + interval '60 days' > now()))
    )
    WHEN 'volunteers_in_role_active' THEN
      v_member.member_status = 'active'
      AND EXISTS (SELECT 1 FROM public.engagements e
        WHERE e.person_id = v_member.person_id AND e.kind = 'volunteer'
          AND e.status = 'active'
          AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
          AND e.role IN ('researcher','leader','manager'))
    WHEN 'external_signer' THEN EXISTS (
      SELECT 1 FROM public.auth_engagements ae
      WHERE ae.person_id = v_member.person_id
        AND ae.kind = 'external_signer'
        AND ae.is_authoritative = true
    )
    WHEN 'member_ratification' THEN false
    ELSE false
  END;
END;
$function$;

COMMENT ON FUNCTION public._can_sign_gate(uuid, uuid, text, text, uuid) IS
  'p95 #120 V4: leader/leader_awareness/external_signer convertidos de operational_role (V3) para engagement-derived auth (V4). Path A híbrido: sign_chain_leader via can_by_member + 5 seed rows scope=organization (cobre engagements que sync_operational_role_cache mapeia para tribe_leader/manager/deputy_manager); external_signer via auth_engagements EXISTS inline (0 active). chapter_witness mantém V3 fallback (operational_role=chapter_liaison) — out of scope this PR.';

NOTIFY pgrst, 'reload schema';
