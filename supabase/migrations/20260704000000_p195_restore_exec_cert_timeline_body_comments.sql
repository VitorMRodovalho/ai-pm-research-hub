-- ============================================================
-- p195 Process Hygiene: restore exec_cert_timeline body comments (drift recovery)
-- ============================================================
-- WHAT: re-apply exec_cert_timeline body verbatim from migration 20260693000000
-- to restore the 2 inline `--` comments missing from live prosrc.
--
-- WHY: Phase C drift audit at p195 close detected exec_cert_timeline as the
-- ONLY remaining DRIFTED DEFINITE entry (1 of 827 live functions). Live prosrc
-- is 752 bytes; migration capture 926 bytes; diff is 2 comment lines:
--   -- V4 auth gate (ADR-0011 p181 sweep + p182 cleanup): can_by_member('manage_platform')
--   -- Body uses only built-in PG functions + public.* — extensions schema not needed.
-- Function logic is identical; only inline doc comments stripped at some
-- prior CREATE OR REPLACE (likely via execute_sql without comment preservation).
--
-- Re-applying the canonical migration body restores parity → ratchets
-- drifted_definite_count from 1 to 0.
--
-- POST-APPLY VALIDATION (verified inline):
--   live prosrc length: 752 → 926 (matches migration capture)
--   Phase C drift audit: drifted_definite_count 1 → 0
--
-- ROLLBACK: not needed — pure comment restoration, zero logic change.
-- ============================================================

CREATE OR REPLACE FUNCTION public.exec_cert_timeline(p_months integer DEFAULT 12)
 RETURNS TABLE(
   cohort_month date,
   members_in_cohort integer,
   members_with_tier2 integer,
   members_with_tier1 integer,
   pct_with_tier2 numeric,
   pct_with_tier1 numeric,
   avg_days_to_tier2 numeric,
   avg_days_to_tier1 numeric
 )
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_member_id uuid;
begin
  -- V4 auth gate (ADR-0011 p181 sweep + p182 cleanup): can_by_member('manage_platform')
  -- Body uses only built-in PG functions + public.* — extensions schema not needed.
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid()
  LIMIT 1;

  IF v_member_id IS NULL OR NOT public.can_by_member(v_member_id, 'manage_platform', NULL, NULL) THEN
    RAISE EXCEPTION 'insufficient_privilege' USING errcode = '42501';
  END IF;

  RETURN QUERY
  SELECT
    v.cohort_month,
    v.members_in_cohort,
    v.members_with_tier2,
    v.members_with_tier1,
    v.pct_with_tier2,
    v.pct_with_tier1,
    v.avg_days_to_tier2,
    v.avg_days_to_tier1
  FROM public.vw_exec_cert_timeline v
  WHERE v.cohort_month >= (
    date_trunc('month', now())::date
    - make_interval(months => greatest(1, least(coalesce(p_months, 12), 60)))
  )
  ORDER BY v.cohort_month DESC;
end;
$function$;
