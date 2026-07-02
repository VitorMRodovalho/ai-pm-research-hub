-- #1026 Fatia A — event-triggered Drive-teardown detection + positive clean-attestation.
--
-- Behavior-additive over #209 / ADR-0107. Makes DETECTION immediate on offboard (was the weekly cron 63,
-- up-to-7-day lag) and records a positive "verified no Drive access at <scanned_at>" attestation so a member
-- with no queue row is no longer ambiguous (LL#588: absence of a row != confirmed clean).
--
-- The approval model is UNCHANGED: the targeted scan still enqueues pending_revoke rows for manual GP approval
-- (approve_drive_revocation / bulk_approve_drive_revocations) + the hourly drain cron 64. There is NO auto-approve
-- here — that is Fatia B (gated by an ADR-0107 amendment + invariant AL amendment + council). AL-safe: this only
-- creates pending_revoke rows, and only post-commit for members already at offboarded_at IS NOT NULL.

-- ---------------------------------------------------------------------------------------------------------------
-- 1) Targeted variant of get_offboarded_member_emails — resolve the email set for ONE offboarded member.
--    Overload (different arg count) => no DROP; mirrors the no-arg version incl. the pii_access_log write (Art.37).
--    List-reader that writes pii_access_log => VOLATILE (default, matching the sibling).
-- ---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_offboarded_member_emails(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_rows jsonb; v_member_ids uuid[];
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;

  WITH emails AS (
    SELECT m.id AS member_id, lower(m.email) AS email
    FROM public.members m
    WHERE m.id = p_member_id
      AND m.member_status IN ('inactive','alumni') AND m.offboarded_at IS NOT NULL
      AND m.email IS NOT NULL AND m.email <> ''
    UNION
    SELECT me.member_id, lower(me.email::text) AS email
    FROM public.member_emails me
    JOIN public.members m ON m.id = me.member_id
    WHERE m.id = p_member_id
      AND m.member_status IN ('inactive','alumni') AND m.offboarded_at IS NOT NULL
      AND me.email IS NOT NULL
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('member_id', member_id, 'email', email)), '[]'::jsonb),
         coalesce(array_agg(DISTINCT member_id), ARRAY[]::uuid[])
  INTO v_rows, v_member_ids
  FROM emails;

  -- LGPD Art.37: system (event-trigger) read of an ex-member's emails for the targeted Drive scan.
  IF cardinality(v_member_ids) > 0 THEN
    INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason)
    SELECT NULL, mid, ARRAY['email'], 'audit_drive_offboarding_access',
           'event-triggered drive permission scan: offboarded email match set'
    FROM unnest(v_member_ids) AS mid;
  END IF;

  RETURN v_rows;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_offboarded_member_emails(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_offboarded_member_emails(uuid) TO service_role;

-- ---------------------------------------------------------------------------------------------------------------
-- 2) Positive clean-attestation ledger. A row with grants_found=0 is the "verified no Drive access at scanned_at"
--    attestation. Dedicated table (not a column on member_offboarding_records, which is UNIQUE(member_id) and would
--    overwrite history on re-offboard). member_id FK ON DELETE SET NULL preserves LGPD Art.16 scan evidence past
--    member deletion/anonymization (CASCADE would destroy it; RESTRICT would block the anonymization cron).
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.drive_teardown_scans (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id         uuid REFERENCES public.members(id) ON DELETE SET NULL,
  scanned_at        timestamptz NOT NULL DEFAULT now(),
  scan_source       text NOT NULL CHECK (scan_source IN ('event','weekly','manual')),
  emails_scanned    int NOT NULL DEFAULT 0,
  grants_found      int NOT NULL DEFAULT 0,
  deletable_queued  int NOT NULL DEFAULT 0,
  exceptions_found  int NOT NULL DEFAULT 0,
  notes             text,
  created_at        timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.drive_teardown_scans IS '#1026 Fatia A: per-member Drive-teardown scan ledger. grants_found=0 is the positive "verified no Drive access at scanned_at" attestation (LL#588: absence of a queue row != confirmed clean). Multiple rows per member_id are expected (re-offboard + weekly backstop each produce their own row). member_id FK ON DELETE SET NULL preserves LGPD Art.16 scan evidence across member deletion/anonymization.';

CREATE INDEX IF NOT EXISTS drive_teardown_scans_member_idx ON public.drive_teardown_scans (member_id, scanned_at DESC);

ALTER TABLE public.drive_teardown_scans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS drive_teardown_scans_deny_all ON public.drive_teardown_scans;
CREATE POLICY drive_teardown_scans_deny_all ON public.drive_teardown_scans
  AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
REVOKE ALL ON public.drive_teardown_scans FROM anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- 3) Writer RPC — the detection EF calls this ONCE per member_id after scanning that member (targeted or weekly),
--    including grants_found=0 (the clean attestation). Counts only, no PII => no pii_access_log here.
-- ---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_drive_teardown_scan(
  p_member_id uuid,
  p_scan_source text,
  p_emails_scanned int,
  p_grants_found int,
  p_deletable_queued int,
  p_exceptions_found int,
  p_notes text DEFAULT NULL
) RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id uuid;
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;
  IF p_scan_source IS NULL OR p_scan_source NOT IN ('event','weekly','manual') THEN
    RAISE EXCEPTION 'invalid scan_source: %', p_scan_source;
  END IF;
  INSERT INTO public.drive_teardown_scans
    (member_id, scan_source, emails_scanned, grants_found, deletable_queued, exceptions_found, notes)
  VALUES (p_member_id, p_scan_source, coalesce(p_emails_scanned,0), coalesce(p_grants_found,0),
          coalesce(p_deletable_queued,0), coalesce(p_exceptions_found,0), p_notes)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.record_drive_teardown_scan(uuid,text,int,int,int,int,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_drive_teardown_scan(uuid,text,int,int,int,int,text) TO service_role;

-- ---------------------------------------------------------------------------------------------------------------
-- 4) Event-trigger: on offboard, dispatch a TARGETED Drive scan via pg_net (fire-and-forget). The dispatch is
--    isolated in a sub-block so a vault/pg_net failure logs to admin_audit_log and RETURNs — it must NEVER roll
--    back the offboard transaction (that would break the whole member-lifecycle + LGPD Art.18 delete path). cron 63
--    remains the weekly reconciliation backstop. Column-scoped AFTER UPDATE OF member_status avoids double-firing
--    on the secondary operational_role UPDATE that sync_operational_role_cache issues in the same tx.
-- ---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._drive_teardown_enqueue_scan()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_key text;
BEGIN
  BEGIN
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
    IF v_key IS NULL THEN
      RAISE EXCEPTION 'service_role_key not in vault';
    END IF;
    PERFORM net.http_post(
      url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/audit-drive-offboarding-access',
      body := jsonb_build_object('member_id', NEW.id, 'source', 'event'),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_key
      ),
      timeout_milliseconds := 150000
    );
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (NULL, 'drive_teardown_trigger_dispatch_error', 'member', NEW.id,
            jsonb_build_object('error', SQLERRM, 'sqlstate', SQLSTATE));
  END;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._drive_teardown_enqueue_scan() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_drive_teardown_scan ON public.members;
CREATE TRIGGER trg_drive_teardown_scan
  AFTER UPDATE OF member_status ON public.members
  FOR EACH ROW
  WHEN (old.member_status IS DISTINCT FROM new.member_status
        AND new.member_status IN ('alumni','inactive')
        AND new.offboarded_at IS NOT NULL)
  EXECUTE FUNCTION public._drive_teardown_enqueue_scan();

COMMENT ON TRIGGER trg_drive_teardown_scan ON public.members IS '#1026 Fatia A: on offboard (member_status -> alumni/inactive with offboarded_at set), dispatch a targeted Drive-permission scan via pg_net (fire-and-forget, exception-isolated). Covers BOTH admin_offboard_member and _reacceptance_disengage (#976). cron 63 remains the weekly backstop.';

NOTIFY pgrst, 'reload schema';
