-- Track Q-A Batch H — orphan recovery: selection / application (14 fns)
--
-- Captures live bodies as-of 2026-04-25 for selection cycle / application
-- surface (admin tribe management, scoring computation, importers, ranking
-- readers, gate preview). Bodies preserved verbatim from
-- `pg_get_functiondef` — no behavior change.
--
-- Phase B drift candidates surfaced (NOT fixed here):
-- 1. admin_force_tribe_selection + admin_remove_tribe_selection use legacy
--    `members.role` column in their authority gate; the V4 column is
--    `operational_role`. If members.role no longer exists, these RPCs are
--    currently broken in production. Capture-and-note per Phase A rule.
-- 2. admin_get_tribe_allocations references `m.tribe_id` (post-ADR-0015 the
--    canonical path is engagements). Captured verbatim; flag for Phase B.
-- 3. compute_application_scores uses simple AVG over weighted_subtotal,
--    while import_historical_evaluations / import_leader_evaluations use
--    PERT formula (2*min+4*avg+2*max)/8. Different aggregation paths
--    coexist across the surface — Phase B should pick one and reconcile.
-- 4. import_historical_evaluations + import_historical_interviews +
--    import_leader_evaluations all hardcode the cycle3-2026 cycle code AND
--    two specific evaluator UUIDs (Vitor + Fabricio). One-shot importers
--    not parameterized — flag for archival vs parameterization decision.
--
-- All 14 are SECURITY DEFINER. No new state, just capture.

CREATE OR REPLACE FUNCTION public.admin_force_tribe_selection(p_member_id uuid, p_tribe_id integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_current_count INTEGER;
  v_max_slots INTEGER := 6;
BEGIN
  -- Only superadmin or manager
  IF NOT EXISTS (
    SELECT 1 FROM members
    WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR role = 'manager')
  ) THEN
    RETURN json_build_object('error', 'Acesso negado');
  END IF;

  -- Check slot availability
  SELECT COUNT(*) INTO v_current_count
  FROM tribe_selections WHERE tribe_id = p_tribe_id;

  IF v_current_count >= v_max_slots THEN
    RETURN json_build_object('error', 'Tribo lotada (' || v_current_count || '/' || v_max_slots || ')');
  END IF;

  -- Remove existing selection if any
  DELETE FROM tribe_selections WHERE member_id = p_member_id;

  -- Insert new selection
  INSERT INTO tribe_selections (member_id, tribe_id, selected_at)
  VALUES (p_member_id, p_tribe_id, now());

  RETURN json_build_object('success', true, 'tribe_id', p_tribe_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_tribe_allocations()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM members
    WHERE auth_id = auth.uid()
    AND (is_superadmin = true
         OR operational_role IN ('manager', 'deputy_manager')
         OR 'co_gp' = ANY(COALESCE(designations, '{}')))
  ) THEN
    RETURN json_build_object('error', 'Acesso negado');
  END IF;

  RETURN (
    SELECT json_agg(row_to_json(t))
    FROM (
      SELECT
        m.id AS member_id, m.name, m.email, m.phone, m.photo_url,
        m.operational_role, m.designations,
        compute_legacy_role(m.operational_role, m.designations) AS role,
        compute_legacy_roles(m.operational_role, m.designations) AS roles,
        m.chapter, m.tribe_id AS fixed_tribe_id, m.current_cycle_active,
        ts.tribe_id AS selected_tribe_id, ts.selected_at
      FROM members m
      LEFT JOIN tribe_selections ts ON m.id = ts.member_id
      WHERE m.current_cycle_active = true
      ORDER BY ts.tribe_id ASC NULLS FIRST, m.name ASC
    ) t
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_remove_tribe_selection(p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM members
    WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR role = 'manager')
  ) THEN
    RETURN json_build_object('error', 'Acesso negado');
  END IF;

  DELETE FROM tribe_selections WHERE member_id = p_member_id;
  RETURN json_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.compute_application_scores(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_app record;
  v_obj_avg numeric;
  v_int_avg numeric;
  v_lead_avg numeric;
  v_research numeric;
  v_leader numeric;
BEGIN
  SELECT role_applied, promotion_path INTO v_app
  FROM selection_applications WHERE id = p_application_id;
  IF v_app.role_applied IS NULL THEN
    RETURN jsonb_build_object('error', 'application_not_found');
  END IF;

  -- Average the weighted_subtotals per evaluation_type (already PERT-consolidated when individual evals submitted)
  SELECT AVG(weighted_subtotal) INTO v_obj_avg
  FROM selection_evaluations
  WHERE application_id = p_application_id AND evaluation_type = 'objective' AND submitted_at IS NOT NULL;

  SELECT AVG(weighted_subtotal) INTO v_int_avg
  FROM selection_evaluations
  WHERE application_id = p_application_id AND evaluation_type = 'interview' AND submitted_at IS NOT NULL;

  SELECT AVG(weighted_subtotal) INTO v_lead_avg
  FROM selection_evaluations
  WHERE application_id = p_application_id AND evaluation_type = 'leader_extra' AND submitted_at IS NOT NULL;

  -- research_score: obj + int (null if either is missing → incomplete)
  IF v_obj_avg IS NOT NULL AND v_int_avg IS NOT NULL THEN
    v_research := round(v_obj_avg + v_int_avg, 2);
  ELSIF v_obj_avg IS NOT NULL THEN
    v_research := round(v_obj_avg, 2);  -- partial: objective only (pre-interview stage)
  ELSE
    v_research := NULL;
  END IF;

  -- leader_score: weighted formula per CR-047 (0.7 research + 0.3 leader_extra)
  -- Only computed for leader track OR triaged-to-leader candidates
  IF v_app.role_applied = 'leader' OR v_app.promotion_path = 'triaged_to_leader' THEN
    IF v_research IS NOT NULL AND v_lead_avg IS NOT NULL THEN
      v_leader := round(v_research * 0.7 + v_lead_avg * 0.3, 2);
    ELSIF v_research IS NOT NULL THEN
      v_leader := v_research;  -- partial: no leader_extra yet
    ELSE
      v_leader := NULL;
    END IF;
  END IF;

  -- Update the row
  UPDATE selection_applications
  SET research_score = v_research,
      leader_score = v_leader,
      final_score = COALESCE(v_leader, v_research),  -- display fallback
      updated_at = now()
  WHERE id = p_application_id;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'research_score', v_research,
    'leader_score', v_leader,
    'objective_pert', v_obj_avg,
    'interview_pert', v_int_avg,
    'leader_extra_pert', v_lead_avg
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.enrich_applications_from_csv(p_cycle_id uuid, p_rows jsonb, p_opportunity_id text, p_snapshot_date text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_row jsonb; v_email text; v_app_id uuid; v_enriched int := 0; v_not_found int := 0;
  v_essay_mapping jsonb; v_opp record;
  v_field text; v_essay_val text;
  v_motivation text; v_areas text; v_availability text;
  v_academic text; v_proposed text; v_leadership text; v_chapter_aff text;
BEGIN
  SELECT * INTO v_opp FROM vep_opportunities WHERE opportunity_id = p_opportunity_id;
  v_essay_mapping := coalesce(v_opp.essay_mapping, '{}'::jsonb);

  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_email := lower(trim(v_row->>'email'));
    SELECT id INTO v_app_id FROM selection_applications
    WHERE cycle_id = p_cycle_id AND lower(email) = v_email LIMIT 1;
    IF v_app_id IS NULL THEN v_not_found := v_not_found + 1; CONTINUE; END IF;

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

    UPDATE selection_applications SET
      vep_application_id = COALESCE(vep_application_id, v_row->>'application_id'),
      vep_opportunity_id = COALESCE(vep_opportunity_id, p_opportunity_id),
      pmi_id = COALESCE(NULLIF(pmi_id, ''), v_row->>'pmi_id'),
      phone = COALESCE(NULLIF(phone, ''), v_row->>'phone'),
      linkedin_url = COALESCE(NULLIF(linkedin_url, ''), v_row->>'linkedin_url'),
      resume_url = COALESCE(NULLIF(resume_url, ''), v_row->>'resume_url'),
      certifications = COALESCE(NULLIF(certifications, ''), v_row->>'certifications'),
      reason_for_applying = COALESCE(NULLIF(reason_for_applying, ''), v_row->>'reason_for_applying'),
      chapter_affiliation = COALESCE(NULLIF(chapter_affiliation, ''), v_chapter_aff),
      motivation_letter = COALESCE(NULLIF(motivation_letter, ''), v_motivation),
      areas_of_interest = COALESCE(NULLIF(areas_of_interest, ''), v_areas),
      availability_declared = COALESCE(NULLIF(availability_declared, ''), v_availability),
      academic_background = COALESCE(NULLIF(academic_background, ''), v_academic),
      proposed_theme = COALESCE(NULLIF(proposed_theme, ''), v_proposed),
      leadership_experience = COALESCE(NULLIF(leadership_experience, ''), v_leadership),
      application_date = COALESCE(application_date, NULLIF(trim(v_row->>'application_date'), '')::date),
      industry = COALESCE(NULLIF(industry, ''), v_row->>'industry'),
      updated_at = now()
    WHERE id = v_app_id;

    INSERT INTO selection_membership_snapshots (
      application_id, membership_status, chapter_affiliations, certifications, is_partner_chapter, source
    ) VALUES (
      v_app_id, v_row->>'membership_status',
      parse_vep_chapters(v_row->>'membership_status'), v_row->>'certifications',
      parse_vep_chapters(v_row->>'membership_status') && (SELECT array_agg(chapter_code) FROM partner_chapters WHERE is_active = true),
      'csv_enrichment_' || coalesce(p_snapshot_date, to_char(now(), 'YYYYMMDD'))
    );
    v_enriched := v_enriched + 1;
  END LOOP;

  RETURN json_build_object('enriched', v_enriched, 'not_found', v_not_found,
    'cycle_id', p_cycle_id, 'opportunity_id', p_opportunity_id, 'snapshot_date', p_snapshot_date);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_application_interviews(p_application_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN (
    SELECT coalesce(json_agg(json_build_object(
      'id', si.id, 'scheduled_at', si.scheduled_at, 'duration_minutes', si.duration_minutes,
      'status', si.status, 'conducted_at', si.conducted_at, 'theme_of_interest', si.theme_of_interest,
      'notes', si.notes, 'interviewer_ids', si.interviewer_ids
    ) ORDER BY si.created_at DESC), '[]'::json)
    FROM selection_interviews si
    WHERE si.application_id = p_application_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_application_score_breakdown(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_evals jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager','deputy_manager') AND NOT (v_caller.designations && ARRAY['curator'])) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM selection_applications WHERE id = p_application_id;
  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error', 'application_not_found');
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'evaluation_type', e.evaluation_type,
    'evaluator_name', m.name,
    'weighted_subtotal', e.weighted_subtotal,
    'submitted_at', e.submitted_at,
    'scores', e.scores
  ) ORDER BY e.evaluation_type, m.name)
  INTO v_evals
  FROM selection_evaluations e
  JOIN members m ON m.id = e.evaluator_id
  WHERE e.application_id = p_application_id AND e.submitted_at IS NOT NULL;

  RETURN jsonb_build_object(
    'application_id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'email', v_app.email,
    'role_applied', v_app.role_applied,
    'promotion_path', v_app.promotion_path,
    'status', v_app.status,
    'research_score', v_app.research_score,
    'leader_score', v_app.leader_score,
    'rank_researcher', v_app.rank_researcher,
    'rank_leader', v_app.rank_leader,
    'evaluations', COALESCE(v_evals, '[]'::jsonb),
    'linked_application_id', v_app.linked_application_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_selection_committee(p_cycle_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN '[]'::json; END IF;

  RETURN (
    SELECT coalesce(json_agg(json_build_object(
      'id', sc.id, 'member_id', sc.member_id, 'role', sc.role, 'can_interview', sc.can_interview,
      'member_name', m.name, 'member_role', m.operational_role
    ) ORDER BY m.name), '[]'::json)
    FROM selection_committee sc
    JOIN members m ON m.id = sc.member_id
    WHERE sc.cycle_id = p_cycle_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_selection_cycles()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN '[]'::json; END IF;

  RETURN (
    SELECT coalesce(json_agg(json_build_object(
      'id', c.id, 'cycle_code', c.cycle_code, 'title', c.title, 'status', c.status
    ) ORDER BY c.created_at DESC), '[]'::json)
    FROM selection_cycles c
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_selection_rankings(p_cycle_code text DEFAULT NULL::text, p_track text DEFAULT 'both'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_cycle_id uuid;
  v_researcher jsonb;
  v_leader jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager','deputy_manager') AND NOT (v_caller.designations && ARRAY['curator'])) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: admin/GP/curator only');
  END IF;

  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    SELECT id INTO v_cycle_id FROM selection_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found');
  END IF;

  IF p_track IN ('researcher', 'both') THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rank', rank_researcher,
      'applicant_name', applicant_name,
      'chapter', chapter,
      'research_score', research_score,
      'status', status,
      'promotion_path', promotion_path
    ) ORDER BY rank_researcher), '[]'::jsonb)
    INTO v_researcher
    FROM selection_applications
    WHERE cycle_id = v_cycle_id AND rank_researcher IS NOT NULL;
  END IF;

  IF p_track IN ('leader', 'both') THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rank', rank_leader,
      'applicant_name', applicant_name,
      'chapter', chapter,
      'research_score', research_score,
      'leader_score', leader_score,
      'status', status,
      'promotion_path', promotion_path
    ) ORDER BY rank_leader), '[]'::jsonb)
    INTO v_leader
    FROM selection_applications
    WHERE cycle_id = v_cycle_id AND rank_leader IS NOT NULL;
  END IF;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'track', p_track,
    'researcher_track', COALESCE(v_researcher, '[]'::jsonb),
    'leader_track', COALESCE(v_leader, '[]'::jsonb),
    'formula', jsonb_build_object(
      'research_score', 'objective_pert + interview_pert',
      'leader_score', 'research_score * 0.7 + leader_extra_pert * 0.3',
      'tiebreaker', 'Standard Competition Ranking (ISO 80000-2) + applicant_name ASC'
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.import_historical_evaluations(p_data jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_row jsonb;
  v_app_id uuid;
  v_imported_obj int := 0;
  v_imported_intv int := 0;
  v_not_found int := 0;
  v_cycle_id uuid;
  v_criteria jsonb;
  v_cycle record;
  v_criterion jsonb;
  v_key text;
  v_weight numeric;
  v_score numeric;
  v_weighted_sum numeric;
BEGIN
  SELECT * INTO v_cycle FROM selection_cycles WHERE cycle_code = 'cycle3-2026';
  v_cycle_id := v_cycle.id;
  v_criteria := v_cycle.objective_criteria;

  FOR v_row IN SELECT * FROM jsonb_array_elements(p_data)
  LOOP
    SELECT id INTO v_app_id FROM selection_applications
    WHERE cycle_id = v_cycle_id AND lower(email) = lower(trim(v_row->>'email'))
    LIMIT 1;

    IF v_app_id IS NULL THEN v_not_found := v_not_found + 1; CONTINUE; END IF;

    -- Fabricio objective
    IF (v_row->'fabricio_scores_conv') IS NOT NULL AND jsonb_typeof(v_row->'fabricio_scores_conv') = 'object'
       AND (SELECT count(*) FROM jsonb_object_keys(v_row->'fabricio_scores_conv')) > 0 THEN
      v_weighted_sum := 0;
      FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_criteria) LOOP
        v_key := v_criterion->>'key'; v_weight := (v_criterion->>'weight')::numeric;
        v_score := COALESCE((v_row->'fabricio_scores_conv'->>v_key)::numeric, 0);
        v_weighted_sum := v_weighted_sum + (v_weight * v_score);
      END LOOP;
      INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, notes, submitted_at)
      VALUES (v_app_id, '92d26057-5550-4f15-a3bf-b00eed5f32f9', 'objective',
              v_row->'fabricio_scores_conv', ROUND(v_weighted_sum, 2),
              'Importado planilha Ciclo 3 2026 (escala 0-5→0-10)', now())
      ON CONFLICT (application_id, evaluator_id, evaluation_type)
      DO UPDATE SET scores = EXCLUDED.scores, weighted_subtotal = EXCLUDED.weighted_subtotal, notes = EXCLUDED.notes, submitted_at = EXCLUDED.submitted_at;
      v_imported_obj := v_imported_obj + 1;
    END IF;

    -- Vitor objective
    IF (v_row->'vitor_scores_conv') IS NOT NULL AND jsonb_typeof(v_row->'vitor_scores_conv') = 'object'
       AND (SELECT count(*) FROM jsonb_object_keys(v_row->'vitor_scores_conv')) > 0 THEN
      v_weighted_sum := 0;
      FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_criteria) LOOP
        v_key := v_criterion->>'key'; v_weight := (v_criterion->>'weight')::numeric;
        v_score := COALESCE((v_row->'vitor_scores_conv'->>v_key)::numeric, 0);
        v_weighted_sum := v_weighted_sum + (v_weight * v_score);
      END LOOP;
      INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, notes, submitted_at)
      VALUES (v_app_id, '880f736c-3e76-4df4-9375-33575c190305', 'objective',
              v_row->'vitor_scores_conv', ROUND(v_weighted_sum, 2),
              'Importado planilha Ciclo 3 2026 (escala 0-5→0-10)', now())
      ON CONFLICT (application_id, evaluator_id, evaluation_type)
      DO UPDATE SET scores = EXCLUDED.scores, weighted_subtotal = EXCLUDED.weighted_subtotal, notes = EXCLUDED.notes, submitted_at = EXCLUDED.submitted_at;
      v_imported_obj := v_imported_obj + 1;
    END IF;

    -- Interview (attributed to Vitor as lead)
    IF (v_row->'interview_scores_conv') IS NOT NULL AND jsonb_typeof(v_row->'interview_scores_conv') = 'object'
       AND (SELECT count(*) FROM jsonb_object_keys(v_row->'interview_scores_conv')) > 0 THEN
      v_weighted_sum := 0;
      FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_cycle.interview_criteria) LOOP
        v_key := v_criterion->>'key'; v_weight := (v_criterion->>'weight')::numeric;
        v_score := COALESCE((v_row->'interview_scores_conv'->>v_key)::numeric, 0);
        v_weighted_sum := v_weighted_sum + (v_weight * v_score);
      END LOOP;
      INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, notes, submitted_at)
      VALUES (v_app_id, '880f736c-3e76-4df4-9375-33575c190305', 'interview',
              v_row->'interview_scores_conv', ROUND(v_weighted_sum, 2),
              'Entrevistador: ' || COALESCE(v_row->>'interviewer','?') || ' | ' || COALESCE(v_row->>'interview_when','') || ' | Tema: ' || COALESCE(v_row->>'theme',''),
              now())
      ON CONFLICT (application_id, evaluator_id, evaluation_type)
      DO UPDATE SET scores = EXCLUDED.scores, weighted_subtotal = EXCLUDED.weighted_subtotal, notes = EXCLUDED.notes, submitted_at = EXCLUDED.submitted_at;
      v_imported_intv := v_imported_intv + 1;
    END IF;

    -- Update contact info
    UPDATE selection_applications SET
      phone = COALESCE(NULLIF(phone, ''), v_row->>'phone'),
      linkedin_url = COALESCE(NULLIF(linkedin_url, ''), v_row->>'linkedin'),
      proposed_theme = COALESCE(NULLIF(proposed_theme, ''), v_row->>'theme'),
      updated_at = now()
    WHERE id = v_app_id;
  END LOOP;

  -- Recalculate PERT objective
  UPDATE selection_applications sa SET objective_score_avg = sub.pert
  FROM (
    SELECT application_id, ROUND((2*MIN(weighted_subtotal)+4*AVG(weighted_subtotal)+2*MAX(weighted_subtotal))/8,2) as pert
    FROM selection_evaluations WHERE evaluation_type='objective' AND submitted_at IS NOT NULL
      AND application_id IN (SELECT id FROM selection_applications WHERE cycle_id = v_cycle_id)
    GROUP BY application_id HAVING COUNT(*)>=2
  ) sub WHERE sa.id = sub.application_id;

  -- Recalculate PERT interview + final
  UPDATE selection_applications sa SET interview_score = sub.pert, final_score = COALESCE(sa.objective_score_avg,0) + sub.pert
  FROM (
    SELECT application_id, ROUND((2*MIN(weighted_subtotal)+4*AVG(weighted_subtotal)+2*MAX(weighted_subtotal))/8,2) as pert
    FROM selection_evaluations WHERE evaluation_type='interview' AND submitted_at IS NOT NULL
      AND application_id IN (SELECT id FROM selection_applications WHERE cycle_id = v_cycle_id)
    GROUP BY application_id
  ) sub WHERE sa.id = sub.application_id;

  -- Apps with only objective score
  UPDATE selection_applications SET final_score = COALESCE(objective_score_avg,0)
  WHERE cycle_id = v_cycle_id AND interview_score IS NULL AND objective_score_avg IS NOT NULL AND final_score IS NULL;

  RETURN json_build_object('imported_objective_evals', v_imported_obj, 'imported_interview_evals', v_imported_intv, 'not_found', v_not_found);
END;
$function$;

CREATE OR REPLACE FUNCTION public.import_historical_interviews(p_data jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_row jsonb; v_app_id uuid; v_created int := 0; v_not_found int := 0;
  v_cycle_id uuid; v_when text; v_date_part text; v_scheduled_at timestamptz;
  v_fab_id uuid := '92d26057-5550-4f15-a3bf-b00eed5f32f9';
  v_vit_id uuid := '880f736c-3e76-4df4-9375-33575c190305';
  v_interviewer_ids uuid[];
BEGIN
  SELECT id INTO v_cycle_id FROM selection_cycles WHERE cycle_code = 'cycle3-2026';

  FOR v_row IN SELECT * FROM jsonb_array_elements(p_data)
  LOOP
    SELECT id INTO v_app_id FROM selection_applications
    WHERE cycle_id = v_cycle_id AND lower(email) = lower(trim(v_row->>'email'))
    AND status NOT IN ('converted', 'withdrawn', 'cancelled')
    LIMIT 1;

    IF v_app_id IS NULL THEN
      -- Try any record for this email
      SELECT id INTO v_app_id FROM selection_applications
      WHERE cycle_id = v_cycle_id AND lower(email) = lower(trim(v_row->>'email'))
      LIMIT 1;
    END IF;

    IF v_app_id IS NULL THEN v_not_found := v_not_found + 1; CONTINUE; END IF;

    -- Determine interviewers
    v_when := COALESCE(v_row->>'interviewer', '');
    IF v_when ILIKE '%Vitor%' AND v_when ILIKE '%Fabricio%' THEN
      v_interviewer_ids := ARRAY[v_vit_id, v_fab_id];
    ELSIF v_when ILIKE '%Fabricio%' THEN
      v_interviewer_ids := ARRAY[v_fab_id];
    ELSE
      v_interviewer_ids := ARRAY[v_vit_id];
    END IF;

    -- Parse date: "Realizado 1/31 9:00am (EST)" → 2026-01-31T09:00:00-05:00
    v_scheduled_at := NULL;
    v_when := COALESCE(v_row->>'when', '');
    IF v_when ILIKE '%Realizado%' OR v_when ILIKE '%realizado%' THEN
      BEGIN
        v_date_part := regexp_replace(v_when, '.*?(\d{1,2}/\d{1,2}).*', '\1');
        IF v_date_part ~ '^\d{1,2}/\d{1,2}$' THEN
          v_scheduled_at := ('2026-' || lpad(split_part(v_date_part,'/',1),2,'0') || '-' || lpad(split_part(v_date_part,'/',2),2,'0') || 'T12:00:00-03:00')::timestamptz;
        END IF;
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;

    -- Insert interview record
    INSERT INTO selection_interviews (
      application_id, interviewer_ids, scheduled_at, duration_minutes,
      status, conducted_at, theme_of_interest
    ) VALUES (
      v_app_id, v_interviewer_ids,
      COALESCE(v_scheduled_at, now()),
      30,
      'completed',
      COALESCE(v_scheduled_at, now()),
      v_row->>'theme'
    ) ON CONFLICT DO NOTHING;

    v_created := v_created + 1;
  END LOOP;

  RETURN json_build_object('created', v_created, 'not_found', v_not_found);
END;
$function$;

CREATE OR REPLACE FUNCTION public.import_leader_evaluations(p_data jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_row jsonb; v_app_id uuid; v_imported_obj int := 0; v_imported_intv int := 0; v_not_found int := 0;
  v_cycle record; v_criterion jsonb; v_key text; v_weight numeric; v_score numeric; v_weighted_sum numeric;
BEGIN
  SELECT * INTO v_cycle FROM selection_cycles WHERE cycle_code = 'cycle3-2026';

  FOR v_row IN SELECT * FROM jsonb_array_elements(p_data)
  LOOP
    SELECT id INTO v_app_id FROM selection_applications
    WHERE cycle_id = v_cycle.id AND lower(email) = lower(trim(v_row->>'email'))
    LIMIT 1;

    IF v_app_id IS NULL THEN v_not_found := v_not_found + 1; CONTINUE; END IF;

    -- Fabricio leader_extra eval
    IF (v_row->'fabricio_scores_conv') IS NOT NULL AND jsonb_typeof(v_row->'fabricio_scores_conv') = 'object'
       AND (SELECT count(*) FROM jsonb_object_keys(v_row->'fabricio_scores_conv')) > 0 THEN
      v_weighted_sum := 0;
      FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_cycle.leader_extra_criteria) LOOP
        v_key := v_criterion->>'key'; v_weight := (v_criterion->>'weight')::numeric;
        v_score := COALESCE((v_row->'fabricio_scores_conv'->>v_key)::numeric, 0);
        v_weighted_sum := v_weighted_sum + (v_weight * v_score);
      END LOOP;
      INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, notes, submitted_at)
      VALUES (v_app_id, '92d26057-5550-4f15-a3bf-b00eed5f32f9', 'leader_extra',
              v_row->'fabricio_scores_conv', ROUND(v_weighted_sum, 2),
              'Importado planilha Líderes Ciclo 3 2026 (escala 0-5→0-10)', now())
      ON CONFLICT (application_id, evaluator_id, evaluation_type)
      DO UPDATE SET scores = EXCLUDED.scores, weighted_subtotal = EXCLUDED.weighted_subtotal, notes = EXCLUDED.notes, submitted_at = EXCLUDED.submitted_at;
      v_imported_obj := v_imported_obj + 1;
    END IF;

    -- Vitor leader_extra eval
    IF (v_row->'vitor_scores_conv') IS NOT NULL AND jsonb_typeof(v_row->'vitor_scores_conv') = 'object'
       AND (SELECT count(*) FROM jsonb_object_keys(v_row->'vitor_scores_conv')) > 0 THEN
      v_weighted_sum := 0;
      FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_cycle.leader_extra_criteria) LOOP
        v_key := v_criterion->>'key'; v_weight := (v_criterion->>'weight')::numeric;
        v_score := COALESCE((v_row->'vitor_scores_conv'->>v_key)::numeric, 0);
        v_weighted_sum := v_weighted_sum + (v_weight * v_score);
      END LOOP;
      INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, notes, submitted_at)
      VALUES (v_app_id, '880f736c-3e76-4df4-9375-33575c190305', 'leader_extra',
              v_row->'vitor_scores_conv', ROUND(v_weighted_sum, 2),
              'Importado planilha Líderes Ciclo 3 2026 (escala 0-5→0-10)', now())
      ON CONFLICT (application_id, evaluator_id, evaluation_type)
      DO UPDATE SET scores = EXCLUDED.scores, weighted_subtotal = EXCLUDED.weighted_subtotal, notes = EXCLUDED.notes, submitted_at = EXCLUDED.submitted_at;
      v_imported_obj := v_imported_obj + 1;
    END IF;

    -- Interview (if not already imported from researcher sheet)
    IF (v_row->'interview_scores_conv') IS NOT NULL AND jsonb_typeof(v_row->'interview_scores_conv') = 'object'
       AND (SELECT count(*) FROM jsonb_object_keys(v_row->'interview_scores_conv')) > 0
       AND NOT EXISTS (
         SELECT 1 FROM selection_evaluations WHERE application_id = v_app_id AND evaluation_type = 'interview' AND submitted_at IS NOT NULL
       ) THEN
      v_weighted_sum := 0;
      FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_cycle.interview_criteria) LOOP
        v_key := v_criterion->>'key'; v_weight := (v_criterion->>'weight')::numeric;
        v_score := COALESCE((v_row->'interview_scores_conv'->>v_key)::numeric, 0);
        v_weighted_sum := v_weighted_sum + (v_weight * v_score);
      END LOOP;
      INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, notes, submitted_at)
      VALUES (v_app_id, '880f736c-3e76-4df4-9375-33575c190305', 'interview',
              v_row->'interview_scores_conv', ROUND(v_weighted_sum, 2),
              'Entrevista Líder: ' || COALESCE(v_row->>'interviewer','?') || ' | ' || COALESCE(v_row->>'interview_when','') || ' | Tema: ' || COALESCE(v_row->>'theme',''),
              now())
      ON CONFLICT (application_id, evaluator_id, evaluation_type)
      DO UPDATE SET scores = EXCLUDED.scores, weighted_subtotal = EXCLUDED.weighted_subtotal, notes = EXCLUDED.notes, submitted_at = EXCLUDED.submitted_at;
      v_imported_intv := v_imported_intv + 1;
    END IF;

    -- Update role_applied to 'leader' or 'both' + contact
    UPDATE selection_applications SET
      role_applied = CASE WHEN role_applied = 'researcher' THEN 'both' ELSE 'leader' END,
      phone = COALESCE(NULLIF(phone, ''), v_row->>'phone'),
      linkedin_url = COALESCE(NULLIF(linkedin_url, ''), v_row->>'linkedin'),
      proposed_theme = COALESCE(NULLIF(proposed_theme, ''), v_row->>'theme'),
      updated_at = now()
    WHERE id = v_app_id;
  END LOOP;

  -- Recalculate: leader_extra PERT adds to objective_score_avg
  UPDATE selection_applications sa SET
    objective_score_avg = COALESCE(sa.objective_score_avg, 0) + sub.pert_leader,
    final_score = COALESCE(sa.objective_score_avg, 0) + sub.pert_leader + COALESCE(sa.interview_score, 0)
  FROM (
    SELECT application_id,
      ROUND((2*MIN(weighted_subtotal)+4*AVG(weighted_subtotal)+2*MAX(weighted_subtotal))/8,2) as pert_leader
    FROM selection_evaluations WHERE evaluation_type = 'leader_extra' AND submitted_at IS NOT NULL
      AND application_id IN (SELECT id FROM selection_applications WHERE cycle_id = v_cycle.id)
    GROUP BY application_id HAVING COUNT(*) >= 2
  ) sub WHERE sa.id = sub.application_id;

  -- Recalculate interview for newly added interviews
  UPDATE selection_applications sa SET
    interview_score = sub.pert_intv,
    final_score = COALESCE(sa.objective_score_avg, 0) + sub.pert_intv
  FROM (
    SELECT application_id,
      ROUND((2*MIN(weighted_subtotal)+4*AVG(weighted_subtotal)+2*MAX(weighted_subtotal))/8,2) as pert_intv
    FROM selection_evaluations WHERE evaluation_type = 'interview' AND submitted_at IS NOT NULL
      AND application_id IN (SELECT id FROM selection_applications WHERE cycle_id = v_cycle.id)
    GROUP BY application_id
  ) sub WHERE sa.id = sub.application_id;

  RETURN json_build_object('imported_leader_evals', v_imported_obj, 'imported_interview_evals', v_imported_intv, 'not_found', v_not_found);
END;
$function$;

CREATE OR REPLACE FUNCTION public.preview_gate_eligibles(p_doc_type text, p_submitter_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_gates jsonb; v_result jsonb := '[]'::jsonb;
  v_gate jsonb; v_count int; v_sample jsonb;
BEGIN
  v_gates := public.resolve_default_gates(p_doc_type);
  IF v_gates IS NULL THEN RETURN NULL; END IF;

  FOR v_gate IN SELECT * FROM jsonb_array_elements(v_gates)
  LOOP
    SELECT count(*) INTO v_count
    FROM public.members m
    WHERE m.is_active = true
      AND public._can_sign_gate(m.id, NULL, v_gate->>'kind', p_doc_type, p_submitter_id);

    SELECT coalesce(jsonb_agg(m.name ORDER BY m.name), '[]'::jsonb) INTO v_sample
    FROM (
      SELECT m.name FROM public.members m
      WHERE m.is_active = true
        AND public._can_sign_gate(m.id, NULL, v_gate->>'kind', p_doc_type, p_submitter_id)
      ORDER BY m.name
      LIMIT 3
    ) m;

    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'gate_kind', v_gate->>'kind',
      'gate_order', (v_gate->>'order')::int,
      'threshold', v_gate->'threshold',
      'count', v_count,
      'sample', v_sample
    ));
  END LOOP;

  RETURN v_result;
END;
$function$;
