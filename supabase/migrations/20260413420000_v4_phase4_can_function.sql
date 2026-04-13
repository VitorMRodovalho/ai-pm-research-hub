-- ============================================================================
-- V4 Phase 4 — Migration 3/5: can() function + helpers
-- ADR: ADR-0007 (Authority as Derived Grant from Active Engagements)
-- Rollback: DROP FUNCTION public.can(uuid, text, text, uuid);
--           DROP FUNCTION public.can_by_member(uuid, text, text, uuid);
--           DROP FUNCTION public.why_denied(uuid, text, text, uuid);
-- ============================================================================

-- can(person_id, action, resource_type, resource_id)
-- Returns true if person has any authoritative engagement that grants the action.
-- For initiative-scoped actions, also checks that the engagement's initiative
-- matches the resource's initiative.

CREATE OR REPLACE FUNCTION public.can(
  p_person_id uuid,
  p_action text,
  p_resource_type text DEFAULT NULL,
  p_resource_id uuid DEFAULT NULL
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.auth_engagements ae
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = p_action
    WHERE ae.person_id = p_person_id
      AND ae.is_authoritative = true
      AND (
        -- Organization/global scope: always grants
        ekp.scope IN ('organization', 'global')
        -- Initiative-scoped: must match the resource
        OR (
          ekp.scope = 'initiative'
          AND ae.initiative_id IS NOT NULL
          AND (
            -- Match by initiative UUID
            ae.initiative_id = p_resource_id
            -- Match when no specific resource requested (general capability check)
            OR (p_resource_id IS NULL AND ae.legacy_tribe_id IS NOT NULL)
            -- Match by legacy tribe_id integer via resource_type hint
            OR (p_resource_type = 'tribe' AND ae.legacy_tribe_id = (p_resource_id::text)::integer)
          )
        )
      )
  );
$$;

COMMENT ON FUNCTION public.can(uuid, text, text, uuid) IS 'V4: Authority gate — returns true if person has active engagement granting action (ADR-0007). Shadow mode: runs alongside canWrite/canWriteBoard.';

GRANT EXECUTE ON FUNCTION public.can(uuid, text, text, uuid) TO authenticated;

-- can_by_member: convenience wrapper using legacy member_id
-- This is the bridge for existing code that has member.id but not person_id.
CREATE OR REPLACE FUNCTION public.can_by_member(
  p_member_id uuid,
  p_action text,
  p_resource_type text DEFAULT NULL,
  p_resource_id uuid DEFAULT NULL
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT public.can(
    (SELECT id FROM public.persons WHERE legacy_member_id = p_member_id),
    p_action, p_resource_type, p_resource_id
  );
$$;

COMMENT ON FUNCTION public.can_by_member(uuid, text, text, uuid) IS 'V4: Authority gate via legacy member_id bridge. Resolves to can() via persons.legacy_member_id.';

GRANT EXECUTE ON FUNCTION public.can_by_member(uuid, text, text, uuid) TO authenticated;

-- why_denied: diagnostic function for admin "why can't X do Y?"
CREATE OR REPLACE FUNCTION public.why_denied(
  p_person_id uuid,
  p_action text,
  p_resource_type text DEFAULT NULL,
  p_resource_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE
  v_result jsonb;
  v_person_exists boolean;
  v_has_engagements integer;
  v_has_authoritative integer;
  v_has_permission integer;
BEGIN
  -- Check person exists
  SELECT EXISTS(SELECT 1 FROM persons WHERE id = p_person_id) INTO v_person_exists;
  IF NOT v_person_exists THEN
    RETURN jsonb_build_object('denied', true, 'reason', 'person_not_found', 'person_id', p_person_id);
  END IF;

  -- Count engagements
  SELECT count(*) INTO v_has_engagements
  FROM engagements WHERE person_id = p_person_id AND status IN ('active', 'suspended');

  IF v_has_engagements = 0 THEN
    RETURN jsonb_build_object('denied', true, 'reason', 'no_active_engagements', 'person_id', p_person_id);
  END IF;

  -- Count authoritative engagements
  SELECT count(*) INTO v_has_authoritative
  FROM auth_engagements WHERE person_id = p_person_id AND is_authoritative = true;

  IF v_has_authoritative = 0 THEN
    RETURN jsonb_build_object(
      'denied', true, 'reason', 'no_authoritative_engagements',
      'detail', 'Engagements exist but none are authoritative (check dates, agreement, status)',
      'engagements', (
        SELECT jsonb_agg(jsonb_build_object(
          'kind', ae.kind, 'role', ae.role, 'status', ae.status,
          'is_authoritative', ae.is_authoritative,
          'start_date', ae.start_date, 'end_date', ae.end_date,
          'requires_agreement', ae.requires_agreement,
          'has_agreement', ae.agreement_certificate_id IS NOT NULL
        ))
        FROM auth_engagements ae WHERE ae.person_id = p_person_id
      )
    );
  END IF;

  -- Count matching permissions
  SELECT count(*) INTO v_has_permission
  FROM auth_engagements ae
  JOIN engagement_kind_permissions ekp ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = p_action
  WHERE ae.person_id = p_person_id AND ae.is_authoritative = true;

  IF v_has_permission = 0 THEN
    RETURN jsonb_build_object(
      'denied', true, 'reason', 'no_matching_permission',
      'action', p_action,
      'active_roles', (
        SELECT jsonb_agg(DISTINCT jsonb_build_object('kind', ae.kind, 'role', ae.role, 'initiative_id', ae.initiative_id))
        FROM auth_engagements ae WHERE ae.person_id = p_person_id AND ae.is_authoritative = true
      ),
      'available_actions', (
        SELECT jsonb_agg(DISTINCT ekp.action)
        FROM auth_engagements ae
        JOIN engagement_kind_permissions ekp ON ekp.kind = ae.kind AND ekp.role = ae.role
        WHERE ae.person_id = p_person_id AND ae.is_authoritative = true
      )
    );
  END IF;

  -- Has permission — not denied
  RETURN jsonb_build_object('denied', false, 'granted_by', (
    SELECT jsonb_agg(jsonb_build_object(
      'engagement_id', ae.engagement_id, 'kind', ae.kind, 'role', ae.role,
      'scope', ekp.scope, 'initiative_id', ae.initiative_id
    ))
    FROM auth_engagements ae
    JOIN engagement_kind_permissions ekp ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = p_action
    WHERE ae.person_id = p_person_id AND ae.is_authoritative = true
  ));
END;
$$;

COMMENT ON FUNCTION public.why_denied(uuid, text, text, uuid) IS 'V4: Diagnostic — explains why a person can/cannot perform an action. For admin/debug use.';

GRANT EXECUTE ON FUNCTION public.why_denied(uuid, text, text, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
