-- #511 — sibling self-service RPCs: match the caller's application by PRIMARY email OR any member_emails alternate.
-- Sweep mirror of #447 (get_my_application_status). Before: each RPC resolved the candidate's application by the
-- member's PRIMARY email only (members.email), so applications whose canonical selection_applications.email is a
-- reconciled ALTERNATE (post-#445 member_emails) were invisible to the candidate's own self-service surface — and,
-- for export_my_data(), OMITTED FROM THE LGPD Art.18 data export.
-- After: WHERE selection_applications.email IN (caller's primary UNION caller's member_emails alternates).
-- Safe (no leak): member_emails.email is globally UNIQUE and no email maps to >1 member (verified live 2026-06-05:
--                 0 emails owned by >1 member), so the UNION cannot surface another person's application.
-- Affected RPCs (all body-only CREATE OR REPLACE, same signatures, no new params):
--   export_my_data(), get_my_selection_result(), get_my_evaluation_feedback(),
--   update_my_application(jsonb), upload_my_resume(text,text).
-- Rollback: re-apply each pre-#511 body (single-equality WHERE lower(trim(a.email)) = lower(trim(v_caller.email)),
--           and for export_my_data WHERE sa.email = v_member_email).

-- ── 1. export_my_data() — LGPD Art.18 export must include alternate-email applications ──────────────
CREATE OR REPLACE FUNCTION public.export_my_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_member_email text;
  v_person_id uuid;
  v_result jsonb;
BEGIN
  SELECT id, email INTO v_member_id, v_member_email
  FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT id INTO v_person_id FROM public.persons WHERE legacy_member_id = v_member_id;

  SELECT jsonb_build_object(
    'profile', (SELECT row_to_json(m)::jsonb FROM public.members m WHERE m.id = v_member_id),
    'person', CASE WHEN v_person_id IS NOT NULL THEN
      (SELECT row_to_json(p)::jsonb FROM public.persons p WHERE p.id = v_person_id)
    ELSE NULL END,
    'engagements', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', e.id, 'kind', e.kind, 'role', e.role, 'status', e.status,
        'initiative_name', i.name, 'start_date', e.start_date, 'end_date', e.end_date,
        'legal_basis', e.legal_basis, 'has_agreement', (e.agreement_certificate_id IS NOT NULL),
        'granted_at', e.granted_at, 'revoked_at', e.revoked_at, 'revoke_reason', e.revoke_reason
      ) ORDER BY e.start_date DESC)
      FROM public.engagements e LEFT JOIN public.initiatives i ON i.id = e.initiative_id
      WHERE e.person_id = v_person_id
    ), '[]'::jsonb),
    'attendance', COALESCE((SELECT jsonb_agg(row_to_json(a)::jsonb) FROM public.attendance a WHERE a.member_id = v_member_id), '[]'::jsonb),
    'gamification', COALESCE((SELECT jsonb_agg(row_to_json(g)::jsonb) FROM public.gamification_points g WHERE g.member_id = v_member_id), '[]'::jsonb),
    'notifications', COALESCE((SELECT jsonb_agg(row_to_json(n)::jsonb) FROM public.notifications n WHERE n.recipient_id = v_member_id), '[]'::jsonb),
    'board_assignments', COALESCE((SELECT jsonb_agg(row_to_json(ba)::jsonb) FROM public.board_item_assignments ba WHERE ba.member_id = v_member_id), '[]'::jsonb),
    'cycle_history', COALESCE((SELECT jsonb_agg(row_to_json(mch)::jsonb) FROM public.member_cycle_history mch WHERE mch.member_id = v_member_id), '[]'::jsonb),
    'certificates', COALESCE((SELECT jsonb_agg(row_to_json(c)::jsonb) FROM public.certificates c WHERE c.member_id = v_member_id), '[]'::jsonb),
    -- #511: include applications under the caller's PRIMARY email OR any member_emails alternate (LGPD Art.18 completeness).
    'selection_applications', COALESCE((
      SELECT jsonb_agg(row_to_json(sa)::jsonb)
      FROM public.selection_applications sa
      WHERE lower(trim(sa.email)) IN (
        SELECT lower(trim(m.email::text))  FROM public.members m        WHERE m.id = v_member_id         AND m.email IS NOT NULL
        UNION
        SELECT lower(trim(me.email::text)) FROM public.member_emails me WHERE me.member_id = v_member_id AND me.email IS NOT NULL
      )
    ), '[]'::jsonb),
    'onboarding', COALESCE((SELECT jsonb_agg(row_to_json(op)::jsonb) FROM public.onboarding_progress op WHERE op.member_id = v_member_id), '[]'::jsonb),
    'exported_at', now()
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- ── 2. get_my_selection_result() ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_my_selection_result()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_apps jsonb;
  v_is_final boolean;
BEGIN
  SELECT id, email, name INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Find all applications matching this member's email (could be 2 for dual-track)
  SELECT coalesce(jsonb_agg(row_to_json(app_data) ORDER BY (app_data->>'created_at') DESC), '[]'::jsonb)
  INTO v_apps
  FROM (
    SELECT
      a.id as application_id,
      a.cycle_id,
      sc.cycle_code,
      sc.title as cycle_title,
      a.role_applied,
      a.promotion_path,
      a.status,
      a.created_at,
      -- Status is "final" if approved, converted, rejected, withdrawn, cancelled, or objective_cutoff
      a.status = ANY(ARRAY['approved','converted','rejected','objective_cutoff','withdrawn','cancelled']) as is_final,
      -- Own scores (always visible when stage is complete)
      a.objective_score_avg as objective_score,
      a.interview_score,
      a.research_score,
      a.leader_score,
      -- Rank — ONLY shown when status is final (avoid oscillation anxiety)
      CASE
        WHEN a.status = ANY(ARRAY['approved','converted','rejected','objective_cutoff','withdrawn','cancelled'])
        THEN a.rank_researcher
        ELSE NULL
      END as rank_researcher,
      CASE
        WHEN a.status = ANY(ARRAY['approved','converted','rejected','objective_cutoff','withdrawn','cancelled'])
        THEN a.rank_leader
        ELSE NULL
      END as rank_leader,
      -- Breakdown of evaluations (own rows only)
      (
        SELECT jsonb_object_agg(
          e.evaluation_type,
          jsonb_build_object(
            'pert_score', e.weighted_subtotal,
            'submitted_at', e.submitted_at
          )
        )
        FROM selection_evaluations e
        WHERE e.application_id = a.id AND e.submitted_at IS NOT NULL
        AND e.evaluator_id IN (
          -- Average across evaluators — one row per type
          SELECT evaluator_id FROM selection_evaluations WHERE application_id = a.id AND submitted_at IS NOT NULL LIMIT 1
        )
      ) as own_evaluations_sample,
      -- Total pool size for relative context
      (
        SELECT count(*) FROM selection_applications sa2
        WHERE sa2.cycle_id = a.cycle_id
          AND sa2.role_applied = a.role_applied
          AND sa2.status NOT IN ('withdrawn','cancelled')
      ) as track_pool_size
    FROM selection_applications a
    JOIN selection_cycles sc ON sc.id = a.cycle_id
    -- #511: match caller's PRIMARY email OR any member_emails alternate (leak-safe: member_emails.email globally UNIQUE).
    WHERE lower(trim(a.email)) IN (
      SELECT lower(trim(m.email::text))  FROM public.members m        WHERE m.id = v_caller.id         AND m.email IS NOT NULL
      UNION
      SELECT lower(trim(me.email::text)) FROM public.member_emails me WHERE me.member_id = v_caller.id AND me.email IS NOT NULL
    )
  ) app_data;

  RETURN jsonb_build_object(
    'member_id', v_caller.id,
    'member_name', v_caller.name,
    'applications', v_apps,
    'note', 'Ranks são exibidos apenas após o status final da seleção. Durante o processo, você vê apenas seu status e notas próprias.'
  );
END;
$function$;

-- ── 3. get_my_evaluation_feedback() ────────────────────────────────────────────────────────────────
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

  -- Most recent application
  SELECT a.id, a.objective_score_avg, a.interview_score, a.research_score, a.leader_score,
         a.feedback, a.status, sc.phase, sc.cycle_code
  INTO v_app
  FROM public.selection_applications a
  JOIN public.selection_cycles sc ON sc.id = a.cycle_id
  -- #511: match caller's PRIMARY email OR any member_emails alternate (leak-safe: member_emails.email globally UNIQUE).
  WHERE lower(trim(a.email)) IN (
    SELECT lower(trim(m.email::text))  FROM public.members m        WHERE m.id = v_caller.id         AND m.email IS NOT NULL
    UNION
    SELECT lower(trim(me.email::text)) FROM public.member_emails me WHERE me.member_id = v_caller.id AND me.email IS NOT NULL
  )
  ORDER BY a.created_at DESC
  LIMIT 1;

  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error','no_application');
  END IF;

  -- Gate: only post-reveal phase OR final status
  IF NOT (v_app.phase = ANY(v_reveal_phases))
     AND v_app.status NOT IN ('approved','converted','rejected','objective_cutoff') THEN
    RETURN jsonb_build_object(
      'feedback_available', false,
      'reason', 'phase_not_revealed',
      'current_phase', v_app.phase,
      'note', 'Feedback será disponibilizado quando o ciclo entrar em fase de revelação (evaluations_closed em diante).'
    );
  END IF;

  -- Aggregate evaluations (own application only)
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
END;
$function$;

-- ── 4. update_my_application(p_fields jsonb) ───────────────────────────────────────────────────────
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

  -- Filter to allowed keys only
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

  -- Find candidate's most recent non-terminal application
  -- #511: match caller's PRIMARY email OR any member_emails alternate (leak-safe: member_emails.email globally UNIQUE).
  SELECT a.id, a.status, sc.phase INTO v_app_id, v_status, v_phase
  FROM public.selection_applications a
  JOIN public.selection_cycles sc ON sc.id = a.cycle_id
  WHERE lower(trim(a.email)) IN (
      SELECT lower(trim(m.email::text))  FROM public.members m        WHERE m.id = v_caller.id         AND m.email IS NOT NULL
      UNION
      SELECT lower(trim(me.email::text)) FROM public.member_emails me WHERE me.member_id = v_caller.id AND me.email IS NOT NULL
    )
    AND a.status NOT IN ('approved','converted','rejected','objective_cutoff','withdrawn','cancelled')
  ORDER BY a.created_at DESC
  LIMIT 1;

  IF v_app_id IS NULL THEN
    RAISE EXCEPTION 'No active application found for %', v_caller.email;
  END IF;

  -- Block edits during evaluation phases (avoid candidato editing while being evaluated)
  IF v_phase IN ('evaluating','interviews','ranking') THEN
    RAISE EXCEPTION 'Cannot edit application during phase %: contact comitê if needed', v_phase;
  END IF;

  -- Apply patch — use jsonb_populate_record-like pattern via dynamic UPDATE
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

-- ── 5. upload_my_resume(p_url text, p_file_type text) ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.upload_my_resume(p_url text, p_file_type text DEFAULT 'pdf'::text)
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

  -- #511: match caller's PRIMARY email OR any member_emails alternate (leak-safe: member_emails.email globally UNIQUE).
  SELECT a.id, sc.phase INTO v_app_id, v_phase
  FROM public.selection_applications a
  JOIN public.selection_cycles sc ON sc.id = a.cycle_id
  WHERE lower(trim(a.email)) IN (
      SELECT lower(trim(m.email::text))  FROM public.members m        WHERE m.id = v_caller.id         AND m.email IS NOT NULL
      UNION
      SELECT lower(trim(me.email::text)) FROM public.member_emails me WHERE me.member_id = v_caller.id AND me.email IS NOT NULL
    )
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

-- Review fold (#511): make get_my_selection_result's authenticated EXECUTE explicit.
-- The other four RPCs carry an explicit GRANT in earlier migrations; this one relied on the
-- Postgres PUBLIC default only. Idempotent — locks the grant independent of any future
-- change to the PUBLIC default posture. (prosrc-neutral: does not alter any function body.)
GRANT EXECUTE ON FUNCTION public.get_my_selection_result() TO authenticated;
