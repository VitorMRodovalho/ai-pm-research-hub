-- ADR-0057 — auth_rls_initplan FINAL batch (closes 100%)
-- Wrap auth.uid() / auth.role() in (SELECT ...) for InitPlan caching.
-- 27 policies covering 4 z_archive + 23 public tables.
-- Cumulative across batches 1-5: 76 policies wrapped (advisor lint count → 0).
-- Pure mechanical transform — no ACL change, no role/permissive change.

-- ============================================================================
-- z_archive policies (4)
-- ============================================================================

DROP POLICY IF EXISTS "Managers create presentations" ON z_archive.presentations;
CREATE POLICY "Managers create presentations" ON z_archive.presentations
  AS PERMISSIVE FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM members
      WHERE members.auth_id = (SELECT auth.uid())
        AND (members.is_superadmin = true OR members.operational_role = 'manager'::text)
    )
  );

DROP POLICY IF EXISTS admin_read_role_changes ON z_archive.member_role_changes;
CREATE POLICY admin_read_role_changes ON z_archive.member_role_changes
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager'::text, 'deputy_manager'::text]))
    )
  );

DROP POLICY IF EXISTS self_read_role_changes ON z_archive.member_role_changes;
CREATE POLICY self_read_role_changes ON z_archive.member_role_changes
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    member_id = (
      SELECT members.id
      FROM members
      WHERE members.auth_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS comms_token_alerts_admin ON z_archive.comms_token_alerts;
CREATE POLICY comms_token_alerts_admin ON z_archive.comms_token_alerts
  AS PERMISSIVE FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM members
      WHERE members.auth_id = (SELECT auth.uid())
        AND (
          members.is_superadmin
          OR members.operational_role = ANY (ARRAY['manager'::text, 'deputy_manager'::text])
          OR members.designations && ARRAY['comms_leader'::text]
        )
    )
  );

-- ============================================================================
-- public.document_versions (3)
-- ============================================================================

DROP POLICY IF EXISTS document_versions_read_published ON public.document_versions;
CREATE POLICY document_versions_read_published ON public.document_versions
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    locked_at IS NOT NULL
    OR EXISTS (
      SELECT 1
      FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND (
          m.operational_role = ANY (ARRAY['manager'::text, 'deputy_manager'::text])
          OR 'curator'::text = ANY (m.designations)
        )
    )
  );

DROP POLICY IF EXISTS document_versions_insert_admin ON public.document_versions;
CREATE POLICY document_versions_insert_admin ON public.document_versions
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND can_by_member(m.id, 'manage_member'::text)
    )
  );

DROP POLICY IF EXISTS document_versions_delete_drafts ON public.document_versions;
CREATE POLICY document_versions_delete_drafts ON public.document_versions
  AS PERMISSIVE FOR DELETE TO authenticated
  USING (
    locked_at IS NULL
    AND EXISTS (
      SELECT 1
      FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND can_by_member(m.id, 'manage_member'::text)
    )
  );

-- ============================================================================
-- public.approval_chains (3)
-- ============================================================================

DROP POLICY IF EXISTS approval_chains_write_admin ON public.approval_chains;
CREATE POLICY approval_chains_write_admin ON public.approval_chains
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND can_by_member(m.id, 'manage_member'::text)
    )
  );

DROP POLICY IF EXISTS approval_chains_update_admin ON public.approval_chains;
CREATE POLICY approval_chains_update_admin ON public.approval_chains
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND can_by_member(m.id, 'manage_member'::text)
    )
  );

DROP POLICY IF EXISTS approval_chains_read_scoped ON public.approval_chains;
CREATE POLICY approval_chains_read_scoped ON public.approval_chains
  AS PERMISSIVE FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND can_by_member(m.id, 'manage_member'::text)
    )
    OR document_id IN (
      SELECT mds.document_id
      FROM member_document_signatures mds
      WHERE mds.member_id IN (
        SELECT m.id FROM members m WHERE m.auth_id = (SELECT auth.uid())
      )
    )
    OR document_id IN (
      SELECT gd.id FROM governance_documents gd WHERE gd.status = 'active'::text
    )
  );

-- ============================================================================
-- public.approval_signoffs (2)
-- ============================================================================

DROP POLICY IF EXISTS approval_signoffs_insert_self_or_rpc ON public.approval_signoffs;
CREATE POLICY approval_signoffs_insert_self_or_rpc ON public.approval_signoffs
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (
    signer_id IN (
      SELECT members.id FROM members WHERE members.auth_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS approval_signoffs_read_scoped ON public.approval_signoffs;
CREATE POLICY approval_signoffs_read_scoped ON public.approval_signoffs
  AS PERMISSIVE FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND can_by_member(m.id, 'manage_member'::text)
    )
    OR signer_id IN (
      SELECT m.id FROM members m WHERE m.auth_id = (SELECT auth.uid())
    )
  );

-- ============================================================================
-- public.document_comments (3)
-- ============================================================================

DROP POLICY IF EXISTS document_comments_insert_active ON public.document_comments;
CREATE POLICY document_comments_insert_active ON public.document_comments
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (
    author_id IN (
      SELECT members.id FROM members
      WHERE members.auth_id = (SELECT auth.uid()) AND members.is_active = true
    )
  );

DROP POLICY IF EXISTS document_comments_update_author ON public.document_comments;
CREATE POLICY document_comments_update_author ON public.document_comments
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (
    author_id IN (
      SELECT members.id FROM members WHERE members.auth_id = (SELECT auth.uid())
    )
    OR EXISTS (
      SELECT 1
      FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND (
          m.operational_role = ANY (ARRAY['manager'::text, 'deputy_manager'::text])
          OR 'curator'::text = ANY (m.designations)
        )
    )
  );

DROP POLICY IF EXISTS document_comments_read_visibility ON public.document_comments;
CREATE POLICY document_comments_read_visibility ON public.document_comments
  AS PERMISSIVE FOR SELECT
  USING (
    author_id IN (
      SELECT m.id FROM members m WHERE m.auth_id = (SELECT auth.uid())
    )
    OR EXISTS (
      SELECT 1
      FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND can_by_member(m.id, 'manage_member'::text)
    )
    OR (
      visibility = 'curator_only'::text
      AND EXISTS (
        SELECT 1
        FROM members m
        WHERE m.auth_id = (SELECT auth.uid())
          AND (
            'curator'::text = ANY (m.designations)
            OR m.operational_role = ANY (ARRAY['manager'::text, 'deputy_manager'::text, 'tribe_leader'::text])
          )
      )
    )
    OR (
      visibility = 'change_notes'::text
      AND EXISTS (
        SELECT 1
        FROM members m
        WHERE m.auth_id = (SELECT auth.uid())
          AND (
            m.operational_role = ANY (ARRAY['manager'::text, 'deputy_manager'::text, 'tribe_leader'::text])
            OR 'chapter_board'::text = ANY (m.designations)
            OR 'chapter_witness'::text = ANY (m.designations)
            OR 'curator'::text = ANY (m.designations)
          )
      )
    )
  );

-- ============================================================================
-- public.document_comment_edits (1)
-- ============================================================================

DROP POLICY IF EXISTS document_comment_edits_read_scoped ON public.document_comment_edits;
CREATE POLICY document_comment_edits_read_scoped ON public.document_comment_edits
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    edited_by IN (
      SELECT members.id FROM members WHERE members.auth_id = (SELECT auth.uid())
    )
    OR comment_id IN (
      SELECT document_comments.id FROM document_comments
      WHERE document_comments.author_id IN (
        SELECT members.id FROM members WHERE members.auth_id = (SELECT auth.uid())
      )
    )
    OR EXISTS (
      SELECT 1 FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND can_by_member(m.id, 'manage_member'::text)
    )
  );

-- ============================================================================
-- public.hub_resources (1)
-- ============================================================================

DROP POLICY IF EXISTS hub_resources_delete ON public.hub_resources;
CREATE POLICY hub_resources_delete ON public.hub_resources
  AS PERMISSIVE FOR DELETE TO authenticated
  USING (
    COALESCE(
      (SELECT m.is_superadmin FROM members m WHERE m.auth_id = (SELECT auth.uid()) LIMIT 1),
      false
    ) = true
  );

-- ============================================================================
-- public.tribe_deliverables (1)  -- auth.role() pattern
-- ============================================================================

DROP POLICY IF EXISTS tribe_deliverables_read ON public.tribe_deliverables;
CREATE POLICY tribe_deliverables_read ON public.tribe_deliverables
  AS PERMISSIVE FOR SELECT
  USING (
    (SELECT auth.role()) = 'authenticated'::text
  );

-- ============================================================================
-- public.broadcast_log (1)
-- ============================================================================

DROP POLICY IF EXISTS broadcast_log_read_sender ON public.broadcast_log;
CREATE POLICY broadcast_log_read_sender ON public.broadcast_log
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    sender_id = (
      SELECT m.id FROM members m WHERE m.auth_id = (SELECT auth.uid()) LIMIT 1
    )
  );

-- ============================================================================
-- public.member_document_signatures (1)
-- ============================================================================

DROP POLICY IF EXISTS member_doc_sigs_read_self_or_admin ON public.member_document_signatures;
CREATE POLICY member_doc_sigs_read_self_or_admin ON public.member_document_signatures
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    member_id IN (
      SELECT members.id FROM members WHERE members.auth_id = (SELECT auth.uid())
    )
    OR EXISTS (
      SELECT 1 FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND can_by_member(m.id, 'manage_member'::text)
    )
  );

-- ============================================================================
-- public.member_offboarding_records (1) — both USING and WITH CHECK
-- ============================================================================

DROP POLICY IF EXISTS offboarding_records_update_authorized ON public.member_offboarding_records;
CREATE POLICY offboarding_records_update_authorized ON public.member_offboarding_records
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (
    rls_can('manage_member'::text)
    OR EXISTS (
      SELECT 1 FROM members m
      WHERE m.id = member_offboarding_records.member_id
        AND m.auth_id = (SELECT auth.uid())
    )
  )
  WITH CHECK (
    rls_can('manage_member'::text)
    OR EXISTS (
      SELECT 1 FROM members m
      WHERE m.id = member_offboarding_records.member_id
        AND m.auth_id = (SELECT auth.uid())
    )
  );

-- ============================================================================
-- public.campaign_sends (1)
-- ============================================================================

DROP POLICY IF EXISTS "Comms team reads sends" ON public.campaign_sends;
CREATE POLICY "Comms team reads sends" ON public.campaign_sends
  AS PERMISSIVE FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND 'comms_team'::text = ANY (m.designations)
    )
  );

-- ============================================================================
-- public.comms_media_items (1)
-- ============================================================================

DROP POLICY IF EXISTS comms_media_items_read ON public.comms_media_items;
CREATE POLICY comms_media_items_read ON public.comms_media_items
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    rls_is_superadmin()
    OR rls_can('manage_member'::text)
    OR rls_can('write'::text)
    OR EXISTS (
      SELECT 1 FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND 'comms_member'::text = ANY (COALESCE(m.designations, '{}'::text[]))
    )
  );

-- ============================================================================
-- public.comms_metrics_daily (1)
-- ============================================================================

DROP POLICY IF EXISTS comms_metrics_admin_read ON public.comms_metrics_daily;
CREATE POLICY comms_metrics_admin_read ON public.comms_metrics_daily
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    rls_is_superadmin()
    OR rls_can('manage_member'::text)
    OR rls_can('write'::text)
    OR EXISTS (
      SELECT 1 FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND 'comms_member'::text = ANY (COALESCE(m.designations, '{}'::text[]))
    )
  );

-- ============================================================================
-- public.webinars (1)
-- ============================================================================

DROP POLICY IF EXISTS webinars_update_v2 ON public.webinars;
CREATE POLICY webinars_update_v2 ON public.webinars
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (
    rls_is_superadmin()
    OR rls_can('manage_member'::text)
    OR organizer_id = (
      SELECT m.id FROM members m WHERE m.auth_id = (SELECT auth.uid()) LIMIT 1
    )
    OR (
      SELECT m.id FROM members m WHERE m.auth_id = (SELECT auth.uid()) LIMIT 1
    ) = ANY (co_manager_ids)
  );

-- ============================================================================
-- public.chapter_needs (1)
-- ============================================================================

DROP POLICY IF EXISTS chapter_needs_insert ON public.chapter_needs;
CREATE POLICY chapter_needs_insert ON public.chapter_needs
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND m.id = chapter_needs.submitted_by
        AND m.chapter = chapter_needs.chapter
        AND m.designations && ARRAY['chapter_board'::text, 'sponsor'::text, 'chapter_liaison'::text]
    )
  );

-- ============================================================================
-- public.pii_access_log (1)
-- ============================================================================

DROP POLICY IF EXISTS pii_log_admin_read_v4 ON public.pii_access_log;
CREATE POLICY pii_log_admin_read_v4 ON public.pii_access_log
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    rls_is_superadmin()
    OR rls_can('manage_member'::text)
    OR target_member_id = (
      SELECT m.id FROM members m WHERE m.auth_id = (SELECT auth.uid()) LIMIT 1
    )
  );

NOTIFY pgrst, 'reload schema';
