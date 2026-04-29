-- Phase B'' batch 17.5: finalize_decisions V3 hardcode → V4 can_by_member('manage_platform')
-- V3 admin bypass: is_superadmin OR operational_role IN ('manager','deputy_manager')
-- V4 mapping: manage_platform (covers sa + manager/deputy_manager/co_gp)
-- Resource-scoped check (committee lead) preserved
-- Impact: V3=2, V4=2 admin-bypass (clean match; +co_gp parity is admin-tier consistent)
CREATE OR REPLACE FUNCTION public.finalize_decisions(p_cycle_id uuid, p_decisions jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_committee record;
  v_decision jsonb;
  v_app_id uuid;
  v_app record;
  v_status text;
  v_feedback text;
  v_convert_to text;
  v_approved_count int := 0;
  v_rejected_count int := 0;
  v_waitlisted_count int := 0;
  v_converted_count int := 0;
  v_created_members int := 0;
  v_member_id uuid;
  v_has_partner boolean;
BEGIN
  -- Auth: committee lead (resource) or platform admin (V4 manage_platform)
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_committee FROM selection_committee
  WHERE cycle_id = p_cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RETURN json_build_object('error', 'Unauthorized: must be committee lead or platform admin');
  END IF;

  FOR v_decision IN SELECT * FROM jsonb_array_elements(p_decisions)
  LOOP
    v_app_id := (v_decision->>'application_id')::uuid;
    v_status := v_decision->>'decision';
    v_feedback := v_decision->>'feedback';
    v_convert_to := v_decision->>'convert_to';

    SELECT * INTO v_app FROM selection_applications WHERE id = v_app_id AND cycle_id = p_cycle_id;
    IF NOT FOUND THEN CONTINUE; END IF;

    -- Handle conversion flow (researcher → leader)
    IF v_convert_to IS NOT NULL AND v_convert_to != '' THEN
      UPDATE selection_applications SET
        status = 'converted',
        converted_from = v_app.role_applied,
        converted_to = v_convert_to,
        conversion_reason = coalesce(v_feedback, 'Promoted by committee'),
        role_applied = v_convert_to,
        feedback = coalesce(v_feedback, feedback),
        updated_at = now()
      WHERE id = v_app_id;
      v_converted_count := v_converted_count + 1;

      -- Notify candidate with conversion offer
      PERFORM create_notification(
        m.id, 'selection_conversion_offer',
        'Proposta de conversão de papel',
        'O comitê identificou seu perfil para o papel de ' || v_convert_to || '. Acesse a plataforma para mais detalhes.',
        '/admin/selection', 'selection_application', v_app_id
      ) FROM members m WHERE m.email = v_app.email;

      CONTINUE;
    END IF;

    -- Normal decision
    UPDATE selection_applications SET
      status = v_status, feedback = coalesce(v_feedback, feedback), updated_at = now()
    WHERE id = v_app_id;

    IF v_status = 'approved' THEN
      v_approved_count := v_approved_count + 1;

      -- Partner chapter validation
      SELECT EXISTS (
        SELECT 1 FROM selection_membership_snapshots WHERE application_id = v_app_id AND is_partner_chapter = true
      ) INTO v_has_partner;
      IF NOT v_has_partner THEN
        UPDATE selection_applications SET tags = array_append(tags, 'no_partner_chapter')
        WHERE id = v_app_id AND NOT ('no_partner_chapter' = ANY(tags));
      END IF;

      -- Find or create member
      SELECT id INTO v_member_id FROM members WHERE email = v_app.email LIMIT 1;

      IF v_member_id IS NOT NULL THEN
        -- Reactivate existing member
        UPDATE members SET is_active = true, current_cycle_active = true, updated_at = now()
        WHERE id = v_member_id AND (is_active = false OR current_cycle_active = false);
      ELSE
        -- Create new member
        INSERT INTO members (name, email, pmi_id, chapter, operational_role, is_active, current_cycle_active)
        VALUES (v_app.applicant_name, v_app.email, v_app.pmi_id, v_app.chapter,
          CASE WHEN v_app.role_applied = 'leader' THEN 'tribe_leader' ELSE 'researcher' END, true, true)
        RETURNING id INTO v_member_id;
        v_created_members := v_created_members + 1;
      END IF;

      -- Seed pre-onboarding + standard onboarding steps
      INSERT INTO onboarding_progress (application_id, member_id, step_key, status, sla_deadline, metadata)
      SELECT v_app_id, v_member_id, s.key, 'pending', now() + (s.sla || ' days')::interval,
             jsonb_build_object('xp', s.xp, 'phase', 'pre_onboarding')
      FROM (VALUES ('create_account',50,7),('setup_credly',75,14),('explore_platform',50,14),('read_blog',50,14),('start_pmi_certs',150,30)) AS s(key,xp,sla)
      WHERE NOT EXISTS (SELECT 1 FROM onboarding_progress WHERE member_id = v_member_id AND step_key = s.key);

      INSERT INTO onboarding_progress (application_id, member_id, step_key, status, sla_deadline)
      SELECT v_app_id, v_member_id, (step->>'key'), 'pending', now() + ((step->>'sla_days')::int || ' days')::interval
      FROM selection_cycles sc, jsonb_array_elements(sc.onboarding_steps) AS step
      WHERE sc.id = p_cycle_id
      AND NOT EXISTS (SELECT 1 FROM onboarding_progress WHERE member_id = v_member_id AND step_key = (step->>'key'));

      PERFORM check_pre_onboarding_auto_steps(v_member_id);

      -- Notify approved member
      PERFORM create_notification(
        v_member_id, 'selection_approved',
        'Parabéns! Você foi aprovado no Núcleo IA',
        'Sua candidatura foi aprovada. Acesse a plataforma para iniciar o onboarding.',
        '/onboarding', 'selection_application', v_app_id
      );

    ELSIF v_status = 'rejected' THEN
      v_rejected_count := v_rejected_count + 1;
    ELSIF v_status = 'waitlist' THEN
      v_waitlisted_count := v_waitlisted_count + 1;
    END IF;

    -- Audit
    INSERT INTO data_anomaly_log (anomaly_type, severity, message, details)
    VALUES ('selection_decision', 'info', v_app.applicant_name || ' → ' || v_status,
      jsonb_build_object('application_id', v_app_id, 'decision', v_status, 'actor', v_caller.name));
  END LOOP;

  -- Diversity snapshot
  INSERT INTO selection_diversity_snapshots (cycle_id, snapshot_type, metrics)
  VALUES (p_cycle_id, 'approved', (
    SELECT jsonb_build_object(
      'by_chapter', (SELECT jsonb_object_agg(coalesce(chapter,'unknown'), cnt) FROM (SELECT chapter, count(*) as cnt FROM selection_applications WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY chapter) x),
      'by_gender', (SELECT jsonb_object_agg(coalesce(gender,'unknown'), cnt) FROM (SELECT gender, count(*) as cnt FROM selection_applications WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY gender) x),
      'by_role', (SELECT jsonb_object_agg(role_applied, cnt) FROM (SELECT role_applied, count(*) as cnt FROM selection_applications WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY role_applied) x),
      'total_approved', v_approved_count, 'total_rejected', v_rejected_count,
      'total_converted', v_converted_count, 'finalized_at', now()
    )
  ));

  RETURN json_build_object(
    'approved', v_approved_count, 'rejected', v_rejected_count,
    'waitlisted', v_waitlisted_count, 'converted', v_converted_count,
    'members_created', v_created_members, 'cycle_id', p_cycle_id
  );
END;
$function$;
