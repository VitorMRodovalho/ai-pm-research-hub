-- #1034 + #1028: DB-level write-time guards for two lifecycle invariants that were only
-- enforced periodically (check_schema_invariants) or in a single SECDEF RPC, leaving
-- direct-REST / alternate paths able to violate them silently.

-- ── #1034: an expired engagement cannot end in the future (invariant Q_expired_engagement_end_date).
-- Whatever path sets status='expired' (manage_initiative_engagement, admin edit, direct REST),
-- clamp a null/future end_date down to today. A legitimate past end_date is preserved (the
-- guard only fires when end_date IS NULL or > CURRENT_DATE). The periodic invariant stays as
-- the backstop.
CREATE OR REPLACE FUNCTION public._trg_clamp_expired_engagement_end_date()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.status = 'expired' AND (NEW.end_date IS NULL OR NEW.end_date > CURRENT_DATE) THEN
    NEW.end_date := CURRENT_DATE;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_clamp_expired_engagement_end_date ON public.engagements;
CREATE TRIGGER trg_clamp_expired_engagement_end_date
  BEFORE INSERT OR UPDATE ON public.engagements
  FOR EACH ROW EXECUTE FUNCTION public._trg_clamp_expired_engagement_end_date();

-- ── #1028-A: member_status='observer' is retired (#1022-C). admin_offboard_member already
-- refuses it, but a caller with manage_member could still write it via direct PostgREST.
-- Reject NEW observer at the data layer. Pre-existing historical rows are grandfathered
-- (an UPDATE of a row that is ALREADY observer is allowed). sync_member_status_consistency
-- only READS observer (never assigns it), so a BEFORE trigger sees the caller's value.
CREATE OR REPLACE FUNCTION public._trg_reject_new_observer_member_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.member_status = 'observer'
     AND (TG_OP = 'INSERT' OR OLD.member_status IS DISTINCT FROM 'observer') THEN
    RAISE EXCEPTION 'member_status=observer is retired (#1022-C / #1028); it is not creatable'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_reject_new_observer_member_status ON public.members;
CREATE TRIGGER trg_reject_new_observer_member_status
  BEFORE INSERT OR UPDATE OF member_status ON public.members
  FOR EACH ROW EXECUTE FUNCTION public._trg_reject_new_observer_member_status();
