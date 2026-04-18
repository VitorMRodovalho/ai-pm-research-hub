-- ============================================================================
-- Phase IP-1: RLS policies for 5 tables
-- Rollback: DROP POLICY ... for each; ALTER TABLE ... DISABLE ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE public.document_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.approval_chains ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.approval_signoffs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_document_signatures ENABLE ROW LEVEL SECURITY;

-- document_versions
DROP POLICY IF EXISTS document_versions_read_published ON public.document_versions;
CREATE POLICY document_versions_read_published ON public.document_versions
  FOR SELECT TO authenticated
  USING (
    locked_at IS NOT NULL
    OR EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid()
               AND (m.operational_role IN ('manager','deputy_manager') OR 'curator' = ANY(m.designations)))
  );

DROP POLICY IF EXISTS document_versions_insert_admin ON public.document_versions;
CREATE POLICY document_versions_insert_admin ON public.document_versions
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid()
            AND public.can_by_member(m.id, 'manage_member'))
  );

-- approval_chains
DROP POLICY IF EXISTS approval_chains_read_all_auth ON public.approval_chains;
CREATE POLICY approval_chains_read_all_auth ON public.approval_chains
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS approval_chains_write_admin ON public.approval_chains;
CREATE POLICY approval_chains_write_admin ON public.approval_chains
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid()
            AND public.can_by_member(m.id, 'manage_member'))
  );

DROP POLICY IF EXISTS approval_chains_update_admin ON public.approval_chains;
CREATE POLICY approval_chains_update_admin ON public.approval_chains
  FOR UPDATE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid()
            AND public.can_by_member(m.id, 'manage_member'))
  );

-- approval_signoffs (immutable, write only via sign_ip_ratification RPC)
DROP POLICY IF EXISTS approval_signoffs_read_all_auth ON public.approval_signoffs;
CREATE POLICY approval_signoffs_read_all_auth ON public.approval_signoffs
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS approval_signoffs_insert_self_or_rpc ON public.approval_signoffs;
CREATE POLICY approval_signoffs_insert_self_or_rpc ON public.approval_signoffs
  FOR INSERT TO authenticated
  WITH CHECK (
    signer_id IN (SELECT id FROM public.members WHERE auth_id = auth.uid())
  );

-- document_comments (visibility-based)
DROP POLICY IF EXISTS document_comments_read_visibility ON public.document_comments;
CREATE POLICY document_comments_read_visibility ON public.document_comments
  FOR SELECT TO authenticated
  USING (
    visibility = 'public'
    OR author_id IN (SELECT id FROM public.members WHERE auth_id = auth.uid())
    OR (visibility = 'curator_only' AND EXISTS (
      SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid()
        AND ('curator' = ANY(m.designations) OR m.operational_role IN ('manager','deputy_manager','tribe_leader'))
    ))
  );

DROP POLICY IF EXISTS document_comments_insert_active ON public.document_comments;
CREATE POLICY document_comments_insert_active ON public.document_comments
  FOR INSERT TO authenticated
  WITH CHECK (
    author_id IN (SELECT id FROM public.members WHERE auth_id = auth.uid() AND is_active = true)
  );

DROP POLICY IF EXISTS document_comments_update_author ON public.document_comments;
CREATE POLICY document_comments_update_author ON public.document_comments
  FOR UPDATE TO authenticated
  USING (
    author_id IN (SELECT id FROM public.members WHERE auth_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid()
               AND (m.operational_role IN ('manager','deputy_manager') OR 'curator' = ANY(m.designations)))
  );

-- member_document_signatures
DROP POLICY IF EXISTS member_doc_sigs_read_self_or_admin ON public.member_document_signatures;
CREATE POLICY member_doc_sigs_read_self_or_admin ON public.member_document_signatures
  FOR SELECT TO authenticated
  USING (
    member_id IN (SELECT id FROM public.members WHERE auth_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid()
               AND public.can_by_member(m.id, 'manage_member'))
  );

DROP POLICY IF EXISTS member_doc_sigs_insert_self_or_rpc ON public.member_document_signatures;
CREATE POLICY member_doc_sigs_insert_self_or_rpc ON public.member_document_signatures
  FOR INSERT TO authenticated
  WITH CHECK (
    member_id IN (SELECT id FROM public.members WHERE auth_id = auth.uid())
  );
