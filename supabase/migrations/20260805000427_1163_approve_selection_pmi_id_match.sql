-- #1163 — approve_selection_application: match member/person by pmi_id first (email fallback)
-- + allow the researcher -> tribe_leader promotion on the leader track.
--
-- ROOT CAUSE (409 on approval): the member lookup matched ONLY by lower(email). When an
-- applicant's PMI-registered application email diverges from their platform member email
-- (same pmi_id), the lookup returned NULL and the function fell into the INSERT path, which
-- collided on members_pmi_id_key (UNIQUE pmi_id) -> 23505 -> PostgREST 409. Reproduced with
-- Paulo Alves de Oliveira Junior (member paulo-junior@outlook.com, app pejota81@gmail.com,
-- shared pmi_id 1158211). Same identity-drift class as #1130 (stable join by pmi_id).
--
-- SECONDARY (promotion no-op): the promotion CASE only elevated members whose current role was
-- observer/guest/none/alumni/inactive. An already-active `researcher` promoted on the leader
-- track (v_target_role = 'tribe_leader') was not covered, so the promotion silently did nothing.
-- We add researcher -> tribe_leader only (never a demotion: target 'researcher' does not promote
-- a researcher, and higher roles are untouched).
--
-- persons has NO unique on pmi_id/email, so there the email-only match did not 409 but silently
-- FORKED identity (a duplicate person for the same human); the pmi_id-first match fixes that too.

CREATE OR REPLACE FUNCTION public.approve_selection_application(p_application_id uuid, p_decision jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id        uuid;
  v_caller_name      text;
  v_caller_person_id uuid;
  v_caller_org_id    uuid;
  v_app              record;
  v_member_id        uuid;
  v_person_id        uuid;
  v_member_role      text;
  v_member_status    text;
  v_target_role      text;
  v_engagement_role  text;
  v_engagement_kind  text := 'volunteer';
  v_legal_basis      text := 'contract';
  v_cycle_end_date   date;
  v_member_chapter   text;
  v_default_days     int;
  v_requires_agreement boolean;
  v_engagement_id    uuid;
  v_existing_engagement_id uuid;
  v_seeded_count     int := 0;
  v_promoted         boolean := false;
  v_member_created   boolean := false;
  v_person_created   boolean := false;
  v_engagement_created boolean := false;
  v_classify         jsonb;
  v_br_codes         text[];
  v_code             text;
  v_entry_derived    text;
BEGIN
  SELECT id, name, person_id, organization_id
    INTO v_caller_id, v_caller_name, v_caller_person_id, v_caller_org_id
  FROM public.members WHERE auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Application not found');
  END IF;
  IF v_app.status NOT IN ('approved', 'converted') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Application status must be approved or converted',
      'current_status', v_app.status
    );
  END IF;
  IF v_app.email IS NULL OR length(trim(v_app.email)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Application has no email');
  END IF;

  SELECT sc.close_date
    INTO v_cycle_end_date
  FROM public.selection_cycles sc
  WHERE sc.id = v_app.cycle_id;

  IF v_cycle_end_date IS NOT NULL AND v_cycle_end_date < CURRENT_DATE THEN
    v_cycle_end_date := NULL;
  END IF;

  v_member_chapter := COALESCE(
    NULLIF(trim(v_app.chapter), ''),
    'Outro'
  );

  v_target_role := CASE
    WHEN v_app.role_applied = 'leader'     THEN 'tribe_leader'
    WHEN v_app.role_applied = 'researcher' THEN 'researcher'
    ELSE NULL
  END;

  -- #1163: match the member by pmi_id first (stable identity key), email as fallback. Matching by
  -- email alone missed members whose PMI-registered email diverges from the application email, then
  -- the INSERT path collided on members_pmi_id_key (UNIQUE pmi_id) -> 23505 -> PostgREST 409.
  SELECT id, person_id, operational_role, member_status
    INTO v_member_id, v_person_id, v_member_role, v_member_status
  FROM public.members
  WHERE (NULLIF(trim(v_app.pmi_id), '') IS NOT NULL AND pmi_id = NULLIF(trim(v_app.pmi_id), ''))
     OR lower(email) = lower(v_app.email)
  ORDER BY CASE
    WHEN NULLIF(trim(v_app.pmi_id), '') IS NOT NULL AND pmi_id = NULLIF(trim(v_app.pmi_id), '') THEN 0
    ELSE 1
  END
  LIMIT 1;

  IF v_member_id IS NULL THEN
    INSERT INTO public.members (
      organization_id,
      name, email, pmi_id, chapter,
      operational_role, is_active, current_cycle_active
    )
    VALUES (
      v_app.organization_id,
      v_app.applicant_name, v_app.email, v_app.pmi_id, v_member_chapter,
      COALESCE(v_target_role, 'researcher'),
      true, true
    )
    RETURNING id, person_id, operational_role, member_status
      INTO v_member_id, v_person_id, v_member_role, v_member_status;
    v_member_created := true;
  ELSE
    UPDATE public.members SET
      is_active = true,
      current_cycle_active = true,
      updated_at = now()
    WHERE id = v_member_id
      AND (is_active = false OR current_cycle_active = false);

    -- #1163: a researcher approved on the leader track is a genuine elevation to tribe_leader.
    -- The prior set omitted 'researcher', so leader promotions of an already-active researcher
    -- silently did not take effect. Only researcher -> tribe_leader is added here; this is never a
    -- demotion (target 'researcher' does not promote a researcher, higher roles are left untouched).
    IF v_target_role IS NOT NULL
       AND v_member_status = 'active'
       AND (
         v_member_role IN ('observer', 'guest', 'none', 'alumni', 'inactive')
         OR (v_member_role = 'researcher' AND v_target_role = 'tribe_leader')
       )
    THEN
      UPDATE public.members
      SET operational_role = v_target_role, updated_at = now()
      WHERE id = v_member_id;
      v_promoted := true;
    END IF;
  END IF;

  IF v_person_id IS NULL THEN
    -- #1163: same identity-drift class — prefer pmi_id so we do not fork identity into a duplicate
    -- person (persons has no unique on pmi_id/email, so an email-only match silently created one).
    SELECT id INTO v_person_id
    FROM public.persons
    WHERE (NULLIF(trim(v_app.pmi_id), '') IS NOT NULL AND pmi_id = NULLIF(trim(v_app.pmi_id), ''))
       OR lower(email) = lower(v_app.email)
    ORDER BY CASE
      WHEN NULLIF(trim(v_app.pmi_id), '') IS NOT NULL AND pmi_id = NULLIF(trim(v_app.pmi_id), '') THEN 0
      ELSE 1
    END
    LIMIT 1;

    IF v_person_id IS NULL THEN
      INSERT INTO public.persons (
        organization_id, name, email, pmi_id, phone,
        consent_status, legacy_member_id
      )
      VALUES (
        v_app.organization_id,
        v_app.applicant_name, v_app.email, v_app.pmi_id, v_app.phone,
        'pending', v_member_id
      )
      RETURNING id INTO v_person_id;
      v_person_created := true;
    END IF;

    UPDATE public.members SET person_id = v_person_id, updated_at = now()
    WHERE id = v_member_id AND person_id IS NULL;
  END IF;

  IF v_person_id IS NOT NULL THEN
    v_classify := public.classify_entry_chapter(
      v_app.pmi_memberships, v_app.community_profile_private, v_app.pmi_data_fetched_at
    );
    v_br_codes := ARRAY(SELECT jsonb_array_elements_text(v_classify->'active_br_codes'));

    IF v_br_codes IS NOT NULL AND array_length(v_br_codes, 1) >= 1 THEN
      FOREACH v_code IN ARRAY v_br_codes LOOP
        PERFORM public.upsert_chapter_affiliation(v_person_id, v_code, 'pmi_vep', false);
      END LOOP;

      IF array_length(v_br_codes, 1) = 1 THEN
        v_entry_derived := v_br_codes[1];
        UPDATE public.members
        SET entry_chapter_code = v_entry_derived, updated_at = now()
        WHERE id = v_member_id AND entry_chapter_code IS DISTINCT FROM v_entry_derived;
      END IF;
    END IF;
  END IF;

  v_engagement_role := CASE
    WHEN v_app.role_applied IN ('leader', 'researcher', 'coordinator', 'manager') THEN v_app.role_applied
    ELSE 'researcher'
  END;

  SELECT ek.default_duration_days, ek.requires_agreement
    INTO v_default_days, v_requires_agreement
  FROM public.engagement_kinds ek WHERE ek.slug = v_engagement_kind;

  SELECT id INTO v_existing_engagement_id
  FROM public.engagements
  WHERE person_id = v_person_id
    AND kind = v_engagement_kind
    AND status = 'active'
  ORDER BY start_date DESC
  LIMIT 1;

  IF v_existing_engagement_id IS NULL THEN
    INSERT INTO public.engagements (
      person_id, organization_id,
      kind, role, status,
      start_date, end_date,
      legal_basis,
      selection_application_id,
      granted_by, granted_at,
      metadata
    )
    VALUES (
      v_person_id,
      v_app.organization_id,
      v_engagement_kind, v_engagement_role, 'active',
      CURRENT_DATE,
      COALESCE(
        v_cycle_end_date,
        CURRENT_DATE + (COALESCE(v_default_days, 180) || ' days')::interval
      ),
      v_legal_basis,
      p_application_id,
      v_caller_person_id,
      now(),
      jsonb_build_object(
        'source', 'approve_selection_application',
        'role_applied', v_app.role_applied,
        'application_status', v_app.status,
        'chapter_source', CASE
          WHEN NULLIF(trim(v_app.chapter), '') IS NOT NULL THEN 'application'
          ELSE 'no_chapter_declared'
        END,
        'member_chapter', v_member_chapter
      )
    )
    RETURNING id INTO v_engagement_id;
    v_engagement_created := true;
  ELSE
    UPDATE public.engagements
    SET selection_application_id = p_application_id, updated_at = now()
    WHERE id = v_existing_engagement_id AND selection_application_id IS NULL;
    v_engagement_id := v_existing_engagement_id;
  END IF;

  INSERT INTO public.onboarding_progress (application_id, member_id, step_key, status, metadata)
  SELECT p_application_id, v_member_id, s.id, 'pending', '{}'::jsonb
  FROM public.onboarding_steps s
  WHERE s.is_required = true
    AND NOT (s.id = 'volunteer_term' AND NOT COALESCE(v_requires_agreement, FALSE))
    AND public.onboarding_step_applies(s.applies_to_role, COALESCE(v_target_role, 'researcher'))
    AND NOT EXISTS (
      SELECT 1 FROM public.onboarding_progress op
      WHERE op.member_id = v_member_id AND op.step_key = s.id
    );
  GET DIAGNOSTICS v_seeded_count = ROW_COUNT;

  INSERT INTO public.onboarding_progress (application_id, member_id, step_key, status, sla_deadline)
  SELECT p_application_id, v_member_id, (step->>'key'), 'pending',
         now() + ((step->>'sla_days')::int || ' days')::interval
  FROM public.selection_cycles sc, jsonb_array_elements(sc.onboarding_steps) AS step
  WHERE sc.id = v_app.cycle_id
    AND NOT EXISTS (
      SELECT 1 FROM public.onboarding_progress
      WHERE member_id = v_member_id AND step_key = (step->>'key')
    );

  PERFORM public.check_pre_onboarding_auto_steps(v_member_id);

  IF NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE recipient_id = v_member_id
      AND type = 'selection_approved'
      AND source_id = p_application_id
  ) THEN
    PERFORM public.create_notification(
      v_member_id,
      'selection_approved',
      'Parabens! Voce foi aprovado no Nucleo IA',
      'Sua candidatura foi aprovada. Acesse a plataforma para iniciar o onboarding.',
      '/onboarding',
      'selection_application',
      p_application_id
    );
  END IF;

  INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'selection_approval_canonical',
    'info',
    'Canonical approval for ' || v_app.applicant_name || ' (' || v_app.status || ')',
    jsonb_build_object(
      'application_id',     p_application_id,
      'application_status', v_app.status,
      'actor_id',           v_caller_id,
      'actor_name',         v_caller_name,
      'member_id',          v_member_id,
      'person_id',          v_person_id,
      'engagement_id',      v_engagement_id,
      'member_created',     v_member_created,
      'person_created',     v_person_created,
      'engagement_created', v_engagement_created,
      'onboarding_seeded',  v_seeded_count,
      'role_promoted',      v_promoted,
      'promoted_to',        CASE WHEN v_promoted THEN v_target_role ELSE NULL END,
      'requires_agreement', v_requires_agreement,
      'agreement_pending',  v_requires_agreement,
      'member_chapter',     v_member_chapter,
      'chapter_source',     CASE
        WHEN NULLIF(trim(v_app.chapter), '') IS NOT NULL THEN 'application'
        ELSE 'no_chapter_declared'
      END,
      'chapter_diagnosis',      v_classify->>'bucket',
      'chapter_active_br_codes', COALESCE(v_classify->'active_br_codes', '[]'::jsonb),
      'entry_chapter_derived',   v_entry_derived
    )
  );

  RETURN jsonb_build_object(
    'success',            true,
    'application_id',     p_application_id,
    'member_id',          v_member_id,
    'person_id',          v_person_id,
    'engagement_id',      v_engagement_id,
    'member_created',     v_member_created,
    'person_created',     v_person_created,
    'engagement_created', v_engagement_created,
    'onboarding_seeded',  v_seeded_count,
    'role_promoted',      v_promoted,
    'promoted_to',        CASE WHEN v_promoted THEN v_target_role ELSE NULL END,
    'agreement_pending',  v_requires_agreement,
    'member_chapter',     v_member_chapter,
    'chapter_diagnosis',      v_classify->>'bucket',
    'chapter_active_br_codes', COALESCE(v_classify->'active_br_codes', '[]'::jsonb),
    'entry_chapter_derived',   v_entry_derived
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.approve_selection_application(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_selection_application(uuid, jsonb) TO authenticated, service_role;
