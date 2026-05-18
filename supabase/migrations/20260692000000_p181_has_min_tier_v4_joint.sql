-- ============================================================================
-- p181 ADR-0011 V4 sweep: has_min_tier joint migration (5 components)
-- ============================================================================
-- Scope:
--   1. has_min_tier(integer)         — body refactor: rank 4 → can_by_member('manage_platform'); rank 5 → is_superadmin
--   2. RLS announcements_admin_write — swap has_min_tier(4) → rls_can('manage_platform')
--   3. RLS home_schedule_manage      — swap has_min_tier(4) → rls_can('manage_platform')
--   4. RLS mch_superadmin_write      — swap has_min_tier(5) → rls_is_superadmin() (no V4 catalog for rank-5)
--   5. exec_cert_timeline(integer)   — swap has_min_tier(4) → can_by_member('manage_platform')
--
-- Rationale (handoff p181 TIER A):
--   - V4 catalog manage_platform = {manager, deputy_manager, co_gp} on volunteer kind.
--   - V3 has_min_tier(4) surface = {manager, deputy_manager}.
--   - V4 is SUPERSET (+co_gp). Net caller-surface expansion today: 0 (no active co_gp without superadmin).
--   - mch_superadmin_write stays direct via rls_is_superadmin() (no V4 catalog for global superadmin).
--   - has_min_tier deprecated; DROP scheduled p182+ after this sweep validates clean.
--
-- Sediment applied:
--   - apply_migration via MCP DOES NOT auto-register; manual repair required after apply.
--   - Defensive auth gates on public-by-design RPCs are bugs — N/A here (no anon-grant surface).
--   - JWT-simulated smoke pattern: set_config in FROM clause forces CTE evaluation.
--
-- Rollback:
--   - Revert has_min_tier body to V3 rank ladder (manager/deputy_manager/tribe_leader/etc.)
--   - Revert 3 RLS policies to USING (has_min_tier(N)) WITH CHECK (has_min_tier(N))
--   - Revert exec_cert_timeline body to IF NOT has_min_tier(4) THEN RAISE
-- ============================================================================

-- 1. has_min_tier body refactor (CREATE OR REPLACE — signature unchanged)
CREATE OR REPLACE FUNCTION public.has_min_tier(required_rank integer)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_member_id uuid;
  v_is_superadmin boolean := false;
  v_rank integer := 0;
begin
  -- DEPRECATED p181 (ADR-0011 V4 sweep). Callers should migrate to rls_can() / can_by_member()
  -- / rls_is_superadmin() directly. DROP scheduled p182+ after migration validates clean.
  --
  -- V4 mapping:
  --   rank 5 = is_superadmin (no V4 catalog equiv for global superadmin)
  --   rank 4 = can_by_member('manage_platform') — V4 catalog superset of V3 manager+deputy_manager (+co_gp)
  --   ranks 0-3 = no current callers; returns false defensively (forces migration of any forgotten caller)
  SELECT m.id, m.is_superadmin
    INTO v_member_id, v_is_superadmin
  FROM public.members m
  WHERE m.auth_id = auth.uid()
  LIMIT 1;

  IF v_member_id IS NULL THEN
    RETURN false;
  END IF;

  IF v_is_superadmin = true THEN
    v_rank := 5;
  ELSIF public.can_by_member(v_member_id, 'manage_platform', NULL, NULL) THEN
    v_rank := 4;
  ELSE
    v_rank := 0;
  END IF;

  RETURN v_rank >= required_rank;
end;
$function$;

COMMENT ON FUNCTION public.has_min_tier(integer) IS
  'DEPRECATED p181 (ADR-0011 V4 sweep). Use rls_can() / can_by_member() / rls_is_superadmin() directly. DROP scheduled p182+ after sweep validates clean.';

-- 2. RLS announcements_admin_write — V4 swap (manage_platform)
DROP POLICY IF EXISTS announcements_admin_write ON public.announcements;
CREATE POLICY announcements_admin_write ON public.announcements
  FOR ALL
  TO authenticated
  USING (public.rls_can('manage_platform'))
  WITH CHECK (public.rls_can('manage_platform'));

-- 3. RLS home_schedule_manage — V4 swap (manage_platform)
DROP POLICY IF EXISTS home_schedule_manage ON public.home_schedule;
CREATE POLICY home_schedule_manage ON public.home_schedule
  FOR ALL
  TO authenticated
  USING (public.rls_can('manage_platform'))
  WITH CHECK (public.rls_can('manage_platform'));

-- 4. RLS mch_superadmin_write — direct rls_is_superadmin (no V4 catalog for rank-5)
DROP POLICY IF EXISTS mch_superadmin_write ON public.member_cycle_history;
CREATE POLICY mch_superadmin_write ON public.member_cycle_history
  FOR ALL
  TO authenticated
  USING (public.rls_is_superadmin())
  WITH CHECK (public.rls_is_superadmin());

-- 5. exec_cert_timeline body refactor (CREATE OR REPLACE — signature unchanged)
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
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_member_id uuid;
begin
  -- V4 auth gate (ADR-0011 p181 sweep): replaces has_min_tier(4) with can_by_member('manage_platform')
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

-- Reload PostgREST schema cache (idempotent)
NOTIFY pgrst, 'reload schema';
