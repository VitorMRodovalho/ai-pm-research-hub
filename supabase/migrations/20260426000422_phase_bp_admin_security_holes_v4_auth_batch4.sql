-- Track Q Phase B' — V4 auth migration (batch 4) + 2 SECURITY HOLE FIXES
--
-- Batch 4 has TWO scopes:
--
-- (A) V3 -> V4 conversion of 2 captured functions (same template as batches 1-3):
--     - get_ghost_visitors — admin-only listing of authenticated users
--       without member records. Legacy V3
--       (is_superadmin OR manager OR deputy_manager).
--     - admin_send_campaign — sends member/external campaigns. Legacy V3
--       same gate. Preserves rate-limit semantics; only the auth check is
--       refactored.
--
-- (B) DRIFT SIGNALS #7 + #8 — security holes surfaced during Phase B' batch
--     4 triage. Both functions are SECDEF without ANY caller authorization:
--     - admin_inactivate_member — deactivates an arbitrary member.
--       Currently exposed via /admin/member/[id].astro UI gate, but RPC
--       itself has no DB-side gate. Any authenticated PostgREST caller
--       can invoke it directly. Adding can_by_member('manage_member').
--     - import_vep_applications — bulk-imports selection applications
--       from VEP CSV. Exposed via /admin/selection.astro UI. Adds
--       can_by_member('manage_platform').
--
-- Privilege expansion analysis (verified live data 2026-04-25):
--   manage_platform safety check: legacy_count=2 (Vitor SA, Fabricio SA),
--   v4_count=2, would_gain=null, would_lose=null. Zero authorization
--   change in production today. Co_gp + deputy_manager engagements would
--   inherit access — consistent with admin authority semantics.
--   manage_member safety check: v4_count=2 (Vitor + Fabricio via
--   superadmin fast-path). For admin_inactivate_member this TIGHTENS
--   authority from "any authenticated caller" (security hole) to
--   manage_member ladder.
--
-- Bodies otherwise verbatim from p52 Q-A captures + p52 Q-B drift
-- corrections (plus added gate at the top, no other body changes).

-- ========================================================================
-- (A) V3 -> V4 conversions
-- ========================================================================

CREATE OR REPLACE FUNCTION public.get_ghost_visitors()
 RETURNS TABLE(auth_id uuid, email text, provider text, created_at timestamp with time zone, last_sign_in_at timestamp with time zone, possible_member_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

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
$function$;

CREATE OR REPLACE FUNCTION public.admin_send_campaign(
  p_template_id uuid,
  p_audience_filter jsonb DEFAULT '{}'::jsonb,
  p_scheduled_at timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_external_contacts jsonb DEFAULT '[]'::jsonb
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_send_id uuid;
  v_count int := 0;
  v_ext_count int := 0;
  v_sends_last_hour int;
  v_sends_last_day int;
  v_member record;
  v_tmpl record;
  v_roles text[];
  v_desigs text[];
  v_chapters text[];
  v_all boolean;
  v_include_inactive boolean;
  v_ext record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Forbidden: only GP/DM can send campaigns';
  END IF;

  SELECT COUNT(*) INTO v_sends_last_hour FROM public.campaign_sends
  WHERE sent_by = v_caller_id AND created_at > now() - interval '1 hour' AND status NOT IN ('draft','failed');
  IF v_sends_last_hour >= 1 THEN RAISE EXCEPTION 'Rate limit: max 1 campaign per hour'; END IF;

  SELECT COUNT(*) INTO v_sends_last_day FROM public.campaign_sends
  WHERE sent_by = v_caller_id AND created_at > now() - interval '1 day' AND status NOT IN ('draft','failed');
  IF v_sends_last_day >= 3 THEN RAISE EXCEPTION 'Rate limit: max 3 campaigns per day'; END IF;

  SELECT * INTO v_tmpl FROM public.campaign_templates WHERE id = p_template_id;
  IF v_tmpl IS NULL THEN RAISE EXCEPTION 'Template not found'; END IF;

  v_roles := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'roles', '[]'::jsonb)));
  v_desigs := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'designations', '[]'::jsonb)));
  v_chapters := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'chapters', '[]'::jsonb)));
  v_all := COALESCE((p_audience_filter->>'all')::boolean, false);
  v_include_inactive := COALESCE((p_audience_filter->>'include_inactive')::boolean, false);

  INSERT INTO public.campaign_sends (id, template_id, sent_by, audience_filter, status, scheduled_at)
  VALUES (gen_random_uuid(), p_template_id, v_caller_id, p_audience_filter,
          CASE WHEN p_scheduled_at IS NOT NULL THEN 'scheduled' ELSE 'pending_delivery' END, p_scheduled_at)
  RETURNING id INTO v_send_id;

  FOR v_member IN
    SELECT m.id, 'pt' AS lang
    FROM public.members m
    WHERE m.email IS NOT NULL
      AND (
        (m.is_active = true AND m.current_cycle_active = true)
        OR (v_include_inactive AND (m.is_active = false OR m.current_cycle_active = false))
      )
      AND (
        v_all OR v_include_inactive
        OR (array_length(v_roles, 1) > 0 AND m.operational_role = ANY(v_roles))
        OR (array_length(v_desigs, 1) > 0 AND m.designations && v_desigs)
        OR (array_length(v_chapters, 1) > 0 AND m.chapter = ANY(v_chapters))
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.campaign_recipients cr2
        JOIN public.campaign_sends cs2 ON cs2.id = cr2.send_id
        WHERE cr2.member_id = m.id AND cr2.unsubscribed = true
      )
  LOOP
    INSERT INTO public.campaign_recipients (send_id, member_id, language)
    VALUES (v_send_id, v_member.id, v_member.lang);
    v_count := v_count + 1;
  END LOOP;

  FOR v_ext IN SELECT * FROM jsonb_array_elements(p_external_contacts)
  LOOP
    INSERT INTO public.campaign_recipients (send_id, external_email, external_name, language)
    VALUES (v_send_id, v_ext.value->>'email', v_ext.value->>'name', COALESCE(v_ext.value->>'language', 'en'));
    v_ext_count := v_ext_count + 1;
  END LOOP;

  UPDATE public.campaign_sends SET recipient_count = v_count + v_ext_count WHERE id = v_send_id;

  RETURN jsonb_build_object(
    'send_id', v_send_id, 'member_recipients', v_count, 'external_recipients', v_ext_count,
    'total_recipients', v_count + v_ext_count,
    'status', CASE WHEN p_scheduled_at IS NOT NULL THEN 'scheduled' ELSE 'pending_delivery' END
  );
END;
$function$;

-- ========================================================================
-- (B) Security hole fixes — drift signals #7 and #8
-- ========================================================================

-- Drift signal #7: admin_inactivate_member had NO auth gate. SECDEF
-- function callable by ANY authenticated user via PostgREST. Adding
-- can_by_member('manage_member') tightens to admin/leader ladder.
CREATE OR REPLACE FUNCTION public.admin_inactivate_member(
  p_member_id uuid,
  p_reason text DEFAULT NULL::text
)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor_id uuid;
BEGIN
  SELECT id INTO v_actor_id FROM public.members WHERE auth_id = auth.uid();
  IF v_actor_id IS NULL OR NOT public.can_by_member(v_actor_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member permission';
  END IF;

  UPDATE public.members
     SET is_active = false,
         inactivation_reason = p_reason
   WHERE id = p_member_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_actor_id, 'member.inactivated', 'member', p_member_id,
    jsonb_build_object('is_active', false, 'reason', p_reason)
  );

  RETURN json_build_object('success', true);
END;
$function$;

-- Drift signal #8: import_vep_applications had NO auth gate. Bulk-imports
-- selection applications from VEP CSV. Exposed via /admin/selection.astro
-- UI but RPC itself was wide-open SECDEF. Adding
-- can_by_member('manage_platform').
CREATE OR REPLACE FUNCTION public.import_vep_applications(
  p_cycle_id uuid,
  p_rows jsonb,
  p_opportunity_id text DEFAULT NULL::text,
  p_role text DEFAULT 'researcher'::text
)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
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
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission for VEP import';
  END IF;

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
    'cycle_id', p_cycle_id, 'opportunity_id', p_opportunity_id
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
