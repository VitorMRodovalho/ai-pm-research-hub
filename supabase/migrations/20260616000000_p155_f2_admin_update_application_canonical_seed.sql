-- p155 F2: admin_update_application — fix data_anomaly_log columns + canonical onboarding seed
--
-- Two bugs in one RPC body:
-- (a) INSERT INTO data_anomaly_log used 'message'/'details' (cols don't exist; transaction rolled back).
--     Real cols: 'description' (text) and 'context' (jsonb).
-- (b) Onboarding seed inserted 5 legacy XP-gamification step_keys (create_account, setup_credly,
--     explore_platform, read_blog, start_pmi_certs) which DO NOT exist in onboarding_steps table.
--     Dashboard counts completed/total from onboarding_steps (is_required=true), so seeded rows
--     were invisible — 0% even when candidate did work.
--
-- Fix (a): rewrite INSERT to use description/context.
-- Fix (b): seed canonical 7 steps from onboarding_steps WHERE is_required=true. Same shape as the
--          existing 248 valid rows in production (sla_deadline NULL, metadata empty).
--
-- Cycle-specific onboarding_steps (selection_cycles.onboarding_steps JSONB — accept_terms,
-- join_whatsapp, platform_access, kick_off, profile_complete) intentionally NOT seeded here.
-- That's a separate concern (finalize_decisions RPC handles bulk) — discussed as future ADR.
--
-- Driver: PM directive p155 (2026-05-13) — Herlon + João aprovação iminente needs working seed.

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
  v_seeded_count int := 0;
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

  -- If status changed to approved: validate partner chapter + seed onboarding
  IF v_new_status = 'approved' AND v_old_status <> 'approved' THEN
    -- Partner chapter check (flag, not block)
    IF NOT EXISTS (
      SELECT 1 FROM selection_membership_snapshots sms
      WHERE sms.application_id = p_application_id AND sms.is_partner_chapter = true
    ) THEN
      UPDATE selection_applications SET tags = array_append(tags, 'no_partner_chapter')
      WHERE id = p_application_id AND NOT ('no_partner_chapter' = ANY(tags));
    END IF;

    -- Resolve member by email (must already exist; admin_update_application does not create members)
    IF v_app.email IS NOT NULL THEN
      SELECT id INTO v_member_id FROM members WHERE email = v_app.email LIMIT 1;

      IF v_member_id IS NOT NULL THEN
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

        -- Auto-detect immediately (idempotent helper from pre_onboarding migration)
        PERFORM check_pre_onboarding_auto_steps(v_member_id);
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
      'onboarding_seeded', v_seeded_count
    )
  );

  RETURN json_build_object(
    'success',           true,
    'old_status',        v_old_status,
    'new_status',        v_new_status,
    'onboarding_seeded', v_seeded_count
  );
END;
$function$;

-- Cleanup: delete the 5 orphan rows from the previous broken seed
-- (member d29c42fd-d021-459f-be82-ab17c27b905a — already has 4 canonical rows separately)
DELETE FROM onboarding_progress
WHERE step_key IN ('create_account', 'setup_credly', 'explore_platform', 'read_blog', 'start_pmi_certs');

COMMENT ON FUNCTION public.admin_update_application(uuid, jsonb) IS
  'Admin-side status update on a selection application. Gated by manage_platform. On status→approved: seeds canonical onboarding (onboarding_steps WHERE is_required=true). Audit in data_anomaly_log (description, context). p155 F2 (2026-05-13): fixed data_anomaly_log column drift + replaced legacy 5-step gamification seed with canonical 7-step pipeline.';
