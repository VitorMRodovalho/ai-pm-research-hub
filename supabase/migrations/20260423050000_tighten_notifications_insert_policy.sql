-- ═══════════════════════════════════════════════════════════════
-- Drop permissive notifications INSERT policy
-- Why: notif_insert_system had WITH CHECK=true for authenticated role,
-- which let any authenticated user insert notifications for any
-- recipient — a privilege escalation risk. System notifications go
-- through SECURITY DEFINER RPCs (bypass RLS) and Edge Functions with
-- service_role (bypass RLS), so the policy served no legitimate purpose.
-- rpc_only_deny_all (already in place) continues to block direct client writes.
-- Rollback: recreate with the same USING/WITH CHECK (not recommended).
-- ═══════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "notif_insert_system" ON public.notifications;
