-- #1551 — ACL sweep over SECURITY DEFINER functions reachable by anon/PUBLIC.
--
-- Context: #1543 established the correct shape for a cron-context function — no auth.uid()
-- gate (there is no JWT under pg_cron), which makes the ACL the ONLY protection. Where the
-- REVOKE never accompanied the gate removal, a writing function stayed open to the world.
--
-- Measured 2026-07-31 (re-run the queries in the issue; do not recite these findings):
--   * The family query in the issue returns 9, not the 3 its title guessed.
--   * The broader invariant (SECDEF + writes + no caller gate + anon/PUBLIC EXECUTE) returns
--     14 non-trigger functions.
--   * Confirmed by probe, not inferred: an anonymous POST to /rest/v1/rpc/record_milestone
--     returned HTTP 204. It wrote nothing only because the probe passed NULL, which the body
--     early-returns on.
--
-- Two classification traps this sweep had to survive, both of which produce a wrong verdict:
--   1. can_by_member() in the body is NOT necessarily a caller gate. In detect_recurrence_
--      stockout_cron and detect_credly_unmapped_cron it selects WHO RECEIVES the notification.
--      Both are in fact ungated.
--   2. Trigger-returning functions carry ACLs but are not reachable through PostgREST, so
--      including them inflates the finding from 14 to 68.
--
-- Safety argument for every REVOKE below: when a SECURITY DEFINER function calls another
-- function, EXECUTE is checked as the OWNER, not as the original caller. Verified that all
-- in-database callers of these targets are themselves SECURITY DEFINER (0 SECURITY INVOKER
-- callers), and that every out-of-database caller uses the service_role key.
--
-- Refs #1551, #1543, #1548

-- ---------------------------------------------------------------------------
-- A. Ungated writers with no client caller — close to service_role only.
--    Callers: other SECDEF functions, pg_cron (runs as postgres), or a service_role client.
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public._compute_pert_cutoff_core(p_cycle_id uuid, p_role text, p_filter_active_only boolean, p_score_column text, p_actor_id uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._compute_pert_cutoff_core(p_cycle_id uuid, p_role text, p_filter_active_only boolean, p_score_column text, p_actor_id uuid) TO service_role;

REVOKE ALL ON FUNCTION public._enqueue_engagement_welcome(p_engagement_id uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._enqueue_engagement_welcome(p_engagement_id uuid) TO service_role;

REVOKE ALL ON FUNCTION public._log_gate_attempt(p_application_id uuid, p_rpc_name text, p_caller_id uuid, p_gate_passed boolean, p_gate_failed_code text, p_gate_failed_reason text, p_bypass_requested boolean, p_bypass_granted boolean, p_payload jsonb, p_organization_id uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._log_gate_attempt(p_application_id uuid, p_rpc_name text, p_caller_id uuid, p_gate_passed boolean, p_gate_failed_code text, p_gate_failed_reason text, p_bypass_requested boolean, p_bypass_granted boolean, p_payload jsonb, p_organization_id uuid) TO service_role;

REVOKE ALL ON FUNCTION public._recompute_application_pert(p_application_id uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._recompute_application_pert(p_application_id uuid) TO service_role;

REVOKE ALL ON FUNCTION public._refresh_preview_gate_eligibles_for_member(p_member_id uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._refresh_preview_gate_eligibles_for_member(p_member_id uuid) TO service_role;

REVOKE ALL ON FUNCTION public._sync_interview_to_event(p_interview_id uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._sync_interview_to_event(p_interview_id uuid) TO service_role;

-- Scheduled as cron job "recompute-pert-cutoffs-weekly", which runs as postgres.
REVOKE ALL ON FUNCTION public.recompute_all_active_pert_cutoffs() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.recompute_all_active_pert_cutoffs() TO service_role;

-- The probe target: anonymous EXECUTE was confirmed live before this migration.
REVOKE ALL ON FUNCTION public.record_milestone(p_member_id uuid, p_milestone_key text, p_source_type text, p_source_id uuid, p_metadata jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_milestone(p_member_id uuid, p_milestone_key text, p_source_type text, p_source_id uuid, p_metadata jsonb) TO service_role;

-- Called by the pmi-vep-sync Cloudflare worker, which builds its client with the
-- service_role key (cloudflare-workers/pmi-vep-sync/src/db.ts).
REVOKE ALL ON FUNCTION public.log_cron_run_start(p_worker_name text, p_scheduled_for timestamp with time zone, p_metrics jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.log_cron_run_start(p_worker_name text, p_scheduled_for timestamp with time zone, p_metrics jsonb) TO service_role;

REVOKE ALL ON FUNCTION public.log_cron_run_complete(p_run_id uuid, p_status text, p_metrics jsonb, p_errors jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.log_cron_run_complete(p_run_id uuid, p_status text, p_metrics jsonb, p_errors jsonb) TO service_role;

-- The three ungated cron detectors. detect_recurrence_stockout_cron is the one the issue
-- found; the other two share its shape and were surfaced by the sweep.
REVOKE ALL ON FUNCTION public.detect_credly_unmapped_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.detect_credly_unmapped_cron() TO service_role;

REVOKE ALL ON FUNCTION public.detect_recurrence_stockout_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.detect_recurrence_stockout_cron() TO service_role;

-- Called by the send-weekly-member-digest edge function, which uses the service_role key.
-- Any authenticated member could previously generate the digest batch for every active member.
REVOKE ALL ON FUNCTION public.generate_weekly_member_digest_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.generate_weekly_member_digest_cron() TO service_role;

-- ---------------------------------------------------------------------------
-- B. Properly gated admin RPCs (auth.uid() + can_by_member + RAISE) that also carried a
--    PUBLIC/anon grant. The gate already fails closed for an anonymous caller, so this is
--    defence in depth: PUBLIC is broader than any caller needs, and it covers roles that do
--    not exist yet. authenticated is KEPT because these are reached from the admin UI and
--    from the MCP edge function, whose client is built with the anon key plus the caller JWT.
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.detect_and_notify_detractors() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.detect_and_notify_detractors() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.detect_operational_alerts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.detect_operational_alerts() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.generate_agenda_template(p_tribe_id integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_agenda_template(p_tribe_id integer) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- C. Public-by-design counters. anon EXECUTE is the point (they are called from the public
--    blog and publications pages), so it is granted explicitly instead of being inherited
--    from PUBLIC. Same reachability, narrower grantee set.
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.increment_blog_view(p_slug text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_blog_view(p_slug text) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.increment_publication_view(p_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_publication_view(p_id uuid) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Deliberately NOT touched, so the reasoning is not re-derived next time:
--
--   log_mcp_usage — the MCP edge function logs through a client built with the anon key plus
--     the caller JWT, and logUsage() swallows its own errors so tool execution never breaks.
--     Revoking would therefore not fail loudly; it would silently stop the audit trail. It
--     does accept a caller-supplied p_member_id, which is a spoofing surface, but the fix is
--     a derivation inside the body, not an ACL change. Tracked as a follow-up.
--
--   capture_visitor_lead — public lead form on three marketing sections. anon is the point,
--     and its ACL carries no PUBLIC grant.
--
--   detect_inactive_members / detect_onboarding_overdue / generate_institutional_export_manifest
--     — real caller gates, and their ACLs already carry neither anon nor PUBLIC.
-- ---------------------------------------------------------------------------
