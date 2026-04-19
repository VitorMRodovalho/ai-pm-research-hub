-- ============================================================================
-- IP-3d hotfix — RLS recursion approval_chains ↔ approval_signoffs
--
-- Sintoma (detectado em smoke 19/Abr p34): "infinite recursion detected in
-- policy for relation approval_signoffs" ao fazer SELECT direto em
-- approval_chains via PostgREST. Origem: IP-1 D6 tightening (migration
-- 20260429040000) criou policies que mutualmente se referenciam:
--   * approval_chains_read_scoped: id IN (SELECT approval_chain_id FROM approval_signoffs ...)
--   * approval_signoffs_read_scoped: approval_chain_id IN (SELECT id FROM approval_chains ...)
-- Postgres entra em loop ao resolver as policies aninhadas.
--
-- Fix: remover branches recursivas. Authorization legítima cobre via:
--   * admin (can_by_member('manage_member'))
--   * member_document_signatures do caller (member ratificado vê a chain que ratificou)
--   * governance_documents.status='active' (chains de doc ativo são publicos)
--   * signer_id = caller (signoff self-read direto)
--   * Casos edge (signer não-admin ainda não ratificou): via RPCs SECURITY
--     DEFINER (get_chain_workflow_detail, get_pending_ratifications,
--     list_document_comments). Essas RPCs bypassam RLS e retornam shapes
--     auditados já hoje.
--
-- Rollback: restaurar policies originais de IP-1 D6 — não recomendado, a
-- recursion volta. Se precisar de signer visibility direto, adicionar
-- coluna denormalizada document_id em approval_signoffs + trigger sync.
-- ============================================================================

DROP POLICY IF EXISTS approval_chains_read_scoped ON public.approval_chains;
CREATE POLICY approval_chains_read_scoped ON public.approval_chains
  FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid() AND can_by_member(m.id, 'manage_member'))
    OR document_id IN (
      SELECT mds.document_id FROM public.member_document_signatures mds
      WHERE mds.member_id IN (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid())
    )
    OR document_id IN (SELECT gd.id FROM public.governance_documents gd WHERE gd.status = 'active')
  );

DROP POLICY IF EXISTS approval_signoffs_read_scoped ON public.approval_signoffs;
CREATE POLICY approval_signoffs_read_scoped ON public.approval_signoffs
  FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid() AND can_by_member(m.id, 'manage_member'))
    OR signer_id IN (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid())
  );

COMMENT ON POLICY approval_chains_read_scoped ON public.approval_chains IS
  'IP-3d hotfix 19/Abr: removida branch id IN (SELECT FROM approval_signoffs ...) que causava recursion. Signer-only reads via RPC SECURITY DEFINER (get_chain_workflow_detail).';

COMMENT ON POLICY approval_signoffs_read_scoped ON public.approval_signoffs IS
  'IP-3d hotfix 19/Abr: removidas branches que acessavam approval_chains (mutualmente recursivas). Admin + signer-self cobrem casos diretos.';

NOTIFY pgrst, 'reload schema';
