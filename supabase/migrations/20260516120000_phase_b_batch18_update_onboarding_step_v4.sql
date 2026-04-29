-- Phase B'' batch 18.3: update_onboarding_step V3 sa-bypass → V4 can_by_member('manage_platform')
-- V3 composite: own step (resource) OR is_superadmin OR committee lead (resource)
-- V4: replace is_superadmin IS TRUE with can_by_member('manage_platform')
-- Resource-scoped checks (member.id = v_member_id + committee role='lead') preserved
-- Impact: V3=2 sa, V4=2 manage_platform (clean match; +manager/deputy/co_gp parity)
CREATE OR REPLACE FUNCTION public.update_onboarding_step(p_application_id uuid, p_step_key text, p_status text DEFAULT 'completed'::text, p_evidence_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_step record;
  v_member_id uuid;
  v_total int;
  v_completed int;
  v_all_done boolean;
  v_tribe_leader record;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Validate status
  IF p_status NOT IN ('completed', 'skipped', 'in_progress') THEN
    RAISE EXCEPTION 'Invalid status: must be completed, skipped, or in_progress';
  END IF;

  -- 3. Get application
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- 4. Get step
  SELECT * INTO v_step FROM public.onboarding_progress
    WHERE application_id = p_application_id AND step_key = p_step_key;
  IF v_step IS NULL THEN
    RAISE EXCEPTION 'Onboarding step not found';
  END IF;

  v_member_id := v_step.member_id;

  -- 5. V4 Authorization: own step, committee lead (resource), or platform admin
  IF NOT public.can_by_member(v_caller.id, 'manage_platform'::text) AND v_caller.id != v_member_id THEN
    DECLARE v_is_lead boolean := false;
    BEGIN
      SELECT EXISTS(
        SELECT 1 FROM public.selection_committee
        WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead'
      ) INTO v_is_lead;
      IF NOT v_is_lead THEN
        RAISE EXCEPTION 'Unauthorized: can only update own steps, be committee lead, or platform admin';
      END IF;
    END;
  END IF;

  -- 6. Update step
  UPDATE public.onboarding_progress
  SET status = p_status,
      completed_at = CASE WHEN p_status IN ('completed', 'skipped') THEN now() ELSE NULL END,
      evidence_url = COALESCE(p_evidence_url, evidence_url)
  WHERE application_id = p_application_id AND step_key = p_step_key;

  -- 7. Check if all steps are done
  SELECT COUNT(*) INTO v_total FROM public.onboarding_progress WHERE application_id = p_application_id;
  SELECT COUNT(*) INTO v_completed FROM public.onboarding_progress
    WHERE application_id = p_application_id AND status IN ('completed', 'skipped');

  v_all_done := (v_completed = v_total AND v_total > 0);

  -- 8. If all steps done → activate member + notify
  IF v_all_done AND v_member_id IS NOT NULL THEN
    UPDATE public.members
    SET is_active = true,
        current_cycle_active = true
    WHERE id = v_member_id;

    -- Update application status
    UPDATE public.selection_applications
    SET status = 'approved', updated_at = now()
    WHERE id = p_application_id;

    -- Notify tribe leader
    IF EXISTS(SELECT 1 FROM public.members WHERE id = v_member_id AND tribe_id IS NOT NULL) THEN
      SELECT m.* INTO v_tribe_leader
      FROM public.members m
      WHERE m.tribe_id = (SELECT tribe_id FROM public.members WHERE id = v_member_id)
        AND m.operational_role = 'tribe_leader'
      LIMIT 1;

      IF v_tribe_leader.id IS NOT NULL THEN
        PERFORM public.create_notification(
          v_tribe_leader.id,
          'selection_onboarding_complete',
          'Onboarding Concluído',
          v_app.applicant_name || ' completou o onboarding e está ativo na tribo.',
          '/workspace',
          'selection_application',
          p_application_id
        );
      END IF;
    END IF;

    -- Notify comms team
    PERFORM public.create_notification(
      v_caller.id,
      'selection_onboarding_complete',
      'Onboarding Concluído',
      v_app.applicant_name || ' completou todas as etapas de onboarding.',
      '/admin/selection',
      'selection_application',
      p_application_id
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'step_key', p_step_key,
    'new_status', p_status,
    'all_done', v_all_done,
    'completed_steps', v_completed,
    'total_steps', v_total
  );
END;
$function$;
