-- Security sweep Onda 1 — flip security_invoker on 6 SECURITY DEFINER views
-- Triage: 2026-04-23 p40 (#82 comment 4309743302). Closes 6/11 ERROR advisor findings.
-- Surviving 5 findings (members_public_safe, public_members, gamification_leaderboard,
-- member_attendance_summary, recurring_event_groups) go to Onda 2/3 (product review).
--
-- Safety analysis per view (pre-flight done 2026-04-23):
--   * active_members: W139 anon already revoked; authenticated members see via
--     members_read_by_members policy (is_active=true AND rls_is_member()) — same rows.
--   * impact_hours_summary / impact_hours_total: anon kept (natural 0-content via
--     events+attendance RLS for anon) so UI doesn't 403 on pre-auth render.
--   * vw_exec_cert_timeline / vw_exec_skills_radar: zero runtime callers in src/
--     (only generated types). Admin-only via SECDEF RPC wrappers.
--   * auth_engagements: 8 SECURITY DEFINER auth-chain callers (can, rls_can_for_*,
--     sync_operational_role_cache, why_denied, check_schema_invariants,
--     create_external_signer_invite, get_ratification_reminder_targets) all owned by
--     postgres — current_user inside them = postgres (table owner) → RLS bypassed
--     → view returns all rows as before. Flip is transparent.
--
-- Rollback: ALTER VIEW ... SET (security_invoker = false); GRANT SELECT ... back.

-- 1. active_members — anon already revoked W139
ALTER VIEW public.active_members SET (security_invoker = true);

-- 2. impact_hours_summary — tribe-level aggregate, anon grant kept (RLS restricts to 0 for anon)
ALTER VIEW public.impact_hours_summary SET (security_invoker = true);

-- 3. impact_hours_total — platform-wide aggregate, anon grant kept (UI anon-pre-auth)
ALTER VIEW public.impact_hours_total SET (security_invoker = true);

-- 4. vw_exec_cert_timeline — exec analytics, zero runtime caller → full lockdown
ALTER VIEW public.vw_exec_cert_timeline SET (security_invoker = true);
REVOKE SELECT ON public.vw_exec_cert_timeline FROM anon, authenticated;

-- 5. vw_exec_skills_radar — same
ALTER VIEW public.vw_exec_skills_radar SET (security_invoker = true);
REVOKE SELECT ON public.vw_exec_skills_radar FROM anon, authenticated;

-- 6. auth_engagements — V4 auth foundation (8 SECDEF callers own'd by postgres)
ALTER VIEW public.auth_engagements SET (security_invoker = true);
REVOKE SELECT ON public.auth_engagements FROM anon;
COMMENT ON VIEW public.auth_engagements IS
  'V4 authority view (ADR-0007). Consumed by 8 SECURITY DEFINER functions in the auth chain: can, rls_can_for_initiative, rls_can_for_tribe, sync_operational_role_cache, why_denied, create_external_signer_invite, get_ratification_reminder_targets, check_schema_invariants. These callers run as postgres (table owner) — current_user inside them bypasses RLS on the underlying engagements/persons/initiatives tables, so security_invoker=true is functionally identical. Anon SELECT revoked (2026-04-23) — authority data must not be queryable by anon directly. service_role + authenticated retain SELECT (the latter is gated by engagements RLS when invoked outside a SECDEF function).';
