-- ============================================================================
-- #472 correction #1 — WEBHOOK MIRROR (production-effect follow-up)
-- ----------------------------------------------------------------------------
-- Context: corr-1 (migration 20260805000091) hardened the canonical SQL surface
-- sync_calendar_booking_to_interview, but that RPC is the OLD issue-#116 path
-- (only referenced by generated types). The LIVE booking ingress is the Astro
-- route src/pages/api/calendar-webhook.ts (header-auth). So the matching upgrade
-- only reaches production once the webhook uses it.
--
-- This migration adds a small READ-ONLY matcher that the webhook calls, so the
-- candidate-resolution semantics live in ONE faithful place (mirrors corr-1's
-- WHERE/ORDER BY) instead of being re-implemented in TS — where they would be
-- both duplicated AND subtly wrong: selection_applications.email is `text`
-- (not citext), so the webhook's prior `.ilike('email', guest)` treated `_`/`%`
-- as wildcards (e.g. the real candidate `j_coelho@id.uff.br` — the `_` matched
-- any char) and was case-sensitive only by accident of ILIKE. The matcher uses
-- LOWER(TRIM(a.email)) = guest (exact, case-insensitive) like the RPC.
--
-- What it mirrors from corr-1 (20260805000091):
--   • OPEN/ACTIVE cycle scope (the webhook had NO cycle filter → could attach a
--     booking to a closed-cycle application).
--   • PRIMARY email match OR same-member ALTERNATE (member_emails bridge) — the
--     bridge requires the SAME member_id on both sides, so there is zero
--     cross-candidate risk; the direct primary match is always preferred.
--   • tie-break: primary > most-recently-opened cycle > newest application.
-- What it KEEPS from the webhook (not the RPC): the pre-interview status
--   allow-list, so a booking never re-opens an already-decided/terminal app.
--
-- NOTE: this is intentional, minimal duplication of the corr-1 match shape (the
-- RPC also INSERTs + promotes + audits, so it is not a drop-in read). The
-- contract test p472-corr1-webhook-matcher asserts the matcher and the webhook
-- stay aligned (same email semantics + member_emails bridge), the same
-- ladder-parity pattern used for the worker↔migration alignment in corr-2.
--
-- ROLLBACK: DROP FUNCTION public.match_booking_application(text);
--           (read-only, no data effect; the webhook would need to revert too.)
--           The sync_calendar_booking_to_interview grant lockdown below is
--           defense-in-depth; to revert: GRANT EXECUTE ... TO anon, authenticated.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.match_booking_application(p_guest_email text)
RETURNS TABLE (
  application_id   uuid,
  applicant_name   text,
  app_status       text,
  interview_status text,
  cycle_id         uuid,
  matched_by       text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_guest text;
  v_guest_member_id uuid;
BEGIN
  v_guest := NULLIF(LOWER(TRIM(p_guest_email)), '');
  IF v_guest IS NULL THEN
    RETURN;  -- empty set
  END IF;

  -- alternate-email bridge: resolve the guest email to a member (if any). A
  -- candidate is usually not a member, so this is NULL in the common case; it
  -- only helps a member-candidate whose calendar invite carries a different
  -- email than the application (same member_id required on both sides).
  SELECT me.member_id INTO v_guest_member_id
  FROM public.member_emails me
  WHERE me.email = v_guest::citext
  LIMIT 1;

  RETURN QUERY
  SELECT a.id,
         a.applicant_name,
         a.status,
         a.interview_status,
         a.cycle_id,
         (CASE WHEN LOWER(TRIM(a.email)) = v_guest THEN 'primary' ELSE 'alternate' END)::text
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE c.status IN ('open', 'active')
    -- pre-interview allow-list (kept from the webhook): never re-opens a
    -- decided/terminal app. NOTE: the corr-1 RPC's promotion guard also lists
    -- 'in_review', but that status is PHANTOM — it appears in neither the live
    -- status census nor the canonical V4 ladder (migration 20260805000090), so it
    -- is intentionally omitted here (verified live: 0 applications in_review).
    AND a.status IN ('submitted', 'screening', 'objective_eval', 'objective_cutoff',
                     'interview_pending', 'interview_scheduled')
    AND (
      LOWER(TRIM(a.email)) = v_guest
      OR (
        v_guest_member_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.member_emails me2
          WHERE me2.member_id = v_guest_member_id
            AND me2.email = LOWER(TRIM(a.email))::citext
        )
      )
    )
  ORDER BY (LOWER(TRIM(a.email)) = v_guest) DESC,
           c.open_date DESC NULLS LAST,
           a.created_at DESC
  LIMIT 1;
END;
$function$;

-- internal webhook helper: the live ingress calls it with the service_role key.
-- SERVICE_ROLE ONLY — it is SECURITY DEFINER and returns applicant_name + status
-- for any supplied email (bypassing RLS), so granting it to `authenticated` would
-- let any logged-in member enumerate candidate PII by guessing emails (LGPD Art.
-- 18). The DB-gated contract probes use the service-role key, so no `authenticated`
-- grant is needed.
REVOKE ALL ON FUNCTION public.match_booking_application(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.match_booking_application(text) TO service_role;

-- Defense-in-depth (corr-1 follow-up): the canonical RPC sync_calendar_booking_to_interview
-- inherited a GRANT TO anon, authenticated from its issue-#116 origin migration
-- (20260516920000) — corr-1 (20260805000091) used CREATE OR REPLACE without a grant
-- block, so the broad grant survived. The shared-secret-in-payload was the only gate.
-- It is the DEAD path now (zero SQL/route callers — the live ingress is the webhook),
-- so lock it to service_role like the matcher. No behavioural change for the webhook.
REVOKE ALL ON FUNCTION public.sync_calendar_booking_to_interview(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sync_calendar_booking_to_interview(jsonb) TO service_role;

NOTIFY pgrst, 'reload schema';
