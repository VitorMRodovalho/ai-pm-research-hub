-- =====================================================================
-- #965 — Systemic privilege-drift: SECDEF functions carry the default PUBLIC
-- EXECUTE grant (callable by anon/authenticated via PostgREST POST /rest/v1/rpc).
--
-- Root cause: Postgres CREATE FUNCTION grants EXECUTE to PUBLIC by default;
-- migrations that GRANT … TO service_role without a matching REVOKE … FROM
-- PUBLIC leave anon/authenticated able to trigger a paid/dispatch side-effect.
-- The worst (campaign_send_one_off open-relay) was fixed in #963; this PR closes
-- the verified-safe subset of the rest + installs a CI ratchet. ADR-0118.
--
-- SCOPE (this PR): the 6 functions whose caller graph is CRON + TRIGGER + SECDEF-
-- only (verified live this turn — REVOKE non-regressive; service_role/postgres
-- retain EXECUTE so cron/worker/SECDEF callers are unaffected; definers retain
-- EXECUTE for inner calls). NOT a mechanical mass-revoke ([LL] #588 — each was
-- caller-graph + intent checked):
--   * process_pending_email_queue()                      — cron 'dispatch-pending-emails'   (http_post)
--   * analyze_application_video_async(uuid,text,boolean) — SECDEF wrapper analyze_application_video
--                                                          (MCP) + upload trigger (already DROPPED) (http_post)
--   * retry_pending_ai_analyses()                        — cron + SECDEF readers              (http_post)
--   * retry_pending_ai_triages()                         — cron 'retry-pending-ai-triages'    (http_post)
--   * generate_weekly_leader_digest_cron()               — cron 'send-weekly-leader-digest';
--       inserts transactional notifications for every tribe leader => anon = notification/email SPAM
--   * _grant_auto_xp(text,uuid,uuid,text,boolean)        — 9 trg_*_xp triggers + register_event_showcase
--       (all SECDEF); takes arbitrary p_recipient_id => anon/authenticated = XP FRAUD
-- grep src/ + supabase/functions/ for .rpc('<name>') on all 6 = ZERO direct anon/authenticated callers.
--
-- EXPLICITLY NOT REVOKED (verified by-design / token-gated — stays anon-reachable):
--   * request_application_enrichment(text,jsonb) — onboarding_tokens 'profile_completion' (EnrichmentCard.tsx)
--   * opt_out_all_pillars(text)                  — onboarding_tokens 'video_screening' (same class)
--   Both validate a token + RAISE on invalid; revoking anon would break the applicant flow. They live in the
--   forward-defense allowlist (the sweep heuristic can't see token-gating), NOT in this revoke.
--
-- NOT in scope this PR (lower-severity, tracked in the allowlist for a future ratchet-down pass; each needs
-- its own caller-graph check before revoking — e.g. recompute_all_active_pert_cutoffs has an MCP wrapper hint).
--
-- Forward-defense (the durable fix): audit RPC _audit_secdef_public_grant_drift() (catalog-read, identities
-- only — no bodies/PII; uses has_function_privilege per-oid, robust to overloads) + the CI ratchet test
-- tests/contracts/965-secdef-public-grant-drift.test.mjs (live set EQUALS a categorized allowlist).
--
-- GROUNDING (live 2026-06-30, project ldrfrvwhxsmgaabwmaik): all 6 carry an anon-reachable EXECUTE grant;
-- single signature each. REVOKE-only (+1 SELECT-only RPC) => rpc-migration-coverage/body-drift unaffected for
-- existing bodies; the new RPC is captured here. Sweep = 36 unique names; post-revoke = 30 = the allowlist.
-- =====================================================================

-- ── 1. Revoke the 6 verified cron/trigger/SECDEF-only side-effect functions ──
REVOKE EXECUTE ON FUNCTION public.process_pending_email_queue() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.process_pending_email_queue() TO service_role;

REVOKE EXECUTE ON FUNCTION public.analyze_application_video_async(uuid, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.analyze_application_video_async(uuid, text, boolean) TO service_role;

REVOKE EXECUTE ON FUNCTION public.retry_pending_ai_analyses() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.retry_pending_ai_analyses() TO service_role;

REVOKE EXECUTE ON FUNCTION public.retry_pending_ai_triages() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.retry_pending_ai_triages() TO service_role;

REVOKE EXECUTE ON FUNCTION public.generate_weekly_leader_digest_cron() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.generate_weekly_leader_digest_cron() TO service_role;

REVOKE EXECUTE ON FUNCTION public._grant_auto_xp(text, uuid, uuid, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._grant_auto_xp(text, uuid, uuid, text, boolean) TO service_role;

-- ── 2. Forward-defense audit RPC (#730-style: catalog-read, returns identities only — no bodies/PII).
--    Uses has_function_privilege('anon', oid, 'EXECUTE') => per-overload precise (no routine_name ambiguity).
--    SELECT-only => not itself flagged. REVOKE public/anon (service_role only, for the CI ratchet test). ──
CREATE OR REPLACE FUNCTION public._audit_secdef_public_grant_drift()
 RETURNS TABLE(proname text, sends_http boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p.proname::text,
         (position('http_post' in p.prosrc) > 0) AS sends_http
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prosecdef AND p.prorettype <> 'trigger'::regtype
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND position('auth.uid()' in p.prosrc) = 0 AND position('can_by_member' in p.prosrc) = 0
    AND position('public.can(' in p.prosrc) = 0 AND position('auth.role' in p.prosrc) = 0
    AND position('current_setting' in p.prosrc) = 0
    AND (p.prosrc ~* '\m(insert|update|delete)\M' OR position('http_post' in p.prosrc) > 0)
  ORDER BY 2 DESC, 1;
$function$;
REVOKE EXECUTE ON FUNCTION public._audit_secdef_public_grant_drift() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._audit_secdef_public_grant_drift() TO service_role;

NOTIFY pgrst, 'reload schema';
