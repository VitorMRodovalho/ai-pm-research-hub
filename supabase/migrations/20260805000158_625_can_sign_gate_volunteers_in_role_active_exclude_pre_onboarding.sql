-- =====================================================================================
-- #625 (sweep de coorte / Passo 3 do épico #660) — coorte `volunteers_in_role_active` do gate de
-- ratificação deixa de contar a coorte pré-onboarding.
--
-- Bug (aterrado 2026-06-12): o ramo `volunteers_in_role_active` de _can_sign_gate exige
--   member_status='active' AND engagement volunteer ativo (researcher/leader/manager) — MAS um
--   membro pré-onboarding TEM esse engagement ativo (só falta o termo). O denominador 'all' do gate
--   (_gate_threshold_met: count(*) FROM members WHERE is_active AND _can_sign_gate(...)) então conta
--   23 pré-onboarding como signatários OBRIGATÓRIOS → o gate "todos ratificam" do termo/adendo nunca
--   fecharia, pois eles teriam de ratificar o PRÓPRIO termo que ainda não assinaram. Defeito circular,
--   mesma família do #654 (que tornou _can_sign_gate puro / denominador 'all').
--
-- Fix (audience-scoping, dentro do predicado — não ordering-aware, ≠ guarda de ordem do #654):
--   AND NOT public.member_is_pre_onboarding(v_member.person_id, v_member.member_status) no ramo
--   `volunteers_in_role_active`. Mantém denominador E autorização de assinatura consistentes: um
--   pré-onboarding nem conta no denominador nem pode assinar (correto — ele aceita o termo VIGENTE no
--   onboarding, não ratifica a nova versão como voluntário-em-papel). Demais ramos INALTERADOS.
--
-- Antes→depois (live 2026-06-12, pré-apply): denominador volunteers_in_role_active das 2 chains em
--   review — volunteer_term_template (d72916d7) 55 → 32 · volunteer_addendum (1c593d54) 55 → 32.
--
-- Reproduz a função INTEIRA verbatim da captura anterior (#666, mig 20260805000156) com 1 delta
--   marcado `-- #625`; os comentários inline pré-existentes (-- #666 / -- p200 / -- ADR-0016) são
--   reproduzidos byte-fiéis p/ não driftar o body-hash. CREATE OR REPLACE (preserva ACL; REVOKE/GRANT
--   explícitos p/ apply fresco). Predicado compartilhado read/write/threshold.
--
-- ⚠️ Invalidação de cache (ADR-0016 Amendment 3): preview_gate_eligibles_cache é trigger-mantido em
--   mudanças de DADOS, NÃO em mudança de SEMÂNTICA do _can_sign_gate. volunteers_in_role_active é gate
--   de doc_types CACHEABLE (volunteer_term_template + volunteer_addendum) → o cache fica stale (55) vs
--   live (32) sem um rebuild explícito. refresh_preview_gate_eligibles_cache_all() ao final fecha a
--   janela (no replay e na auditoria de equivalência). (#666 não precisou: o gate 'leader' só existe em
--   project_charter, que não é cacheable.)
-- ROLLBACK: restaurar a captura de _can_sign_gate da mig 20260805000156 / git + refrescar o cache.
-- =====================================================================================
CREATE OR REPLACE FUNCTION public._can_sign_gate(p_member_id uuid, p_chain_id uuid, p_gate_kind text, p_doc_type text DEFAULT NULL::text, p_submitter_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record; v_chain record; v_doc_type text; v_submitter_id uuid;
  v_doc_initiative_id uuid;  -- #666: scope the 'leader' gate to the doc's initiative leader
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
    -- #666: also resolve the doc's initiative (for the 'leader' scope below).
    SELECT gd.doc_type, gd.initiative_id INTO v_doc_type, v_doc_initiative_id
    FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;
    v_submitter_id := v_chain.opened_by;
  ELSE
    IF p_doc_type IS NULL THEN RETURN false; END IF;
    v_doc_type := p_doc_type;
    v_submitter_id := p_submitter_id;
  END IF;

  RETURN CASE p_gate_kind
    -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
    WHEN 'curator' THEN public.can_by_member(v_member.id, 'curate_content')
    -- #666: 'leader' = leader OF THE DOCUMENT'S INITIATIVE (not any sign_chain_leader). The chain
    -- path resolves v_doc_initiative_id; non-initiative org docs (policy/cooperation/volunteer_term,
    -- which legitimately have no initiative) fall back to the bare capability (back-compat). A
    -- project_charter MUST be initiative-scoped, so a charter with a missing initiative link fails
    -- CLOSED here (security review #666 F1) — never "any leader". `leader_awareness` stays broad.
    WHEN 'leader' THEN
      public.can_by_member(v_member.id, 'sign_chain_leader')
      AND (
        (v_doc_initiative_id IS NULL AND v_doc_type IS DISTINCT FROM 'project_charter')
        OR EXISTS (SELECT 1 FROM public.v_initiative_roster r
                   WHERE r.initiative_id = v_doc_initiative_id
                     AND r.member_id = v_member.id
                     AND r.role = 'leader')
      )
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
    -- ADR-0016 Amendment 4: Diretoria de Certificação do capítulo sede (PMI-GO) valida
    -- charters do tema certificação antes da assinatura presidencial. Predicado mínimo
    -- por designação de diretoria (sem chapter_board/legal_signer — validação programática
    -- interna, não contra-assinatura jurídica). doc_type-scoped (defense-in-depth).
    WHEN 'cert_director_go' THEN
      v_member.chapter = 'PMI-GO'
      AND 'certificacao_director' = ANY(v_member.designations)
      AND (v_doc_type IS NULL OR v_doc_type = 'project_charter')
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
    -- #625: um voluntário pré-onboarding (active, mas com engagements ativos ainda pendentes do termo)
    -- NÃO é ainda "volunteer in role active" — contá-lo no denominador 'all' da ratificação é o defeito
    -- circular da família #654 (ele teria de ratificar o próprio termo que ainda não assinou). Exclui
    -- via o helper canônico C0 (mig 20260805000143).
    WHEN 'volunteers_in_role_active' THEN
      v_member.member_status = 'active'
      AND NOT public.member_is_pre_onboarding(v_member.person_id, v_member.member_status)
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

-- Preserve hardened ACL (CREATE OR REPLACE keeps it; explicit for a fresh apply).
REVOKE ALL ON FUNCTION public._can_sign_gate(uuid, uuid, text, text, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public._can_sign_gate(uuid, uuid, text, text, uuid) TO authenticated, service_role;

-- #625: rebuild the hybrid eligibles cache (semantic change above) so preview_gate_eligibles_cache
-- matches live _can_sign_gate for the cacheable volunteer_term_template/volunteer_addendum gates.
-- The public refresh_preview_gate_eligibles_cache_all() is auth.uid()-gated (manage_platform) and
-- would RAISE 'Not authenticated' on a migration replay (no JWT) — so we run the SAME unguarded loop
-- it wraps (PERFORM _refresh_preview_gate_eligibles_for_member per active member + orphan sweep).
DO $cache$
DECLARE r record;
BEGIN
  FOR r IN SELECT m.id FROM public.members m WHERE m.is_active = true LOOP
    PERFORM public._refresh_preview_gate_eligibles_for_member(r.id);
  END LOOP;
  DELETE FROM public.preview_gate_eligibles_cache c
  WHERE NOT EXISTS (SELECT 1 FROM public.members m WHERE m.id = c.member_id AND m.is_active = true);
END
$cache$;

NOTIFY pgrst, 'reload schema';
