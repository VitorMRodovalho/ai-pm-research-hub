-- #1109 Guard 1 (wave-9 harvest, LL #588): a trigger function that fires an external
-- dispatch (net.http_post, or PERFORM of a *_dispatch function) INSIDE the primary
-- transaction propagates a vault/pg_net failure into the primary write's rollback —
-- worst case, offboard (which also runs the LGPD Art.18 delete) breaks because the
-- dispatch was down. The correct pattern wraps the dispatch in
--   BEGIN <dispatch> EXCEPTION WHEN OTHERS THEN <log> END
-- so the side-effect fails soft.
--
-- This audit RPC is the live sweep behind the ratchet contract test (1109-...): it
-- returns the identities of public trigger functions whose body dispatches externally
-- WITHOUT an EXCEPTION WHEN OTHERS handler. Names only — no bodies, no PII. A live-body
-- check (not a static migration grep) is deliberate: dropped/superseded captures in old
-- migrations still contain the pattern (e.g. _trg_video_ai_analysis_on_upload, dropped
-- in p207) — only the CURRENT live bodies matter (same rationale as #730).
--
-- Precision note: "has EXCEPTION WHEN OTHERS" is body-presence, not proof the handler
-- wraps the dispatch — so the guard errs toward false-NEGATIVE (a clean function is
-- never flagged), the safe direction for a CI gate. Baseline at ship: 0 offenders.
CREATE OR REPLACE FUNCTION public._audit_trigger_dispatch_without_handler()
 RETURNS TABLE(proname text, identity_args text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p.proname::text, pg_get_function_identity_arguments(p.oid)::text
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prorettype = 'trigger'::regtype
    AND (p.prosrc ~* 'net\.http_post' OR p.prosrc ~* 'perform\s+[a-z_]+_dispatch')
    AND p.prosrc !~* 'exception\s+when\s+others'
  ORDER BY 1;
$function$;

REVOKE ALL ON FUNCTION public._audit_trigger_dispatch_without_handler() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._audit_trigger_dispatch_without_handler() TO service_role;
