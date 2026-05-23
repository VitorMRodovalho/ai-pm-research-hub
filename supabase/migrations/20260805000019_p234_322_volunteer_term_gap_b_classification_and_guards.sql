-- ============================================================================
-- p234 — #322 / Gap B of #230 reframe:
--   classification leftovers + forward guard + offboarding extension for
--   volunteer_term onboarding step.
-- ADR: ADR-0006 (Person + Engagement) / ADR-0007 (Authority)
--
-- Purpose:
--   p230 audit (2026-05-23) of #230 reframe surfaced Gap B: 4 active + 4
--   inactive members carry onboarding_progress.volunteer_term step status
--   = 'pending' with NO matching cert AND NO active requires_agreement
--   engagement. These rows are classification leftovers — the universal
--   seeding path in approve_selection_application + onboarding_steps catalog
--   seeded volunteer_term unconditionally, but the member's actual engagement
--   kind does not require a volunteer agreement (or was offboarded before
--   signing).
--
--   This migration:
--   (1) Backfills the 8 phantom-pending rows to status='skipped' with metadata
--       reason='no_requires_agreement_engagement' (PM directive 2026-05-23 —
--       NEVER 'completed' unless a cert was actually issued or a real signing
--       event happened; 'skipped' communicates "step does not apply").
--   (2) Forward guard in approve_selection_application: do NOT seed
--       volunteer_term in the Path A (onboarding_steps catalog) INSERT when
--       the resolved engagement kind has requires_agreement=false. Function
--       currently hardcodes v_engagement_kind='volunteer' (requires_agreement
--       =true) so the guard is no-op today — forward-defense for any future
--       change that makes the engagement kind dynamic per role_applied.
--   (3) Offboarding extension in admin_offboard_member: after closing engs,
--       UPDATE any open volunteer_term step → status='skipped' with metadata
--       reason='offboarded_pre_signing'. Idempotent via status='pending'
--       filter; respects #321 trigger ordering (cert insert before offboard
--       → step already 'completed' → skipped UPDATE filtered out).
--   (4) Harmonize get_my_onboarding: treat 'skipped' as a terminal status
--       (≡ 'completed') for both completed_steps count and all_complete bool.
--       Mirrors existing pattern in get_onboarding_status. Required so the 4
--       backfilled active members do not see "incomplete onboarding" on
--       their dashboard despite the step legitimately not applying.
--
-- Scope:
--   - Backfill: ONLY rows that have NO active requires_agreement engagement
--     AND NO issued vol_agreement cert. Defensive against in-flight signing.
--   - Forward guard: ONLY volunteer_term step + Path A catalog seed loop in
--     approve_selection_application. Path B (per-cycle config) does not
--     currently seed volunteer_term (verified live 2026-05-23).
--   - Offboarding extension: ONLY volunteer_term step with status='pending'.
--     Does NOT touch already-completed or already-skipped rows.
--   - get_my_onboarding harmonization: ONLY the completed_steps + all_complete
--     branches. step rendering preserved verbatim — UI can still show step
--     status='skipped' distinctly if it chooses.
--
-- Out of scope (per issue #322):
--   - Gap C (study_group_* catalog config: requires_agreement=true with NULL
--     agreement_template) — handled by #323.
--   - check_schema_invariants() new invariant — PM call after #322 + #323
--     both ship (may overlap with Gap C semantics).
--   - Cron stale-term re-nudge — deferred per #230 reframe.
--   - Generalizing requires_kind_agreement to onboarding_steps catalog —
--     PM chose minimal blast radius (Q3 2026-05-23): inline guard for now.
--
-- PM directives (2026-05-23):
--   - Status='skipped' (NOT 'completed'). Reason metadata required.
--   - Do NOT mint Herlon term. Herlon's hash matches a row with offboarded
--     study_group_owner engagement; the requires_agreement=true check is on
--     ACTIVE engagements only, so his row gets correctly skipped.
--   - Goal metric: 0 active members with pending volunteer_term AND no
--     active requires_agreement engagement post-apply.
--
-- Rollback:
--   -- Forward functions: revert approve_selection_application,
--   --   admin_offboard_member, get_my_onboarding bodies from migration
--   --   20260805000018 era (or earlier) via apply_migration.
--   --
--   -- Backfilled rows: revert by metadata tag (audit trail preserved):
--   UPDATE public.onboarding_progress SET status='pending',
--     completed_at=NULL,
--     metadata = metadata - 'completed_via' - 'reason'
--       - 'backfilled_at' - 'migration'
--   WHERE metadata->>'completed_via' = 'p234_322_backfill_no_agreement_path';
-- ============================================================================

-- ════════════════════════════════════════════════════════════════════════
-- (1) BACKFILL: 8 phantom-pending vol_term rows with no cert + no req-agree
-- ════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_affected int;
  v_affected_ids uuid[];
BEGIN
  WITH backfill_target AS (
    SELECT op.id AS op_id,
           op.member_id,
           m.is_active,
           m.member_status,
           m.person_id
    FROM public.onboarding_progress op
    JOIN public.members m ON m.id = op.member_id
    WHERE op.step_key = 'volunteer_term'
      AND op.status = 'pending'
      -- Defensive: no issued vol_agreement cert (post-#321 trigger should make
      -- this set empty, but check defensively against trigger-disable scenarios)
      AND NOT EXISTS (
        SELECT 1 FROM public.certificates c
        WHERE c.member_id = op.member_id
          AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
      )
      -- Core Gap B condition: no ACTIVE requires_agreement engagement
      AND NOT EXISTS (
        SELECT 1 FROM public.engagements e
        JOIN public.engagement_kinds ek ON ek.slug = e.kind
        WHERE e.person_id = m.person_id
          AND e.status = 'active'
          AND ek.requires_agreement = true
      )
  ),
  updated AS (
    UPDATE public.onboarding_progress op
    SET
      status = 'skipped',
      completed_at = now(),
      updated_at = now(),
      metadata = COALESCE(op.metadata, '{}'::jsonb) || jsonb_build_object(
        'completed_via', 'p234_322_backfill_no_agreement_path',
        'reason', 'no_requires_agreement_engagement',
        'is_active_at_backfill', bt.is_active,
        'member_status_at_backfill', bt.member_status,
        'backfilled_at', now(),
        'migration', '20260805000019'
      )
    FROM backfill_target bt
    WHERE op.id = bt.op_id
    RETURNING op.id, op.member_id
  ),
  audit_insert AS (
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    SELECT
      NULL::uuid AS actor_id,
      'p234_322_backfill_volunteer_term_no_agreement' AS action,
      'onboarding_progress' AS target_type,
      u.id AS target_id,
      jsonb_build_object(
        'onboarding_progress_id', u.id,
        'member_id', u.member_id,
        'reason', 'no_requires_agreement_engagement',
        'migration', '20260805000019'
      )
    FROM updated u
    RETURNING target_id
  )
  SELECT count(*), array_agg(target_id) INTO v_affected, v_affected_ids FROM audit_insert;

  RAISE NOTICE '#322 backfill: % vol_term rows marked skipped (no_requires_agreement_engagement). IDs: %', v_affected, v_affected_ids;
END$$;

-- ════════════════════════════════════════════════════════════════════════
-- (2) FORWARD GUARD: approve_selection_application skips volunteer_term
--     seed when v_requires_agreement is false (forward-defense)
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.approve_selection_application(p_application_id uuid, p_decision jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id        uuid;
  v_caller_name      text;
  v_caller_person_id uuid;
  v_caller_org_id    uuid;
  v_app              record;
  v_member_id        uuid;
  v_person_id        uuid;
  v_member_role      text;
  v_member_status    text;
  v_target_role      text;
  v_engagement_role  text;
  v_engagement_kind  text := 'volunteer';
  v_legal_basis      text := 'contract';
  v_cycle_end_date   date;
  v_default_days     int;
  v_requires_agreement boolean;
  v_engagement_id    uuid;
  v_existing_engagement_id uuid;
  v_seeded_count     int := 0;
  v_promoted         boolean := false;
  v_member_created   boolean := false;
  v_person_created   boolean := false;
  v_engagement_created boolean := false;
BEGIN
  SELECT id, name, person_id, organization_id
    INTO v_caller_id, v_caller_name, v_caller_person_id, v_caller_org_id
  FROM public.members WHERE auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Application not found');
  END IF;
  IF v_app.status NOT IN ('approved', 'converted') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Application status must be approved or converted',
      'current_status', v_app.status
    );
  END IF;
  IF v_app.email IS NULL OR length(trim(v_app.email)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Application has no email');
  END IF;

  v_target_role := CASE
    WHEN v_app.role_applied = 'leader'     THEN 'tribe_leader'
    WHEN v_app.role_applied = 'researcher' THEN 'researcher'
    ELSE NULL
  END;

  SELECT id, person_id, operational_role, member_status
    INTO v_member_id, v_person_id, v_member_role, v_member_status
  FROM public.members WHERE lower(email) = lower(v_app.email) LIMIT 1;

  IF v_member_id IS NULL THEN
    INSERT INTO public.members (
      organization_id,
      name, email, pmi_id, chapter,
      operational_role, is_active, current_cycle_active
    )
    VALUES (
      v_app.organization_id,
      v_app.applicant_name, v_app.email, v_app.pmi_id, v_app.chapter,
      COALESCE(v_target_role, 'researcher'),
      true, true
    )
    RETURNING id, person_id, operational_role, member_status
      INTO v_member_id, v_person_id, v_member_role, v_member_status;
    v_member_created := true;
  ELSE
    UPDATE public.members SET
      is_active = true,
      current_cycle_active = true,
      updated_at = now()
    WHERE id = v_member_id
      AND (is_active = false OR current_cycle_active = false);

    IF v_target_role IS NOT NULL
       AND v_member_role IN ('observer', 'guest', 'none', 'alumni', 'inactive')
       AND v_member_status = 'active'
    THEN
      UPDATE public.members
      SET operational_role = v_target_role, updated_at = now()
      WHERE id = v_member_id;
      v_promoted := true;
    END IF;
  END IF;

  IF v_person_id IS NULL THEN
    SELECT id INTO v_person_id
    FROM public.persons WHERE lower(email) = lower(v_app.email) LIMIT 1;

    IF v_person_id IS NULL THEN
      INSERT INTO public.persons (
        organization_id, name, email, pmi_id, phone,
        consent_status, legacy_member_id
      )
      VALUES (
        v_app.organization_id,
        v_app.applicant_name, v_app.email, v_app.pmi_id, v_app.phone,
        'pending', v_member_id
      )
      RETURNING id INTO v_person_id;
      v_person_created := true;
    END IF;

    UPDATE public.members SET person_id = v_person_id, updated_at = now()
    WHERE id = v_member_id AND person_id IS NULL;
  END IF;

  v_engagement_role := CASE
    WHEN v_app.role_applied IN ('leader', 'researcher', 'coordinator', 'manager') THEN v_app.role_applied
    ELSE 'researcher'
  END;

  SELECT sc.end_date INTO v_cycle_end_date
  FROM public.selection_cycles sc WHERE sc.id = v_app.cycle_id;

  SELECT ek.default_duration_days, ek.requires_agreement
    INTO v_default_days, v_requires_agreement
  FROM public.engagement_kinds ek WHERE ek.slug = v_engagement_kind;

  IF v_cycle_end_date IS NOT NULL AND v_cycle_end_date < CURRENT_DATE THEN
    v_cycle_end_date := NULL;
  END IF;

  SELECT id INTO v_existing_engagement_id
  FROM public.engagements
  WHERE person_id = v_person_id
    AND kind = v_engagement_kind
    AND status = 'active'
  ORDER BY start_date DESC
  LIMIT 1;

  IF v_existing_engagement_id IS NULL THEN
    INSERT INTO public.engagements (
      person_id, organization_id,
      kind, role, status,
      start_date, end_date,
      legal_basis,
      selection_application_id,
      granted_by, granted_at,
      metadata
    )
    VALUES (
      v_person_id,
      v_app.organization_id,
      v_engagement_kind, v_engagement_role, 'active',
      CURRENT_DATE,
      COALESCE(
        v_cycle_end_date,
        CURRENT_DATE + (COALESCE(v_default_days, 180) || ' days')::interval
      ),
      v_legal_basis,
      p_application_id,
      v_caller_person_id,
      now(),
      jsonb_build_object(
        'source', 'approve_selection_application',
        'role_applied', v_app.role_applied,
        'application_status', v_app.status
      )
    )
    RETURNING id INTO v_engagement_id;
    v_engagement_created := true;
  ELSE
    UPDATE public.engagements
    SET selection_application_id = p_application_id, updated_at = now()
    WHERE id = v_existing_engagement_id AND selection_application_id IS NULL;
    v_engagement_id := v_existing_engagement_id;
  END IF;

  -- #322 forward guard: skip volunteer_term step when the resolved engagement
  -- kind does NOT have requires_agreement=true. v_engagement_kind is hardcoded
  -- to 'volunteer' (requires_agreement=true) today, so this guard is no-op
  -- now. Forward-defense for any future change that makes the engagement
  -- kind dynamic per role_applied / cycle config.
  INSERT INTO public.onboarding_progress (application_id, member_id, step_key, status, metadata)
  SELECT p_application_id, v_member_id, s.id, 'pending', '{}'::jsonb
  FROM public.onboarding_steps s
  WHERE s.is_required = true
    AND NOT (s.id = 'volunteer_term' AND NOT COALESCE(v_requires_agreement, FALSE))
    AND NOT EXISTS (
      SELECT 1 FROM public.onboarding_progress op
      WHERE op.member_id = v_member_id AND op.step_key = s.id
    );
  GET DIAGNOSTICS v_seeded_count = ROW_COUNT;

  INSERT INTO public.onboarding_progress (application_id, member_id, step_key, status, sla_deadline)
  SELECT p_application_id, v_member_id, (step->>'key'), 'pending',
         now() + ((step->>'sla_days')::int || ' days')::interval
  FROM public.selection_cycles sc, jsonb_array_elements(sc.onboarding_steps) AS step
  WHERE sc.id = v_app.cycle_id
    AND NOT EXISTS (
      SELECT 1 FROM public.onboarding_progress
      WHERE member_id = v_member_id AND step_key = (step->>'key')
    );

  PERFORM public.check_pre_onboarding_auto_steps(v_member_id);

  IF NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE recipient_id = v_member_id
      AND type = 'selection_approved'
      AND source_id = p_application_id
  ) THEN
    PERFORM public.create_notification(
      v_member_id,
      'selection_approved',
      'Parabéns! Você foi aprovado no Núcleo IA',
      'Sua candidatura foi aprovada. Acesse a plataforma para iniciar o onboarding.',
      '/onboarding',
      'selection_application',
      p_application_id
    );
  END IF;

  INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'selection_approval_canonical',
    'info',
    'Canonical approval for ' || v_app.applicant_name || ' (' || v_app.status || ')',
    jsonb_build_object(
      'application_id',     p_application_id,
      'application_status', v_app.status,
      'actor_id',           v_caller_id,
      'actor_name',         v_caller_name,
      'member_id',          v_member_id,
      'person_id',          v_person_id,
      'engagement_id',      v_engagement_id,
      'member_created',     v_member_created,
      'person_created',     v_person_created,
      'engagement_created', v_engagement_created,
      'onboarding_seeded',  v_seeded_count,
      'role_promoted',      v_promoted,
      'promoted_to',        CASE WHEN v_promoted THEN v_target_role ELSE NULL END,
      'requires_agreement', v_requires_agreement,
      'agreement_pending',  v_requires_agreement
    )
  );

  RETURN jsonb_build_object(
    'success',            true,
    'application_id',     p_application_id,
    'member_id',          v_member_id,
    'person_id',          v_person_id,
    'engagement_id',      v_engagement_id,
    'member_created',     v_member_created,
    'person_created',     v_person_created,
    'engagement_created', v_engagement_created,
    'onboarding_seeded',  v_seeded_count,
    'role_promoted',      v_promoted,
    'promoted_to',        CASE WHEN v_promoted THEN v_target_role ELSE NULL END,
    'agreement_pending',  v_requires_agreement
  );
END;
$function$;

COMMENT ON FUNCTION public.approve_selection_application(uuid, jsonb) IS
  '#322 (p234 / Gap B of #230 reframe): adds forward guard in Path A onboarding step seed to skip volunteer_term when the resolved engagement kind has requires_agreement=false. Otherwise byte-identical to pre-p234 body.';

-- ════════════════════════════════════════════════════════════════════════
-- (3) OFFBOARDING EXTENSION: admin_offboard_member auto-skips open
--     volunteer_term steps for offboarded members
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_offboard_member(p_member_id uuid, p_new_status text, p_reason_category text, p_reason_detail text DEFAULT NULL::text, p_reassign_to uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller             record;
  v_member             record;
  v_audit_id           uuid;
  v_new_role           text;
  v_items_reassigned   integer := 0;
  v_engagements_closed integer := 0;
  v_vol_terms_skipped  integer := 0;
  v_prev_status        text;
  v_reason_record      record;
  v_certificate_id     uuid;
  v_certificate_code   text;
  v_emit_error         text;
  v_current_cycle_int  integer;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  IF p_new_status NOT IN ('observer','alumni','inactive') THEN
    RETURN jsonb_build_object('error','Invalid status: ' || p_new_status);
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Member not found'); END IF;

  v_prev_status := COALESCE(v_member.member_status,'active');

  IF v_prev_status = p_new_status THEN
    RETURN jsonb_build_object('error','Member is already ' || p_new_status);
  END IF;

  BEGIN
    PERFORM public.validate_status_transition(v_prev_status, p_new_status);
  EXCEPTION WHEN sqlstate '22023' THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_caller.id, 'member.status_transition_blocked', 'member', p_member_id,
      jsonb_build_object('attempted_from', v_prev_status, 'attempted_to', p_new_status),
      jsonb_build_object('error', SQLERRM, 'arm9_gate', 'validate_status_transition')
    );
    RETURN jsonb_build_object('error', SQLERRM, 'arm9_gate', 'validate_status_transition');
  END;

  v_new_role := CASE p_new_status
    WHEN 'alumni'   THEN 'alumni'
    WHEN 'observer' THEN 'observer'
    WHEN 'inactive' THEN 'none'
  END;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id, 'member.status_transition', 'member', p_member_id,
    jsonb_strip_nulls(jsonb_build_object(
      'previous_status', v_prev_status, 'new_status', p_new_status,
      'previous_tribe_id', v_member.tribe_id
    )),
    jsonb_strip_nulls(jsonb_build_object(
      'reason_category', p_reason_category, 'reason_detail', p_reason_detail,
      'items_reassigned_to', p_reassign_to
    ))
  )
  RETURNING id INTO v_audit_id;

  IF v_member.operational_role IS DISTINCT FROM v_new_role THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_caller.id, 'member.role_change', 'member', p_member_id,
      jsonb_build_object(
        'field', 'operational_role',
        'old_value', to_jsonb(v_member.operational_role),
        'new_value', to_jsonb(v_new_role),
        'effective_date', CURRENT_DATE
      ),
      jsonb_strip_nulls(jsonb_build_object(
        'change_type', 'role_changed',
        'reason', p_reason_detail,
        'authorized_by', v_caller.id
      ))
    );
  END IF;

  UPDATE public.members SET
    member_status        = p_new_status,
    operational_role     = v_new_role,
    is_active            = false,
    designations         = '{}'::text[],
    offboarded_at        = now(),
    offboarded_by        = v_caller.id,
    status_changed_at    = now(),
    status_change_reason = COALESCE(p_reason_detail, p_reason_category),
    updated_at           = now()
  WHERE id = p_member_id;

  IF v_member.person_id IS NOT NULL THEN
    UPDATE public.engagements SET
      status = 'offboarded', end_date = CURRENT_DATE,
      revoked_at = now(), revoked_by = v_caller.person_id,
      revoke_reason = COALESCE(p_reason_detail, p_reason_category),
      updated_at = now()
    WHERE person_id = v_member.person_id AND status = 'active';
    GET DIAGNOSTICS v_engagements_closed = ROW_COUNT;
  END IF;

  IF p_reassign_to IS NOT NULL THEN
    UPDATE public.board_items SET assignee_id = p_reassign_to
    WHERE assignee_id = p_member_id AND status != 'archived';
    GET DIAGNOSTICS v_items_reassigned = ROW_COUNT;
  END IF;

  -- #322 offboarding extension: auto-skip any open volunteer_term step for
  -- the offboarded member. Idempotent via status='pending' filter. Respects
  -- #321 trigger ordering: if a cert was inserted before offboard, the step
  -- is already 'completed' and gets filtered out here.
  UPDATE public.onboarding_progress
  SET
    status = 'skipped',
    completed_at = now(),
    updated_at = now(),
    metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
      'completed_via', 'p234_322_offboarding_extension',
      'reason', 'offboarded_pre_signing',
      'offboarded_to_status', p_new_status,
      'offboarded_at', now(),
      'migration', '20260805000019'
    )
  WHERE member_id = p_member_id
    AND step_key = 'volunteer_term'
    AND status = 'pending';
  GET DIAGNOSTICS v_vol_terms_skipped = ROW_COUNT;

  IF v_vol_terms_skipped > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (
      v_caller.id,
      'onboarding.volunteer_term_skipped_on_offboard',
      'member',
      p_member_id,
      jsonb_build_object(
        'rows_affected', v_vol_terms_skipped,
        'offboarded_to_status', p_new_status,
        'reason', 'offboarded_pre_signing',
        'migration', '20260805000019'
      )
    );
  END IF;

  -- ARM-9 G3: auto-emit alumni_recognition certificate
  IF p_new_status = 'alumni' AND p_reason_category IS NOT NULL THEN
    SELECT * INTO v_reason_record FROM public.offboard_reason_categories
    WHERE code = p_reason_category;

    IF FOUND AND v_reason_record.preserves_return_eligibility = true THEN
      BEGIN
        -- Safe cycle extraction: digits from cycle_code text, fallback 3
        SELECT COALESCE(NULLIF(regexp_replace(cycle_code, '[^0-9]', '', 'g'), '')::int, 3)
        INTO v_current_cycle_int
        FROM public.cycles WHERE is_current = true LIMIT 1;
        v_current_cycle_int := COALESCE(v_current_cycle_int, 3);

        v_certificate_code := 'CERT-' || extract(year FROM now())::text || '-' || upper(substr(md5(random()::text), 1, 6));

        INSERT INTO public.certificates (
          member_id, type, title, description, cycle, function_role,
          language, issued_by, verification_code, issued_at, source
        ) VALUES (
          p_member_id,
          'alumni_recognition',
          'Reconhecimento Alumni — Núcleo IA & GP',
          'Em reconhecimento à contribuição como voluntário(a) ao programa Núcleo IA & GP. Saída amigável em ' || to_char(now(), 'DD/MM/YYYY') || ' (' || v_reason_record.label_pt || '). Elegível para retorno via re-engagement pipeline.',
          v_current_cycle_int,
          v_member.operational_role,
          'pt-BR',
          v_caller.id,
          v_certificate_code,
          now(),
          'arm9_g3_auto_emit'
        )
        RETURNING id INTO v_certificate_id;

        PERFORM public.create_notification(
          p_member_id,
          'certificate_issued',
          'Certificado Alumni emitido',
          'Você recebeu o certificado Reconhecimento Alumni — válido para perfil profissional e LinkedIn.',
          '/gamification',
          'certificate',
          v_certificate_id
        );
      EXCEPTION WHEN OTHERS THEN
        v_emit_error := SQLERRM;
        v_certificate_id := NULL;
        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_caller.id, 'arm9.alumni_badge_emit_failed', 'member', p_member_id,
          jsonb_build_object('reason_category', p_reason_category),
          jsonb_build_object('error', v_emit_error)
        );
      END;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'audit_id', v_audit_id,
    'transition_id', v_audit_id,
    'member_name', v_member.name,
    'previous_status', v_prev_status,
    'new_status', p_new_status,
    'new_role', v_new_role,
    'items_reassigned', v_items_reassigned,
    'engagements_closed', v_engagements_closed,
    'vol_terms_skipped', v_vol_terms_skipped,
    'designations_cleared', COALESCE(array_length(v_member.designations,1),0),
    'alumni_certificate_id', v_certificate_id,
    'alumni_certificate_emit_error', v_emit_error
  );
END;
$function$;

COMMENT ON FUNCTION public.admin_offboard_member(uuid, text, text, text, uuid) IS
  '#322 (p234 / Gap B of #230 reframe): auto-skips any open volunteer_term step for the offboarded member with reason=offboarded_pre_signing. Idempotent via status=pending filter. Respects #321 trigger ordering. Otherwise byte-identical to pre-p234 body.';

-- ════════════════════════════════════════════════════════════════════════
-- (4) UX HARMONIZE: get_my_onboarding treats 'skipped' as terminal status
--     (≡ 'completed') for completed_steps + all_complete
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_my_onboarding()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member_id uuid; v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  -- Auto-generate progress rows
  INSERT INTO onboarding_progress (member_id, step_key, status)
  SELECT v_member_id, s.id, 'pending'
  FROM onboarding_steps s
  WHERE NOT EXISTS (SELECT 1 FROM onboarding_progress op WHERE op.member_id = v_member_id AND op.step_key = s.id);

  SELECT jsonb_build_object(
    'member_id', v_member_id,
    'total_steps', (SELECT count(*) FROM onboarding_steps WHERE is_required),
    -- #322 (p234 / Gap B of #230): treat 'skipped' as terminal (≡ completed)
    -- for completion counting. Mirrors get_onboarding_status behavior. Required
    -- so backfilled rows with reason='no_requires_agreement_engagement' do not
    -- show as incomplete on the dashboard for the 4 active members in Gap B.
    'completed_steps', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_member_id AND status IN ('completed', 'skipped') AND step_key IN (SELECT id FROM onboarding_steps)),
    'all_complete', (NOT EXISTS (
      SELECT 1 FROM onboarding_steps s
      JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = v_member_id
      WHERE s.is_required AND op.status NOT IN ('completed', 'skipped')
    )),
    'steps', (SELECT jsonb_agg(row_to_json(t) ORDER BY t.step_order) FROM (
      SELECT s.id AS step_id, s.step_order, s.label_pt, s.label_en, s.label_es,
        s.description_pt, s.description_en, s.description_es, s.icon, s.is_required,
        COALESCE(op.status, 'pending') AS status, op.completed_at, op.metadata
      FROM onboarding_steps s
      LEFT JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = v_member_id
      ORDER BY s.step_order
    ) t)
  ) INTO v_result;
  RETURN v_result;
END; $function$;

COMMENT ON FUNCTION public.get_my_onboarding() IS
  '#322 (p234 / Gap B of #230 reframe): treats status=skipped as terminal (equivalent to completed) for completed_steps + all_complete. Mirrors get_onboarding_status pattern. step rendering preserved verbatim — UI can render skipped distinctly if needed.';

-- ════════════════════════════════════════════════════════════════════════
-- SANITY check: 0 active members with pending vol_term AND no active
-- requires_agreement engagement (goal metric per #322 AC)
-- ════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_violation_count int;
BEGIN
  SELECT count(*) INTO v_violation_count
  FROM public.onboarding_progress op
  JOIN public.members m ON m.id = op.member_id
  WHERE op.step_key = 'volunteer_term'
    AND op.status = 'pending'
    AND COALESCE(m.is_active, FALSE) IS TRUE
    AND NOT EXISTS (
      SELECT 1 FROM public.engagements e
      JOIN public.engagement_kinds ek ON ek.slug = e.kind
      WHERE e.person_id = m.person_id
        AND e.status = 'active'
        AND ek.requires_agreement = true
    );

  IF v_violation_count > 0 THEN
    RAISE EXCEPTION '#322 sanity FAIL: % active members still have pending volunteer_term AND no active requires_agreement engagement. Backfill query failed to cover all Gap B rows.', v_violation_count;
  END IF;
  RAISE NOTICE '#322 sanity OK: 0 active members with pending volunteer_term and no active requires_agreement engagement.';
END$$;

NOTIFY pgrst, 'reload schema';
