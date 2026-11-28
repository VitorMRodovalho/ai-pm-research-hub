-- #3201: the event guest certificate PDF prints the member who counter-signed as its second
-- signatory, so issuance freezes that member's ROLE next to the name already frozen in
-- content_snapshot. Optional key p_data->>'counter_signed_by_role': only kept when there is a
-- counter-signer, stripped of control characters and capped at 80 characters. Everything else is
-- the live body unchanged (same signature, so grants are preserved).
CREATE OR REPLACE FUNCTION public.issue_event_guest_certificate(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_person uuid;
  v_caller_member uuid;
  v_org uuid := COALESCE(NULLIF(p_data->>'organization_id','')::uuid, '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid);
  v_event record;
  v_email text;
  v_name text;
  v_person uuid;
  v_created_person boolean := false;
  v_counter uuid;
  v_counter_name text;
  v_counter_role text;
  v_issuer_name text;
  v_code text;
  v_cert_id uuid;
  v_title text;
  v_lang text;
  v_existing_code text;
  v_retention date;
  v_consent_version text;
BEGIN
  SELECT p.id INTO v_caller_person FROM public.persons p WHERE p.auth_id = auth.uid();
  IF v_caller_person IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT (
    public.can(v_caller_person, 'manage_event', 'organization', v_org)
    OR public.can(v_caller_person, 'manage_platform', 'organization', v_org)
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_event or manage_platform at organization scope');
  END IF;

  SELECT m.id, m.name INTO v_caller_member, v_issuer_name FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_member IS NULL THEN
    RETURN jsonb_build_object('error', 'Caller has no members row; issued_by must be a member (renders the issuer signature)');
  END IF;

  v_email := lower(trim(p_data->>'guest_email'));
  v_name := trim(p_data->>'guest_name');
  IF v_email IS NULL OR v_email = '' OR position('@' IN v_email) = 0 THEN
    RETURN jsonb_build_object('error', 'guest_email is required (valid email)');
  END IF;
  IF v_name IS NULL OR v_name = '' THEN
    RETURN jsonb_build_object('error', 'guest_name is required');
  END IF;

  SELECT e.id, e.title, e.date INTO v_event FROM public.events e WHERE e.id = NULLIF(p_data->>'event_id','')::uuid;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event not found', 'event_id', p_data->>'event_id');
  END IF;

  v_lang := COALESCE(NULLIF(p_data->>'language',''), 'pt-BR');
  v_title := COALESCE(NULLIF(trim(p_data->>'title'),''), v_event.title);
  v_retention := (v_event.date + interval '1 year')::date;

  v_counter := NULLIF(p_data->>'counter_signed_by','')::uuid;
  IF v_counter IS NOT NULL THEN
    SELECT m.name INTO v_counter_name FROM public.members m WHERE m.id = v_counter;
    IF v_counter_name IS NULL THEN
      RETURN jsonb_build_object('error', 'counter_signed_by member not found', 'counter_signed_by', v_counter);
    END IF;
    -- #3201: role printed under the counter-signer's name; typed text, so no control characters
    v_counter_role := NULLIF(left(btrim(regexp_replace(coalesce(p_data->>'counter_signed_by_role', ''), '[[:cntrl:]]', '', 'g')), 80), '');
  END IF;

  SELECT p.id INTO v_person
  FROM public.persons p
  WHERE p.organization_id = v_org
    AND p.anonymized_at IS NULL
    AND (
      lower(p.email) = v_email
      OR EXISTS (SELECT 1 FROM unnest(p.secondary_emails) se WHERE lower(se) = v_email)
    )
  ORDER BY (p.auth_id IS NOT NULL) DESC, p.created_at ASC
  LIMIT 1;

  IF v_person IS NULL THEN
    v_consent_version := NULLIF(trim(p_data->>'consent_version'), '');
    IF v_consent_version IS NULL OR v_consent_version NOT LIKE 'event-guest%' THEN
      RETURN jsonb_build_object(
        'error', 'consent_version is required when creating a guest person and must start with event-guest',
        'hint', 'name the consent instrument captured at registration, e.g. event-guest-aftershow-2026-airmeet-form'
      );
    END IF;
    BEGIN
      INSERT INTO public.persons (organization_id, name, email, consent_status, consent_accepted_at, consent_version)
      VALUES (v_org, v_name, v_email, 'accepted', now(), v_consent_version)
      RETURNING id INTO v_person;
      v_created_person := true;
    EXCEPTION WHEN unique_violation THEN
      SELECT p.id INTO v_person
      FROM public.persons p
      WHERE p.organization_id = v_org AND lower(p.email) = v_email
      ORDER BY p.created_at ASC
      LIMIT 1;
    END;
  END IF;

  SELECT g.verification_code INTO v_existing_code
  FROM public.event_guest_certificates g
  WHERE g.person_id = v_person AND g.event_id = v_event.id AND g.status = 'issued';
  IF v_existing_code IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'already_issued', 'verification_code', v_existing_code, 'person_id', v_person);
  END IF;

  LOOP
    v_code := 'CERT-EVT-' || to_char(now(), 'YYYY') || '-' || upper(substr(md5(random()::text), 1, 6));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.event_guest_certificates WHERE verification_code = v_code)
      AND NOT EXISTS (SELECT 1 FROM public.certificates WHERE verification_code = v_code);
  END LOOP;

  INSERT INTO public.event_guest_certificates (
    organization_id, person_id, event_id, title, description, verification_code, language,
    issued_by, counter_signed_by, counter_signed_at, content_snapshot, retention_until
  )
  VALUES (
    v_org, v_person, v_event.id, v_title, NULLIF(trim(p_data->>'description'),''), v_code, v_lang,
    v_caller_member, v_counter, CASE WHEN v_counter IS NOT NULL THEN now() END,
    jsonb_build_object(
      'guest_name', v_name,
      'event_title', v_event.title,
      'event_date', v_event.date,
      'body_copy', '1008_option_a_no_pdu',
      'issued_by_name', v_issuer_name,
      'counter_signed_by_name', v_counter_name,
      'counter_signed_by_role', v_counter_role
    ),
    v_retention
  )
  RETURNING id INTO v_cert_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (
    v_caller_member, 'issue_event_guest_certificate', 'event_guest_certificate', v_cert_id,
    jsonb_build_object(
      'event_id', v_event.id,
      'person_id', v_person,
      'verification_code', v_code,
      'created_person', v_created_person,
      'retention_until', v_retention
    )
  );

  RETURN jsonb_build_object(
    'ok', true,
    'certificate_id', v_cert_id,
    'verification_code', v_code,
    'person_id', v_person,
    'created_person', v_created_person,
    'retention_until', v_retention
  );
END;
$function$;
