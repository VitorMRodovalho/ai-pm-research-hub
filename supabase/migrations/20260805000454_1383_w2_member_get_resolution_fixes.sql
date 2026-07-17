-- EPIC #1383 Wave 2 (members/engagements/initiatives) — raw-RPC failure fixes absorbed by member_get.
-- (1) get_person: accept a members.id OR a persons.id for p_person_id (raw #2-failure class,
--     17/20 fails/180d "Person not found" when a members.id was passed). Pure additive fallback.
-- (2) get_active_engagements: initiatives has no column `name` (it is `title`) — the raw tool
--     failed 3/3 with "column i.name does not exist". Single-column fix.
-- Bodies based on the LIVE pg_get_functiondef (reference-create-or-replace-base-on-live-body);
-- CREATE OR REPLACE preserves existing grants (not in the anon-drift set; no grant change needed).

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
  v_scope text;
BEGIN
  SELECT id INTO v_caller_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT id INTO v_caller_person_id FROM public.persons WHERE legacy_member_id = v_caller_member_id;

  IF p_person_id IS NULL THEN
    v_target_person_id := v_caller_person_id;
  ELSE
    -- #1383 W2: accept either a persons.id OR a members.id (persons.legacy_member_id).
    -- Raw get_person #2-failure class: callers passing a members.id got 'Person not found' (17/20, 180d).
    SELECT id INTO v_target_person_id FROM public.persons WHERE id = p_person_id;
    IF v_target_person_id IS NULL THEN
      SELECT id INTO v_target_person_id FROM public.persons WHERE legacy_member_id = p_person_id;
    END IF;
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

  -- FU-2 Slice A: chapter-scope — a non-GP/non-sede caller sees PII only for own-chapter people.
  IF v_can_pii AND v_target_person_id <> v_caller_person_id THEN
    v_scope := public.caller_chapter_scope();
    IF v_scope IS NOT NULL
       AND (SELECT m.chapter FROM public.members m WHERE m.id = v_person.legacy_member_id) IS DISTINCT FROM v_scope THEN
      v_can_pii := false;
    END IF;
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
      'status', e.status, 'initiative_id', e.initiative_id, 'initiative_name', i.title,
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
