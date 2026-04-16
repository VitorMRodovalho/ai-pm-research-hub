-- ═══════════════════════════════════════════════════════════════
-- RLS policy for selection_membership_snapshots
-- Why: table was created with RLS enabled in 20260401020000 but no
-- policies shipped, so `authenticated` gets default-deny. Active table
-- with 383 rows of PMI membership/chapter affiliation per applicant —
-- needs explicit read grants for selection committee.
-- Rollback: DROP POLICY admin_read_membership_snapshots ON public.selection_membership_snapshots;
-- ═══════════════════════════════════════════════════════════════

CREATE POLICY "admin_read_membership_snapshots" ON public.selection_membership_snapshots
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND (
          m.is_superadmin = true
          OR m.operational_role IN ('manager', 'deputy_manager')
          OR m.designations && ARRAY['sponsor', 'curator']
        )
    )
  );
