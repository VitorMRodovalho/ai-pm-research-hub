-- update_my_profile: aceita o novo campo de consentimento do mapa (allow_state_in_public_map).
CREATE OR REPLACE FUNCTION public.update_my_profile(p_fields jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_allowed_fields text[] := ARRAY['name','phone','linkedin_url','credly_url','share_whatsapp','pmi_id','state','country','photo_url','signature_url','address','city','birth_date','share_address','share_birth_date','allow_state_in_public_map'];
  v_field text;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  FOR v_field IN SELECT jsonb_object_keys(p_fields) LOOP
    IF NOT (v_field = ANY(v_allowed_fields)) THEN
      RETURN jsonb_build_object('error', 'Field not allowed: ' || v_field);
    END IF;
  END LOOP;

  UPDATE members SET
    name = CASE WHEN p_fields ? 'name' AND length(p_fields->>'name') >= 2 THEN p_fields->>'name' ELSE name END,
    phone = CASE WHEN p_fields ? 'phone' THEN p_fields->>'phone' ELSE phone END,
    linkedin_url = CASE WHEN p_fields ? 'linkedin_url' THEN p_fields->>'linkedin_url' ELSE linkedin_url END,
    credly_url = CASE WHEN p_fields ? 'credly_url' THEN p_fields->>'credly_url' ELSE credly_url END,
    share_whatsapp = CASE WHEN p_fields ? 'share_whatsapp' THEN (p_fields->>'share_whatsapp')::boolean ELSE share_whatsapp END,
    share_address = CASE WHEN p_fields ? 'share_address' THEN (p_fields->>'share_address')::boolean ELSE share_address END,
    share_birth_date = CASE WHEN p_fields ? 'share_birth_date' THEN (p_fields->>'share_birth_date')::boolean ELSE share_birth_date END,
    allow_state_in_public_map = CASE WHEN p_fields ? 'allow_state_in_public_map' THEN (p_fields->>'allow_state_in_public_map')::boolean ELSE allow_state_in_public_map END,
    pmi_id = CASE WHEN p_fields ? 'pmi_id' THEN p_fields->>'pmi_id' ELSE pmi_id END,
    state = CASE WHEN p_fields ? 'state' THEN p_fields->>'state' ELSE state END,
    country = CASE WHEN p_fields ? 'country' THEN p_fields->>'country' ELSE country END,
    photo_url = CASE WHEN p_fields ? 'photo_url' THEN p_fields->>'photo_url' ELSE photo_url END,
    signature_url = CASE WHEN p_fields ? 'signature_url' THEN p_fields->>'signature_url' ELSE signature_url END,
    address = CASE WHEN p_fields ? 'address' THEN p_fields->>'address' ELSE address END,
    city = CASE WHEN p_fields ? 'city' THEN p_fields->>'city' ELSE city END,
    birth_date = CASE WHEN p_fields ? 'birth_date' THEN (p_fields->>'birth_date')::date ELSE birth_date END,
    profile_completed_at = CASE WHEN profile_completed_at IS NULL THEN now() ELSE profile_completed_at END,
    -- Any profile update counts as a data review
    data_last_reviewed_at = CASE WHEN array_length(ARRAY(SELECT jsonb_object_keys(p_fields)), 1) > 0 THEN now() ELSE data_last_reviewed_at END,
    updated_at = now()
  WHERE id = v_caller.id;

  RETURN jsonb_build_object('ok', true, 'updated_fields', (SELECT array_agg(k) FROM jsonb_object_keys(p_fields) k));
END;
$function$;

-- get_member_by_auth: retorna allow_state_in_public_map p/ o checkbox do perfil refletir o valor salvo.
CREATE OR REPLACE FUNCTION public.get_member_by_auth()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_member_id uuid;
  v_existing_auth_id uuid;
  v_result json;
BEGIN
  IF v_uid IS NULL THEN
    RETURN NULL;
  END IF;

  -- Step 1: direct match on members.auth_id (the common case)
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_uid LIMIT 1;

  -- Step 2: match on secondary_auth_ids (admin-pre-approved alternates -> safe to rotate)
  IF v_member_id IS NULL THEN
    SELECT id INTO v_member_id
      FROM public.members
     WHERE v_uid = ANY(COALESCE(secondary_auth_ids, '{}'))
     LIMIT 1;

    IF v_member_id IS NOT NULL THEN
      SELECT auth_id INTO v_existing_auth_id FROM public.members WHERE id = v_member_id;

      UPDATE public.members
         SET auth_id            = v_uid,
             secondary_auth_ids = array_append(
                                    array_remove(COALESCE(secondary_auth_ids, '{}'::uuid[]), v_uid),
                                    v_existing_auth_id
                                  ),
             updated_at         = now()
       WHERE id = v_member_id;

      -- p177 D=1 fix: sync persons.auth_id to the new primary (mirror try_auto_link_ghost).
      UPDATE public.persons
         SET auth_id = v_uid
       WHERE legacy_member_id = v_member_id
         AND (auth_id IS NULL OR auth_id <> v_uid);

      INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
      VALUES (
        v_member_id,
        'members.auth_id.rotated_secondary_to_primary',
        'member',
        v_member_id,
        jsonb_build_object(
          'promoted_auth_id', v_uid,
          'demoted_auth_id', v_existing_auth_id
        ),
        jsonb_build_object('via', 'get_member_by_auth.step2_secondary_auth_ids_match')
      );
    END IF;
  END IF;

  -- Step 3: PRIMARY email first-link (only when auth_id IS NULL -- genuine ghost first login).
  -- P168 R3-a: dropped the (a) secondary_emails match branch and (b) replace-existing-auth_id
  -- branch. Both were the mechanism behind Paulo Alves identity hijack.
  IF v_member_id IS NULL THEN
    SELECT lower(email) INTO v_email FROM auth.users WHERE id = v_uid;

    IF v_email IS NOT NULL THEN
      SELECT id INTO v_member_id
        FROM public.members
       WHERE lower(email) = v_email
         AND auth_id IS NULL
       LIMIT 1;

      IF v_member_id IS NOT NULL THEN
        UPDATE public.members
           SET auth_id    = v_uid,
               updated_at = now()
         WHERE id = v_member_id;

        -- p177 D=1 fix: sync persons.auth_id on first-link (mirror try_auto_link_ghost).
        UPDATE public.persons
           SET auth_id = v_uid
         WHERE legacy_member_id = v_member_id
           AND (auth_id IS NULL OR auth_id <> v_uid);

        INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_member_id,
          'members.auth_id.first_link',
          'member',
          v_member_id,
          jsonb_build_object(
            'linked_auth_id', v_uid,
            'matched_via',    'primary_email',
            'matched_email',  v_email
          ),
          jsonb_build_object('via', 'get_member_by_auth.step3_primary_email_when_null')
        );
      END IF;
    END IF;
  END IF;

  IF v_member_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Return JSON shape -- adds allow_state_in_public_map (Cycle4 PD-MAP); rest UNCHANGED.
  SELECT row_to_json(q) INTO v_result FROM (
    SELECT m.id, m.name, m.email, m.secondary_emails,
      m.pmi_id, m.phone, m.operational_role, m.designations,
      compute_legacy_role(m.operational_role, m.designations)  AS role,
      compute_legacy_roles(m.operational_role, m.designations) AS roles,
      m.chapter, m.tribe_id, m.current_cycle_active, m.is_superadmin, m.is_active,
      m.member_status, m.state, m.country, m.share_whatsapp, m.signature_url,
      m.address, m.city, m.birth_date,
      m.share_address, m.share_birth_date, m.allow_state_in_public_map,
      m.privacy_consent_accepted_at, m.privacy_consent_version, m.data_last_reviewed_at,
      m.inactivated_at, m.inactivation_reason,
      m.photo_url, m.linkedin_url, m.auth_id,
      m.credly_url, m.credly_badges, m.cpmai_certified,
      m.created_at, m.updated_at
    FROM public.members m
    WHERE m.id = v_member_id
  ) q;

  RETURN v_result;
END;
$function$;
