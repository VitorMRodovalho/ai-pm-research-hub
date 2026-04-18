-- ============================================================================
-- Migration: Phase IP-2 A.3 — tighten approval_chains/approval_signoffs SELECT RLS
-- ADR-0016 D6: remove USING (true); scope to admin + signer self + ratificador + active docs
-- Rollback:
--   DROP POLICY approval_chains_read_scoped ON public.approval_chains;
--   DROP POLICY approval_signoffs_read_scoped ON public.approval_signoffs;
--   CREATE POLICY approval_chains_read_all_auth ON public.approval_chains FOR SELECT TO authenticated USING (true);
--   CREATE POLICY approval_signoffs_read_all_auth ON public.approval_signoffs FOR SELECT TO authenticated USING (true);
-- ============================================================================

-- ---------------------------------------------------------------------------
-- approval_chains: scope SELECT to relevant users.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS approval_chains_read_all_auth ON public.approval_chains;
DROP POLICY IF EXISTS approval_chains_read_scoped ON public.approval_chains;

CREATE POLICY approval_chains_read_scoped ON public.approval_chains
  FOR SELECT TO authenticated
  USING (
    -- admin: full visibility for audit
    EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid()
            AND public.can_by_member(m.id, 'manage_member'))
    -- signatário: chains onde o caller registrou signoff
    OR id IN (
      SELECT approval_chain_id FROM public.approval_signoffs
      WHERE signer_id IN (SELECT id FROM public.members WHERE auth_id = auth.uid())
    )
    -- ratificador: chains de docs onde o caller tem member_document_signatures
    OR document_id IN (
      SELECT document_id FROM public.member_document_signatures
      WHERE member_id IN (SELECT id FROM public.members WHERE auth_id = auth.uid())
    )
    -- documentos ativos: visibilidade universal (post-ratificação)
    OR document_id IN (
      SELECT id FROM public.governance_documents WHERE status = 'active'
    )
  );

-- ---------------------------------------------------------------------------
-- approval_signoffs: mirror visibility logic — if chain is visible, signoffs are.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS approval_signoffs_read_all_auth ON public.approval_signoffs;
DROP POLICY IF EXISTS approval_signoffs_read_scoped ON public.approval_signoffs;

CREATE POLICY approval_signoffs_read_scoped ON public.approval_signoffs
  FOR SELECT TO authenticated
  USING (
    -- admin
    EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid()
            AND public.can_by_member(m.id, 'manage_member'))
    -- self signoffs
    OR signer_id IN (SELECT id FROM public.members WHERE auth_id = auth.uid())
    -- chain onde o caller assinou (peer visibility dentro da mesma chain)
    OR approval_chain_id IN (
      SELECT approval_chain_id FROM public.approval_signoffs s2
      WHERE s2.signer_id IN (SELECT id FROM public.members WHERE auth_id = auth.uid())
    )
    -- chain de doc onde o caller ratificou
    OR approval_chain_id IN (
      SELECT id FROM public.approval_chains
      WHERE document_id IN (
        SELECT document_id FROM public.member_document_signatures
        WHERE member_id IN (SELECT id FROM public.members WHERE auth_id = auth.uid())
      )
    )
    -- chain de documento ativo
    OR approval_chain_id IN (
      SELECT id FROM public.approval_chains
      WHERE document_id IN (SELECT id FROM public.governance_documents WHERE status = 'active')
    )
  );

COMMENT ON POLICY approval_chains_read_scoped ON public.approval_chains IS
  'ADR-0016 D6. Visibilidade scoped: admin | signatário | ratificador | doc ativo. Substitui approval_chains_read_all_auth (USING true) de IP-1.';

COMMENT ON POLICY approval_signoffs_read_scoped ON public.approval_signoffs IS
  'ADR-0016 D6. Espelha approval_chains scoping via chain_id: admin | self | peer na chain | ratificador da chain | doc ativo.';
