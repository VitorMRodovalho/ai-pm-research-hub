-- ADR-0053: auth_rls_initplan perf fix — batch 1 (#82 P1 deferred)
--
-- Postgres planner can cache `(SELECT auth.uid())` as an InitPlan once per
-- query, but bare `auth.uid()` is re-evaluated per row. Supabase advisor
-- flags this as `auth_rls_initplan` WARN.
--
-- Fix is mechanical: wrap auth.uid() / auth.role() / auth.jwt() in
-- `(SELECT ...)`. Semantically identical, but planner caches it.
--
-- Batch 1 scope: 13 simple `(auth.uid() = column)` patterns across 7 tables.
-- These are user-owned record self-management policies — uniformly simple
-- structure with low risk. Future batches (ADR-0054+) will tackle more
-- complex policies (multi-clause OR/AND, subqueries, etc.).
--
-- All policies are PERMISSIVE; rewrite preserves exact semantic. Each
-- policy is DROP'd + re-CREATE'd with the wrapped expression.
--
-- Pattern transformation:
--   `(auth.uid() = user_id)` → `((SELECT auth.uid()) = user_id)`
--
-- Out of scope (deferred to ADR-0054+):
--   * Policies with subquery EXISTS containing auth.uid() (need surgical care)
--   * Policies with OR clauses mixing auth.uid() and rls_can() (composition risk)
--   * Multi-condition WITH CHECK clauses

-- =====================================================================
-- analysis_results (2)
-- =====================================================================

DROP POLICY IF EXISTS "Users can insert own analyses" ON public.analysis_results;
CREATE POLICY "Users can insert own analyses" ON public.analysis_results
  FOR INSERT TO public
  WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can view own analyses" ON public.analysis_results;
CREATE POLICY "Users can view own analyses" ON public.analysis_results
  FOR SELECT TO public
  USING ((SELECT auth.uid()) = user_id);

-- =====================================================================
-- comparison_results (2)
-- =====================================================================

DROP POLICY IF EXISTS "Users can insert own comparisons" ON public.comparison_results;
CREATE POLICY "Users can insert own comparisons" ON public.comparison_results
  FOR INSERT TO public
  WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can view own comparisons" ON public.comparison_results;
CREATE POLICY "Users can view own comparisons" ON public.comparison_results
  FOR SELECT TO public
  USING ((SELECT auth.uid()) = user_id);

-- =====================================================================
-- evm_analyses (2)
-- =====================================================================

DROP POLICY IF EXISTS "Users can insert own EVM analyses" ON public.evm_analyses;
CREATE POLICY "Users can insert own EVM analyses" ON public.evm_analyses
  FOR INSERT TO public
  WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can view own EVM analyses" ON public.evm_analyses;
CREATE POLICY "Users can view own EVM analyses" ON public.evm_analyses
  FOR SELECT TO public
  USING ((SELECT auth.uid()) = user_id);

-- =====================================================================
-- member_activity_sessions (1) — uses subquery; preserve full structure
-- =====================================================================

DROP POLICY IF EXISTS "Members can insert own sessions" ON public.member_activity_sessions;
CREATE POLICY "Members can insert own sessions" ON public.member_activity_sessions
  FOR INSERT TO public
  WITH CHECK (member_id = (
    SELECT members.id FROM public.members
    WHERE members.auth_id = (SELECT auth.uid())
  ));

-- =====================================================================
-- risk_simulations (2)
-- =====================================================================

DROP POLICY IF EXISTS "Users can insert own risk simulations" ON public.risk_simulations;
CREATE POLICY "Users can insert own risk simulations" ON public.risk_simulations
  FOR INSERT TO public
  WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can view own risk simulations" ON public.risk_simulations;
CREATE POLICY "Users can view own risk simulations" ON public.risk_simulations
  FOR SELECT TO public
  USING ((SELECT auth.uid()) = user_id);

-- =====================================================================
-- tia_analyses (2)
-- =====================================================================

DROP POLICY IF EXISTS "Users can insert own TIA analyses" ON public.tia_analyses;
CREATE POLICY "Users can insert own TIA analyses" ON public.tia_analyses
  FOR INSERT TO public
  WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can view own TIA analyses" ON public.tia_analyses;
CREATE POLICY "Users can view own TIA analyses" ON public.tia_analyses
  FOR SELECT TO public
  USING ((SELECT auth.uid()) = user_id);

-- =====================================================================
-- user_profiles (2)
-- =====================================================================

DROP POLICY IF EXISTS "Users can update own profile" ON public.user_profiles;
CREATE POLICY "Users can update own profile" ON public.user_profiles
  FOR UPDATE TO public
  USING ((SELECT auth.uid()) = id);

DROP POLICY IF EXISTS "Users can view own profile" ON public.user_profiles;
CREATE POLICY "Users can view own profile" ON public.user_profiles
  FOR SELECT TO public
  USING ((SELECT auth.uid()) = id);

-- Reload PostgREST surface (RLS changes affect cache)
NOTIFY pgrst, 'reload schema';

-- =====================================================================
-- Rollback (commented). Restore bare auth.uid() expressions.
-- =====================================================================
-- DROP POLICY ... ON public.<table>;
-- CREATE POLICY ... USING (auth.uid() = column);
-- (per-policy restore needed; see commit history for original definitions)
