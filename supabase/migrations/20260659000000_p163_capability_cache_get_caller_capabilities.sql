-- p163 — Capability cache RPC for frontend gating (Opção C, ADR-0007 conformity)
-- Refs: docs/audit/P163_A3_BACKFILL_DECISION_AUDIT.md, ADR-0007, ADR-0080
--
-- Backstory: V3 frontend gates use `member.operational_role === 'tribe_leader'`
-- patterns. operational_role is a single-value cache; promoting someone via the
-- V4 priority ladder leaks scope (a workgroup leader becomes "tribe_leader"
-- globally and gets admin/board/event privileges they don't have institutionally).
-- can() is the V4 source of truth, but it is per-action and per-resource — a
-- frontend gate that needs N actions cannot make N round-trips per render.
--
-- Solution: get_caller_capabilities() returns the caller's full action surface
-- pre-computed. Frontend caches it on bootstrap (alongside member object) and
-- evaluates gates locally with O(1) lookups. RPC body mirrors can()'s semantics
-- exactly (same engagement_kind_permissions JOIN), so it is the source-of-truth
-- shape, not a reinterpretation.
--
-- Shape:
--   {
--     "caller_id": uuid,
--     "person_id": uuid,
--     "org_actions": ["write", "manage_member", ...],   // scope IN ('organization','global')
--     "initiative_actions": {                            // scope='initiative'
--       "<initiative_uuid>": ["write_board", "award_champion", ...],
--       ...
--     },
--     "tribe_actions": {                                 // scope='initiative' resolved via legacy_tribe_id
--       "<tribe_id_int>": ["write_board", ...],
--       ...
--     }
--   }
--
-- Semantics parity with can():
--   canFor(caps, action)                                = action ∈ caps.org_actions
--   canFor(caps, action, {type:'initiative', id})       = action ∈ caps.org_actions ∨ action ∈ caps.initiative_actions[id]
--   canFor(caps, action, {type:'tribe', id})            = action ∈ caps.org_actions ∨ action ∈ caps.tribe_actions[id]
--
-- Auth: any authenticated caller; returns capabilities for the auth.uid() member.
-- Returns empty/zero structure if caller has no member or no engagements.
--
-- Performance: single SQL pass per scope bucket, indexed by auth_engagements.person_id.
--
-- Rollback: DROP FUNCTION public.get_caller_capabilities();

CREATE OR REPLACE FUNCTION public.get_caller_capabilities()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_org_actions text[];
  v_initiative_actions jsonb;
  v_tribe_actions jsonb;
BEGIN
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m
  WHERE m.auth_id = auth.uid()
  LIMIT 1;

  IF v_caller_person_id IS NULL THEN
    RETURN jsonb_build_object(
      'caller_id', NULL,
      'person_id', NULL,
      'org_actions', '[]'::jsonb,
      'initiative_actions', '{}'::jsonb,
      'tribe_actions', '{}'::jsonb
    );
  END IF;

  -- Org/global-scope actions: granted everywhere.
  SELECT COALESCE(array_agg(DISTINCT ekp.action), ARRAY[]::text[])
  INTO v_org_actions
  FROM public.auth_engagements ae
  JOIN public.engagement_kind_permissions ekp
    ON ekp.kind = ae.kind AND ekp.role = ae.role
  WHERE ae.person_id = v_caller_person_id
    AND ae.is_authoritative = true
    AND ekp.scope IN ('organization', 'global');

  -- Initiative-scoped actions: keyed by initiative_id (uuid as text).
  SELECT COALESCE(jsonb_object_agg(initiative_id::text, actions), '{}'::jsonb)
  INTO v_initiative_actions
  FROM (
    SELECT ae.initiative_id, array_agg(DISTINCT ekp.action ORDER BY ekp.action) AS actions
    FROM public.auth_engagements ae
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role
    WHERE ae.person_id = v_caller_person_id
      AND ae.is_authoritative = true
      AND ekp.scope = 'initiative'
      AND ae.initiative_id IS NOT NULL
    GROUP BY ae.initiative_id
  ) sub;

  -- Tribe-scoped actions: same engagement set, indexed by legacy_tribe_id (int as text).
  -- Mirrors can() resource_type='tribe' branch (ae.legacy_tribe_id = (p_resource_id::text)::int).
  SELECT COALESCE(jsonb_object_agg(legacy_tribe_id::text, actions), '{}'::jsonb)
  INTO v_tribe_actions
  FROM (
    SELECT ae.legacy_tribe_id, array_agg(DISTINCT ekp.action ORDER BY ekp.action) AS actions
    FROM public.auth_engagements ae
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role
    WHERE ae.person_id = v_caller_person_id
      AND ae.is_authoritative = true
      AND ekp.scope = 'initiative'
      AND ae.legacy_tribe_id IS NOT NULL
    GROUP BY ae.legacy_tribe_id
  ) sub;

  RETURN jsonb_build_object(
    'caller_id', v_caller_member_id,
    'person_id', v_caller_person_id,
    'org_actions', to_jsonb(v_org_actions),
    'initiative_actions', v_initiative_actions,
    'tribe_actions', v_tribe_actions
  );
END;
$function$;

COMMENT ON FUNCTION public.get_caller_capabilities() IS
'Returns capability cache for the authenticated caller (ADR-0007 V4 capability cache for UI gates). Mirrors can() semantics. Bootstrap-time, cached client-side. See docs/audit/P163_A3_BACKFILL_DECISION_AUDIT.md.';

REVOKE EXECUTE ON FUNCTION public.get_caller_capabilities() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_caller_capabilities() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_caller_capabilities() TO authenticated;

NOTIFY pgrst, 'reload schema';
