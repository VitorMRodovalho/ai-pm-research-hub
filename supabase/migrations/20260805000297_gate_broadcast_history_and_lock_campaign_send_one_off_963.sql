-- #963 comms-class hardening — two confirmed holes found in the completeness sweep that
-- followed the #961/#964 fixes (the "sweep the whole class after fixing one" lesson, [LL] #588).
--
-- (1) broadcast_history(): SECURITY DEFINER reader, EXECUTE to `authenticated`, NO gate.
--     Returned broadcast subject / recipient_count / sender_name / tribe — comms-ops data
--     readable by any logged-in member. Now gated behind can_view_comms_analytics() (same
--     model as #961/#883/#964). Denied → empty set. The only caller (comms-ops.astro) is
--     already comms-tier, so non-regressive. Converted sql→plpgsql for an explicit early gate.
--
-- (2) campaign_send_one_off(): SECURITY DEFINER email sender, EXECUTE to PUBLIC/anon/
--     authenticated — the Postgres CREATE-default PUBLIC grant that the original migration
--     20260516200000 never revoked (it only added an explicit service_role grant). The caller
--     controls p_to_email + template variables, so any anon/authenticated user could send an
--     org-template email to an arbitrary address, attributed to a GP-tier member, bypassing
--     admin_send_campaign's rate-limit (open-relay / phishing using the org's sender
--     reputation). Fix: revoke the broad grant, restoring the original service-role-only
--     intent. Verified safe: all 11 DB callers (notify_selection_cutoff_approved,
--     dispatch_pending_welcomes, process_pending_*, request_interview_reschedule,
--     mark_interview_status, recirculate_governance_doc, dispatch_consent_nudge, …) are
--     SECURITY DEFINER — the nested PERFORM runs as owner=postgres, not the request role — and
--     the pmi-vep-sync Cloudflare Worker calls with SUPABASE_SERVICE_ROLE_KEY.
--
-- Two-sided live verification (2026-06-29, prod):
--   broadcast_history:
--     * Leticia Clemente (comms_member)      → comms_gate=true,  26/26 broadcasts visible
--     * Gerson Albuquerque Neto (no desig)   → comms_gate=false, 0 rows (was leaking all 26)
--   campaign_send_one_off EXECUTE grants after revoke → {postgres, service_role} only.
--
-- The in-body RPC gate is the boundary (ADR-0106). A broader systemic finding — other
-- service-role-only SECDEF functions still carrying the default PUBLIC EXECUTE grant
-- (process_pending_email_queue, analyze_application_video_async, request_application_enrichment,
-- retry_pending_ai_analyses/_triages, internal _* helpers) — is filed separately for a
-- dedicated per-function audit (NOT a mechanical mass-revoke: many anon-by-design token/lead
-- RPCs legitimately carry the grant).

-- (1) broadcast_history: add can_view_comms_analytics() gate ----------------------------------
CREATE OR REPLACE FUNCTION public.broadcast_history(p_tribe_id integer DEFAULT NULL::integer, p_limit integer DEFAULT 50)
 RETURNS TABLE(id uuid, tribe_id integer, tribe_name text, subject text, recipient_count integer, sent_at timestamp with time zone, sent_by_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- #963: broadcast subjects + recipient counts + sender are comms-ops data — restrict to
  -- the comms-analytics tier (comms team / managers / governance). Denied → empty set.
  IF NOT public.can_view_comms_analytics() THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    bl.id,
    i.legacy_tribe_id AS tribe_id,
    i.title AS tribe_name,
    bl.subject,
    bl.recipient_count,
    bl.sent_at,
    m.name AS sent_by_name
  FROM public.broadcast_log bl
  LEFT JOIN public.initiatives i ON i.id = bl.initiative_id
  LEFT JOIN public.members m ON m.id = bl.sender_id
  WHERE (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
  ORDER BY bl.sent_at DESC
  LIMIT p_limit;
END;
$function$
;

-- (2) campaign_send_one_off: revoke the accidental broad EXECUTE (service-role-only intent) ---
REVOKE EXECUTE ON FUNCTION public.campaign_send_one_off(text, text, jsonb, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.campaign_send_one_off(text, text, jsonb, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.campaign_send_one_off(text, text, jsonb, jsonb) FROM authenticated;
