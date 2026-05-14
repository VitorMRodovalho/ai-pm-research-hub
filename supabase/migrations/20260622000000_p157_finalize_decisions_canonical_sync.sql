-- p157 #1: finalize_decisions — sync canonical pattern with admin_update_application (F2 Op A+B p155)
--
-- Drifts fixed:
-- (a) Onboarding seed used legacy 5-step XP-gamification keys (create_account, setup_credly,
--     explore_platform, read_blog, start_pmi_certs) which DO NOT exist in onboarding_steps. Same
--     bug as admin_update_application p155 F2. Replaces with canonical seed from
--     onboarding_steps WHERE is_required=true (matching F2 shape).
-- (b) INSERT INTO data_anomaly_log used columns 'message'/'details' which do not exist; real cols
--     are 'description'/'context'. Same silent rollback bug fixed in admin_update_application p155
--     F2 (the entire transaction rolled back on each loop iteration — historic bulk decisions had
--     UPDATE applied but selection_decision audit entries dropped). anomaly_type retained as
--     'selection_decision' (distinct from 'selection_status_change' in F2) to keep audit trails
--     separable between bulk and single-application paths.
-- (c) Op B parity for REACTIVATION branch: when an existing (returning) member is found, the
--     prior code only flipped is_active/current_cycle_active — it never promoted
--     operational_role even when role_applied implied a higher level (e.g., alumni approved as
--     tribe_leader). Adds same guard pattern as admin_update_application Op B: only promote if
--     currently non-active role AND member_status='active'. Creation branch already sets the
--     correct operational_role at INSERT (line below) so no change is required there.
--
-- Cycle-specific seed (selection_cycles.onboarding_steps JSONB) PRESERVED — intentional split
-- between admin_update_application (single applicant, canonical-only) and finalize_decisions
-- (bulk, canonical + cycle). See p155 F2 migration header for rationale.
--
-- Out of scope (handoff p157 #2 — separate AFTER UPDATE trigger): VEP→Termo automation. The
-- p155 op_a_b header already flagged this as Op C–F deferred work.

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
  v_promoted_count int := 0;
  v_member_id uuid;
  v_member_role text;
  v_member_status text;
  v_target_role text;
  v_promoted_this_app boolean;
  v_has_partner boolean;
  v_seeded_count int;
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
    v_promoted_this_app := false;
    v_target_role := NULL;

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
      v_seeded_count := 0;

      -- Partner chapter validation
      SELECT EXISTS (
        SELECT 1 FROM selection_membership_snapshots WHERE application_id = v_app_id AND is_partner_chapter = true
      ) INTO v_has_partner;
      IF NOT v_has_partner THEN
        UPDATE selection_applications SET tags = array_append(tags, 'no_partner_chapter')
        WHERE id = v_app_id AND NOT ('no_partner_chapter' = ANY(tags));
      END IF;

      -- Find or create member
      SELECT id, operational_role, member_status
        INTO v_member_id, v_member_role, v_member_status
      FROM members WHERE email = v_app.email LIMIT 1;

      IF v_member_id IS NOT NULL THEN
        -- Reactivate existing member
        UPDATE members SET is_active = true, current_cycle_active = true, updated_at = now()
        WHERE id = v_member_id AND (is_active = false OR current_cycle_active = false);

        -- Op B parity (sync with admin_update_application): promote operational_role if
        -- currently non-active. Only when member_status='active' to avoid trigger override.
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
          v_promoted_this_app := true;
          v_promoted_count := v_promoted_count + 1;
        END IF;
      ELSE
        -- Create new member (operational_role set inline → no separate Op B needed)
        INSERT INTO members (name, email, pmi_id, chapter, operational_role, is_active, current_cycle_active)
        VALUES (v_app.applicant_name, v_app.email, v_app.pmi_id, v_app.chapter,
          CASE WHEN v_app.role_applied = 'leader' THEN 'tribe_leader' ELSE 'researcher' END, true, true)
        RETURNING id INTO v_member_id;
        v_created_members := v_created_members + 1;
      END IF;

      -- Seed canonical onboarding steps (is_required=true) — skip rows already present
      -- Replaces previous legacy 5-step XP-gamification seed (those keys don't exist in
      -- onboarding_steps; dashboard counted 0% completion regardless of progress).
      INSERT INTO onboarding_progress (application_id, member_id, step_key, status, metadata)
      SELECT v_app_id, v_member_id, s.id, 'pending', '{}'::jsonb
      FROM onboarding_steps s
      WHERE s.is_required = true
        AND NOT EXISTS (
          SELECT 1 FROM onboarding_progress op
          WHERE op.member_id = v_member_id AND op.step_key = s.id
        );
      GET DIAGNOSTICS v_seeded_count = ROW_COUNT;

      -- Seed cycle-specific onboarding_steps (from selection_cycles.onboarding_steps JSONB)
      -- PRESERVED: intentional bulk-vs-single split (see header).
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

    -- Audit (fixed cols: description/context — were message/details which rolled back the tx)
    INSERT INTO data_anomaly_log (anomaly_type, severity, description, context)
    VALUES (
      'selection_decision',
      'info',
      v_app.applicant_name || ' → ' || v_status,
      jsonb_build_object(
        'application_id', v_app_id,
        'decision',       v_status,
        'actor',          v_caller.name,
        'member_id',      v_member_id,
        'role_promoted',  v_promoted_this_app,
        'promoted_to',    CASE WHEN v_promoted_this_app THEN v_target_role ELSE NULL END
      )
    );
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
    'members_created', v_created_members,
    'members_promoted', v_promoted_count,
    'cycle_id', p_cycle_id
  );
END;
$function$;

-- Defensive cleanup: catch orphan legacy 5-step rows that may have been seeded by
-- finalize_decisions after p155 F2 (which patched admin_update_application only).
-- F2 already deleted rows existing at 2026-05-13; this catches any seeded since by bulk path.
DELETE FROM onboarding_progress
WHERE step_key IN ('create_account', 'setup_credly', 'explore_platform', 'read_blog', 'start_pmi_certs')
  AND NOT EXISTS (
    SELECT 1 FROM onboarding_steps s WHERE s.id = onboarding_progress.step_key
  );

COMMENT ON FUNCTION public.finalize_decisions(uuid, jsonb) IS
  'Bulk decision finalizer for a selection cycle. Gated by committee lead OR can_by_member(manage_platform). For each application: applies status, on approved creates-or-reactivates member, promotes operational_role on reactivation (Op B parity with admin_update_application), seeds canonical onboarding (onboarding_steps WHERE is_required=true) + cycle-specific (selection_cycles.onboarding_steps JSONB), runs check_pre_onboarding_auto_steps, notifies. Audit in data_anomaly_log (description, context). p157 #1 (2026-05-14): canonical seed + column drift + Op B parity. Out of scope: VEP→Termo automation (separate trigger in p157 #2).';

NOTIFY pgrst, 'reload schema';
