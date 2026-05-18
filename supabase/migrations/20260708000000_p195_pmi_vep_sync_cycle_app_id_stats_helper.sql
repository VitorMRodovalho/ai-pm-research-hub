-- ============================================================
-- p195 OPP-196.A: cycle app_id stats helper RPC for Worker heuristic
-- ============================================================
-- WHAT: helper aggregation RPC used by pmi-vep-sync Worker's
-- pickCycleByAppIdSequence() heuristic. Returns per-cycle app_id min/max
-- + sample count for the heuristic to infer the correct cycle when an
-- application lacks an application_date (Active status / historical
-- legacy import).
--
-- WHY: Worker can do client-side aggregation (fallback already implemented)
-- but a server-side RPC is ~5x faster (single indexed query vs full select
-- + JS reduce). Marked SECURITY DEFINER + restricted to service_role only
-- so it's not exposed to anon/authenticated.
--
-- USE CASE: PM p195 follow-up — importing historical cycle 2 candidates
-- now Active in VEP. App_ids predate cycle 3 (268xxx-277xxx). Once at
-- least 1 cycle 2 app is imported, this RPC + pickCycleByAppIdSequence
-- can auto-redirect remaining bulk import to cycle 2 without manual UPDATEs.
--
-- ROLLBACK: DROP FUNCTION public._pmi_vep_sync_cycle_app_id_stats();
--   (Worker falls back to client-side aggregation already implemented.)
-- ============================================================

CREATE OR REPLACE FUNCTION public._pmi_vep_sync_cycle_app_id_stats()
 RETURNS TABLE(
   cycle_id uuid,
   cycle_code text,
   min_app_id int,
   max_app_id int,
   sample_count int
 )
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    sa.cycle_id,
    sc.cycle_code,
    MIN(sa.vep_application_id::int) AS min_app_id,
    MAX(sa.vep_application_id::int) AS max_app_id,
    COUNT(*)::int AS sample_count
  FROM public.selection_applications sa
  JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
  WHERE sa.vep_application_id ~ '^[0-9]+$'  -- defensive: skip non-numeric
  GROUP BY sa.cycle_id, sc.cycle_code;
$function$;

-- service_role only — Worker has service_role key. No anon/authenticated access.
REVOKE EXECUTE ON FUNCTION public._pmi_vep_sync_cycle_app_id_stats() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._pmi_vep_sync_cycle_app_id_stats() TO service_role;
