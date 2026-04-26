-- Track Q-D — SECDEF security hardening sweep (batch 1)
--
-- Scope: 21 SECDEF functions in public schema currently grant EXECUTE
-- to PUBLIC, anon, and authenticated, but are intended for one of:
--   (a) PII crypto helpers (no callers from app code)
--   (b) EF webhook receivers (called only via service_role)
--   (c) pg_cron jobs (called only by postgres role)
--   (d) admin-only writers with no current callers (dead code)
--   (e) admin metadata helpers
--
-- Risk: any authenticated PostgREST caller can invoke each fn directly.
-- Same exposure pattern that surfaced drift signals #7 #8 in p54.
--
-- Strategy: REVOKE EXECUTE FROM PUBLIC, anon, authenticated.
-- Postgres + service_role grants preserved (cron + EF still work).
-- For dead-code admin fns this is non-disruptive (no callers today);
-- if admin UI later needs them, the proper fix is to add a V4
-- can_by_member() gate AND re-grant authenticated.
--
-- Companion to Phase B' (which migrates V3 gates to V4 in captured
-- functions). Phase Q-D is "no-gate-at-all" hardening via REVOKE.
--
-- Sweep methodology (verified 2026-04-25):
--   1. Enumerate 566 SECDEF functions in public schema (excluding
--      extension-owned).
--   2. Filter to "no auth gate" subset: no can_by_member, no can(),
--      no auth.uid() reference, no V3 pattern.
--   3. Of 109 orphan-no-gate external-callable, classify by intended
--      caller (cron/EF/admin/dead). Triaged 21 for batch 1.
--   4. Verified ACLs via pg_proc.proacl: each below has
--      `=X/postgres,anon=X/postgres,authenticated=X/postgres,...`
--      = exposed to ALL PostgREST callers.
--   5. Verified callsites via grep on src/ + supabase/functions/.
--      Dead-code admin fns have ZERO matches; cron fns have only
--      pg_cron job entries; EF fn (process_email_webhook) only called
--      from resend-webhook EF (service_role).
--
-- Future Phase Q-D batches: there are ~80 more orphan-no-gate fns
-- (mostly readers) needing per-fn triage for PII exposure.

-- ========================================================================
-- (a) PII crypto helpers — CRITICAL
--     Wrappers around pgp_sym_encrypt / pgp_sym_decrypt with the
--     app.encryption_key GUC. Public exposure means anyone authenticated
--     could decrypt arbitrary bytea payloads from PII columns.
-- ========================================================================

REVOKE EXECUTE ON FUNCTION public.encrypt_sensitive(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.decrypt_sensitive(bytea) FROM PUBLIC, anon, authenticated;

-- ========================================================================
-- (b) EF service_role-only — process_email_webhook
--     Called by resend-webhook EF (uses service_role). PostgREST
--     callers should not be able to forge email lifecycle events.
-- ========================================================================

REVOKE EXECUTE ON FUNCTION public.process_email_webhook(text, text, jsonb) FROM PUBLIC, anon, authenticated;

-- ========================================================================
-- (c) pg_cron-only functions — only postgres role should invoke
-- ========================================================================

REVOKE EXECUTE ON FUNCTION public.auto_archive_done_cards() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.auto_detect_onboarding_completions() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.comms_check_token_expiry() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.detect_mcp_anomalies() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.generate_weekly_card_digest_cron() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.send_attendance_reminders_cron() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.v4_expire_engagements() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.v4_expire_engagements_shadow() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.v4_notify_expiring_engagements() FROM PUBLIC, anon, authenticated;

-- ========================================================================
-- (d) Dead-code admin writers — no current callers in src/ or EFs
--     If admin UI later needs them, add can_by_member() gate +
--     re-grant authenticated.
-- ========================================================================

REVOKE EXECUTE ON FUNCTION public.compute_application_scores(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.create_initiative(text, text, text, jsonb, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_initiative(uuid, text, text, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.seed_pre_onboarding_steps(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enrich_applications_from_csv(uuid, jsonb, text, text) FROM PUBLIC, anon, authenticated;
-- Three one-shot importers (drift signal #4 PM-blocked on archive vs
-- parameterize; revoking is non-controversial since they're cycle3-2026
-- specific and have no app callers).
REVOKE EXECUTE ON FUNCTION public.import_historical_evaluations(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.import_historical_interviews(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.import_leader_evaluations(jsonb) FROM PUBLIC, anon, authenticated;

-- ========================================================================
-- (e) Admin metadata helper — internal contract-test helper added in
--     p51 Q-C. Should not be PostgREST-callable.
-- ========================================================================

REVOKE EXECUTE ON FUNCTION public._audit_list_public_functions() FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
