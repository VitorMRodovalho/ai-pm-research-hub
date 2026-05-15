-- p163 — REVERT of 20260657 A3 backfill
-- Refs: PM feedback 2026-05-15 — autonomous A3 backfill flagged
--   "estou achando frágil as decisões aqui — preciso de uma auditoria"
--
-- The 20260657 backfill promoted 6 mems to operational_role values derived
-- from the V4 priority ladder (sync_operational_role_cache). The ladder is
-- GLOBAL and "highest engagement wins" — it does not respect SCOPE. PM
-- raised 4 concrete concerns:
--   1. Sarah/Roberto are CURADORES (designation), not tribe leaders. Promoting
--      operational_role to tribe_leader because of a committee/workgroup
--      engagement gives them tribe-leader-tier UI access that does not match
--      their actual functional role.
--   2. Fabricio is vice-GP AND tribe leader. Promoting from tribe_leader to
--      manager (volunteer.manager engagement) may strip tribe-scoped privileges
--      that are wired off `operational_role = tribe_leader` (V3 paths still
--      live in the codebase).
--   3. Mayanna leads the Time de Comunicação INITIATIVE but is researcher in
--      her tribe. Promoting to operational_role = tribe_leader (global) gives
--      privileges in tribe contexts where she is not a leader.
--   4. Maria Luiza/Leticia are members of Time de Comunicação initiative;
--      same scope-leak risk.
--
-- Restoring prior values from admin_audit_log (changes.from). Audit row
-- inserted to keep the lifecycle visible.
--
-- Path forward (next session): per-mem analysis with PM. Possible outcomes:
--   (a) Restore selectively for cases where promotion truly aligns with role.
--   (b) Refine sync_operational_role_cache trigger to weight scope (e.g. only
--       'volunteer' kind feeds the global ladder; initiative-scoped kinds
--       contribute to can() but not the cache).
--   (c) Decouple UI gating from operational_role (use can() with explicit
--       scope at every gate).
--
-- Drift after this revert: A3 returns to 7 (the same state pre-20260657).

WITH last_change AS (
  SELECT DISTINCT ON (target_id)
    target_id AS member_id,
    changes->>'from' AS old_role,
    changes->>'to'   AS expected_now
  FROM public.admin_audit_log
  WHERE action = 'member.operational_role_backfill'
    AND metadata->>'source' = 'p163_a3_backfill_post_p162_track_e'
  ORDER BY target_id, created_at DESC
),
to_revert AS (
  SELECT lc.member_id, lc.old_role, m.operational_role AS cur_role
  FROM last_change lc
  JOIN public.members m ON m.id = lc.member_id
  WHERE m.operational_role = lc.expected_now  -- only revert if still in the post-backfill state
),
audit_inserts AS (
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  SELECT
    NULL,
    'member.operational_role_backfill_revert',
    'member',
    member_id,
    jsonb_build_object('from', cur_role, 'to', old_role),
    jsonb_build_object(
      'source', 'p163_revert_pending_pm_audit',
      'reason', 'PM flagged scope-leak risk (curador vs tribe_leader, initiative leader vs tribe leader, vice-GP cache stripping). Pending detailed audit before any re-application.'
    )
  FROM to_revert
  RETURNING target_id
),
applied AS (
  UPDATE public.members m
  SET operational_role = r.old_role,
      updated_at = now()
  FROM to_revert r
  WHERE m.id = r.member_id
  RETURNING m.id, m.name, m.operational_role
)
SELECT 'revert_summary' AS marker, count(*) AS rows_reverted FROM applied;
