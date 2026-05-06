-- p95 #87 — candidato MCP journey (6 RPCs)
-- Issue body had 16 tools; per p86+p95 audits, anti-bias is SHIPPED (selection_cycles.phase + blind logic).
-- Remaining gap: 6 candidato/committee MCP RPCs missing.
--
-- Auth gate: same pattern as get_my_selection_result — members.auth_id = auth.uid(), then match
-- selection_applications.email (case-insensitive). Candidatos must have a members row to use MCP.
--
-- Scope: 5 candidato + 1 committee
-- 1. update_my_application(p_fields jsonb)        — patch own non-evaluator fields
-- 2. upload_my_resume(p_url, p_file_type?)        — sets resume_url
-- 3. link_my_credly_badge(p_badge_url, name?)     — sets credly_url
-- 4. get_my_application_status()                  — own apps + phase + estimated_decision
-- 5. get_my_evaluation_feedback()                 — own scores only in post-reveal phase
-- 6. get_my_committee_assignments()               — committee member's assigned apps
--
-- Rollback:
--   DROP FUNCTION IF EXISTS public.update_my_application(jsonb);
--   DROP FUNCTION IF EXISTS public.upload_my_resume(text,text);
--   DROP FUNCTION IF EXISTS public.link_my_credly_badge(text,text);
--   DROP FUNCTION IF EXISTS public.get_my_application_status();
--   DROP FUNCTION IF EXISTS public.get_my_evaluation_feedback();
--   DROP FUNCTION IF EXISTS public.get_my_committee_assignments();

-- ============================================================
-- update_my_application — patch whitelisted fields on own application
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_my_application(p_fields jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app_id uuid;
  v_status text;
  v_phase text;
  v_allowed_keys text[] := ARRAY[
    'linkedin_url','resume_url','motivation_letter','areas_of_interest',
    'leadership_experience','academic_background','non_pmi_experience',
    'availability_declared','proposed_theme','credly_url',
    'linkedin_relevant_posts','reason_for_applying','phone'
  ];
  v_filtered jsonb := '{}'::jsonb;
  v_key text;
  v_updated_keys text[] := '{}';
BEGIN
  SELECT id, email, name INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_fields IS NULL OR jsonb_typeof(p_fields) <> 'object' THEN
    RAISE EXCEPTION 'p_fields must be a jsonb object';
  END IF;

  FOR v_key IN SELECT jsonb_object_keys(p_fields)
  LOOP
    IF v_key = ANY(v_allowed_keys) THEN
      v_filtered := v_filtered || jsonb_build_object(v_key, p_fields -> v_key);
      v_updated_keys := array_append(v_updated_keys, v_key);
    END IF;
  END LOOP;

  IF jsonb_typeof(v_filtered) = 'object' AND v_filtered = '{}'::jsonb THEN
    RAISE EXCEPTION 'No allowed fields in p_fields. Allowed: %', array_to_string(v_allowed_keys, ', ');
  END IF;

  SELECT a.id, a.status, sc.phase INTO v_app_id, v_status, v_phase
  FROM public.selection_applications a
  JOIN public.selection_cycles sc ON sc.id = a.cycle_id
  WHERE lower(trim(a.email)) = lower(trim(v_caller.email))
    AND a.status NOT IN ('approved','converted','rejected','objective_cutoff','withdrawn','cancelled')
  ORDER BY a.created_at DESC
  LIMIT 1;

  IF v_app_id IS NULL THEN
    RAISE EXCEPTION 'No active application found for %', v_caller.email;
  END IF;

  IF v_phase IN ('evaluating','interviews','ranking') THEN
    RAISE EXCEPTION 'Cannot edit application during phase %: contact comitê if needed', v_phase;
  END IF;

  UPDATE public.selection_applications a SET
    linkedin_url        = COALESCE((v_filtered->>'linkedin_url'), linkedin_url),
    resume_url          = COALESCE((v_filtered->>'resume_url'), resume_url),
    motivation_letter   = COALESCE((v_filtered->>'motivation_letter'), motivation_letter),
    areas_of_interest   = COALESCE((v_filtered->>'areas_of_interest'), areas_of_interest),
    leadership_experience = COALESCE((v_filtered->>'leadership_experience'), leadership_experience),
    academic_background = COALESCE((v_filtered->>'academic_background'), academic_background),
    non_pmi_experience  = COALESCE((v_filtered->>'non_pmi_experience'), non_pmi_experience),
    availability_declared = COALESCE((v_filtered->>'availability_declared'), availability_declared),
    proposed_theme      = COALESCE((v_filtered->>'proposed_theme'), proposed_theme),
    credly_url          = COALESCE((v_filtered->>'credly_url'), credly_url),
    reason_for_applying = COALESCE((v_filtered->>'reason_for_applying'), reason_for_applying),
    phone               = COALESCE((v_filtered->>'phone'), phone),
    linkedin_relevant_posts = CASE
      WHEN v_filtered ? 'linkedin_relevant_posts'
      THEN (SELECT array_agg(value::text) FROM jsonb_array_elements_text(v_filtered->'linkedin_relevant_posts'))
      ELSE linkedin_relevant_posts
    END,
    updated_at = now()
  WHERE a.id = v_app_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id, 'update_my_application', 'selection_application', v_app_id,
    jsonb_build_object('updated_keys', to_jsonb(v_updated_keys)),
    jsonb_build_object('source','mcp','issue','#87','phase_at_edit', v_phase)
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_app_id,
    'updated_fields', to_jsonb(v_updated_keys)
  );
END; $function$;

GRANT EXECUTE ON FUNCTION public.update_my_application(jsonb) TO authenticated;

-- ============================================================
-- upload_my_resume — sets resume_url with optional file_type
-- ============================================================
CREATE OR REPLACE FUNCTION public.upload_my_resume(
  p_url text,
  p_file_type text DEFAULT 'pdf'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app_id uuid;
  v_phase text;
BEGIN
  SELECT id, email, name INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_url IS NULL OR length(trim(p_url)) = 0 THEN
    RAISE EXCEPTION 'p_url is required';
  END IF;

  SELECT a.id, sc.phase INTO v_app_id, v_phase
  FROM public.selection_applications a
  JOIN public.selection_cycles sc ON sc.id = a.cycle_id
  WHERE lower(trim(a.email)) = lower(trim(v_caller.email))
    AND a.status NOT IN ('approved','converted','rejected','objective_cutoff','withdrawn','cancelled')
  ORDER BY a.created_at DESC
  LIMIT 1;

  IF v_app_id IS NULL THEN
    RAISE EXCEPTION 'No active application found for %', v_caller.email;
  END IF;
  IF v_phase IN ('evaluating','interviews','ranking') THEN
    RAISE EXCEPTION 'Cannot update resume during phase %: contact comitê', v_phase;
  END IF;

  UPDATE public.selection_applications
     SET resume_url = trim(p_url), updated_at = now()
   WHERE id = v_app_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id, 'upload_my_resume', 'selection_application', v_app_id,
    jsonb_build_object('resume_url', p_url, 'file_type', p_file_type),
    jsonb_build_object('source','mcp','issue','#87')
  );

  RETURN jsonb_build_object('success', true, 'application_id', v_app_id, 'resume_url', p_url);
END; $function$;

GRANT EXECUTE ON FUNCTION public.upload_my_resume(text,text) TO authenticated;

-- ============================================================
-- link_my_credly_badge — sets credly_url + optionally records badge_name in metadata
-- ============================================================
CREATE OR REPLACE FUNCTION public.link_my_credly_badge(
  p_badge_url text,
  p_badge_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app_id uuid;
  v_phase text;
BEGIN
  SELECT id, email, name INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_badge_url IS NULL OR length(trim(p_badge_url)) = 0 THEN
    RAISE EXCEPTION 'p_badge_url is required';
  END IF;

  SELECT a.id, sc.phase INTO v_app_id, v_phase
  FROM public.selection_applications a
  JOIN public.selection_cycles sc ON sc.id = a.cycle_id
  WHERE lower(trim(a.email)) = lower(trim(v_caller.email))
    AND a.status NOT IN ('approved','converted','rejected','objective_cutoff','withdrawn','cancelled')
  ORDER BY a.created_at DESC
  LIMIT 1;

  IF v_app_id IS NULL THEN
    RAISE EXCEPTION 'No active application found for %', v_caller.email;
  END IF;
  IF v_phase IN ('evaluating','interviews','ranking') THEN
    RAISE EXCEPTION 'Cannot link badge during phase %: contact comitê', v_phase;
  END IF;

  UPDATE public.selection_applications
     SET credly_url = trim(p_badge_url), updated_at = now()
   WHERE id = v_app_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id, 'link_my_credly_badge', 'selection_application', v_app_id,
    jsonb_build_object('credly_url', p_badge_url, 'badge_name', p_badge_name),
    jsonb_build_object('source','mcp','issue','#87')
  );

  RETURN jsonb_build_object('success', true, 'application_id', v_app_id, 'credly_url', p_badge_url);
END; $function$;

GRANT EXECUTE ON FUNCTION public.link_my_credly_badge(text,text) TO authenticated;

-- ============================================================
-- get_my_application_status — own apps with current phase + decision estimate
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_my_application_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_apps jsonb;
BEGIN
  SELECT id, email, name INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.created_at DESC), '[]'::jsonb) INTO v_apps
  FROM (
    SELECT
      a.id AS application_id,
      a.cycle_id,
      sc.cycle_code,
      sc.title AS cycle_title,
      sc.phase,
      sc.status AS cycle_status,
      sc.close_date,
      a.role_applied,
      a.promotion_path,
      a.status,
      a.cycle_decision_date,
      a.created_at,
      a.updated_at,
      a.linkedin_url,
      a.resume_url,
      a.credly_url,
      a.motivation_letter IS NOT NULL AS has_motivation,
      a.consent_ai_analysis_at IS NOT NULL AS ai_consent_granted,
      CASE
        WHEN sc.phase = 'evaluating' THEN (
          SELECT COUNT(*)::int FROM public.selection_evaluations e
          WHERE e.application_id = a.id AND e.submitted_at IS NOT NULL
        )
        ELSE NULL
      END AS submitted_evaluations_count,
      a.status = ANY(ARRAY['approved','converted','rejected','objective_cutoff','withdrawn','cancelled']) AS is_final
    FROM public.selection_applications a
    JOIN public.selection_cycles sc ON sc.id = a.cycle_id
    WHERE lower(trim(a.email)) = lower(trim(v_caller.email))
  ) r;

  RETURN jsonb_build_object(
    'member_id', v_caller.id,
    'email', v_caller.email,
    'applications', v_apps,
    'count', jsonb_array_length(v_apps)
  );
END; $function$;

GRANT EXECUTE ON FUNCTION public.get_my_application_status() TO authenticated;

-- ============================================================
-- get_my_evaluation_feedback — own scores ONLY in post-reveal phase
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_my_evaluation_feedback()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_evals jsonb;
  v_reveal_phases text[] := ARRAY['evaluations_closed','interviews','interviews_closed','ranking','announcement','onboarding']::text[];
BEGIN
  SELECT id, email, name INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  SELECT a.id, a.objective_score_avg, a.interview_score, a.research_score, a.leader_score,
         a.feedback, a.status, sc.phase, sc.cycle_code
  INTO v_app
  FROM public.selection_applications a
  JOIN public.selection_cycles sc ON sc.id = a.cycle_id
  WHERE lower(trim(a.email)) = lower(trim(v_caller.email))
  ORDER BY a.created_at DESC
  LIMIT 1;

  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error','no_application');
  END IF;

  IF NOT (v_app.phase = ANY(v_reveal_phases))
     AND v_app.status NOT IN ('approved','converted','rejected','objective_cutoff') THEN
    RETURN jsonb_build_object(
      'feedback_available', false,
      'reason', 'phase_not_revealed',
      'current_phase', v_app.phase,
      'note', 'Feedback será disponibilizado quando o ciclo entrar em fase de revelação (evaluations_closed em diante).'
    );
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.evaluation_type), '[]'::jsonb) INTO v_evals
  FROM (
    SELECT e.evaluation_type, e.weighted_subtotal, e.scores, e.notes, e.submitted_at
    FROM public.selection_evaluations e
    WHERE e.application_id = v_app.id AND e.submitted_at IS NOT NULL
  ) r;

  RETURN jsonb_build_object(
    'feedback_available', true,
    'application_id', v_app.id,
    'cycle_code', v_app.cycle_code,
    'phase', v_app.phase,
    'status', v_app.status,
    'objective_score_avg', v_app.objective_score_avg,
    'interview_score', v_app.interview_score,
    'research_score', v_app.research_score,
    'leader_score', v_app.leader_score,
    'narrative_feedback', v_app.feedback,
    'evaluations', v_evals
  );
END; $function$;

GRANT EXECUTE ON FUNCTION public.get_my_evaluation_feedback() TO authenticated;

-- ============================================================
-- get_my_committee_assignments — applications assigned to caller as committee member
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_my_committee_assignments()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_committee_cycles uuid[];
  v_assignments jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  SELECT array_agg(DISTINCT cycle_id) INTO v_committee_cycles
  FROM public.selection_committee
  WHERE member_id = v_caller_id;

  IF v_committee_cycles IS NULL OR array_length(v_committee_cycles, 1) IS NULL THEN
    RETURN jsonb_build_object(
      'is_committee_member', false,
      'assignments', '[]'::jsonb,
      'count', 0
    );
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.created_at DESC), '[]'::jsonb) INTO v_assignments
  FROM (
    SELECT
      a.id AS application_id,
      a.cycle_id,
      sc.cycle_code,
      sc.phase AS cycle_phase,
      a.applicant_name,
      a.role_applied,
      a.promotion_path,
      a.status,
      a.created_at,
      EXISTS (
        SELECT 1 FROM public.selection_evaluations e
        WHERE e.application_id = a.id
          AND e.evaluator_id = v_caller_id
          AND e.submitted_at IS NOT NULL
      ) AS i_have_submitted,
      (
        SELECT count(*)::int FROM public.selection_evaluations e
        WHERE e.application_id = a.id
          AND e.evaluator_id = v_caller_id
      ) AS my_evaluation_rows,
      sc.min_evaluators
    FROM public.selection_applications a
    JOIN public.selection_cycles sc ON sc.id = a.cycle_id
    WHERE a.cycle_id = ANY(v_committee_cycles)
      AND a.status NOT IN ('withdrawn','cancelled')
  ) r;

  RETURN jsonb_build_object(
    'is_committee_member', true,
    'cycle_ids', to_jsonb(v_committee_cycles),
    'assignments', v_assignments,
    'count', jsonb_array_length(v_assignments)
  );
END; $function$;

GRANT EXECUTE ON FUNCTION public.get_my_committee_assignments() TO authenticated;
