-- ============================================================================
-- GHSA-gh3r-fhjr-cr8w (2) — o ramo "quem assina le o que assina" abria o RASCUNHO
-- ============================================================================
--
-- WHAT: em _can_read_governance_version, o ramo de quem abriu, assinou ou pode assinar cadeia
--   aberta do documento passa a exigir que a versao pedida seja a DA CADEIA ou ja travada.
-- WHY: a condicao amarrava so o documento. Medido em 23/09/2026, depois de 20260923211446:
--   um pesquisador ativo sem capacidade de revisao recebia de get_next_draft_version o rascunho
--   inteiro de um documento cuja cadeia aberta tem portao volunteers_in_role_active; no controle,
--   documento sem cadeia aberta, recebia exists=false. O comentario dizia "le o que assina"; a
--   condicao dizia "le tudo do documento". Rascunho volta a depender so de revisao, curadoria ou
--   autoria, como no draft preview.
-- ROLLBACK: reaplicar o helper de 20260923211446 (reabre o furo; nao fazer).
-- ============================================================================

CREATE OR REPLACE FUNCTION public._can_read_governance_version(p_version_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_member uuid;
  v_ver record;
  v_doc record;
BEGIN
  -- service_role ja le as tabelas direto; o portao existe para contas de pessoa.
  IF auth.role() = 'service_role' THEN
    RETURN true;
  END IF;

  -- Membro ativo. Conta autenticada sem cadastro (fantasma) e anon nao leem nada.
  SELECT m.id INTO v_member
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true
  LIMIT 1;
  IF v_member IS NULL THEN
    RETURN false;
  END IF;

  SELECT dv.id, dv.document_id, dv.locked_at, dv.authored_by INTO v_ver
  FROM public.document_versions dv WHERE dv.id = p_version_id;
  IF v_ver.id IS NULL THEN
    RETURN false;
  END IF;

  SELECT gd.id, gd.visibility_class INTO v_doc
  FROM public.governance_documents gd WHERE gd.id = v_ver.document_id;
  IF v_doc.id IS NULL THEN
    RETURN false;
  END IF;

  -- audit_restricted: so manage_platform, como no leitor (manage_member NAO basta).
  IF v_doc.visibility_class = 'audit_restricted' THEN
    RETURN public.can_by_member(v_member, 'manage_platform');
  END IF;

  IF public.can_by_member(v_member, 'manage_member') THEN
    RETURN true;
  END IF;

  -- Quem abriu, assinou ou pode assinar uma cadeia ABERTA do documento le o que assina,
  -- inclusive em documento legal_scoped: a versao DA CADEIA, ou versao ja travada (o diff contra
  -- as anteriores). NUNCA rascunho por este ramo: sem a amarra de versao, o portao aberto a
  -- voluntarios de uma cadeia qualquer abria o rascunho do documento para quase todo membro.
  IF EXISTS (
    SELECT 1 FROM public.approval_chains ac
    WHERE ac.document_id = v_doc.id AND ac.closed_at IS NULL
      AND (ac.version_id = v_ver.id OR v_ver.locked_at IS NOT NULL)
      AND (
        ac.opened_by = v_member
        OR EXISTS (SELECT 1 FROM public.approval_signoffs s
                   WHERE s.approval_chain_id = ac.id AND s.signer_id = v_member)
        OR EXISTS (SELECT 1 FROM jsonb_array_elements(ac.gates) g
                   WHERE public._can_sign_gate(v_member, ac.id, g->>'kind'))
      )
  ) THEN
    RETURN true;
  END IF;

  IF v_doc.visibility_class = 'admin_only' THEN
    RETURN false;
  END IF;

  IF v_doc.visibility_class = 'legal_scoped' THEN
    RETURN EXISTS (SELECT 1 FROM public.member_document_signatures mds
                   WHERE mds.member_id = v_member AND mds.document_id = v_doc.id AND mds.is_current = true);
  END IF;

  -- public / active_members: versao travada e de todo membro ativo (espelho do leitor).
  IF v_ver.locked_at IS NOT NULL THEN
    RETURN true;
  END IF;

  -- Rascunho: espelho do draft preview (revisao de governanca, curadoria ou autoria).
  RETURN v_ver.authored_by = v_member
      OR public.can_by_member(v_member, 'participate_in_governance_review')
      OR public.can_by_member(v_member, 'curate_content');
END;
$fn$;

REVOKE ALL ON FUNCTION public._can_read_governance_version(uuid) FROM PUBLIC, anon, authenticated;
