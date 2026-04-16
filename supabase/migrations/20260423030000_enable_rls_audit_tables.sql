-- ═══════════════════════════════════════════════════════════════
-- Enable RLS on audit tables (LGPD compliance — GC-162)
-- Tables: member_role_changes, selection_ranking_snapshots
-- Source: Supabase security advisors flagged rls_disabled_in_public (ERROR).
-- These tables hold sensitive governance data:
-- - member_role_changes: auditable history of role/designation/tribe changes
-- - selection_ranking_snapshots: selection committee ranking snapshots (PII)
-- Access model: admin-only reads, system writes via RPC.
-- Rollback: ALTER TABLE ... DISABLE ROW LEVEL SECURITY; DROP POLICY ...;
-- ═══════════════════════════════════════════════════════════════

-- ── member_role_changes ──
ALTER TABLE public.member_role_changes ENABLE ROW LEVEL SECURITY;

-- Admins read everything
CREATE POLICY "admin_read_role_changes" ON public.member_role_changes
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager'))
    )
  );

-- Members read their own history
CREATE POLICY "self_read_role_changes" ON public.member_role_changes
  FOR SELECT TO authenticated
  USING (
    member_id = (SELECT id FROM public.members WHERE auth_id = auth.uid())
  );

-- Writes happen via SECURITY DEFINER RPCs only (no direct insert/update/delete from client)

-- ── selection_ranking_snapshots ──
ALTER TABLE public.selection_ranking_snapshots ENABLE ROW LEVEL SECURITY;

-- Admins + selection committee (curators/sponsors) read
CREATE POLICY "admin_read_selection_rankings" ON public.selection_ranking_snapshots
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

-- Writes happen via SECURITY DEFINER RPCs only
