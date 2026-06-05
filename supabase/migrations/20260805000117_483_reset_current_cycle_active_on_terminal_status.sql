-- #483 — reset members.current_cycle_active=false on terminal member_status
--
-- Bug: offboarding (admin_offboard_member) flips member_status -> alumni/inactive,
-- is_active -> false, operational_role, designations -> '{}' — but NEVER clears
-- current_cycle_active (CCA). The sync_member_status_consistency() BEFORE-trigger
-- coerces is_active / role / designations on the same UPDATE OF member_status,
-- yet also left CCA untouched. Result: 3 offboarded members (Andressa Martins,
-- Maria Luiza, Herlon Alves de Sousa — all offboarded 2026-05-31) carried
-- current_cycle_active=true, contradicting "active in the current cycle" and
-- corrupting every consumer that keys on CCA (e.g. the get_gamification_leaderboard
-- / get_public_leaderboard cohort's `current_cycle_active=true` branch).
--
-- Root cause: CCA is maintained only on the way INTO a cycle
-- (approve_selection_application INSERT, update_onboarding_step SET cca=true).
-- No writer resets it on the way OUT.
--
-- Fix (structural prevention + one-time reconciliation):
--   1) extend the B-trigger to also reset current_cycle_active=false for
--      observer/alumni/inactive — covers ALL paths that touch member_status
--      (offboard RPC, admin update, bulk status change, direct UPDATE OF
--      member_status), since the trigger is BEFORE INSERT OR UPDATE OF
--      member_status,operational_role,is_active,designations.
--   2) one-time DML to clear the rows already drifted (the 3 above).
--
-- NOT in scope (routed to #419/#421 canonical "active now" predicate): the
-- get_gamification_leaderboard / get_public_leaderboard cohort gate keys on
-- (current_cycle_active=true OR EXISTS current-cycle points) with NO is_active
-- filter, so offboarded members WITH current-cycle points still surface. This
-- fix removes them from the current_cycle_active branch; the predicate
-- hardening (add an is_active/member_status guard) belongs in #419/#421.
--
-- Follow-up (deferred): add a B2_current_cycle_active_terminal_status row to
-- check_schema_invariants() for ongoing drift detection (full-function
-- reproduction warrants its own focused change). This migration's contract
-- test (tests/contracts/483-current-cycle-active-terminal-status.test.mjs)
-- provides the equivalent CI-time guarantee in the meantime.
--
-- Rollback: CREATE OR REPLACE the prior body (drop the CCA clause). The DML is
-- not rolled back (it corrects drift; re-drift would require re-offboarding).

CREATE OR REPLACE FUNCTION public.sync_member_status_consistency()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.member_status = 'active' AND NEW.is_active = false THEN NEW.is_active := true; END IF;
  IF NEW.member_status IN ('observer','alumni','inactive') AND NEW.is_active = true THEN NEW.is_active := false; END IF;
  IF NEW.member_status IN ('observer','alumni','inactive') AND NEW.current_cycle_active = true THEN NEW.current_cycle_active := false; END IF;
  IF NEW.member_status = 'alumni' AND NEW.operational_role IS DISTINCT FROM 'alumni' THEN NEW.operational_role := 'alumni'; END IF;
  IF NEW.member_status = 'observer' AND NEW.operational_role NOT IN ('observer','guest','none') THEN NEW.operational_role := 'observer'; END IF;
  IF NEW.member_status IN ('observer','alumni','inactive') AND NEW.designations IS NOT NULL AND array_length(NEW.designations, 1) > 0 THEN NEW.designations := '{}'::text[]; END IF;
  RETURN NEW;
END; $function$;

-- one-time reconciliation of the existing drift (3 rows at migration time)
UPDATE public.members
SET current_cycle_active = false
WHERE member_status IN ('observer','alumni','inactive')
  AND current_cycle_active = true;
