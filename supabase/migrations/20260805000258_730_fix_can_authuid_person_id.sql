-- #730: get_person / get_active_engagements passed auth.uid() to can(), but can() joins
-- auth_engagements.person_id = persons.id — an auth user id can never match, so the
-- view_pii / manage_member gates ALWAYS failed closed (a legitimate holder could never see
-- another person's PII / engagements via these RPCs). Fail-closed → no leak, but a real
-- sub-grant. Fix: resolve the caller's person_id first and pass THAT to can().
--
-- The caller person_id is resolved via persons.legacy_member_id = (member where auth_id =
-- auth.uid()) — the SAME identity path these functions already use for their own-record
-- self-check — so the authority check and the self-comparison stay coherent (rather than
-- introducing a second persons.auth_id path that could diverge from the self-check).

CREATE OR REPLACE FUNCTION public.get_active_engagements(p_person_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_target_person_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT id INTO v_caller_person_id FROM public.persons WHERE legacy_member_id = v_caller_member_id;

  IF p_person_id IS NULL THEN
    v_target_person_id := v_caller_person_id;
  ELSE
    v_target_person_id := p_person_id;
    IF v_target_person_id != v_caller_person_id THEN
      IF NOT public.can(v_caller_person_id, 'manage_member', NULL, NULL) THEN
        RETURN jsonb_build_object('error', 'Unauthorized: manage_member required');
      END IF;
    END IF;
  END IF;

  IF v_target_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Person not found');
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', e.id, 'kind', e.kind, 'kind_display', ek.display_name, 'role', e.role,
      'status', e.status, 'initiative_id', e.initiative_id, 'initiative_name', i.name,
      'initiative_kind', i.kind, 'start_date', e.start_date, 'end_date', e.end_date,
      'legal_basis', e.legal_basis, 'has_agreement', (e.agreement_certificate_id IS NOT NULL),
      'is_authoritative', (e.status = 'active' AND e.start_date <= CURRENT_DATE
        AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
        AND (e.agreement_certificate_id IS NOT NULL OR NOT COALESCE(ek.requires_agreement, false))),
      'granted_at', e.granted_at
    ) ORDER BY e.start_date DESC
  ), '[]'::jsonb) INTO v_result
  FROM public.engagements e
  JOIN public.engagement_kinds ek ON ek.slug = e.kind
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.person_id = v_target_person_id AND e.status = 'active';

  RETURN jsonb_build_object('person_id', v_target_person_id, 'engagements', v_result, 'count', jsonb_array_length(v_result));
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_person(p_person_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_target_person_id uuid;
  v_can_pii boolean;
  v_person record;
BEGIN
  SELECT id INTO v_caller_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT id INTO v_caller_person_id FROM public.persons WHERE legacy_member_id = v_caller_member_id;

  IF p_person_id IS NULL THEN
    v_target_person_id := v_caller_person_id;
  ELSE
    v_target_person_id := p_person_id;
  END IF;

  IF v_target_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Person not found');
  END IF;

  IF v_target_person_id = v_caller_person_id THEN
    v_can_pii := true;
  ELSE
    SELECT public.can(v_caller_person_id, 'view_pii', NULL, NULL) INTO v_can_pii;
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
    'email', CASE WHEN v_can_pii THEN v_person.email ELSE NULL END,
    'phone', CASE WHEN v_can_pii AND v_person.share_whatsapp THEN v_person.phone ELSE NULL END,
    'address', CASE WHEN v_can_pii AND v_person.share_address THEN v_person.address ELSE NULL END,
    'birth_date', CASE WHEN v_can_pii AND v_person.share_birth_date THEN v_person.birth_date::text ELSE NULL END,
    'pmi_id', CASE WHEN v_can_pii THEN v_person.pmi_id ELSE NULL END,
    'legacy_member_id', v_person.legacy_member_id
  );
END;
$function$;

-- #730 forward-defense: audit helper listing any public function whose body resolves authority
-- via can(auth.uid(...)) instead of a resolved person_id. The match pattern is split via
-- concatenation so THIS function's own body never contains the contiguous forbidden substring
-- (else it would flag itself forever). Returns function identities only (no bodies, no PII).
-- service_role-only (least privilege; consumed by the 730 contract guard).
CREATE OR REPLACE FUNCTION public._audit_can_authuid_function_bodies()
 RETURNS TABLE(proname text, identity_args text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p.proname::text, pg_get_function_identity_arguments(p.oid)::text
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosrc ILIKE ('%can(auth.' || 'uid()%')
  ORDER BY 1;
$function$;

REVOKE ALL ON FUNCTION public._audit_can_authuid_function_bodies() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._audit_can_authuid_function_bodies() TO service_role;
