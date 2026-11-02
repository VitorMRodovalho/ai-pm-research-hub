-- p163 — A3 backfill SELETIVO post-Opção C
-- Refs: docs/audit/P163_A3_BACKFILL_DECISION_AUDIT.md, ADR-0083
--
-- Após Opção C (capability cache + Tier A/B migration), as gates de UI
-- não dependem mais de operational_role para autoridade — usam canFor
-- scope-aware. Logo, promover Fabricio de tribe_leader para manager é seguro:
--   - Manager TIER_PERMISSIONS é SUPERSET de tribe_leader (não há perda)
--   - Display-only gates (PresentationLayer, tribe/[id] headerLeader) já
--     mitigados (badge inclui manager; headerLeader prefere tribes.leader_member_id)
--   - V4 actions canForAdminEntry, canFor('manage_event'), etc. já passam
--     para Fabricio via volunteer.co_gp engagement (org-scoped)
--
-- Excluídos do backfill (status quo mantido per PM audit):
--   - Sarah/Roberto (curadores): operational_role permanece observer; autoridade
--     de curadoria via designation curator + can() scoped
--   - Mayanna/Maria Luiza/Leticia (workgroup leaders): operational_role permanece
--     researcher; autoridade no Hub Comunicação via canFor scope=initiative
--
-- Audit row inserted distinguished from p163_a3_backfill_post_p162_track_e
-- via metadata.source = 'p163_selective_post_opcao_c'.

WITH target AS (
  SELECT m.id, m.name, m.operational_role AS old_role, 'manager'::text AS new_role
  FROM public.members m
  WHERE m.id = '92d26057-5550-4f15-a3bf-b00eed5f32f9'  -- Fabricio Costa
    AND m.operational_role = 'tribe_leader'
    AND EXISTS (
      SELECT 1 FROM public.auth_engagements ae
      WHERE ae.person_id = m.person_id
        AND ae.is_authoritative = true
        AND ae.kind = 'volunteer'
        AND ae.role = 'co_gp'
    )
),
audit_insert AS (
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  SELECT
    NULL,
    'member.operational_role_backfill',
    'member',
    id,
    jsonb_build_object('from', old_role, 'to', new_role),
    jsonb_build_object(
      'source', 'p163_selective_post_opcao_c',
      'reason', 'Vice-GP via volunteer.co_gp authoritative engagement; promoted from tribe_leader to manager. Manager TIER_PERMISSIONS is superset of tribe_leader. Tier A/B gates migrated (ADR-0083) — no scope-leak introduced. Display-only headerLeader/badge gates updated.',
      'name_for_audit', name
    )
  FROM target
  RETURNING target_id
),
applied AS (
  UPDATE public.members m
  SET operational_role = t.new_role,
      updated_at = now()
  FROM target t
  WHERE m.id = t.id
  RETURNING m.id, m.name, m.operational_role
)
SELECT 'fabricio_backfill_summary' AS marker, count(*) AS rows_updated FROM applied;
