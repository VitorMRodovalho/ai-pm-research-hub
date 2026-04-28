-- ADR-0058 batch 5 — drop misleading PERMISSIVE deny policies (no-ops)
-- These policies are PERMISSIVE + USING false — functionally a no-op.
-- PERMISSIVE policies grant access via OR; USING false never grants. So
-- they don't actually deny anything (real denial would require RESTRICTIVE).
-- The actual denial comes from RLS default-deny when no PERMISSIVE passes.
-- Dropping these eliminates 10 mpp WARN with zero behavior change.

DROP POLICY IF EXISTS rpc_only_deny_all ON public.member_cycle_history;
DROP POLICY IF EXISTS rpc_only_deny_all ON public.notification_preferences;
DROP POLICY IF EXISTS rpc_only_deny_all ON public.notifications;
DROP POLICY IF EXISTS partner_cards_deny_direct_writes ON public.partner_cards;

COMMENT ON TABLE public.member_cycle_history IS
  'RLS-protected: only superadmins (mch_superadmin_write USING has_min_tier(5)) have direct access. Non-superadmin authenticated users access via SECDEF RPCs. Anon blocked by RLS default-deny. (Removed misleading PERMISSIVE+USING false deny policy in ADR-0058 batch 5.)';

COMMENT ON TABLE public.notification_preferences IS
  'RLS-protected: members access only own preferences (notifpref_own USING member_id matches caller). Mutations through SECDEF RPCs. Anon blocked by RLS default-deny. (Removed misleading PERMISSIVE+USING false deny policy in ADR-0058 batch 5.)';

COMMENT ON TABLE public.notifications IS
  'RLS-protected: members read only own notifications (notif_select_own USING recipient_id matches caller). All mutations through SECDEF RPCs. Anon blocked by RLS default-deny. (Removed misleading PERMISSIVE+USING false deny policy in ADR-0058 batch 5.)';

COMMENT ON TABLE public.partner_cards IS
  'RLS-protected: authenticated members read all rows (partner_cards_read_authenticated USING true). All mutations through SECDEF RPCs. Anon blocked by RLS default-deny. (Removed misleading PERMISSIVE+USING false deny policy in ADR-0058 batch 5.)';

NOTIFY pgrst, 'reload schema';
