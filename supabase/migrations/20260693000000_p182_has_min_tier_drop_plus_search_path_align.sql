-- ============================================================================
-- p182 ADR-0011 V4 sweep closure: DROP has_min_tier + exec_cert_timeline search_path align
-- ============================================================================
-- Scope:
--   1. DROP FUNCTION public.has_min_tier(integer)
--   2. CREATE OR REPLACE exec_cert_timeline with aligned search_path
--      ('public', 'pg_temp' — drops 'extensions' since body uses no pgcrypto/extensions
--      functions; aligned with has_min_tier convention).
--
-- Rationale (handoff p182 TIER A):
--   - p181 migrated all 4 live callers (3 RLS policies + exec_cert_timeline) off
--     has_min_tier. Body was marked DEPRECATED via COMMENT, DROP scheduled p182+.
--   - Verified at p182 boot: pg_policies callers = 0; pg_proc body references = 1
--     (exec_cert_timeline comment line only — historical breadcrumb, not a runtime call).
--   - No CASCADE needed (no real dependencies).
--   - database.gen.ts will regenerate cleanly on next type sync (typed signature
--     auto-derived from pg_proc).
--
-- Pre-2026-04-24 file references — superseded by V4 sweep chain (code-reviewer
-- MEDIUM finding p181 + platform-guardian MEDIUM finding p182):
--   - `20260308002252_comms_metrics_v1.sql` (lines 54-76) — comms_metrics_daily
--     policies. Superseded by `20260427030000` + `20260514200000`.
--   - `20260308003330_comms_metrics_v2_ingestion.sql` (lines 36-37) —
--     can_manage_comms_metrics() dynamic-dispatch fallback `to_regprocedure
--     ('public.has_min_tier(integer)')` IS NOT NULL guard + `has_min_tier(4)`
--     call. Superseded by `20260515040000_phase_b_batch14_can_manage_comms
--     _metrics_sync_points_v4.sql` (pure V4 `can_by_member('manage_comms')`,
--     no has_min_tier reference). The to_regprocedure pattern is a soft
--     fallback — even with old body active, DROP causes regprocedure to
--     return NULL and the fallback branch executes safely.
--   - `20260309100000_broadcast_log.sql` (line 56) — broadcast_log policy.
--     Superseded by `20260427030000` + `20260428010000` + `20260514460000`.
--   - `20260309080000_members_rls_and_public_view.sql` (lines 35, 65-66, 72) —
--     members RLS policies. Superseded by V4 phase 4 migration chain.
-- Confirmed clean via pg_policies query at p181 close + p182 boot + p182 mid-sweep council.
--
-- Sediment applied:
--   - apply_migration via MCP DOES NOT auto-register; manual repair required.
--   - DROP migration body is small + idempotent (IF EXISTS).
--   - Body-drift parser captures CREATE OR REPLACE FUNCTION for exec_cert_timeline
--     here as the new latest capture — drift count net 0.
--
-- Rollback:
--   - Recreate has_min_tier body per `20260692000000` (p181 version with V4 mapping).
--   - Revert exec_cert_timeline search_path to 'public', 'extensions'.
-- ============================================================================

-- 1. DROP has_min_tier (idempotent — IF EXISTS protects against re-run)
DROP FUNCTION IF EXISTS public.has_min_tier(integer);

-- 2. CREATE OR REPLACE exec_cert_timeline with aligned search_path
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

NOTIFY pgrst, 'reload schema';
