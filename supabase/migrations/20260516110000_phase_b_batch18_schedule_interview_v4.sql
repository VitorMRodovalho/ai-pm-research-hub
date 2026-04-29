-- Phase B'' batch 18.2: schedule_interview V3 sa-bypass → V4 can_by_member('manage_platform')
-- V3 composite gate: committee lead (resource) OR is_superadmin
-- V4: replace is_superadmin IS TRUE with can_by_member('manage_platform')
-- Resource-scoped check (committee role='lead') preserved
-- Impact: V3=2 sa, V4=2 manage_platform (clean match; +manager/deputy/co_gp parity)
CREATE OR REPLACE FUNCTION public.schedule_interview(p_application_id uuid, p_interviewer_ids uuid[], p_scheduled_at timestamp with time zone, p_duration_minutes integer DEFAULT 30, p_calendar_event_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
  v_interview_id uuid;
  v_interviewer_id uuid;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Get application
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- 3. V4 authorization: committee lead (resource) or platform admin
  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or platform admin';
  END IF;

  -- 4. Validate application is ready for interview
  IF v_app.status NOT IN ('interview_pending', 'interview_scheduled') THEN
    RAISE EXCEPTION 'Application status % does not allow scheduling interview', v_app.status;
  END IF;

  -- 5. Create interview record
  INSERT INTO public.selection_interviews (
    application_id, interviewer_ids, scheduled_at,
    duration_minutes, status, calendar_event_id
  ) VALUES (
    p_application_id, p_interviewer_ids, p_scheduled_at,
    p_duration_minutes, 'scheduled', p_calendar_event_id
  )
  RETURNING id INTO v_interview_id;

  -- 6. Update application status
  UPDATE public.selection_applications
  SET status = 'interview_scheduled', updated_at = now()
  WHERE id = p_application_id;

  -- 7. Notify interviewers
  FOREACH v_interviewer_id IN ARRAY p_interviewer_ids
  LOOP
    PERFORM public.create_notification(
      v_interviewer_id,
      'selection_interview_scheduled',
      'Entrevista agendada: ' || v_app.applicant_name,
      'Entrevista com ' || v_app.applicant_name || ' (' || COALESCE(v_app.chapter, '') || ') agendada para ' || to_char(p_scheduled_at, 'DD/MM/YYYY HH24:MI'),
      '/admin/selection',
      'selection_interview',
      v_interview_id
    );
  END LOOP;

  -- 8. Notify candidate if they are a member
  PERFORM public.create_notification(
    m.id,
    'selection_interview_scheduled',
    'Sua entrevista foi agendada',
    'Entrevista agendada para ' || to_char(p_scheduled_at, 'DD/MM/YYYY HH24:MI') || '. Prepare-se!',
    NULL,
    'selection_interview',
    v_interview_id
  )
  FROM public.members m
  WHERE m.email = v_app.email;

  RETURN jsonb_build_object(
    'success', true,
    'interview_id', v_interview_id,
    'scheduled_at', p_scheduled_at,
    'application_status', 'interview_scheduled'
  );
END;
$function$;
