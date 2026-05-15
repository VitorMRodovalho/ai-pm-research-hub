-- p163 (post p162 Track E) — A3 invariant backfill
-- Refs: handoff_p163 item #22, ADR-0007, ADR-0080
--
-- Track E (p162) extended sync_operational_role_cache CASE chain to cover 5 V4 kinds
-- (study_group_owner, committee_member, committee_coordinator, workgroup_member, workgroup_coordinator).
-- Trigger fires only on engagement INSERT/UPDATE/DELETE — existing rows whose
-- engagements weren't touched stayed stale. A3 invariant detected 6 mems with drift.
--
-- 6 affected:
--   Sarah Faria          observer → tribe_leader  (committee/workgroup engagement now mapped)
--   Roberto Macêdo       observer → tribe_leader  (same)
--   Fabricio Costa       tribe_leader → manager   (volunteer manager engagement was already there; trigger missed re-eval)
--   Leticia Clemente     researcher → tribe_leader
--   Maria Luiza          researcher → tribe_leader
--   Mayanna Duarte       researcher → tribe_leader
--
-- Excluded: Eder Valasco (no authoritative engagement at all — institutional placeholder; PM TBD).
-- Approach: replicate trigger CASE chain via SELECT, UPDATE only mems whose computed value differs
-- AND who have ≥1 authoritative engagement (Eder-class is filtered out).
-- Audit: row inserted in admin_audit_log per change.
--
-- Rollback: hold prior values from members.updated_at history (none — UPDATE preserves no log
-- beyond the audit_log row created here). Manual revert: UPDATE members SET operational_role = '<prior>'
-- per the audit changes.metadata.from value.

WITH expected AS (
  SELECT
    m.id AS member_id,
    m.name,
    m.operational_role AS cur_role,
    CASE
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
      WHEN bool_or(
        (ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader'))
        OR (ae.kind IN ('study_group_owner','committee_coordinator','workgroup_coordinator')
            AND ae.role IN ('leader','co_leader','owner','coordinator'))
        OR (ae.kind IN ('committee_member','workgroup_member')
            AND ae.role IN ('leader','coordinator'))
      ) THEN 'tribe_leader'
      WHEN bool_or(
        (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
        OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
            AND ae.role IN ('researcher','contributor','member','participant'))
      ) THEN 'researcher'
      WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
      WHEN bool_or(ae.kind = 'observer') THEN 'observer'
      WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
      WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
      WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
      WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
      ELSE 'guest'
    END AS expected_role
  FROM public.members m
  JOIN public.auth_engagements ae ON ae.person_id = m.person_id AND ae.is_authoritative = true
  GROUP BY m.id, m.name, m.operational_role
),
to_update AS (
  SELECT member_id, name, cur_role, expected_role
  FROM expected
  WHERE cur_role IS DISTINCT FROM expected_role
),
audit_inserts AS (
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  SELECT
    NULL,
    'member.operational_role_backfill',
    'member',
    member_id,
    jsonb_build_object('from', cur_role, 'to', expected_role),
    jsonb_build_object(
      'source', 'p163_a3_backfill_post_p162_track_e',
      'reason', 'sync_operational_role_cache trigger CASE chain extended in 20260652; existing rows needed re-evaluation',
      'name_for_audit', name
    )
  FROM to_update
  RETURNING target_id
),
applied AS (
  UPDATE public.members m
  SET operational_role = e.expected_role,
      updated_at = now()
  FROM to_update e
  WHERE m.id = e.member_id
  RETURNING m.id, m.name, m.operational_role
)
SELECT 'backfill_summary' AS marker, count(*) AS rows_updated FROM applied;
