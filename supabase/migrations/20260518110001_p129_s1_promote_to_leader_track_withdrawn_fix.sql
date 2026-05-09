-- p129 S1 Sistemic fix: promote_to_leader_track RPC must set researcher app
-- status='withdrawn' (not allow it to remain in flow that may be auto/manually rejected).
-- Driver: Herlon + Ana/Hayala/Marcos cycle 3 batch 1 — researcher apps showing 'rejected'
-- when semantically they should be 'withdrawn' (candidate accepted as leader instead).
-- PM Vitor flagged: "naturalmente ocorre na vaga de pesquisador pq a pessoa que é lider
-- aceita so a de lider".

CREATE OR REPLACE FUNCTION public.promote_to_leader_track(p_application_id uuid, p_create_leader_app boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_src record;
  v_new_leader_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'promote') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires promote permission');
  END IF;
  SELECT * INTO v_src FROM public.selection_applications WHERE id = p_application_id;
  IF v_src.id IS NULL THEN RETURN jsonb_build_object('error', 'application_not_found'); END IF;
  IF v_src.role_applied = 'leader' THEN RETURN jsonb_build_object('error', 'already_leader_track'); END IF;

  -- p129 fix: when promoting to leader track, mark researcher app as 'withdrawn'
  -- (semantically correct: candidate is no longer pursuing researcher track).
  -- Status preserved if already terminal (approved/rejected/withdrawn) to avoid
  -- overwriting historical decisions.
  UPDATE public.selection_applications
  SET promotion_path = 'triaged_to_leader',
      track_decided_at = now(),
      track_decided_by = v_caller_id,
      status = CASE
        WHEN status IN ('approved', 'rejected', 'withdrawn') THEN status
        ELSE 'withdrawn'
      END,
      feedback = CASE
        WHEN status IN ('approved', 'rejected', 'withdrawn') THEN feedback
        ELSE COALESCE(feedback || E'\n\n', '') ||
             '[auto] Withdrawn from researcher track upon promotion to leader track (linked leader application created).'
      END,
      updated_at = now()
  WHERE id = p_application_id;

  IF p_create_leader_app THEN
    INSERT INTO public.selection_applications (
      cycle_id, applicant_name, email, phone, chapter, role_applied, status,
      linkedin_url, motivation_letter, academic_background, areas_of_interest,
      availability_declared, non_pmi_experience, proposed_theme, leadership_experience,
      linked_application_id, promotion_path, track_decided_at, track_decided_by, created_at
    )
    SELECT cycle_id, applicant_name, email, phone, chapter, 'leader', 'submitted',
           linkedin_url, motivation_letter, academic_background, areas_of_interest,
           availability_declared, non_pmi_experience, proposed_theme, leadership_experience,
           id, 'triaged_to_leader', now(), v_caller_id, now()
    FROM public.selection_applications WHERE id = p_application_id
    RETURNING id INTO v_new_leader_id;
    UPDATE public.selection_applications SET linked_application_id = v_new_leader_id WHERE id = p_application_id;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_caller_id,
    'promote_to_leader_track',
    'selection_application',
    p_application_id,
    jsonb_build_object(
      'created_leader_app', v_new_leader_id,
      'original_role', v_src.role_applied,
      'original_status', v_src.status,
      'researcher_app_marked_withdrawn', v_src.status NOT IN ('approved', 'rejected', 'withdrawn')
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'researcher_application_id', p_application_id,
    'leader_application_id', v_new_leader_id,
    'promotion_path', 'triaged_to_leader'
  );
END; $function$;

NOTIFY pgrst, 'reload schema';
