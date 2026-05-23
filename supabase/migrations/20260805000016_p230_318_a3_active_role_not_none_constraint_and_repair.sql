-- p230 #318 — A3 invariant defense-in-depth + Herlon cache repair
--
-- Context
--   Issue #318: PR #317 CI ratchet revealed A3 violation
--     (member_status='active' AND operational_role='none')
--     for Herlon Alves de Sousa (c8e76355-6004-4dab-af84-a5c4f525ae9a).
--   ARM-9 (detect_inactive_members) was suspected because of timing
--   proximity (18s before the row's updated_at), but auditing all 7
--   public functions that write members.operational_role + every BEFORE
--   trigger on members showed that none of them produce literal 'none'
--   on an active member atomically: admin_offboard_member sets 'none'
--   only when also flipping member_status to 'inactive'; sync_member_status_consistency
--   only coerces toward 'observer'/'alumni'; sync_operational_role_cache's
--   ladder ELSE branch is 'guest', never 'none'.
--
--   The 2026-05-23 18:07:55 mutation that produced (active + 'none')
--   left no admin_audit_log entry, so the writer was either a direct
--   service-role UPDATE via execute_sql OR a call to the unaudited
--   admin_update_member RPC with p_operational_role='none'. Either way,
--   the system has no defense-in-depth against this state today.
--
-- Decision (PM-directed)
--   Add a CHECK constraint at the schema level that rejects
--   (active + 'none') so that no future writer — RPC, EF, manual UPDATE,
--   ARM-9 extension — can create the state again. The A3 invariant
--   already detects this drift in check_schema_invariants() and the
--   check-invariants CI ratchet hard-fails on it; the new CHECK makes
--   the same rule load-bearing at write time.
--
--   Repair Herlon's row using the V4 canonical cache ladder (which
--   computes 'observer' from his authoritative engagements: active
--   observer + active ambassador, study_group_owner already offboarded
--   2026-04-15). The repair must precede the ALTER TABLE so the constraint
--   passes initial validation.
--
-- Rollback
--   1. ALTER TABLE public.members DROP CONSTRAINT chk_a3_active_role_not_none;
--   2. There is no inverse for the Herlon repair — the audit row inserted
--      here documents the old/new values for forensic purposes.
--
-- Cross-ref
--   - .claude/rules/database.md GC-097
--   - check_schema_invariants() invariant A3
--   - sync_operational_role_cache() — canonical V4 ladder source of truth
--   - ADR-0007 — can() / engagement-derived authority

BEGIN;

-- Step 1 — Repair every (active + 'none') member via the V4 cache ladder.
-- Today only Herlon matches, but the WHERE clause is general so that any
-- straggler discovered between audit and apply is also corrected.
WITH derived AS (
  SELECT
    m.id AS member_id,
    COALESCE(
      (SELECT CASE
          WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
          WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
          WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
          WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
          WHEN bool_or(
            (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
            OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
                AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
            OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
                AND ae.role IN ('leader','co_leader','owner','coordinator'))
          ) THEN 'researcher'
          WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
          WHEN bool_or(ae.kind = 'observer') THEN 'observer'
          WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
          WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
          WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
          WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
          ELSE 'guest'
        END
       FROM public.auth_engagements ae
       WHERE ae.person_id = m.person_id AND ae.is_authoritative = true),
      'guest'
    ) AS new_role
  FROM public.members m
  WHERE m.member_status = 'active' AND m.operational_role = 'none'
)
INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
SELECT
  NULL,
  'member.operational_role_a3_repair',
  'member',
  d.member_id,
  jsonb_build_object(
    'field', 'operational_role',
    'old_value', 'none',
    'new_value', d.new_role,
    'effective_date', CURRENT_DATE
  ),
  jsonb_build_object(
    'source', 'p230_318_a3_defense_in_depth',
    'reason', 'derived via V4 cache trigger ladder; (active + none) violates A3 invariant',
    'migration', '20260805000016'
  )
FROM derived d;

UPDATE public.members m
SET operational_role = d.new_role,
    updated_at = now()
FROM (
  SELECT
    m2.id AS member_id,
    COALESCE(
      (SELECT CASE
          WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
          WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
          WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
          WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
          WHEN bool_or(
            (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
            OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
                AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
            OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
                AND ae.role IN ('leader','co_leader','owner','coordinator'))
          ) THEN 'researcher'
          WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
          WHEN bool_or(ae.kind = 'observer') THEN 'observer'
          WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
          WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
          WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
          WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
          ELSE 'guest'
        END
       FROM public.auth_engagements ae
       WHERE ae.person_id = m2.person_id AND ae.is_authoritative = true),
      'guest'
    ) AS new_role
  FROM public.members m2
  WHERE m2.member_status = 'active' AND m2.operational_role = 'none'
) d
WHERE m.id = d.member_id;

-- Step 2 — Schema-level defense-in-depth.
-- Any write path that attempts (active + 'none') now fails immediately
-- with constraint violation 23514 instead of producing A3 drift detected
-- only by check_schema_invariants() at audit time.
ALTER TABLE public.members
  ADD CONSTRAINT chk_a3_active_role_not_none
  CHECK (NOT (member_status = 'active' AND operational_role = 'none'));

COMMIT;

NOTIFY pgrst, 'reload schema';
