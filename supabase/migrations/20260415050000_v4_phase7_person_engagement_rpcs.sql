-- ============================================================================
-- V4 Phase 7b — Person + Engagement RPCs for MCP
-- ADR: ADR-0006 (Person + Engagement Identity Model)
-- Rollback: DROP FUNCTION IF EXISTS public.get_person(uuid);
--           DROP FUNCTION IF EXISTS public.get_active_engagements(uuid);
-- ============================================================================

-- ═══ 1. get_person — returns person profile for the authenticated user ═══
-- Returns the V4 person record with non-PII fields.
-- PII fields (email, phone, address, birth_date) only returned if caller has view_pii.
CREATE OR REPLACE FUNCTION public.get_person(
  p_person_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE
  v_caller_member_id uuid;
  v_target_person_id uuid;
  v_can_pii boolean;
  v_person record;
BEGIN
  -- Auth
  SELECT id INTO v_caller_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Resolve target: if no person_id given, return caller's own person record
  IF p_person_id IS NULL THEN
    SELECT p.id INTO v_target_person_id FROM public.persons p WHERE p.legacy_member_id = v_caller_member_id;
  ELSE
    v_target_person_id := p_person_id;
  END IF;

  IF v_target_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Person not found');
  END IF;

  -- PII gate: own record always visible, others require view_pii
  IF v_target_person_id = (SELECT id FROM public.persons WHERE legacy_member_id = v_caller_member_id) THEN
    v_can_pii := true;
  ELSE
    SELECT public.can(auth.uid(), 'view_pii', NULL, NULL) INTO v_can_pii;
  END IF;

  SELECT * INTO v_person FROM public.persons WHERE id = v_target_person_id;
  IF v_person IS NULL THEN
    RETURN jsonb_build_object('error', 'Person not found');
  END IF;

  RETURN jsonb_build_object(
    'id', v_person.id,
    'name', v_person.name,
    'photo_url', v_person.photo_url,
    'linkedin_url', v_person.linkedin_url,
    'city', v_person.city,
    'state', v_person.state,
    'country', v_person.country,
    'credly_url', v_person.credly_url,
    'credly_badges', COALESCE(v_person.credly_badges, '[]'::jsonb),
    'consent_status', v_person.consent_status,
    -- PII fields: only if authorized
    'email', CASE WHEN v_can_pii THEN v_person.email ELSE NULL END,
    'phone', CASE WHEN v_can_pii AND v_person.share_whatsapp THEN v_person.phone ELSE NULL END,
    'address', CASE WHEN v_can_pii AND v_person.share_address THEN v_person.address ELSE NULL END,
    'birth_date', CASE WHEN v_can_pii AND v_person.share_birth_date THEN v_person.birth_date::text ELSE NULL END,
    'pmi_id', CASE WHEN v_can_pii THEN v_person.pmi_id ELSE NULL END,
    'legacy_member_id', v_person.legacy_member_id
  );
END;
$$;

COMMENT ON FUNCTION public.get_person(uuid) IS
  'V4 (ADR-0006): Returns person profile. PII gated by view_pii permission. Own record always fully visible.';

GRANT EXECUTE ON FUNCTION public.get_person(uuid) TO authenticated;

-- ═══ 2. get_active_engagements — returns active engagements for a person ═══
CREATE OR REPLACE FUNCTION public.get_active_engagements(
  p_person_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE
  v_caller_member_id uuid;
  v_target_person_id uuid;
  v_result jsonb;
BEGIN
  -- Auth
  SELECT id INTO v_caller_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Resolve target
  IF p_person_id IS NULL THEN
    SELECT p.id INTO v_target_person_id FROM public.persons p WHERE p.legacy_member_id = v_caller_member_id;
  ELSE
    v_target_person_id := p_person_id;
    -- Non-self queries require manage_member
    IF v_target_person_id != (SELECT id FROM public.persons WHERE legacy_member_id = v_caller_member_id) THEN
      IF NOT public.can(auth.uid(), 'manage_member', NULL, NULL) THEN
        RETURN jsonb_build_object('error', 'Unauthorized: manage_member required to view other persons engagements');
      END IF;
    END IF;
  END IF;

  IF v_target_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Person not found');
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', e.id,
      'kind', e.kind,
      'kind_display', ek.display_name,
      'role', e.role,
      'status', e.status,
      'initiative_id', e.initiative_id,
      'initiative_name', i.name,
      'initiative_kind', i.kind,
      'start_date', e.start_date,
      'end_date', e.end_date,
      'legal_basis', e.legal_basis,
      'has_agreement', (e.agreement_certificate_id IS NOT NULL),
      'is_authoritative', (
        e.status = 'active'
        AND e.start_date <= CURRENT_DATE
        AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
        AND (e.agreement_certificate_id IS NOT NULL OR NOT COALESCE(ek.requires_agreement, false))
      ),
      'granted_at', e.granted_at
    ) ORDER BY e.start_date DESC
  ), '[]'::jsonb) INTO v_result
  FROM public.engagements e
  JOIN public.engagement_kinds ek ON ek.slug = e.kind
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.person_id = v_target_person_id
    AND e.status = 'active';

  RETURN jsonb_build_object(
    'person_id', v_target_person_id,
    'engagements', v_result,
    'count', jsonb_array_length(v_result)
  );
END;
$$;

COMMENT ON FUNCTION public.get_active_engagements(uuid) IS
  'V4 (ADR-0006): Returns active engagements for a person. Own engagements always visible. Others require manage_member.';

GRANT EXECUTE ON FUNCTION public.get_active_engagements(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
