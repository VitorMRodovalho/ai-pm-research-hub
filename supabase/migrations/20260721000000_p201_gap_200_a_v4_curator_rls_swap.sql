-- ============================================================================
-- p201 GAP-200.A V4 swap — 3 RLS policies still gated by V3 'curator' = ANY(designations)
--
-- Context (corrected scope vs original GAP-200.A description):
-- p200 council code-reviewer + platform-guardian flagged 3 policies at
-- supabase/migrations/20260427030000_v4_phase4_1_rls_legacy_policies.sql lines
-- 445/448/449 — but those lines are INSIDE a rollback comment block (/* at
-- L386 to */ at L459). The LIVE policies at lines 285/298/307 were already
-- V4-swapped in Phase 4.1.
--
-- The REAL V3-curator-gate surface (audited live via pg_policy on 2026-05-19):
--   1. document_versions.document_versions_read_published (SELECT)
--   2. document_comments.document_comments_update_author (UPDATE)
--   3. document_comments.document_comments_read_visibility (SELECT)
-- Source: 20260514200000_adr_0057_auth_rls_initplan_batch_5_final.sql.
--
-- This migration replaces ONLY the `'curator' = ANY(m.designations)` predicate
-- with `can_by_member(m.id, 'curate_content')` (ADR-0087 action). Other V3-style
-- gates in the same policies (operational_role IN (manager/deputy_manager/
-- tribe_leader), chapter_board/chapter_witness designations) are PRESERVED
-- as-is — they are out of scope for ADR-0087 and tracked separately.
--
-- Parity verified pre-migration:
--   - 3 current curators (Fabricio/Roberto/Sarah) have committee_coordinator
--     engagement → can('curate_content') = true
--   - Non-curators → false
--
-- ROLLBACK (idempotent):
--   Replace `can_by_member(m.id, 'curate_content')` back with
--   `'curator' = ANY(m.designations)` in each of the 3 policies via DROP +
--   CREATE pattern. Body restoration only — no permission grant changes.
--
-- ADR: ADR-0087 (V4 curate_content action)
-- Backlog closure: GAP-200.A (HIGH, p200 carry)
-- ============================================================================

-- 1) document_versions_read_published
DROP POLICY IF EXISTS document_versions_read_published ON public.document_versions;
CREATE POLICY document_versions_read_published ON public.document_versions
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    locked_at IS NOT NULL
    OR EXISTS (
      SELECT 1
      FROM public.members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND (
          m.operational_role = ANY (ARRAY['manager'::text, 'deputy_manager'::text])
          OR public.can_by_member(m.id, 'curate_content')
        )
    )
  );

-- 2) document_comments_update_author
DROP POLICY IF EXISTS document_comments_update_author ON public.document_comments;
CREATE POLICY document_comments_update_author ON public.document_comments
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (
    author_id IN (
      SELECT members.id FROM public.members
      WHERE members.auth_id = (SELECT auth.uid())
    )
    OR EXISTS (
      SELECT 1
      FROM public.members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND (
          m.operational_role = ANY (ARRAY['manager'::text, 'deputy_manager'::text])
          OR public.can_by_member(m.id, 'curate_content')
        )
    )
  );

-- 3) document_comments_read_visibility (4 paths: own / manage_member / curator_only / change_notes)
DROP POLICY IF EXISTS document_comments_read_visibility ON public.document_comments;
CREATE POLICY document_comments_read_visibility ON public.document_comments
  AS PERMISSIVE FOR SELECT
  USING (
    author_id IN (
      SELECT m.id FROM public.members m
      WHERE m.auth_id = (SELECT auth.uid())
    )
    OR EXISTS (
      SELECT 1
      FROM public.members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND public.can_by_member(m.id, 'manage_member')
    )
    OR (
      visibility = 'curator_only'::text
      AND EXISTS (
        SELECT 1
        FROM public.members m
        WHERE m.auth_id = (SELECT auth.uid())
          AND (
            public.can_by_member(m.id, 'curate_content')
            OR m.operational_role = ANY (ARRAY['manager'::text, 'deputy_manager'::text, 'tribe_leader'::text])
          )
      )
    )
    OR (
      visibility = 'change_notes'::text
      AND EXISTS (
        SELECT 1
        FROM public.members m
        WHERE m.auth_id = (SELECT auth.uid())
          AND (
            m.operational_role = ANY (ARRAY['manager'::text, 'deputy_manager'::text, 'tribe_leader'::text])
            OR 'chapter_board'::text = ANY (m.designations)
            OR 'chapter_witness'::text = ANY (m.designations)
            OR public.can_by_member(m.id, 'curate_content')
          )
      )
    )
  );

NOTIFY pgrst, 'reload schema';
