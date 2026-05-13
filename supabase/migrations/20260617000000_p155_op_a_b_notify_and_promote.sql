-- p155 F2 Op A + Op B: admin_update_application — notification + operational_role promotion
--
-- Op A (notification parity with finalize_decisions): when approving, PERFORM create_notification
--      so the candidate sees the in-app bell + link to /onboarding. Without this, inline/modal/bulk
--      paths were silent (only bulk-via-finalize_decisions ever notified).
--
-- Op B (operational_role promotion): when role_applied='leader', promote member from
--      non-active operational_role (observer/guest/none/alumni/inactive) to 'tribe_leader'.
--      Researchers: same promotion to 'researcher'. Guards:
--        - Never demote (skip if already at active role)
--        - Require member_status='active' (else sync_member_status_consistency trigger reverts)
--        - V4 cache (sync_operational_role_cache) repopulates from engagements next time someone
--          touches assigned_engagements for this person — accept this drift; matches existing pattern
--          in finalize_decisions (direct UPDATE without engagement provisioning).
--
-- Out of scope (deferred to Op C–F): tribe/initiative assignment, email, auto-detect bridge,
-- VEP→Termo automation.

CREATE OR REPLACE FUNCTION public.admin_update_application(p_application_id uuid, p_data jsonb)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_name text;
  v_app record;
  v_old_status text;
  v_new_status text;
  v_member_id uuid;
  v_member_role text;
  v_member_status text;
  v_seeded_count int := 0;
  v_promoted boolean := false;
  v_target_role text;
BEGIN
  SELECT id, name INTO v_caller_id, v_caller_name FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN json_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN RETURN json_build_object('error', 'Application not found'); END IF;

  v_old_status := v_app.status;
  v_new_status := coalesce(p_data->>'status', v_old_status);

  UPDATE selection_applications SET
    status = v_new_status,
    feedback = coalesce(p_data->>'feedback', feedback),
    tags = CASE WHEN p_data ? 'tags' THEN ARRAY(SELECT jsonb_array_elements_text(p_data->'tags')) ELSE tags END,
    role_applied = coalesce(p_data->>'role_applied', role_applied),
    converted_from = CASE WHEN p_data ? 'converted_from' THEN p_data->>'converted_from' ELSE converted_from END,
    converted_to = CASE WHEN p_data ? 'converted_to' THEN p_data->>'converted_to' ELSE converted_to END,
    conversion_reason = CASE WHEN p_data ? 'conversion_reason' THEN p_data->>'conversion_reason' ELSE conversion_reason END,
    updated_at = now()
  WHERE id = p_application_id;

  IF v_new_status = 'approved' AND v_old_status <> 'approved' THEN
    -- Partner chapter check (flag, not block)
    IF NOT EXISTS (
      SELECT 1 FROM selection_membership_snapshots sms
      WHERE sms.application_id = p_application_id AND sms.is_partner_chapter = true
    ) THEN
      UPDATE selection_applications SET tags = array_append(tags, 'no_partner_chapter')
      WHERE id = p_application_id AND NOT ('no_partner_chapter' = ANY(tags));
    END IF;

    IF v_app.email IS NOT NULL THEN
      SELECT id, operational_role, member_status
        INTO v_member_id, v_member_role, v_member_status
      FROM members WHERE email = v_app.email LIMIT 1;

      IF v_member_id IS NOT NULL THEN
        -- Op B: promote operational_role if currently non-active
        v_target_role := CASE
          WHEN v_app.role_applied = 'leader'     THEN 'tribe_leader'
          WHEN v_app.role_applied = 'researcher' THEN 'researcher'
          ELSE NULL
        END;

        IF v_target_role IS NOT NULL
           AND v_member_role IN ('observer','guest','none','alumni','inactive')
           AND v_member_status = 'active'
        THEN
          UPDATE members
          SET operational_role = v_target_role, updated_at = now()
          WHERE id = v_member_id;
          v_promoted := true;
        END IF;

        -- Seed canonical onboarding steps (is_required=true) — skip rows already present
        INSERT INTO onboarding_progress (application_id, member_id, step_key, status, metadata)
        SELECT p_application_id, v_member_id, s.id, 'pending', '{}'::jsonb
        FROM onboarding_steps s
        WHERE s.is_required = true
          AND NOT EXISTS (
            SELECT 1 FROM onboarding_progress op
            WHERE op.member_id = v_member_id AND op.step_key = s.id
          );
        GET DIAGNOSTICS v_seeded_count = ROW_COUNT;

        PERFORM check_pre_onboarding_auto_steps(v_member_id);

        -- Op A: notify candidate in-app (parity with finalize_decisions)
        PERFORM create_notification(
          v_member_id,
          'selection_approved',
          'Parabéns! Você foi aprovado no Núcleo IA',
          'Sua candidatura foi aprovada. Acesse a plataforma para iniciar o onboarding.',
          '/onboarding',
          'selection_application',
          p_application_id
        );
      END IF;
    END IF;
  END IF;

  INSERT INTO data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'selection_status_change',
    'info',
    'Application ' || v_app.applicant_name || ': ' || v_old_status || ' → ' || v_new_status,
    jsonb_build_object(
      'application_id', p_application_id,
      'old_status',     v_old_status,
      'new_status',     v_new_status,
      'actor',          v_caller_name,
      'member_id',      v_member_id,
      'onboarding_seeded', v_seeded_count,
      'role_promoted',  v_promoted,
      'promoted_to',    CASE WHEN v_promoted THEN v_target_role ELSE NULL END
    )
  );

  RETURN json_build_object(
    'success',           true,
    'old_status',        v_old_status,
    'new_status',        v_new_status,
    'onboarding_seeded', v_seeded_count,
    'role_promoted',     v_promoted,
    'promoted_to',       CASE WHEN v_promoted THEN v_target_role ELSE NULL END
  );
END;
$function$;

COMMENT ON FUNCTION public.admin_update_application(uuid, jsonb) IS
  'Admin-side status update on a selection application. Gated by manage_platform. On status→approved: (a) seeds canonical onboarding from onboarding_steps WHERE is_required=true, (b) promotes operational_role to tribe_leader/researcher per role_applied (only if currently non-active and member_status=active — safety against re-demotion + trigger override), (c) creates in-app selection_approved notification (parity with finalize_decisions). Audit in data_anomaly_log (description, context). p155 F2 Op A+B (2026-05-13).';
