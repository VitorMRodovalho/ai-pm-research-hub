-- Track Q-D — comms readers hardening (batch 3a.5)
--
-- Discovery (p58 continuation, post 3a.4):
-- 15 SECDEF readers/helpers in comms bucket. Per-fn callsite + ACL
-- analysis classified into:
--
-- (a) Live with authenticated callers — REVOKE-from-anon (9 fns):
-- - broadcast_history(integer, integer) — broadcast log reader.
--   Caller: src/pages/admin/comms-ops.astro:256.
-- - comms_acknowledge_alert(uuid) — token alert acknowledgement.
--   Caller: src/pages/admin/comms.astro:681. Uses auth.uid()
--   (no V4 gate; admin-shape; Phase B'' candidate for adding
--   `manage_comms` action — surfaced as backlog).
-- - comms_channel_status() — channel sync status. Caller:
--   src/pages/admin/comms.astro:587, 692.
-- - comms_metrics_latest_by_channel(integer) — daily metrics.
--   Caller: src/pages/admin/comms.astro (multiple) + MCP tool.
--   ACL pre-state already lacks PUBLIC (4-grantee).
-- - comms_top_media(text, integer, integer) — top media items.
--   Caller: src/pages/admin/comms.astro:534.
-- - get_comms_dashboard_metrics() — backlog/overdue/format metrics.
--   Caller: src/components/admin/CommsDashboard.tsx:49 + MCP.
-- - get_webinar_lifecycle(uuid) — lifecycle events for webinar.
--   Caller: src/pages/admin/webinars.astro:604 + presence verified
--   in tests/ui-stabilization.test.mjs:101.
-- - list_webinars_v2(text, text, integer) — webinar listing.
--   Caller: src/pages/webinars.astro:19 (member tier),
--   src/pages/admin/webinars.astro:691 (admin), MCP. Member page
--   uses navGetMember() bail pattern.
-- - webinars_pending_comms() — webinars awaiting comms action.
--   Caller: src/pages/admin/comms-ops.astro:216 + MCP.
--
-- (b) Dead — REVOKE-only full lock-down (2 fns):
-- - comms_executive_kpis() — executive aggregate metrics
--   (audience, reach, engagement, growth %, channel_breakdown).
--   0 callers found. Aggregate-only data but admin-shape.
-- - publish_comms_metrics_batch(text, date) — writer (UPDATE
--   comms_metrics_daily); has internal V3 gate
--   (`can_manage_comms_metrics`) but 0 external callers.
--   Per Q-D charter: "AND grant EXECUTE to PUBLIC / anon /
--   authenticated by default" — pre-state ACL had anon grant
--   (4-grantee). Treatment: REVOKE PUBLIC, anon, authenticated
--   per dead-matrix consistency. V3 gate becomes moot but
--   preserved for code-review history.
--
-- Out-of-scope (skipped, documented for follow-up):
-- - admin_manage_comms_channel — V3-gated admin writer
--   (is_superadmin + operational_role + designations). Phase B''
--   candidate for V4 conversion.
-- - auto_comms_card_on_publish — trigger function (no RPC
--   callsite). Internal helper batch 3b.
-- - can_manage_comms_metrics — V3 helper fn used by
--   publish_comms_metrics_batch internal gate. Internal helper
--   batch 3b.
-- - comms_check_token_expiry — already locked down in Q-D
--   batch 1 (postgres + service_role only). REGRESSION NOTE:
--   src/pages/admin/comms.astro:669 still calls it via
--   sb.rpc('comms_check_token_expiry') wrapped in try/catch
--   (silent failure with console.warn). Audit doc surfaces this
--   as a follow-up — either restore authenticated grant for
--   admin reader use or refactor admin page to a different RPC.
--
-- Total: 11 fns triaged in batch 3a.5 (9 live REVOKE-from-anon +
-- 2 dead REVOKE-only). 4 fns documented as out-of-scope.
--
-- Risk: low. Authenticated callers via admin pages and MCP
-- preserved on the 9 live fns. Dead fns become un-callable
-- externally; postgres + service_role retained.

-- ============================================================
-- (a) Live with authenticated callers — REVOKE-from-anon
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.broadcast_history(integer, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.comms_acknowledge_alert(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.comms_channel_status() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.comms_metrics_latest_by_channel(integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.comms_top_media(text, integer, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_comms_dashboard_metrics() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_webinar_lifecycle(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_webinars_v2(text, text, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.webinars_pending_comms() FROM PUBLIC, anon;

-- ============================================================
-- (b) Dead — REVOKE-only full lock-down
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.comms_executive_kpis() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.publish_comms_metrics_batch(text, date) FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
