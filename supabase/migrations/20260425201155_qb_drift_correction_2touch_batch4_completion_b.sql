-- Track Q-B Phase B (2-touch drift diff) — drift-correction batch 4 completion part B (12 fns)
--
-- Final part of batch 4: captures the last 12 of 35 drifted 2-touch fns.
-- After this, 2-touch drift coverage = 35/35 = 100%, completing Phase B.
--
-- Captured (part B — 12 fns):
--   get_ghost_visitors, get_selection_dashboard, get_version_diff,
--   import_vep_applications, list_pending_curation,
--   manage_initiative_engagement, offboard_member, register_own_presence,
--   submit_curation_review, submit_interview_scores, try_auto_link_ghost,
--   upsert_event_minutes.

CREATE OR REPLACE FUNCTION public.get_ghost_visitors()
 RETURNS TABLE(auth_id uuid, email text, provider text, created_at timestamp with time zone, last_sign_in_at timestamp with time zone, possible_member_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.members
    WHERE public.members.auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'))
  ) THEN RAISE EXCEPTION 'Admin only'; END IF;

  RETURN QUERY
  SELECT
    au.id,
    au.email::text,
    (au.raw_app_meta_data->>'provider')::text,
    au.created_at,
    au.last_sign_in_at,
    COALESCE(
      (SELECT m.name FROM public.members m WHERE lower(m.email) = lower(au.email) LIMIT 1),
      (SELECT m.name FROM public.members m
       WHERE lower(m.name) LIKE '%' || lower(split_part(split_part(au.email, '@', 1), '.', 1)) || '%'
         AND length(split_part(split_part(au.email, '@', 1), '.', 1)) >= 4
       LIMIT 1)
    )::text
  FROM auth.users au
  LEFT JOIN public.members m2 ON m2.auth_id = au.id
  WHERE m2.id IS NULL
  ORDER BY au.last_sign_in_at DESC NULLS LAST;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_selection_dashboard(p_cycle_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_caller record; v_cycle_id uuid; v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager','deputy_manager') AND NOT (v_caller.designations && ARRAY['curator'])) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    SELECT id INTO v_cycle_id FROM selection_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found', 'cycle', null, 'applications', '[]'::jsonb, 'stats', jsonb_build_object('total', 0));
  END IF;

  SELECT jsonb_build_object(
    'cycle', (SELECT jsonb_build_object('id', c.id, 'cycle_code', c.cycle_code, 'title', c.title, 'status', c.status,
      'interview_booking_url', c.interview_booking_url,
      'interview_questions', COALESCE(c.interview_questions, '[]'::jsonb)) FROM selection_cycles c WHERE c.id = v_cycle_id),
    'applications', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', a.id, 'applicant_name', a.applicant_name, 'email', a.email,
        'phone', a.phone, 'role_applied', a.role_applied, 'chapter', a.chapter, 'status', a.status,
        'objective_score', a.objective_score_avg, 'final_score', a.final_score,
        'research_score', a.research_score, 'leader_score', a.leader_score,
        'rank_researcher', a.rank_researcher, 'rank_leader', a.rank_leader,
        'promotion_path', a.promotion_path, 'linked_application_id', a.linked_application_id,
        'rank_chapter', a.rank_chapter, 'rank_overall', a.rank_overall,
        'linkedin_url', a.linkedin_url, 'resume_url', a.resume_url,
        'tags', a.tags, 'feedback', a.feedback, 'motivation', a.motivation_letter,
        'experience_years', a.seniority_years, 'membership_status', a.membership_status,
        'certifications', a.certifications, 'is_returning_member', a.is_returning_member,
        'application_date', a.application_date, 'academic_background', a.academic_background,
        'areas_of_interest', a.areas_of_interest, 'availability_declared', a.availability_declared,
        'non_pmi_experience', a.non_pmi_experience, 'proposed_theme', a.proposed_theme,
        'leadership_experience', a.leadership_experience, 'created_at', a.created_at,
        'member_credly_url', (SELECT m.credly_url FROM members m WHERE lower(m.email) = lower(a.email) LIMIT 1),
        'member_photo_url', (SELECT m.photo_url FROM members m WHERE lower(m.email) = lower(a.email) LIMIT 1)
      ) ORDER BY COALESCE(a.leader_score, a.research_score, a.final_score) DESC NULLS LAST)
      FROM selection_applications a WHERE a.cycle_id = v_cycle_id
    ), '[]'::jsonb),
    'stats', jsonb_build_object(
      'total', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id),
      'approved', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND status IN ('approved', 'converted')),
      'rejected', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND status IN ('rejected', 'objective_cutoff')),
      'pending', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND status IN ('submitted', 'screening', 'objective_eval', 'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval')),
      'cancelled', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND status IN ('cancelled', 'withdrawn')),
      'waitlist', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND status = 'waitlist'),
      'leader_ranked', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND rank_leader IS NOT NULL),
      'researcher_ranked', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND rank_researcher IS NOT NULL))
  ) INTO v_result;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_version_diff(p_version_a uuid, p_version_b uuid, p_include_content boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid;
  v_a record; v_b record;
  v_payload_a jsonb; v_payload_b jsonb;
BEGIN
  SELECT m.id INTO v_member_id FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_version_a IS NULL OR p_version_b IS NULL THEN
    RAISE EXCEPTION 'both version ids are required' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT dv.id, dv.document_id, dv.version_number, dv.version_label,
         dv.authored_at, dv.locked_at, dv.content_html, dv.content_markdown,
         dv.content_diff_json, dv.notes, m.name AS authored_by_name
  INTO v_a FROM public.document_versions dv
  LEFT JOIN public.members m ON m.id = dv.authored_by WHERE dv.id = p_version_a;

  SELECT dv.id, dv.document_id, dv.version_number, dv.version_label,
         dv.authored_at, dv.locked_at, dv.content_html, dv.content_markdown,
         dv.content_diff_json, dv.notes, m.name AS authored_by_name
  INTO v_b FROM public.document_versions dv
  LEFT JOIN public.members m ON m.id = dv.authored_by WHERE dv.id = p_version_b;

  IF v_a.id IS NULL OR v_b.id IS NULL THEN
    RETURN jsonb_build_object('both_exist', false,
      'version_a_exists', (v_a.id IS NOT NULL), 'version_b_exists', (v_b.id IS NOT NULL));
  END IF;

  IF v_a.document_id <> v_b.document_id THEN
    RETURN jsonb_build_object('both_exist', true, 'same_document', false,
      'document_id_a', v_a.document_id, 'document_id_b', v_b.document_id);
  END IF;

  v_payload_a := jsonb_build_object('version_id', v_a.id, 'version_number', v_a.version_number,
    'version_label', v_a.version_label, 'authored_by_name', v_a.authored_by_name,
    'authored_at', v_a.authored_at, 'locked_at', v_a.locked_at,
    'content_html_length', length(v_a.content_html),
    'content_markdown_length', length(v_a.content_markdown), 'notes', v_a.notes);
  IF p_include_content THEN
    v_payload_a := v_payload_a
      || jsonb_build_object('content_html', v_a.content_html)
      || jsonb_build_object('content_markdown', v_a.content_markdown);
  END IF;

  v_payload_b := jsonb_build_object('version_id', v_b.id, 'version_number', v_b.version_number,
    'version_label', v_b.version_label, 'authored_by_name', v_b.authored_by_name,
    'authored_at', v_b.authored_at, 'locked_at', v_b.locked_at,
    'content_html_length', length(v_b.content_html),
    'content_markdown_length', length(v_b.content_markdown), 'notes', v_b.notes);
  IF p_include_content THEN
    v_payload_b := v_payload_b
      || jsonb_build_object('content_html', v_b.content_html)
      || jsonb_build_object('content_markdown', v_b.content_markdown);
  END IF;

  RETURN jsonb_build_object('both_exist', true, 'same_document', true,
    'document_id', v_a.document_id, 'include_content', p_include_content,
    'version_a', v_payload_a, 'version_b', v_payload_b,
    'pre_computed_diff', COALESCE(v_b.content_diff_json, v_a.content_diff_json),
    'newer_version_id', CASE WHEN v_a.version_number > v_b.version_number THEN v_a.id ELSE v_b.id END,
    'older_version_id', CASE WHEN v_a.version_number > v_b.version_number THEN v_b.id ELSE v_a.id END);
END;
$$;

CREATE OR REPLACE FUNCTION public.import_vep_applications(p_cycle_id uuid, p_rows jsonb, p_opportunity_id text DEFAULT NULL::text, p_role text DEFAULT 'researcher'::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_row jsonb; v_imported int := 0; v_skipped_dedup int := 0;
  v_skipped_declined int := 0; v_skipped_active int := 0;
  v_flagged_review int := 0; v_updated_snapshots int := 0; v_returning int := 0;
  v_app_id uuid; v_vep_app_id text; v_vep_status text; v_email text;
  v_membership text; v_chapters text[]; v_has_partner boolean;
  v_existing_app_id uuid; v_existing_member record;
  v_prev_cycles text[]; v_app_count int; v_partner_codes text[];
  v_primary_chapter text; v_cycle record; v_essay_mapping jsonb;
  v_opp record; v_app_date date;
  v_motivation text; v_areas text; v_availability text;
  v_academic text; v_proposed text; v_leadership text; v_chapter_aff text;
  v_field text; v_essay_val text;
  v_is_returning_offboarded boolean;
BEGIN
  SELECT array_agg(chapter_code) INTO v_partner_codes FROM partner_chapters WHERE is_active = true;
  SELECT * INTO v_cycle FROM selection_cycles WHERE id = p_cycle_id;
  SELECT * INTO v_opp FROM vep_opportunities WHERE opportunity_id = p_opportunity_id;
  v_essay_mapping := coalesce(v_opp.essay_mapping, '{"1":"essay_q1","2":"essay_q2","3":"essay_q3","4":"essay_q4","5":"essay_q5"}'::jsonb);
  IF v_opp.role_default IS NOT NULL THEN p_role := v_opp.role_default; END IF;

  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_vep_app_id := v_row->>'application_id';
    v_vep_status := v_row->>'app_status';
    v_email := lower(trim(v_row->>'email'));
    v_membership := v_row->>'membership_status';

    IF v_vep_status IN ('OfferNotExtended', 'Declined', 'Withdrawn') THEN
      v_skipped_declined := v_skipped_declined + 1; CONTINUE;
    END IF;

    v_chapters := parse_vep_chapters(v_membership);
    v_has_partner := v_chapters && v_partner_codes;

    IF v_vep_status IN ('Active', 'Complete') THEN
      SELECT id INTO v_existing_app_id FROM selection_applications WHERE lower(email) = v_email LIMIT 1;
      IF v_existing_app_id IS NOT NULL THEN
        INSERT INTO selection_membership_snapshots (application_id, membership_status, chapter_affiliations, certifications, is_partner_chapter, source)
        VALUES (v_existing_app_id, v_membership, v_chapters, v_row->>'certifications', v_has_partner, 'csv_active_snapshot');
        v_updated_snapshots := v_updated_snapshots + 1;
      END IF;
      v_skipped_active := v_skipped_active + 1; CONTINUE;
    END IF;

    SELECT id INTO v_existing_app_id FROM selection_applications WHERE vep_application_id = v_vep_app_id;
    IF v_existing_app_id IS NOT NULL THEN
      INSERT INTO selection_membership_snapshots (application_id, membership_status, chapter_affiliations, certifications, is_partner_chapter, source)
      VALUES (v_existing_app_id, v_membership, v_chapters, v_row->>'certifications', v_has_partner, 'csv_reimport');
      v_updated_snapshots := v_updated_snapshots + 1;
      v_skipped_dedup := v_skipped_dedup + 1; CONTINUE;
    END IF;

    SELECT id, is_active, operational_role, offboarded_at, chapter INTO v_existing_member
    FROM members WHERE lower(email) = v_email LIMIT 1;

    v_is_returning_offboarded := v_existing_member.id IS NOT NULL AND EXISTS (
      SELECT 1 FROM member_offboarding_records mor WHERE mor.member_id = v_existing_member.id
    );

    IF v_existing_member.id IS NOT NULL AND v_existing_member.is_active = false THEN
      IF v_existing_member.offboarded_at IS NOT NULL
         AND v_existing_member.offboarded_at >= coalesce(v_cycle.open_date, '2026-01-01')::timestamptz THEN
        INSERT INTO data_anomaly_log (anomaly_type, severity, message, details)
        VALUES ('selection_import_flagged_current_cycle', 'high',
          'Candidato inativado no ciclo corrente: ' || (v_row->>'first_name') || ' ' || (v_row->>'last_name'),
          jsonb_build_object('email', v_email, 'member_id', v_existing_member.id,
            'offboarded_at', v_existing_member.offboarded_at, 'vep_app_id', v_vep_app_id));
        v_flagged_review := v_flagged_review + 1; CONTINUE;
      END IF;
    END IF;

    v_primary_chapter := NULL;
    IF v_existing_member.id IS NOT NULL AND v_existing_member.chapter IS NOT NULL THEN
      v_primary_chapter := v_existing_member.chapter;
    ELSIF array_length(v_chapters, 1) > 0 THEN
      SELECT unnest INTO v_primary_chapter FROM unnest(v_chapters)
      WHERE unnest = ANY(v_partner_codes) LIMIT 1;
      IF v_primary_chapter IS NULL THEN v_primary_chapter := v_chapters[1]; END IF;
    END IF;

    SELECT count(*), array_agg(DISTINCT sc.cycle_code)
    INTO v_app_count, v_prev_cycles
    FROM selection_applications sa JOIN selection_cycles sc ON sc.id = sa.cycle_id
    WHERE lower(sa.email) = v_email;
    v_app_count := coalesce(v_app_count, 0) + 1;

    BEGIN
      v_app_date := NULLIF(trim(v_row->>'application_date'), '')::date;
    EXCEPTION WHEN OTHERS THEN v_app_date := NULL; END;

    v_motivation := NULL; v_areas := NULL; v_availability := NULL;
    v_academic := NULL; v_proposed := NULL; v_leadership := NULL; v_chapter_aff := NULL;

    FOR i IN 1..5 LOOP
      v_field := get_essay_field(v_essay_mapping, i::text);
      v_essay_val := v_row->>('essay_q' || i::text);
      IF v_field IS NOT NULL AND v_essay_val IS NOT NULL AND v_essay_val != '' THEN
        CASE v_field
          WHEN 'motivation_letter' THEN v_motivation := v_essay_val;
          WHEN 'chapter_affiliation' THEN v_chapter_aff := v_essay_val;
          WHEN 'areas_of_interest' THEN v_areas := v_essay_val;
          WHEN 'availability_declared' THEN v_availability := v_essay_val;
          WHEN 'academic_background' THEN v_academic := v_essay_val;
          WHEN 'proposed_theme' THEN v_proposed := v_essay_val;
          WHEN 'leadership_experience' THEN v_leadership := v_essay_val;
          ELSE NULL;
        END CASE;
      END IF;
    END LOOP;

    IF v_motivation IS NULL THEN v_motivation := v_row->>'reason_for_applying'; END IF;
    IF v_areas IS NULL THEN v_areas := v_row->>'areas_of_interest'; END IF;

    INSERT INTO selection_applications (
      cycle_id, vep_application_id, vep_opportunity_id,
      applicant_name, first_name, last_name, email, pmi_id,
      chapter, state, country, membership_status, certifications,
      resume_url, role_applied,
      motivation_letter, reason_for_applying, chapter_affiliation,
      areas_of_interest, availability_declared,
      academic_background, proposed_theme, leadership_experience,
      industry, application_date,
      is_returning_member, previous_cycles, application_count,
      imported_at, status
    ) VALUES (
      p_cycle_id, v_vep_app_id, p_opportunity_id,
      trim(coalesce(v_row->>'first_name', '')) || ' ' || trim(coalesce(v_row->>'last_name', '')),
      v_row->>'first_name', v_row->>'last_name', v_email, v_row->>'pmi_id',
      v_primary_chapter, v_row->>'state', v_row->>'country',
      v_membership, v_row->>'certifications',
      v_row->>'resume_url', p_role,
      v_motivation, v_row->>'reason_for_applying', v_chapter_aff,
      v_areas, v_availability,
      v_academic, v_proposed, v_leadership,
      v_row->>'industry', v_app_date,
      v_is_returning_offboarded,
      v_prev_cycles, v_app_count,
      now(), 'submitted'
    ) RETURNING id INTO v_app_id;

    INSERT INTO selection_membership_snapshots (application_id, membership_status, chapter_affiliations, certifications, is_partner_chapter, source)
    VALUES (v_app_id, v_membership, v_chapters, v_row->>'certifications', v_has_partner, 'csv_import');

    v_imported := v_imported + 1;
    IF v_is_returning_offboarded THEN v_returning := v_returning + 1; END IF;
  END LOOP;

  RETURN json_build_object(
    'imported', v_imported, 'skipped_dedup', v_skipped_dedup,
    'skipped_declined', v_skipped_declined, 'skipped_active', v_skipped_active,
    'flagged_review', v_flagged_review,
    'updated_snapshots', v_updated_snapshots, 'returning_members', v_returning,
    'cycle_id', p_cycle_id, 'opportunity_id', p_opportunity_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_pending_curation(p_table text DEFAULT 'all'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_member_id uuid; v_result jsonb := '[]'::jsonb; v_resources jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_member_id, 'write') THEN RAISE EXCEPTION 'Insufficient permissions'; END IF;

  IF p_table IN ('all', 'hub_resources') THEN
    SELECT COALESCE(jsonb_agg(row_to_json(r)), '[]'::jsonb) INTO v_resources
    FROM (
      SELECT h.id, h.title, h.url, h.asset_type AS type, h.source, h.tags,
             h.curation_status, h.trello_card_id, h.cycle_code AS cycle,
             h.created_at, NULL::text AS author_name,
             i.title AS tribe_name,
             'hub_resources' AS _table,
             public.suggest_tags(h.title, h.asset_type, h.cycle_code) AS suggested_tags
      FROM public.hub_resources h
      LEFT JOIN public.initiatives i ON i.id = h.initiative_id
      WHERE h.source IS DISTINCT FROM 'manual'
        AND h.curation_status IN ('draft','pending_review')
      ORDER BY h.created_at DESC LIMIT 200
    ) r;
    v_result := v_result || COALESCE(v_resources, '[]'::jsonb);
  END IF;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.manage_initiative_engagement(p_initiative_id uuid, p_person_id uuid, p_kind text, p_role text DEFAULT 'participant'::text, p_action text DEFAULT 'add'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_caller_person_id uuid; v_initiative record; v_engagement record;
  v_org_id uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
  v_is_admin boolean; v_is_owner_of_initiative boolean; v_kind_allows_owner boolean;
BEGIN
  SELECT p.id INTO v_caller_person_id FROM persons p WHERE p.auth_id = auth.uid();
  IF v_caller_person_id IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  v_is_admin := can(v_caller_person_id, 'manage_member', 'initiative', p_initiative_id);
  IF NOT v_is_admin THEN
    v_is_owner_of_initiative := EXISTS (SELECT 1 FROM engagements e WHERE e.person_id = v_caller_person_id AND e.initiative_id = p_initiative_id AND e.status = 'active' AND (e.kind LIKE '%_owner' OR e.kind LIKE '%_coordinator' OR e.role IN ('owner','coordinator','lead')));
    v_kind_allows_owner := EXISTS (SELECT 1 FROM engagement_kinds ek WHERE ek.slug = p_kind AND ('owner' = ANY(ek.created_by_role) OR 'coordinator' = ANY(ek.created_by_role)));
    IF NOT (v_is_owner_of_initiative AND v_kind_allows_owner) THEN
      RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member permission OR owner/coordinator of this initiative with kind that allows owner creation', 'hint', CASE WHEN NOT v_is_owner_of_initiative THEN 'Caller is not active owner/coordinator of initiative' ELSE 'Engagement kind does not allow owner as creator' END);
    END IF;
  END IF;
  SELECT i.id, i.kind, i.status INTO v_initiative FROM initiatives i WHERE i.id = p_initiative_id;
  IF v_initiative IS NULL THEN RETURN jsonb_build_object('error', 'Initiative not found'); END IF;
  IF v_initiative.status NOT IN ('active', 'draft') THEN RETURN jsonb_build_object('error', 'Initiative is not active'); END IF;
  IF NOT EXISTS (SELECT 1 FROM engagement_kinds ek WHERE ek.slug = p_kind AND v_initiative.kind = ANY(ek.initiative_kinds_allowed)) THEN
    RETURN jsonb_build_object('error', format('Engagement kind "%s" not allowed for initiative kind "%s"', p_kind, v_initiative.kind));
  END IF;
  IF p_action = 'add' THEN
    IF NOT EXISTS (SELECT 1 FROM persons WHERE id = p_person_id) THEN RETURN jsonb_build_object('error', 'Person not found'); END IF;
    IF EXISTS (SELECT 1 FROM engagements e WHERE e.person_id = p_person_id AND e.initiative_id = p_initiative_id AND e.status = 'active') THEN
      RETURN jsonb_build_object('error', 'Person already has active engagement in this initiative');
    END IF;
    INSERT INTO engagements (person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id)
    VALUES (p_person_id, p_initiative_id, p_kind, p_role, 'active', 'consent', v_caller_person_id,
      jsonb_build_object('source', 'manage_initiative_engagement', 'added_by', v_caller_person_id::text, 'invoked_as', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END), v_org_id)
    RETURNING * INTO v_engagement;
    RETURN jsonb_build_object('ok', true, 'action', 'added', 'engagement_id', v_engagement.id, 'authorized_as', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END);
  ELSIF p_action = 'remove' THEN
    UPDATE engagements SET status = 'revoked', revoked_at = now(), revoked_by = v_caller_person_id, revoke_reason = 'Removed via manage_initiative_engagement', updated_at = now()
    WHERE person_id = p_person_id AND initiative_id = p_initiative_id AND status = 'active' RETURNING * INTO v_engagement;
    IF v_engagement IS NULL THEN RETURN jsonb_build_object('error', 'No active engagement found for this person'); END IF;
    RETURN jsonb_build_object('ok', true, 'action', 'removed', 'engagement_id', v_engagement.id);
  ELSIF p_action = 'update_role' THEN
    UPDATE engagements SET role = p_role, updated_at = now()
    WHERE person_id = p_person_id AND initiative_id = p_initiative_id AND status = 'active' RETURNING * INTO v_engagement;
    IF v_engagement IS NULL THEN RETURN jsonb_build_object('error', 'No active engagement found for this person'); END IF;
    RETURN jsonb_build_object('ok', true, 'action', 'role_updated', 'engagement_id', v_engagement.id, 'new_role', p_role);
  ELSE RETURN jsonb_build_object('error', format('Unknown action: %s', p_action));
  END IF;
END; $$;

CREATE OR REPLACE FUNCTION public.offboard_member(p_member_id uuid, p_new_status text, p_reason text, p_effective_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  RETURN public.admin_offboard_member(
    p_member_id       => p_member_id,
    p_new_status      => p_new_status,
    p_reason_category => 'administrative',
    p_reason_detail   => p_reason,
    p_reassign_to     => NULL
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.register_own_presence(p_event_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid; v_role text; v_is_admin boolean;
  v_event_date date; v_event_ts timestamptz;
BEGIN
  SELECT id, operational_role, is_superadmin
  INTO v_member_id, v_role, v_is_admin
  FROM public.members WHERE auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT date INTO v_event_date FROM public.events WHERE id = p_event_id;
  IF v_event_date IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'event_not_found');
  END IF;

  v_event_ts := v_event_date::timestamptz;

  IF NOT (v_is_admin IS TRUE OR v_role IN ('manager', 'deputy_manager', 'tribe_leader')) THEN
    IF now() > v_event_ts + interval '48 hours' THEN
      RETURN json_build_object('success', false, 'error', 'checkin_window_expired',
        'message', 'O prazo de 48h para check-in expirou. Solicite ao gestor.');
    END IF;
    IF now() < v_event_ts - interval '2 hours' THEN
      RETURN json_build_object('success', false, 'error', 'checkin_too_early',
        'message', 'O check-in abre 2h antes do evento.');
    END IF;
  END IF;

  INSERT INTO public.attendance (event_id, member_id, checked_in_at)
  VALUES (p_event_id, v_member_id, now())
  ON CONFLICT (event_id, member_id) DO UPDATE SET checked_in_at = now();

  RETURN json_build_object('success', true, 'member_id', v_member_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_curation_review(p_item_id uuid, p_decision text, p_criteria_scores jsonb DEFAULT '{}'::jsonb, p_feedback_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_caller   members%rowtype;
  v_item     board_items%rowtype;
  v_log_id   uuid; v_pub_id   uuid;
  v_origin_board uuid; v_required int;
  v_current_round int; v_approved_count int;
  v_criteria text[]; v_key text; v_score int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF NOT (
    v_caller.is_superadmin = true
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR 'curator' = ANY(coalesce(v_caller.designations, array[]::text[]))
    OR 'co_gp' = ANY(coalesce(v_caller.designations, array[]::text[]))
  ) THEN RAISE EXCEPTION 'Curatorship access required'; END IF;

  IF p_decision NOT IN ('approved', 'returned_for_revision', 'rejected') THEN
    RAISE EXCEPTION 'Invalid decision: %', p_decision;
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Board item not found'; END IF;
  IF v_item.curation_status <> 'curation_pending' THEN
    RAISE EXCEPTION 'Item is not in curation_pending status';
  END IF;

  IF p_criteria_scores IS NOT NULL AND p_criteria_scores <> '{}'::jsonb THEN
    FOR v_key IN SELECT unnest(ARRAY['clarity','originality','adherence','relevance','ethics'])
    LOOP
      v_score := (p_criteria_scores->>v_key)::int;
      IF v_score IS NULL OR v_score < 1 OR v_score > 5 THEN
        RAISE EXCEPTION 'Invalid score for %: must be 1-5', v_key;
      END IF;
    END LOOP;
  END IF;

  SELECT coalesce(max(review_round), 1) INTO v_current_round
  FROM board_lifecycle_events
  WHERE item_id = p_item_id AND action = 'reviewer_assigned';

  SELECT reviewers_required INTO v_required
  FROM board_sla_config WHERE board_id = v_item.board_id;
  v_required := coalesce(v_required, 2);

  INSERT INTO curation_review_log (
    board_item_id, curator_id, criteria_scores, feedback_notes,
    decision, due_date, completed_at
  ) VALUES (
    p_item_id, v_caller.id, p_criteria_scores, p_feedback_notes,
    p_decision, v_item.curation_due_at, now()
  ) RETURNING id INTO v_log_id;

  INSERT INTO board_lifecycle_events
    (board_id, item_id, action, reason, actor_member_id, review_score, review_round, sla_deadline)
  VALUES
    (v_item.board_id, p_item_id, 'curation_review',
     p_decision || ': ' || coalesce(p_feedback_notes, ''),
     v_caller.id, p_criteria_scores, v_current_round, v_item.curation_due_at);

  IF p_decision = 'approved' THEN
    SELECT count(*) INTO v_approved_count
    FROM curation_review_log
    WHERE board_item_id = p_item_id AND decision = 'approved';

    IF v_approved_count >= v_required THEN
      v_pub_id := public.publish_board_item_from_curation(p_item_id);

      INSERT INTO board_lifecycle_events
        (board_id, item_id, action, reason, actor_member_id, review_round)
      VALUES
        (v_item.board_id, p_item_id, 'curation_approved',
         v_approved_count || '/' || v_required || ' revisores aprovaram',
         v_caller.id, v_current_round);
    END IF;

  ELSIF p_decision = 'returned_for_revision' THEN
    UPDATE board_items SET
      curation_status = 'draft', status = 'review',
      description = coalesce(description, '') ||
        E'\n\n---\n📋 **Feedback do Comitê de Curadoria — Rodada ' || v_current_round || '** (' || to_char(now(), 'DD/MM/YYYY') || E'):\n' ||
        coalesce(p_feedback_notes, 'Sem observações específicas.'),
      updated_at = now()
    WHERE id = p_item_id;

  ELSIF p_decision = 'rejected' THEN
    UPDATE board_items SET
      curation_status = 'draft', status = 'archived',
      description = coalesce(description, '') ||
        E'\n\n---\n❌ **Rejeitado pelo Comitê de Curadoria — Rodada ' || v_current_round || '** (' || to_char(now(), 'DD/MM/YYYY') || E'):\n' ||
        coalesce(p_feedback_notes, 'Não atende aos critérios mínimos.'),
      updated_at = now()
    WHERE id = p_item_id;
  END IF;

  RETURN v_log_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_interview_scores(p_interview_id uuid, p_scores jsonb, p_theme text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_criterion_notes jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record; v_interview record; v_app record; v_cycle record;
  v_criteria jsonb; v_criterion jsonb; v_key text;
  v_score numeric; v_weight numeric; v_weighted_sum numeric := 0;
  v_eval_id uuid; v_all_interviewers_submitted boolean;
  v_all_subtotals numeric[]; v_pert_score numeric;
  v_min_sub numeric; v_max_sub numeric; v_avg_sub numeric;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;

  SELECT * INTO v_interview FROM public.selection_interviews WHERE id = p_interview_id;
  IF v_interview IS NULL THEN RAISE EXCEPTION 'Interview not found'; END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = v_interview.application_id;
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  IF NOT (v_caller.id = ANY(v_interview.interviewer_ids)) AND v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Unauthorized: not an assigned interviewer';
  END IF;

  v_criteria := v_cycle.interview_criteria;

  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_criteria)
  LOOP
    v_key := v_criterion ->> 'key';
    v_weight := COALESCE((v_criterion ->> 'weight')::numeric, 1);

    IF NOT (p_scores ? v_key) THEN
      RAISE EXCEPTION 'Missing score for criterion: %', v_key;
    END IF;

    v_score := (p_scores ->> v_key)::numeric;
    v_weighted_sum := v_weighted_sum + (v_weight * v_score);
  END LOOP;

  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type,
    scores, weighted_subtotal, notes, criterion_notes, submitted_at
  ) VALUES (
    v_interview.application_id, v_caller.id, 'interview',
    p_scores, ROUND(v_weighted_sum, 2), p_notes, COALESCE(p_criterion_notes, '{}'::jsonb), now()
  )
  ON CONFLICT (application_id, evaluator_id, evaluation_type)
  DO UPDATE SET
    scores = EXCLUDED.scores,
    weighted_subtotal = EXCLUDED.weighted_subtotal,
    notes = EXCLUDED.notes,
    criterion_notes = EXCLUDED.criterion_notes,
    submitted_at = now()
  RETURNING id INTO v_eval_id;

  IF p_theme IS NOT NULL THEN
    UPDATE public.selection_interviews
    SET theme_of_interest = p_theme
    WHERE id = p_interview_id;
  END IF;

  v_all_interviewers_submitted := NOT EXISTS (
    SELECT 1 FROM unnest(v_interview.interviewer_ids) iid
    WHERE NOT EXISTS (
      SELECT 1 FROM public.selection_evaluations
      WHERE application_id = v_interview.application_id
        AND evaluator_id = iid
        AND evaluation_type = 'interview'
        AND submitted_at IS NOT NULL
    )
  );

  IF v_all_interviewers_submitted THEN
    UPDATE public.selection_interviews
    SET status = 'completed', conducted_at = now()
    WHERE id = p_interview_id;

    SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal)
    INTO v_all_subtotals
    FROM public.selection_evaluations
    WHERE application_id = v_interview.application_id
      AND evaluation_type = 'interview'
      AND submitted_at IS NOT NULL;

    v_min_sub := v_all_subtotals[1];
    v_max_sub := v_all_subtotals[array_upper(v_all_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg_sub FROM unnest(v_all_subtotals);

    v_pert_score := ROUND((2 * v_min_sub + 4 * v_avg_sub + 2 * v_max_sub) / 8, 2);

    UPDATE public.selection_applications
    SET interview_score = v_pert_score,
        final_score = COALESCE(objective_score_avg, 0) + v_pert_score,
        status = 'final_eval',
        updated_at = now()
    WHERE id = v_interview.application_id;

    PERFORM public.create_notification(
      sc.member_id,
      'selection_evaluation_complete',
      'Avaliação completa: ' || v_app.applicant_name,
      'Todas as avaliações (objetiva + entrevista) de ' || v_app.applicant_name || ' foram concluídas. Nota final: ' || ROUND(COALESCE(v_app.objective_score_avg, 0) + v_pert_score, 2),
      '/admin/selection',
      'selection_application',
      v_app.id
    )
    FROM public.selection_committee sc
    WHERE sc.cycle_id = v_app.cycle_id AND sc.role = 'lead';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'evaluation_id', v_eval_id,
    'weighted_subtotal', ROUND(v_weighted_sum, 2),
    'all_interviewers_submitted', v_all_interviewers_submitted,
    'pert_interview_score', v_pert_score);
END;
$$;

CREATE OR REPLACE FUNCTION public.try_auto_link_ghost()
 RETURNS SETOF members
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_member_id uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM members WHERE auth_id = v_uid) THEN
    UPDATE persons SET auth_id = v_uid
    WHERE legacy_member_id = (SELECT id FROM members WHERE auth_id = v_uid LIMIT 1)
      AND (auth_id IS NULL OR auth_id != v_uid);
    RETURN QUERY SELECT * FROM members WHERE auth_id = v_uid LIMIT 1;
    RETURN;
  END IF;

  SELECT email INTO v_email FROM auth.users WHERE id = v_uid;
  IF v_email IS NULL THEN RETURN; END IF;

  SELECT id INTO v_member_id FROM members
  WHERE lower(email) = lower(v_email) AND auth_id IS NULL
  LIMIT 1;

  IF v_member_id IS NOT NULL THEN
    UPDATE members SET auth_id = v_uid WHERE id = v_member_id;
    UPDATE persons SET auth_id = v_uid WHERE legacy_member_id = v_member_id;
    RETURN QUERY SELECT * FROM members WHERE id = v_member_id;
    RETURN;
  END IF;

  SELECT id INTO v_member_id FROM members
  WHERE lower(email) = lower(v_email) AND auth_id IS NOT NULL AND auth_id != v_uid
  LIMIT 1;

  IF v_member_id IS NOT NULL THEN
    UPDATE members SET auth_id = v_uid WHERE id = v_member_id;
    UPDATE persons SET auth_id = v_uid WHERE legacy_member_id = v_member_id;
    RETURN QUERY SELECT * FROM members WHERE id = v_member_id;
    RETURN;
  END IF;

  RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_event_minutes(p_event_id uuid, p_text text DEFAULT NULL::text, p_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record; v_event record; v_old_text text;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_event FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Event not found'; END IF;

  IF NOT _can_manage_event(p_event_id) THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  IF v_caller.operational_role = 'researcher'
     AND NOT v_caller.is_superadmin
     AND v_event.date + interval '72 hours' < now() THEN
    RAISE EXCEPTION 'Edit window expired — researchers can edit within 72h of the event. Contact your tribe leader.';
  END IF;

  v_old_text := v_event.minutes_text;
  IF v_old_text IS NOT NULL AND length(trim(v_old_text)) > 0 AND p_text IS NOT NULL THEN
    UPDATE events SET
      minutes_edit_history = COALESCE(minutes_edit_history, '[]'::jsonb) || jsonb_build_object(
        'edited_by', v_caller.id,
        'edited_by_name', v_caller.name,
        'edited_at', now(),
        'previous_text_hash', encode(sha256(convert_to(v_old_text, 'UTF8')), 'hex'),
        'previous_length', length(v_old_text)
      )
    WHERE id = p_event_id;
  END IF;

  UPDATE events SET
    minutes_text = COALESCE(p_text, minutes_text),
    minutes_url = COALESCE(p_url, minutes_url),
    minutes_posted_at = CASE WHEN v_old_text IS NULL OR length(trim(COALESCE(v_old_text,''))) = 0 THEN now() ELSE minutes_posted_at END,
    minutes_posted_by = CASE WHEN v_old_text IS NULL OR length(trim(COALESCE(v_old_text,''))) = 0 THEN v_caller.id ELSE minutes_posted_by END,
    minutes_edited_at = CASE WHEN v_old_text IS NOT NULL AND length(trim(v_old_text)) > 0 THEN now() ELSE minutes_edited_at END,
    updated_at = now()
  WHERE id = p_event_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller.id, 'event.minutes_updated', 'event', p_event_id,
    jsonb_build_object('has_text', p_text IS NOT NULL, 'has_url', p_url IS NOT NULL,
      'is_edit', v_old_text IS NOT NULL AND length(trim(COALESCE(v_old_text,''))) > 0));

  RETURN jsonb_build_object('success', true);
END; $$;
