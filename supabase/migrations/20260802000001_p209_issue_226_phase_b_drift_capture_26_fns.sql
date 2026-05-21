-- p209 / issue #226 Phase B — body-hash drift capture (26 functions)
--
-- Captures the LIVE body of 26 public-schema functions whose body had drifted
-- from the latest CREATE FUNCTION migration capture (Phase C body-hash drift
-- check at rpc-migration-coverage.test.mjs:539).
--
-- Captured via pg_get_functiondef(oid) at p209 boot (2026-05-21). Bodies are
-- byte-equivalent to what's live in production — applying this migration is
-- a NO-OP against current state (the new captures match the prior live state).
-- The point is to make the latest migration capture canonical so future drift
-- detection compares apples-to-apples.
--
-- Drift origin (rough):
--   - 7 functions captured stale in 20260723000000_baseline_rpcs_after_schema.sql
--     (local-only baseline file from issue #164 local-stack ordering). The
--     bodies in baseline are older than what's actually live post-W125 +
--     other hardening sessions (p178+, p195+, p197+, p203+, p204+, p205+).
--   - 19 functions where mid-session apply_migration captured an intermediate
--     body but the function was modified again via a later session that
--     didn't re-capture (the original ADR-0029 drift gap).
--
-- This is forward-defense: future Phase B captures should follow this pattern
-- (batch by session, ~25 functions max per file, document drift origins).
--
-- Rollback: not applicable — these are captures of the current live state.
-- If a body is found to be wrong AFTER apply, fix forward via new migration.
--
-- GRANT EXECUTE clauses NOT included in this capture (per code-reviewer LOW finding,
-- PR #228). The 26 functions inherit grants from their original CREATE FUNCTION
-- migrations. For fresh-DB apply (e.g. `supabase db reset` replaying all migrations
-- chronologically), grants from prior files remain in effect after CREATE OR REPLACE.
-- This file does NOT redundantly re-grant. Same pattern as
-- 20260723000000_baseline_rpcs_after_schema.sql and other Phase B captures.
--
-- Pre-existing patterns canonicalized in this capture WITHOUT inline cleanup (also
-- per code-reviewer MED findings — modifying bodies inline would trigger re-drift):
--   - sign_volunteer_agreement (line ~2779): notification recipient WHERE uses
--     `m.operational_role = 'manager' OR m.is_superadmin = true` instead of
--     can_by_member('manage_member') query. Pre-existing since p203 (PR #184).
--     Cleanup tracked as OPP-226.B in docs/audit/P162_GAP_OPPORTUNITY_LOG.md.
--   - update_board_item (line ~2831): v_is_gp hybrid retains is_superadmin +
--     hardcoded `operational_role IN ('manager', 'deputy_manager')` alongside
--     `can_by_member('manage_platform')`. p180 ADR-0011 hybrid intentionally
--     preserved for cache-drift defense-in-depth. No cleanup needed.

-- ============================================================
-- _compute_pert_cutoff_core(p_cycle_id uuid, p_role text, p_filter_active_only boolean, p_score_column text, p_actor_id uuid)
-- ============================================================
CREATE OR REPLACE FUNCTION public._compute_pert_cutoff_core(p_cycle_id uuid, p_role text DEFAULT 'researcher'::text, p_filter_active_only boolean DEFAULT true, p_score_column text DEFAULT 'objective_score_avg'::text, p_actor_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cycle record;
  v_cohort record;
  v_target numeric;
  v_band_lower numeric;
  v_band_upper numeric;
  v_method text;
  v_n int;
  v_updated_rows int;
  v_fallback_target numeric;
BEGIN
  IF p_score_column NOT IN ('objective_score_avg', 'final_score', 'research_score') THEN
    RETURN jsonb_build_object(
      'error', 'invalid_score_column',
      'allowed', jsonb_build_array('objective_score_avg', 'final_score', 'research_score'),
      'received', p_score_column
    );
  END IF;

  SELECT sc.id, sc.cycle_code INTO v_cycle FROM public.selection_cycles sc WHERE sc.id = p_cycle_id;
  IF v_cycle.id IS NULL THEN
    RETURN jsonb_build_object('error', 'cycle_not_found', 'cycle_id', p_cycle_id);
  END IF;

  WITH prior_cycles AS (
    SELECT id FROM public.selection_cycles
    WHERE id != p_cycle_id
      AND created_at < (SELECT created_at FROM public.selection_cycles WHERE id = p_cycle_id)
  ),
  cohort_apps AS (
    SELECT
      CASE p_score_column
        WHEN 'objective_score_avg' THEN sa.objective_score_avg
        WHEN 'final_score' THEN sa.final_score
        WHEN 'research_score' THEN sa.research_score
      END AS s
    FROM public.selection_applications sa
    WHERE sa.cycle_id IN (SELECT id FROM prior_cycles)
      AND sa.role_applied = p_role
      AND sa.status = 'approved'
      AND CASE p_score_column
            WHEN 'objective_score_avg' THEN sa.objective_score_avg IS NOT NULL
            WHEN 'final_score' THEN sa.final_score IS NOT NULL
            WHEN 'research_score' THEN sa.research_score IS NOT NULL
          END
      AND (
        NOT p_filter_active_only
        OR EXISTS (
          SELECT 1 FROM public.engagements e
          JOIN public.persons pp ON pp.id = e.person_id
          WHERE pp.legacy_member_id IS NOT NULL
            AND e.kind = 'volunteer'
            AND e.role = p_role
            AND e.status = 'active'
            AND lower(coalesce(sa.email,'')) IN (
              SELECT lower(m.email) FROM public.members m
              WHERE m.id = pp.legacy_member_id AND m.email IS NOT NULL
            )
        )
      )
  )
  SELECT COUNT(*)::int AS n, MIN(s) AS s_min, MAX(s) AS s_max, AVG(s) AS s_avg
  INTO v_cohort FROM cohort_apps;

  v_n := COALESCE(v_cohort.n, 0);

  IF v_n >= 10 THEN
    v_target := (2 * v_cohort.s_min + 4 * v_cohort.s_avg + 2 * v_cohort.s_max) / 8;
    v_method := 'dynamic';
  ELSE
    SELECT MAX(pert_target_score) INTO v_fallback_target
    FROM public.selection_applications
    WHERE pert_target_score IS NOT NULL AND cycle_id != p_cycle_id;
    IF v_fallback_target IS NULL THEN
      v_target := NULL; v_method := 'disabled';
    ELSE
      v_target := v_fallback_target; v_method := 'historical_fallback';
    END IF;
  END IF;

  IF v_target IS NOT NULL THEN
    v_band_lower := v_target * 0.90;
    v_band_upper := v_target * 1.10;
  END IF;

  UPDATE public.selection_applications
  SET pert_target_score = v_target,
      pert_band_lower = v_band_lower,
      pert_band_upper = v_band_upper,
      pert_cutoff_method = v_method,
      pert_cohort_n = v_n,
      pert_calc_at = now()
  WHERE cycle_id = p_cycle_id;
  GET DIAGNOSTICS v_updated_rows = ROW_COUNT;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    p_actor_id, 'pert_cutoff_computed', 'selection_cycle', p_cycle_id,
    jsonb_build_object(
      'cycle_code', v_cycle.cycle_code,
      'role', p_role,
      'score_column_used', p_score_column,
      'filter_active_only', p_filter_active_only,
      'cohort_n', v_n,
      'cohort_min', v_cohort.s_min,
      'cohort_max', v_cohort.s_max,
      'cohort_avg', v_cohort.s_avg,
      'target_score', v_target,
      'band_lower', v_band_lower,
      'band_upper', v_band_upper,
      'method', v_method,
      'rows_updated', v_updated_rows
    ),
    jsonb_build_object('source', '_compute_pert_cutoff_core', 'actor_kind', CASE WHEN p_actor_id IS NULL THEN 'system' ELSE 'human' END)
  );

  RETURN jsonb_build_object(
    'success', true, 'cycle_id', p_cycle_id, 'cycle_code', v_cycle.cycle_code,
    'role', p_role, 'score_column_used', p_score_column,
    'cohort_n', v_n,
    'cohort_stats', jsonb_build_object('min', v_cohort.s_min, 'max', v_cohort.s_max, 'avg', v_cohort.s_avg),
    'target_score', v_target, 'band_lower', v_band_lower, 'band_upper', v_band_upper,
    'method', v_method, 'rows_updated', v_updated_rows, 'computed_at', now()
  );
END;
$function$
;

-- ============================================================
-- admin_inactivate_member(p_member_id uuid, p_reason text)
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_inactivate_member(p_member_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor_id uuid;
BEGIN
  SELECT id INTO v_actor_id FROM public.members WHERE auth_id = auth.uid();
  IF v_actor_id IS NULL OR NOT public.can_by_member(v_actor_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member permission';
  END IF;

  UPDATE public.members
     SET is_active = false,
         inactivation_reason = p_reason
   WHERE id = p_member_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_actor_id, 'member.inactivated', 'member', p_member_id,
    jsonb_build_object('is_active', false, 'reason', p_reason)
  );

  RETURN json_build_object('success', true);
END;
$function$
;

-- ============================================================
-- admin_update_application(p_application_id uuid, p_data jsonb)
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_update_application(p_application_id uuid, p_data jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id        uuid;
  v_caller_name      text;
  v_app              record;
  v_old_status       text;
  v_new_status       text;
  v_canonical_result jsonb := NULL;
  v_member_id        uuid := NULL;
  v_seeded_count     int := 0;
  v_promoted         boolean := false;
  v_target_role      text;
BEGIN
  SELECT id, name INTO v_caller_id, v_caller_name FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN json_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN RETURN json_build_object('error', 'Application not found'); END IF;

  v_old_status := v_app.status;
  v_new_status := coalesce(p_data->>'status', v_old_status);

  UPDATE public.selection_applications SET
    status            = v_new_status,
    feedback          = coalesce(p_data->>'feedback', feedback),
    tags              = CASE WHEN p_data ? 'tags'              THEN ARRAY(SELECT jsonb_array_elements_text(p_data->'tags')) ELSE tags END,
    role_applied      = coalesce(p_data->>'role_applied', role_applied),
    converted_from    = CASE WHEN p_data ? 'converted_from'    THEN p_data->>'converted_from'    ELSE converted_from END,
    converted_to      = CASE WHEN p_data ? 'converted_to'      THEN p_data->>'converted_to'      ELSE converted_to END,
    conversion_reason = CASE WHEN p_data ? 'conversion_reason' THEN p_data->>'conversion_reason' ELSE conversion_reason END,
    updated_at        = now()
  WHERE id = p_application_id;

  IF v_new_status = 'approved' AND v_old_status <> 'approved' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.selection_membership_snapshots sms
      WHERE sms.application_id = p_application_id AND sms.is_partner_chapter = true
    ) THEN
      UPDATE public.selection_applications
      SET tags = array_append(tags, 'no_partner_chapter')
      WHERE id = p_application_id AND NOT ('no_partner_chapter' = ANY(tags));
    END IF;

    v_canonical_result := public.approve_selection_application(p_application_id, p_data);

    -- Council fix: RAISE so the entire transaction rolls back if canonical fails
    -- (otherwise the UPDATE status='approved' above commits without member/person/
    -- engagement, creating an invariant-R violation).
    IF (v_canonical_result->>'success') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Canonical approval failed: %', coalesce(v_canonical_result->>'error', 'unknown')
        USING ERRCODE = 'P0001',
              DETAIL = v_canonical_result::text;
    END IF;

    v_member_id      := (v_canonical_result->>'member_id')::uuid;
    v_seeded_count   := coalesce((v_canonical_result->>'onboarding_seeded')::int, 0);
    v_promoted       := coalesce((v_canonical_result->>'role_promoted')::boolean, false);
    v_target_role    := v_canonical_result->>'promoted_to';
  END IF;

  INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'selection_status_change',
    'info',
    'Application ' || v_app.applicant_name || ': ' || v_old_status || ' → ' || v_new_status,
    jsonb_build_object(
      'application_id',    p_application_id,
      'old_status',        v_old_status,
      'new_status',        v_new_status,
      'actor',             v_caller_name,
      'member_id',         v_member_id,
      'onboarding_seeded', v_seeded_count,
      'role_promoted',     v_promoted,
      'promoted_to',       CASE WHEN v_promoted THEN v_target_role ELSE NULL END,
      'canonical_invoked', v_canonical_result IS NOT NULL
    )
  );

  RETURN json_build_object(
    'success',           true,
    'old_status',        v_old_status,
    'new_status',        v_new_status,
    'onboarding_seeded', v_seeded_count,
    'role_promoted',     v_promoted,
    'promoted_to',       CASE WHEN v_promoted THEN v_target_role ELSE NULL END,
    'canonical',         v_canonical_result
  );
END;
$function$
;

-- ============================================================
-- analyze_application_video_async(p_application_id uuid, p_pillar text, p_force boolean)
-- ============================================================
CREATE OR REPLACE FUNCTION public.analyze_application_video_async(p_application_id uuid, p_pillar text DEFAULT NULL::text, p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_app record;
  v_url text := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/analyze-application-video';
  v_key text;
  v_dispatch_id bigint;
  v_existing_pending int;
BEGIN
  SELECT id, cycle_id,
         consent_ai_analysis_at, consent_ai_analysis_revoked_at,
         consent_voice_biometric_at, consent_voice_biometric_revoked_at
    INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error', 'application_not_found');
  END IF;

  -- LGPD generic AI consent gate (predates this migration; preserved)
  IF v_app.consent_ai_analysis_at IS NULL OR v_app.consent_ai_analysis_revoked_at IS NOT NULL THEN
    RETURN jsonb_build_object('skipped', true, 'reason', 'consent_pending_or_revoked');
  END IF;

  -- p207 #221: LGPD Art. 11 §I biometric voice consent gate (NEW)
  -- Trigger trg_video_ai_analysis_on_upload was DROPPED at Phase 1 of this
  -- remediation. This gate ALSO refuses manual MCP tool calls until candidate
  -- has explicit Art. 11 consent + non-revoked status. Returns graceful skip
  -- envelope so MCP/UI callers see structured response, not exception.
  IF v_app.consent_voice_biometric_at IS NULL OR v_app.consent_voice_biometric_revoked_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'skipped', true,
      'reason', 'voice_biometric_consent_required',
      'detail', 'LGPD Art. 11 §I — voice biometric is sensitive data requiring explicit consent destacado per Art. 8. Pipeline blocked until consent_voice_biometric_at is captured per Termo de Speaker.',
      'issue', 221
    );
  END IF;

  -- Idempotency: skip if pending suggestion already exists (unless force)
  IF NOT p_force THEN
    SELECT COUNT(*) INTO v_existing_pending FROM public.selection_evaluation_ai_suggestions
    WHERE application_id = p_application_id
      AND evaluation_type = 'video'
      AND used_in_evaluation_id IS NULL
      AND superseded_by IS NULL
      AND (p_pillar IS NULL OR suggested_scores ? p_pillar);
    IF v_existing_pending > 0 THEN
      RETURN jsonb_build_object('skipped', true, 'reason', 'pending_suggestion_exists',
        'existing_count', v_existing_pending,
        'hint', 'pass force=true to regenerate');
    END IF;
  END IF;

  -- Read service_role_key from vault
  SELECT decrypted_secret INTO v_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_key IS NULL THEN
    RAISE EXCEPTION 'service_role_key not in vault (analyze_application_video_async)';
  END IF;

  -- Async dispatch via pg_net (EF returns 200 quickly; analysis is async inside)
  SELECT net.http_post(
    url := v_url,
    body := jsonb_build_object(
      'application_id', p_application_id,
      'pillar', p_pillar,
      'force', p_force,
      'triggered_by', 'rpc'
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    )
  ) INTO v_dispatch_id;

  RETURN jsonb_build_object(
    'dispatched', true,
    'application_id', p_application_id,
    'pillar', COALESCE(p_pillar, 'all'),
    'force', p_force,
    'dispatch_id', v_dispatch_id
  );
END;
$function$
;

-- ============================================================
-- approve_selection_application(p_application_id uuid, p_decision jsonb)
-- ============================================================
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
  v_legal_basis      text := 'contract_volunteer';
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

  -- Council fix: protect against historical-cycle backfill creating an engagement
  -- with status='active' AND end_date < CURRENT_DATE.
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

  INSERT INTO public.onboarding_progress (application_id, member_id, step_key, status, metadata)
  SELECT p_application_id, v_member_id, s.id, 'pending', '{}'::jsonb
  FROM public.onboarding_steps s
  WHERE s.is_required = true
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

  -- Council fix: dedup guard for selection_approved notification on idempotent re-call.
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
$function$
;

-- ============================================================
-- check_schema_invariants((no args))
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_schema_invariants()
 RETURNS TABLE(invariant_name text, description text, severity text, violation_count integer, sample_ids uuid[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL
     AND current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: check_schema_invariants requires authentication';
  END IF;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'alumni' AND operational_role IS DISTINCT FROM 'alumni'
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'A1_alumni_role_consistency'::text,
         'member_status=alumni must coerce operational_role=alumni (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'observer' AND operational_role NOT IN ('observer','guest','none')
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'A2_observer_role_consistency'::text,
         'member_status=observer must coerce operational_role IN (observer,guest,none) (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH computed AS (
    SELECT m.id AS member_id,
      CASE
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
        WHEN bool_or(
          (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
          OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
              AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
          OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
              AND ae.role IN ('leader','co_leader','owner','coordinator'))
        ) THEN 'researcher'
        WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
        WHEN bool_or(ae.kind = 'observer') THEN 'observer'
        WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
        WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
        WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
        WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
        ELSE 'guest'
      END AS expected_role
    FROM public.members m
    LEFT JOIN public.auth_engagements ae ON ae.person_id = m.person_id AND ae.is_authoritative = true
    WHERE m.member_status='active' AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
    GROUP BY m.id
  ),
  drift AS (
    SELECT c.member_id FROM computed c
    JOIN public.members m ON m.id = c.member_id
    WHERE m.operational_role IS DISTINCT FROM c.expected_role
  )
  SELECT 'A3_active_role_engagement_derivation'::text,
         'active member operational_role must equal priority-ladder derivation from active engagements (cache trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE ((member_status='active' AND is_active=false) OR (member_status IN ('observer','alumni','inactive') AND is_active=true))
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'B_is_active_status_mismatch'::text,
         'members.is_active must match member_status mapping (active=true, terminal=false)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive') AND designations IS NOT NULL AND array_length(designations,1)>0
  )
  SELECT 'C_designations_in_terminal_status'::text,
         'members.designations must be empty when member_status is observer/alumni/inactive'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    JOIN public.persons p ON p.id = m.person_id
    WHERE m.auth_id IS NOT NULL AND p.auth_id IS NOT NULL AND m.auth_id IS DISTINCT FROM p.auth_id
  )
  SELECT 'D_auth_id_mismatch_person_member'::text,
         'persons.auth_id and members.auth_id must agree when both are set (ghost resolution sync)'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ae.engagement_id AS e_id FROM public.auth_engagements ae
    JOIN public.members m ON m.person_id = ae.person_id
    WHERE ae.status='active' AND m.member_status IN ('observer','alumni','inactive')
      AND ae.kind NOT IN ('observer','alumni','external_signer','sponsor','chapter_board','partner_contact')
  )
  SELECT 'E_engagement_active_with_terminal_member'::text,
         'engagement.status=active is inconsistent with member.member_status in (observer/alumni/inactive) unless kind matches'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(e_id ORDER BY e_id) FROM (SELECT e_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT i.id AS initiative_id FROM public.initiatives i
    WHERE i.legacy_tribe_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.tribes t WHERE t.id = i.legacy_tribe_id)
  )
  SELECT 'F_initiative_legacy_tribe_orphan'::text,
         'initiatives.legacy_tribe_id must point to an existing tribe (bridge integrity)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(initiative_id ORDER BY initiative_id) FROM (SELECT initiative_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
    WHERE gd.current_version_id IS NOT NULL
      AND (dv.id IS NULL OR dv.locked_at IS NULL)
      AND NOT EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status IN ('review','approved','activated')
          AND ac.closed_at IS NULL
      )
  )
  SELECT 'J_current_version_published'::text,
         'governance_documents.current_version_id must point to a document_versions row with locked_at IS NOT NULL — unless an open approval_chain (review/approved/activated, closed_at NULL) is in flight that will lock the version on close (Phase IP-1, chain-aware).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.operational_role='external_signer'
      AND NOT EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id=m.person_id AND ae.kind='external_signer' AND ae.status='active' AND ae.is_authoritative=true
      )
  )
  SELECT 'K_external_signer_integrity'::text,
         'members.operational_role=external_signer must have an active auth_engagements row with kind=external_signer (Phase IP-1).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.member_status IN ('alumni','observer','inactive') AND m.anonymized_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.member_offboarding_records r WHERE r.member_id=m.id)
  )
  SELECT 'L_offboarding_record_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have a member_offboarding_records row (#91 G3 trigger).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH expected AS (
    SELECT a.id AS application_id, a.research_score AS cached,
      CASE
        WHEN e.obj_avg IS NOT NULL AND e.int_avg IS NOT NULL THEN round(e.obj_avg + e.int_avg, 2)
        WHEN e.obj_avg IS NOT NULL THEN round(e.obj_avg, 2)
        ELSE NULL
      END AS expected
    FROM public.selection_applications a
    CROSS JOIN LATERAL (
      SELECT AVG(weighted_subtotal) FILTER (WHERE evaluation_type='objective' AND submitted_at IS NOT NULL) AS obj_avg,
        AVG(weighted_subtotal) FILTER (WHERE evaluation_type='interview' AND submitted_at IS NOT NULL) AS int_avg
      FROM public.selection_evaluations WHERE application_id=a.id
    ) e
  ),
  drift AS (
    SELECT application_id FROM expected
    WHERE (cached IS NULL) IS DISTINCT FROM (expected IS NULL)
       OR (cached IS NOT NULL AND expected IS NOT NULL AND ABS(cached - expected) > 0.01)
  )
  SELECT 'M_application_score_consistency'::text,
         'selection_applications.research_score must equal compute_application_scores(application_id) derivation (sync trigger trg_recompute_application_scores).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive')
      AND offboarded_at IS NULL AND anonymized_at IS NULL
      AND name <> 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'N_terminal_status_offboarded_at_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have offboarded_at NOT NULL (ARM-9 G6 defense-in-depth complement to L).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ma.id AS artifact_id FROM public.meeting_artifacts ma
    WHERE ma.event_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.events e WHERE e.id = ma.event_id)
  )
  SELECT 'O_meeting_artifact_event_orphan'::text,
         'meeting_artifacts.event_id must point to an existing event when not NULL (FK defense).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(artifact_id ORDER BY artifact_id) FROM (SELECT artifact_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  SELECT 'P_tribe_initiative_bridge_complete'::text,
         'tribes.is_active=true must have at least one initiative.legacy_tribe_id pointing to it (V3-V4 bridge; cron leader digest depends).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM public.tribes t
          WHERE t.is_active = true
            AND NOT EXISTS (SELECT 1 FROM public.initiatives i WHERE i.legacy_tribe_id = t.id)),
         NULL::uuid[];

  RETURN QUERY
  WITH drift AS (
    SELECT id AS engagement_id FROM public.engagements
    WHERE status = 'expired' AND end_date > CURRENT_DATE
  )
  SELECT 'Q_expired_engagement_end_date'::text,
         'engagements.status=expired requires end_date <= CURRENT_DATE (impossible to be expired in the future; VEP service_latest_end_date is source of truth).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT a.id AS application_id
    FROM public.selection_applications a
    WHERE a.status = 'approved'
      AND a.email IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.members m WHERE lower(m.email) = lower(a.email)
      )
  )
  SELECT 'R_approved_application_has_member'::text,
         'selection_applications.status=approved must have a matching members row by lower(email). Bypass of approve_selection_application() canonical RPC creates this drift (Issue #180).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  -- S (p204, #180) — DISTINCT guards against multi-cycle re-applicants inflating count.
  RETURN QUERY
  WITH drift AS (
    SELECT DISTINCT m.id AS member_id
    FROM public.selection_applications a
    JOIN public.members m ON lower(m.email) = lower(a.email)
    WHERE a.status = 'approved' AND m.person_id IS NULL
  )
  SELECT 'S_approved_member_has_person_id'::text,
         'members tied to an approved selection_applications row must have person_id NOT NULL (V4 graph anchor for engagements). Issue #180.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

END;
$function$
;

-- ============================================================
-- complete_leader_review(p_item_id uuid, p_decision text, p_notes text)
-- ============================================================
CREATE OR REPLACE FUNCTION public.complete_leader_review(p_item_id uuid, p_decision text, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_item   board_items%ROWTYPE;
  v_initiative_id uuid;
  v_is_leader boolean := false;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_decision NOT IN ('approved', 'returned', 'waived') THEN
    RAISE EXCEPTION 'Decision must be one of: approved, returned, waived (got: %)', p_decision;
  END IF;

  SELECT * INTO v_item FROM public.board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;

  IF v_item.curation_status NOT IN ('leader_review', 'draft') THEN
    RAISE EXCEPTION 'Leader review can only be completed from leader_review or draft (current: %)', v_item.curation_status;
  END IF;

  SELECT pb.initiative_id INTO v_initiative_id
    FROM public.project_boards pb WHERE pb.id = v_item.board_id;

  IF v_initiative_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.persons p ON p.id = e.person_id
    WHERE e.initiative_id = v_initiative_id
      AND e.status = 'active'
      AND e.role = 'leader'
      AND p.auth_id = auth.uid()
  ) THEN
    v_is_leader := true;
  ELSIF public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    v_is_leader := true;
  END IF;

  IF NOT v_is_leader THEN
    RAISE EXCEPTION 'Leader review requires tribe leadership of card''s initiative or governance reviewer authority';
  END IF;

  IF p_decision IN ('approved', 'waived') THEN
    UPDATE public.board_items
    SET curation_status = 'curation_pending',
        leader_review_completed_at = now(),
        leader_review_decision = p_decision,
        leader_review_notes = p_notes,
        leader_reviewer_id = v_caller.id,
        updated_at = now()
    WHERE id = p_item_id;

    -- Use distinct action for analytics clarity (added to CHECK in B1 fix)
    INSERT INTO public.board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES (
      v_item.board_id,
      p_item_id,
      'leader_review_completed',
      'Leader review ' || p_decision || ' → submetido à curadoria' || COALESCE(' — ' || p_notes, ''),
      v_caller.id
    );
  ELSIF p_decision = 'returned' THEN
    -- p197 fix H2: ALSO reset waiver state when returning. Without this,
    -- author who waived peer review then got returned would have stale
    -- "waived" flag persisting and potentially skip peer review on retry.
    UPDATE public.board_items
    SET curation_status = 'draft',
        leader_review_completed_at = now(),
        leader_review_decision = p_decision,
        leader_review_notes = p_notes,
        leader_reviewer_id = v_caller.id,
        peer_review_completed_at = NULL,
        peer_review_summary = NULL,
        peer_review_waived = false,
        peer_review_waived_reason = NULL,
        updated_at = now()
    WHERE id = p_item_id;

    INSERT INTO public.board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES (
      v_item.board_id,
      p_item_id,
      'leader_review_completed',
      'Leader review devolvido ao autor' || COALESCE(' — ' || p_notes, ''),
      v_caller.id
    );

    -- p197 fix H1: pass 'board_item' literal as p_source_type
    -- (NOT board_id::text — frontend needs semantic type for deep link)
    IF v_item.assignee_id IS NOT NULL THEN
      PERFORM public.create_notification(
        v_item.assignee_id,
        'card_moved',
        'board_item',
        v_item.id,
        v_item.title,
        v_caller.id,
        'Líder devolveu sua peça para revisão' || COALESCE(': ' || p_notes, '')
      );
    END IF;
  END IF;
END;
$function$
;

-- ============================================================
-- compute_pert_cutoff(p_cycle_id uuid, p_role text, p_filter_active_only boolean, p_score_column text)
-- ============================================================
CREATE OR REPLACE FUNCTION public.compute_pert_cutoff(p_cycle_id uuid, p_role text DEFAULT 'researcher'::text, p_filter_active_only boolean DEFAULT true, p_score_column text DEFAULT 'objective_score_avg'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
BEGIN
  SELECT m.id, m.name INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'manage_member');
  END IF;
  RETURN public._compute_pert_cutoff_core(p_cycle_id, p_role, p_filter_active_only, p_score_column, v_caller.id);
END;
$function$
;

-- ============================================================
-- counter_sign_certificate(p_certificate_id uuid, p_signed_ip text, p_signed_user_agent text)
-- ============================================================
CREATE OR REPLACE FUNCTION public.counter_sign_certificate(p_certificate_id uuid, p_signed_ip text DEFAULT NULL::text, p_signed_user_agent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_is_manage_member boolean;
  v_is_chapter_board boolean;
  v_cert record;
  v_contracting_chapter text;
  v_hash text;
  v_signed_at timestamptz := now();
  v_ip inet := NULL;
BEGIN
  p_signed_user_agent := left(p_signed_user_agent, 500);

  SELECT m.id, m.chapter, m.person_id
    INTO v_caller_id, v_caller_chapter, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  v_is_manage_member := public.can_by_member(v_caller_id, 'manage_member');
  v_is_chapter_board := EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.person_id = v_caller_person_id
      AND ae.kind = 'chapter_board'
      AND ae.status = 'active'
  );

  IF NOT v_is_manage_member AND NOT v_is_chapter_board THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  SELECT * INTO v_cert FROM public.certificates WHERE id = p_certificate_id;
  IF v_cert IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  IF v_cert.counter_signed_by IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'already_counter_signed');
  END IF;

  v_contracting_chapter := COALESCE(
    v_cert.content_snapshot->>'contracting_chapter',
    (SELECT m.chapter FROM public.members m WHERE m.id = v_cert.member_id)
  );

  IF v_is_chapter_board AND NOT v_is_manage_member THEN
    IF v_contracting_chapter IS DISTINCT FROM v_caller_chapter THEN
      RETURN jsonb_build_object('error', 'not_authorized_different_chapter');
    END IF;
  END IF;

  v_hash := encode(public.sha256(public.convert_to(
    COALESCE(v_cert.signature_hash,'') || v_caller_id::text || v_signed_at::text || 'nucleo-ia-countersign-salt', 'UTF8'
  )), 'hex');

  BEGIN
    IF p_signed_ip IS NOT NULL AND length(trim(p_signed_ip)) > 0 THEN
      v_ip := p_signed_ip::inet;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL;
  END;

  UPDATE public.certificates
  SET counter_signed_by = v_caller_id,
      counter_signed_at = v_signed_at,
      counter_signature_hash = v_hash
  WHERE id = p_certificate_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'certificate_counter_signed', 'certificate', p_certificate_id,
    jsonb_build_object(
      'verification_code', v_cert.verification_code,
      'type', v_cert.type,
      'contracting_chapter', v_contracting_chapter,
      'counter_signature_hash', v_hash,
      'counter_signed_at', v_signed_at,
      'counter_signer_ip', v_ip::text,
      'counter_signer_user_agent', p_signed_user_agent
    ));

  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  VALUES (v_cert.member_id, 'certificate_ready',
    'Seu ' || v_cert.title || ' esta pronto!',
    'O documento foi contra-assinado e esta disponivel. Codigo: ' || v_cert.verification_code,
    '/certificates', 'certificate', p_certificate_id,
    public._delivery_mode_for('certificate_ready'));

  RETURN jsonb_build_object(
    'success', true,
    'counter_signature_hash', v_hash,
    'counter_signed_at', v_signed_at
  );
END;
$function$
;

-- ============================================================
-- deselect_tribe((no args))
-- ============================================================
CREATE OR REPLACE FUNCTION public.deselect_tribe()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  _member_id UUID;
BEGIN
  SELECT id INTO _member_id FROM members 
  WHERE auth_id = auth.uid()
     OR email = (SELECT email FROM auth.users WHERE id = auth.uid())
     OR (SELECT email FROM auth.users WHERE id = auth.uid()) = ANY(secondary_emails)
  LIMIT 1;
  
  IF _member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Membro não encontrado');
  END IF;
  
  DELETE FROM tribe_selections WHERE member_id = _member_id;
  RETURN json_build_object('success', true);
END;
$function$
;

-- ============================================================
-- finalize_decisions(p_cycle_id uuid, p_decisions jsonb)
-- ============================================================
CREATE OR REPLACE FUNCTION public.finalize_decisions(p_cycle_id uuid, p_decisions jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller            record;
  v_committee         record;
  v_decision          jsonb;
  v_app_id            uuid;
  v_app               record;
  v_status            text;
  v_feedback          text;
  v_convert_to        text;
  v_approved_count    int := 0;
  v_rejected_count    int := 0;
  v_waitlisted_count  int := 0;
  v_converted_count   int := 0;
  v_created_members   int := 0;
  v_promoted_count    int := 0;
  v_canonical_result  jsonb;
  v_member_id         uuid;
  v_promoted_this_app boolean;
  v_target_role       text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = p_cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RETURN json_build_object('error', 'Unauthorized: must be committee lead or platform admin');
  END IF;

  FOR v_decision IN SELECT * FROM jsonb_array_elements(p_decisions)
  LOOP
    v_app_id            := (v_decision->>'application_id')::uuid;
    v_status            := v_decision->>'decision';
    v_feedback          := v_decision->>'feedback';
    v_convert_to        := v_decision->>'convert_to';
    v_promoted_this_app := false;
    v_target_role       := NULL;
    v_member_id         := NULL;
    v_canonical_result  := NULL;

    SELECT * INTO v_app FROM public.selection_applications WHERE id = v_app_id AND cycle_id = p_cycle_id;
    IF NOT FOUND THEN CONTINUE; END IF;

    IF v_convert_to IS NOT NULL AND v_convert_to != '' THEN
      UPDATE public.selection_applications SET
        status            = 'converted',
        converted_from    = v_app.role_applied,
        converted_to      = v_convert_to,
        conversion_reason = coalesce(v_feedback, 'Promoted by committee'),
        role_applied      = v_convert_to,
        feedback          = coalesce(v_feedback, feedback),
        updated_at        = now()
      WHERE id = v_app_id;
      v_converted_count := v_converted_count + 1;

      PERFORM public.create_notification(
        m.id, 'selection_conversion_offer',
        'Proposta de conversão de papel',
        'O comitê identificou seu perfil para o papel de ' || v_convert_to || '. Acesse a plataforma para mais detalhes.',
        '/admin/selection', 'selection_application', v_app_id
      ) FROM public.members m WHERE lower(m.email) = lower(v_app.email);

      CONTINUE;
    END IF;

    IF v_status = 'approved' THEN
      -- Council fix: BEGIN/EXCEPTION sub-block — canonical failure rolls back
      -- this decision (status UPDATE + canonical side-effects) WITHOUT aborting
      -- the rest of the batch (preserves best-effort semantics).
      BEGIN
        UPDATE public.selection_applications SET
          status     = v_status,
          feedback   = coalesce(v_feedback, feedback),
          updated_at = now()
        WHERE id = v_app_id;

        IF NOT EXISTS (
          SELECT 1 FROM public.selection_membership_snapshots
          WHERE application_id = v_app_id AND is_partner_chapter = true
        ) THEN
          UPDATE public.selection_applications SET tags = array_append(tags, 'no_partner_chapter')
          WHERE id = v_app_id AND NOT ('no_partner_chapter' = ANY(tags));
        END IF;

        v_canonical_result := public.approve_selection_application(v_app_id, '{}'::jsonb);

        IF (v_canonical_result->>'success') IS DISTINCT FROM 'true' THEN
          RAISE EXCEPTION 'Canonical approval failed for application %: %',
                          v_app_id,
                          coalesce(v_canonical_result->>'error', 'unknown')
            USING ERRCODE = 'P0001';
        END IF;

        v_approved_count := v_approved_count + 1;
        v_member_id         := (v_canonical_result->>'member_id')::uuid;
        v_promoted_this_app := coalesce((v_canonical_result->>'role_promoted')::boolean, false);
        v_target_role       := v_canonical_result->>'promoted_to';
        IF (v_canonical_result->>'member_created')::boolean THEN
          v_created_members := v_created_members + 1;
        END IF;
        IF v_promoted_this_app THEN
          v_promoted_count := v_promoted_count + 1;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_member_id        := NULL;
        v_canonical_result := jsonb_build_object('success', false, 'error', SQLERRM);
      END;

    ELSIF v_status = 'rejected' THEN
      UPDATE public.selection_applications SET
        status     = v_status,
        feedback   = coalesce(v_feedback, feedback),
        updated_at = now()
      WHERE id = v_app_id;
      v_rejected_count := v_rejected_count + 1;
    ELSIF v_status = 'waitlist' THEN
      UPDATE public.selection_applications SET
        status     = v_status,
        feedback   = coalesce(v_feedback, feedback),
        updated_at = now()
      WHERE id = v_app_id;
      v_waitlisted_count := v_waitlisted_count + 1;
    ELSE
      v_canonical_result := jsonb_build_object('success', false, 'error', 'unknown_decision', 'decision', v_status);
    END IF;

    INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
    VALUES (
      'selection_decision',
      'info',
      v_app.applicant_name || ' → ' || v_status,
      jsonb_build_object(
        'application_id',    v_app_id,
        'decision',          v_status,
        'actor',             v_caller.name,
        'member_id',         v_member_id,
        'role_promoted',     v_promoted_this_app,
        'promoted_to',       CASE WHEN v_promoted_this_app THEN v_target_role ELSE NULL END,
        'canonical_invoked', v_canonical_result IS NOT NULL,
        'canonical_success', (v_canonical_result->>'success')::boolean
      )
    );
  END LOOP;

  INSERT INTO public.selection_diversity_snapshots (cycle_id, snapshot_type, metrics)
  VALUES (p_cycle_id, 'approved', (
    SELECT jsonb_build_object(
      'by_chapter', (SELECT jsonb_object_agg(coalesce(chapter,'unknown'), cnt) FROM (SELECT chapter, count(*) as cnt FROM public.selection_applications WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY chapter) x),
      'by_gender',  (SELECT jsonb_object_agg(coalesce(gender,'unknown'), cnt) FROM (SELECT gender,  count(*) as cnt FROM public.selection_applications WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY gender) x),
      'by_role',    (SELECT jsonb_object_agg(role_applied, cnt) FROM (SELECT role_applied, count(*) as cnt FROM public.selection_applications WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY role_applied) x),
      'total_approved',  v_approved_count,
      'total_rejected',  v_rejected_count,
      'total_converted', v_converted_count,
      'finalized_at',    now()
    )
  ));

  RETURN json_build_object(
    'approved',         v_approved_count,
    'rejected',         v_rejected_count,
    'waitlisted',       v_waitlisted_count,
    'converted',        v_converted_count,
    'members_created',  v_created_members,
    'members_promoted', v_promoted_count,
    'cycle_id',         p_cycle_id
  );
END;
$function$
;

-- ============================================================
-- get_member_by_auth((no args))
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_member_by_auth()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_member_id uuid;
  v_existing_auth_id uuid;
  v_result json;
BEGIN
  IF v_uid IS NULL THEN
    RETURN NULL;
  END IF;

  -- Step 1: direct match on members.auth_id (the common case)
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_uid LIMIT 1;

  -- Step 2: match on secondary_auth_ids (admin-pre-approved alternates → safe to rotate)
  IF v_member_id IS NULL THEN
    SELECT id INTO v_member_id
      FROM public.members
     WHERE v_uid = ANY(COALESCE(secondary_auth_ids, '{}'))
     LIMIT 1;

    IF v_member_id IS NOT NULL THEN
      SELECT auth_id INTO v_existing_auth_id FROM public.members WHERE id = v_member_id;

      UPDATE public.members
         SET auth_id            = v_uid,
             secondary_auth_ids = array_append(
                                    array_remove(COALESCE(secondary_auth_ids, '{}'::uuid[]), v_uid),
                                    v_existing_auth_id
                                  ),
             updated_at         = now()
       WHERE id = v_member_id;

      -- p177 D=1 fix: sync persons.auth_id to the new primary (mirror try_auto_link_ghost).
      UPDATE public.persons
         SET auth_id = v_uid
       WHERE legacy_member_id = v_member_id
         AND (auth_id IS NULL OR auth_id <> v_uid);

      INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
      VALUES (
        v_member_id,
        'members.auth_id.rotated_secondary_to_primary',
        'member',
        v_member_id,
        jsonb_build_object(
          'promoted_auth_id', v_uid,
          'demoted_auth_id', v_existing_auth_id
        ),
        jsonb_build_object('via', 'get_member_by_auth.step2_secondary_auth_ids_match')
      );
    END IF;
  END IF;

  -- Step 3: PRIMARY email first-link (only when auth_id IS NULL — genuine ghost first login).
  -- P168 R3-a: dropped the (a) secondary_emails match branch and (b) replace-existing-auth_id
  -- branch. Both were the mechanism behind Paulo Alves identity hijack.
  IF v_member_id IS NULL THEN
    SELECT lower(email) INTO v_email FROM auth.users WHERE id = v_uid;

    IF v_email IS NOT NULL THEN
      SELECT id INTO v_member_id
        FROM public.members
       WHERE lower(email) = v_email
         AND auth_id IS NULL
       LIMIT 1;

      IF v_member_id IS NOT NULL THEN
        UPDATE public.members
           SET auth_id    = v_uid,
               updated_at = now()
         WHERE id = v_member_id;

        -- p177 D=1 fix: sync persons.auth_id on first-link (mirror try_auto_link_ghost).
        UPDATE public.persons
           SET auth_id = v_uid
         WHERE legacy_member_id = v_member_id
           AND (auth_id IS NULL OR auth_id <> v_uid);

        INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_member_id,
          'members.auth_id.first_link',
          'member',
          v_member_id,
          jsonb_build_object(
            'linked_auth_id', v_uid,
            'matched_via',    'primary_email',
            'matched_email',  v_email
          ),
          jsonb_build_object('via', 'get_member_by_auth.step3_primary_email_when_null')
        );
      END IF;
    END IF;
  END IF;

  IF v_member_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Return JSON shape — UNCHANGED from prior version (callers depend on this).
  SELECT row_to_json(q) INTO v_result FROM (
    SELECT m.id, m.name, m.email, m.secondary_emails,
      m.pmi_id, m.phone, m.operational_role, m.designations,
      compute_legacy_role(m.operational_role, m.designations)  AS role,
      compute_legacy_roles(m.operational_role, m.designations) AS roles,
      m.chapter, m.tribe_id, m.current_cycle_active, m.is_superadmin, m.is_active,
      m.member_status, m.state, m.country, m.share_whatsapp, m.signature_url,
      m.address, m.city, m.birth_date,
      m.share_address, m.share_birth_date,
      m.privacy_consent_accepted_at, m.privacy_consent_version, m.data_last_reviewed_at,
      m.inactivated_at, m.inactivation_reason,
      m.photo_url, m.linkedin_url, m.auth_id,
      m.credly_url, m.credly_badges, m.cpmai_certified,
      m.created_at, m.updated_at
    FROM public.members m
    WHERE m.id = v_member_id
  ) q;

  RETURN v_result;
END;
$function$
;

-- ============================================================
-- get_member_cycle_xp(p_member_id uuid)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_member_cycle_xp(p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  cycle_start_date date;
  v_rank int;
  v_total int;
  result json;
begin
  select cycle_start into cycle_start_date
  from public.cycles where is_current = true limit 1;

  if cycle_start_date is null then
    cycle_start_date := '2026-01-01';
  end if;

  WITH ranked AS (
    SELECT member_id, COALESCE(SUM(points), 0) as total_pts,
           ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(points), 0) DESC) as pos
    FROM public.gamification_points
    GROUP BY member_id
  )
  SELECT pos, (SELECT COUNT(DISTINCT member_id) FROM public.gamification_points)
  INTO v_rank, v_total
  FROM ranked WHERE member_id = p_member_id;

  select json_build_object(
    'lifetime_points', coalesce(sum(points), 0)::int,
    'cycle_points', coalesce(sum(points) filter (where created_at >= cycle_start_date), 0)::int,
    'cycle_attendance', coalesce(sum(points) filter (where category = 'attendance' and created_at >= cycle_start_date), 0)::int,
    'cycle_learning', coalesce(sum(points) filter (where category in ('trail', 'course', 'knowledge_ai_pm') and created_at >= cycle_start_date), 0)::int,
    'cycle_certs', coalesce(sum(points) filter (where category in ('cert_pmi_senior', 'cert_cpmai', 'cert_pmi_mid', 'cert_pmi_practitioner', 'cert_pmi_entry') and created_at >= cycle_start_date), 0)::int,
    'cycle_courses', coalesce(sum(points) filter (where category in ('trail', 'course', 'knowledge_ai_pm') and created_at >= cycle_start_date), 0)::int,
    'cycle_artifacts', coalesce(sum(points) filter (where category = 'artifact' and created_at >= cycle_start_date), 0)::int,
    'cycle_showcase', coalesce(sum(points) filter (where category = 'showcase' and created_at >= cycle_start_date), 0)::int,
    'cycle_bonus', coalesce(sum(points) filter (where category not in ('attendance','trail','course','knowledge_ai_pm','cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry','artifact','badge','specialization','showcase') and created_at >= cycle_start_date), 0)::int,
    'cycle_code', (select cycle_code from public.cycles where is_current = true limit 1),
    'cycle_label', (select cycle_label from public.cycles where is_current = true limit 1),
    'rank_position', coalesce(v_rank, 0),
    'total_ranked', coalesce(v_total, 0)
  ) into result
  from public.gamification_points
  where member_id = p_member_id;

  return coalesce(result, '{}');
end;
$function$
;

-- ============================================================
-- get_my_member_record((no args))
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_my_member_record()
 RETURNS TABLE(id uuid, tribe_id integer, operational_role text, is_superadmin boolean, designations text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    m.id,
    public.get_member_tribe(m.id) AS tribe_id,
    m.operational_role,
    m.is_superadmin,
    m.designations
  FROM public.members m
  WHERE m.auth_id = auth.uid()
     OR auth.uid() = ANY(COALESCE(m.secondary_auth_ids, '{}'))
  LIMIT 1;
$function$
;

-- ============================================================
-- get_selection_dashboard(p_cycle_code text)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_selection_dashboard(p_cycle_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_result jsonb;
  v_stats_a jsonb;
  v_stats_b jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM public.selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    SELECT id INTO v_cycle_id FROM public.selection_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found', 'cycle', null, 'applications', '[]'::jsonb, 'stats', jsonb_build_object('total', 0));
  END IF;

  v_stats_a := jsonb_build_object(
    'total', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id),
    'approved', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('approved', 'converted')),
    'rejected', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('rejected', 'objective_cutoff')),
    'pending', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('submitted', 'screening', 'objective_eval', 'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval')),
    'cancelled', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('cancelled', 'withdrawn')),
    'waitlist', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status = 'waitlist'),
    'leader_ranked', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND rank_leader IS NOT NULL),
    'researcher_ranked', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND rank_researcher IS NOT NULL),
    'ai_analysis_done_count', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_at IS NOT NULL AND ai_analysis IS NOT NULL),
    'consent_ai_pending', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_at IS NULL),
    'consent_ai_consented', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_at IS NOT NULL AND consent_ai_analysis_revoked_at IS NULL),
    'consent_ai_revoked', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_revoked_at IS NOT NULL)
  );

  v_stats_b := jsonb_build_object(
    'with_peer_evals_2plus', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND (SELECT count(DISTINCT e.evaluator_id) FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluation_type = 'objective' AND e.submitted_at IS NOT NULL) >= 2),
    'with_interview_scheduled', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id AND si.status IN ('scheduled','completed','rescheduled'))),
    'with_interview_today', (
      SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id
        AND EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id
          AND si.status = 'scheduled'
          AND (si.scheduled_at AT TIME ZONE 'America/Sao_Paulo')::date = (now() AT TIME ZONE 'America/Sao_Paulo')::date)
    ),
    'with_video_uploaded', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded','transcribing','transcribed'))),
    'with_video_opted_out', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id) AND NOT EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded','transcribing','transcribed'))),
    'with_pmi_member_active', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND pmi_id IS NOT NULL AND pmi_id <> '' AND service_latest_end_date >= CURRENT_DATE),
    'with_chapter_canonical', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND service_history_chapters IS NOT NULL AND service_history_chapters <> '' AND service_history_chapters <> 'PMI Global'),
    'with_re_applicants', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND COALESCE(application_count, 1) > 1),
    'with_briefing_generated', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND last_briefing_at IS NOT NULL),
    'shadow_vep_count', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.cycle_id = v_cycle_id
        AND a.status IN ('approved', 'converted', 'cancelled', 'rejected', 'withdrawn')
        AND EXISTS (
          SELECT 1 FROM public.members m
          WHERE m.is_active = true
            AND lower(m.email) = lower(a.email)
            AND m.created_at < a.created_at
        )
    ),
    'my_evals_submitted', (SELECT count(*) FROM public.selection_evaluations e JOIN public.selection_applications a ON a.id = e.application_id WHERE a.cycle_id = v_cycle_id AND e.evaluator_id = v_caller_id AND e.submitted_at IS NOT NULL),
    'my_evals_pending', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.notifications n WHERE n.type = 'peer_review_requested' AND n.source_id = a.id AND n.recipient_id = v_caller_id) AND NOT EXISTS (SELECT 1 FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id))
  );

  SELECT jsonb_build_object(
    'cycle', (SELECT jsonb_build_object(
      'id', c.id, 'cycle_code', c.cycle_code, 'title', c.title, 'status', c.status,
      'interview_booking_url', c.interview_booking_url,
      'interview_questions', COALESCE(c.interview_questions, '[]'::jsonb),
      'pert_cutoff', (SELECT jsonb_build_object(
        'target_score', MAX(pert_target_score),
        'band_lower', MAX(pert_band_lower),
        'band_upper', MAX(pert_band_upper),
        'cohort_n', MAX(pert_cohort_n),
        'method', MAX(pert_cutoff_method),
        'calc_at', MAX(pert_calc_at),
        'apps_with_pert', COUNT(*) FILTER (WHERE pert_target_score IS NOT NULL),
        'apps_total', COUNT(*)
      ) FROM public.selection_applications WHERE cycle_id = v_cycle_id)
    ) FROM public.selection_cycles c WHERE c.id = v_cycle_id),
    'applications', COALESCE((
      SELECT jsonb_agg(
        -- p197d A hotfix2: application row built as 2 jsonb_build_object chunks
        -- merged via || to dodge PG 100-arg cap (~53 fields × 2 args = 106 args).
        jsonb_build_object(
          'id', a.id, 'applicant_name', a.applicant_name, 'email', a.email,
          'phone', a.phone,
          'role_applied', a.role_applied, 'chapter', a.chapter, 'status', a.status,
          'objective_score', a.objective_score_avg, 'final_score', a.final_score,
          'research_score', a.research_score, 'leader_score', a.leader_score,
          'rank_researcher', a.rank_researcher, 'rank_leader', a.rank_leader,
          'promotion_path', a.promotion_path, 'linked_application_id', a.linked_application_id,
          'rank_chapter', a.rank_chapter, 'rank_overall', a.rank_overall,
          'linkedin_url', a.linkedin_url, 'resume_url', a.resume_url,
          'resume_storage_path', a.resume_storage_path,
          'resume_synced_at', a.resume_synced_at,
          'tags', a.tags, 'feedback', a.feedback,
          'motivation', a.motivation_letter, 'experience_years', a.seniority_years,
          'membership_status', a.membership_status, 'certifications', a.certifications,
          'is_returning_member', a.is_returning_member, 'application_date', a.application_date,
          'academic_background', a.academic_background, 'areas_of_interest', a.areas_of_interest,
          'availability_declared', a.availability_declared, 'non_pmi_experience', a.non_pmi_experience,
          'proposed_theme', a.proposed_theme, 'leadership_experience', a.leadership_experience,
          'created_at', a.created_at, 'interview_status', a.interview_status,
          'interview_reschedule_reason', a.interview_reschedule_reason,
          'interview_reschedule_requested_at', a.interview_reschedule_requested_at,
          'consent_ai_status', CASE
            WHEN a.consent_ai_analysis_revoked_at IS NOT NULL THEN 'revoked'
            WHEN a.consent_ai_analysis_at IS NOT NULL THEN 'consented'
            ELSE 'pending'
          END,
          'consent_ai_at', a.consent_ai_analysis_at,
          'consent_ai_revoked_at', a.consent_ai_analysis_revoked_at,
          'member_credly_url', (SELECT m.credly_url FROM public.members m WHERE lower(m.email) = lower(a.email) LIMIT 1),
          'member_photo_url', (SELECT m.photo_url FROM public.members m WHERE lower(m.email) = lower(a.email) LIMIT 1)
        ) || jsonb_build_object(
          'peer_eval_count', (
            SELECT count(*)::int FROM public.selection_evaluations e
            WHERE e.application_id = a.id AND e.evaluation_type = 'objective' AND e.submitted_at IS NOT NULL
          ),
          'peer_extra', jsonb_build_object(
            'distinct_evaluators', (
              SELECT count(DISTINCT e.evaluator_id)::int FROM public.selection_evaluations e
              WHERE e.application_id = a.id AND e.evaluation_type = 'objective' AND e.submitted_at IS NOT NULL
            ),
            'invites_pending', (
              SELECT count(*)::int FROM public.notifications n
              WHERE n.type = 'peer_review_requested' AND n.source_id = a.id
                AND NOT EXISTS (SELECT 1 FROM public.selection_evaluations e2 WHERE e2.application_id = a.id AND e2.evaluator_id = n.recipient_id)
            )
          ),
          'meta', jsonb_build_object(
            'ai_analysis_done', (a.consent_ai_analysis_at IS NOT NULL AND a.ai_analysis IS NOT NULL),
            'interview_scheduled', EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id AND si.status IN ('scheduled', 'completed', 'rescheduled')),
            'interview_next_at', (
              SELECT MIN(si.scheduled_at) FROM public.selection_interviews si
              WHERE si.application_id = a.id
                AND si.status = 'scheduled'
                AND si.scheduled_at >= now() - interval '12 hours'
            ),
            'has_interview_today', EXISTS (
              SELECT 1 FROM public.selection_interviews si
              WHERE si.application_id = a.id
                AND si.status = 'scheduled'
                AND (si.scheduled_at AT TIME ZONE 'America/Sao_Paulo')::date = (now() AT TIME ZONE 'America/Sao_Paulo')::date
            ),
            'token_consumed', EXISTS (SELECT 1 FROM public.onboarding_tokens t WHERE t.source_id = a.id AND t.source_type = 'pmi_application' AND COALESCE(t.access_count, 0) > 0),
            'video_screening_done', EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded', 'transcribing', 'transcribed', 'opted_out'))
          ),
          'video_agg', jsonb_build_object(
            'status_agg', (SELECT CASE WHEN count(*) = 0 THEN 'none' WHEN count(*) FILTER (WHERE v.status IN ('uploaded','transcribing','transcribed')) > 0 THEN 'uploaded' WHEN count(*) FILTER (WHERE v.status = 'opted_out') = count(*) THEN 'opted_out' ELSE 'partial' END FROM public.pmi_video_screenings v WHERE v.application_id = a.id),
            'uploaded_count', (SELECT count(*)::int FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded','transcribing','transcribed')),
            'total_rows', (SELECT count(*)::int FROM public.pmi_video_screenings v WHERE v.application_id = a.id)
          ),
          'pmi_canonical', jsonb_build_object(
            'chapter_canonical', (
              SELECT trim(c) FROM unnest(string_to_array(COALESCE(a.service_history_chapters, ''), ';')) AS c
              WHERE trim(c) <> '' AND trim(c) <> 'PMI Global' LIMIT 1
            ),
            'is_pmi_member', (a.pmi_id IS NOT NULL AND a.pmi_id <> ''),
            'member_status', CASE
              WHEN a.pmi_id IS NULL OR a.pmi_id = '' THEN 'unknown'
              WHEN a.service_latest_end_date IS NULL THEN 'unknown'
              WHEN a.service_latest_end_date >= CURRENT_DATE THEN 'active'
              ELSE 'past'
            END,
            'member_since', a.service_first_start_date,
            'member_until', a.service_latest_end_date,
            'service_history_count', COALESCE(a.service_history_count, 0),
            'phase_b_fetched_at', a.pmi_data_fetched_at,
            'pmi_id', a.pmi_id
          ),
          'extra_flags', jsonb_build_object(
            'application_count', COALESCE(a.application_count, 1),
            'has_briefing', (a.last_briefing_at IS NOT NULL),
            'briefing_at', a.last_briefing_at,
            'briefing_model', a.last_briefing_model,
            'ai_triage_score', a.ai_triage_score,
            'ai_triage_confidence', a.ai_triage_confidence,
            'is_shadow_vep', (
              a.status IN ('approved', 'converted', 'cancelled', 'rejected', 'withdrawn')
              AND EXISTS (
                SELECT 1 FROM public.members m
                WHERE m.is_active = true
                  AND lower(m.email) = lower(a.email)
                  AND m.created_at < a.created_at
              )
            ),
            'pdf_likely_invalid', EXISTS (
              SELECT 1 FROM storage.objects so
              WHERE so.bucket_id = 'selection-resumes'
                AND so.name = a.resume_storage_path
                AND (so.metadata->>'size')::int < 1000
            )
          ),
          'vep_recon', jsonb_build_object(
            'status_raw', a.vep_status_raw,
            'last_seen_at', a.vep_last_seen_at,
            'reconciled_at', a.vep_reconciled_at
          ),
          'my_eval_status', COALESCE(
            (SELECT CASE WHEN e.submitted_at IS NOT NULL THEN 'submitted' ELSE 'draft' END
              FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id LIMIT 1),
            CASE WHEN EXISTS (SELECT 1 FROM public.notifications n WHERE n.type = 'peer_review_requested' AND n.source_id = a.id AND n.recipient_id = v_caller_id) THEN 'invited' ELSE 'not_invited' END
          ),
          'my_eval_score', (SELECT e.weighted_subtotal FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id AND e.submitted_at IS NOT NULL LIMIT 1)
        )
      ORDER BY COALESCE(a.leader_score, a.research_score, a.final_score) DESC NULLS LAST)
      FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id
    ), '[]'::jsonb),
    'stats', v_stats_a || v_stats_b
  ) INTO v_result;
  RETURN v_result;
END;
$function$
;

-- ============================================================
-- get_selection_rankings(p_cycle_code text, p_track text)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_selection_rankings(p_cycle_code text DEFAULT NULL::text, p_track text DEFAULT 'both'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_pert_cutoff jsonb;
  v_researcher jsonb;
  v_leader jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: admin/GP/curator only');
  END IF;

  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM public.selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    SELECT id INTO v_cycle_id FROM public.selection_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found');
  END IF;

  -- p197c B2: pert_cutoff aggregated from selection_applications (same per cycle)
  SELECT jsonb_build_object(
    'target_score', MAX(pert_target_score),
    'band_lower', MAX(pert_band_lower),
    'band_upper', MAX(pert_band_upper),
    'cohort_n', MAX(pert_cohort_n),
    'method', MAX(pert_cutoff_method),
    'calc_at', MAX(pert_calc_at)
  ) INTO v_pert_cutoff
  FROM public.selection_applications WHERE cycle_id = v_cycle_id;

  IF p_track IN ('researcher', 'both') THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rank', rank_researcher,
      'applicant_name', applicant_name,
      'chapter', chapter,
      'research_score', research_score,
      'status', status,
      'promotion_path', promotion_path,
      -- p197c B2: band_position helps UI/MCP color-code each row
      'pert_band_position', CASE
        WHEN research_score IS NULL OR pert_band_lower IS NULL OR pert_band_upper IS NULL THEN NULL
        WHEN research_score < pert_band_lower THEN 'below'
        WHEN research_score > pert_band_upper THEN 'above'
        ELSE 'within'
      END
    ) ORDER BY rank_researcher), '[]'::jsonb)
    INTO v_researcher
    FROM public.selection_applications
    WHERE cycle_id = v_cycle_id AND rank_researcher IS NOT NULL;
  END IF;

  IF p_track IN ('leader', 'both') THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rank', rank_leader,
      'applicant_name', applicant_name,
      'chapter', chapter,
      'research_score', research_score,
      'leader_score', leader_score,
      'status', status,
      'promotion_path', promotion_path,
      'pert_band_position', CASE
        WHEN leader_score IS NULL OR pert_band_lower IS NULL OR pert_band_upper IS NULL THEN NULL
        WHEN leader_score < pert_band_lower THEN 'below'
        WHEN leader_score > pert_band_upper THEN 'above'
        ELSE 'within'
      END
    ) ORDER BY rank_leader), '[]'::jsonb)
    INTO v_leader
    FROM public.selection_applications
    WHERE cycle_id = v_cycle_id AND rank_leader IS NOT NULL;
  END IF;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'track', p_track,
    'pert_cutoff', v_pert_cutoff,
    'researcher_track', COALESCE(v_researcher, '[]'::jsonb),
    'leader_track', COALESCE(v_leader, '[]'::jsonb),
    'formula', jsonb_build_object(
      'research_score', 'objective_pert + interview_pert',
      'leader_score', 'research_score * 0.7 + leader_extra_pert * 0.3',
      'tiebreaker', 'Standard Competition Ranking (ISO 80000-2) + applicant_name ASC'
    )
  );
END;
$function$
;

-- ============================================================
-- get_tribe_attendance_grid(p_tribe_id integer, p_event_type text)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_tribe_attendance_grid(p_tribe_id integer, p_event_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member_id uuid;
  v_caller_tribe_id integer;
  v_is_admin boolean;
  v_is_stakeholder boolean;
  v_cycle_start date;
  v_tribe_initiative_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  v_caller_tribe_id := public.get_member_tribe(v_member_id);

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  v_is_stakeholder := public.can_by_member(v_member_id, 'manage_partner');

  IF NOT v_is_admin AND NOT v_is_stakeholder
     AND COALESCE(v_caller_tribe_id, -1) <> p_tribe_id THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM public.cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  SELECT id INTO v_tribe_initiative_id
  FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id AND kind = 'research_tribe'
  LIMIT 1;

  WITH
  raw_events AS (
    SELECT e.id, e.date, e.title, e.title_i18n, e.type, e.status, i.legacy_tribe_id AS tribe_id,
           i.title AS tribe_name,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date)::int AS week_number,
           EXTRACT(ISOYEAR FROM e.date)::int AS iso_year,
           EXTRACT(WEEK FROM e.date)::int AS iso_week
    FROM public.events e LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_cycle_start
      AND (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff') OR e.type = 'lideranca')
      AND (p_event_type IS NULL OR e.type = p_event_type)
      AND (e.initiative_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
  ),
  cancelled_with_replan AS (
    SELECT re_cancelled.id AS cancelled_event_id
    FROM raw_events re_cancelled
    WHERE re_cancelled.status = 'cancelled'
      AND re_cancelled.tribe_id = p_tribe_id
      AND EXISTS (
        SELECT 1 FROM raw_events re_sibling
        WHERE re_sibling.id <> re_cancelled.id
          AND re_sibling.tribe_id = p_tribe_id
          AND re_sibling.status = 'scheduled'
          AND re_sibling.iso_year = re_cancelled.iso_year
          AND re_sibling.iso_week = re_cancelled.iso_week
      )
  ),
  grid_events AS (
    SELECT re.id, re.date, re.title, re.title_i18n, re.type, re.status, re.tribe_id,
           re.tribe_name, re.duration_minutes, re.week_number
    FROM raw_events re
    LEFT JOIN cancelled_with_replan cr ON cr.cancelled_event_id = re.id
    WHERE cr.cancelled_event_id IS NULL
    ORDER BY re.date
  ),
  event_row_counts AS (
    SELECT a.event_id, COUNT(*) AS row_count
    FROM public.attendance a
    WHERE a.event_id IN (SELECT id FROM grid_events)
    GROUP BY a.event_id
  ),
  grid_members AS (
    SELECT m.id, m.name,
           public.get_member_tribe(m.id) AS tribe_id,
           m.chapter, m.operational_role, m.designations, m.member_status
    FROM public.members m
    WHERE m.member_status = 'active'
      AND (
        EXISTS (
          SELECT 1 FROM public.engagements e
          WHERE e.person_id = m.person_id
            AND e.kind = 'volunteer' AND e.status = 'active'
            AND e.initiative_id = v_tribe_initiative_id
        )
        OR m.initiative_id = v_tribe_initiative_id
      )
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none')
    UNION
    SELECT DISTINCT m.id, m.name,
           public.get_member_tribe(m.id) AS tribe_id,
           m.chapter, m.operational_role, m.designations, m.member_status
    FROM public.members m
    JOIN public.attendance a ON a.member_id = m.id
    JOIN grid_events ge ON ge.id = a.event_id
    WHERE m.member_status IN ('observer', 'alumni', 'inactive')
      AND ge.tribe_id = p_tribe_id
  ),
  eligibility AS (
    SELECT m.id AS member_id, ge.id AS event_id,
      CASE
        WHEN ge.type IN ('geral', 'kickoff') THEN true
        WHEN ge.type = 'tribo' AND ge.tribe_id = p_tribe_id THEN true
        WHEN ge.type = 'lideranca' AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader') THEN true
        ELSE false
      END AS is_eligible
    FROM grid_members m CROSS JOIN grid_events ge
  ),
  cell_status AS (
    SELECT el.member_id, el.event_id, el.is_eligible,
      CASE
        WHEN ge.status = 'cancelled' THEN 'na'
        WHEN NOT el.is_eligible THEN 'na'
        WHEN ge.date > CURRENT_DATE THEN CASE WHEN gm.member_status != 'active' THEN 'na' ELSE 'scheduled' END
        WHEN a.id IS NOT NULL AND a.excused = true THEN 'excused'
        WHEN a.id IS NOT NULL AND a.present = true THEN 'present'
        WHEN a.id IS NOT NULL AND a.present = false THEN 'absent'
        ELSE CASE
          WHEN gm.member_status != 'active' AND (gm.offboarded_at IS NULL OR gm.offboarded_at::date > ge.date) THEN 'absent'
          WHEN gm.member_status != 'active' AND gm.offboarded_at IS NOT NULL AND gm.offboarded_at::date <= ge.date THEN 'na'
          ELSE 'absent' END
      END AS status
    FROM eligibility el JOIN grid_events ge ON ge.id = el.event_id
    JOIN (SELECT id, member_status, offboarded_at FROM public.members) gm ON gm.id = el.member_id
    LEFT JOIN public.attendance a ON a.member_id = el.member_id AND a.event_id = el.event_id
    LEFT JOIN event_row_counts erc ON erc.event_id = ge.id
  ),
  member_stats AS (
    SELECT cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      ROUND(COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent')), 0), 2) AS rate,
      ROUND(SUM(CASE WHEN cs.status = 'present' THEN ge.duration_minutes ELSE 0 END)::numeric / 60, 1) AS hours
    FROM cell_status cs JOIN grid_events ge ON ge.id = cs.event_id GROUP BY cs.member_id
  ),
  detractor_calc AS (
    SELECT cs.member_id,
      (SELECT COUNT(*) FROM (
        SELECT cs2.status AS cell_status, ROW_NUMBER() OVER (ORDER BY ge2.date DESC) AS rn
        FROM cell_status cs2 JOIN grid_events ge2 ON ge2.id = cs2.event_id
        WHERE cs2.member_id = cs.member_id AND cs2.status IN ('present', 'absent')
        ORDER BY ge2.date DESC
      ) sub WHERE sub.cell_status = 'absent' AND sub.rn <= COALESCE((
        SELECT MIN(rn2) FROM (
          SELECT cs3.status AS cell_status, ROW_NUMBER() OVER (ORDER BY ge3.date DESC) AS rn2
          FROM cell_status cs3 JOIN grid_events ge3 ON ge3.id = cs3.event_id
          WHERE cs3.member_id = cs.member_id AND cs3.status IN ('present', 'absent')
          ORDER BY ge3.date DESC
        ) sub2 WHERE sub2.cell_status = 'present'), 999)) AS consecutive_absences
    FROM cell_status cs GROUP BY cs.member_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT COUNT(DISTINCT id) FROM grid_members WHERE member_status = 'active'),
      'overall_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
      'perfect_attendance', (SELECT COUNT(*) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active' AND ms.rate >= 1.0),
      'below_50', (SELECT COUNT(*) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active' AND ms.rate < 0.5 AND ms.rate > 0),
      'total_events', (SELECT COUNT(*) FROM grid_events),
      'past_events', (SELECT COUNT(*) FROM grid_events WHERE date <= CURRENT_DATE),
      'cancelled_events', (SELECT COUNT(*) FROM grid_events ge_c WHERE ge_c.status = 'cancelled'),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0),
      'detractors_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN grid_members gm ON gm.id = dc.member_id WHERE gm.member_status = 'active' AND dc.consecutive_absences >= 3),
      'at_risk_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN grid_members gm ON gm.id = dc.member_id WHERE gm.member_status = 'active' AND dc.consecutive_absences = 2)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'title_i18n', ge.title_i18n, 'type', ge.type,
      'status', ge.status,
      'tribe_id', ge.tribe_id, 'tribe_name', ge.tribe_name,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_tribe_event', (ge.tribe_id = p_tribe_id), 'is_future', (ge.date > CURRENT_DATE),
      'is_cancelled', (ge.status = 'cancelled')
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'members', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', am.id, 'name', am.name, 'chapter', am.chapter, 'member_status', am.member_status,
      'rate', COALESCE(ms.rate, 0), 'hours', COALESCE(ms.hours, 0),
      'eligible_count', COALESCE(ms.eligible_count, 0), 'present_count', COALESCE(ms.present_count, 0),
      'detractor_status', CASE
        WHEN am.member_status != 'active' THEN 'inactive'
        WHEN COALESCE(dc.consecutive_absences, 0) >= 3 THEN 'detractor'
        WHEN COALESCE(dc.consecutive_absences, 0) = 2 THEN 'at_risk'
        ELSE 'regular' END,
      'consecutive_absences', COALESCE(dc.consecutive_absences, 0),
      'attendance', (SELECT COALESCE(jsonb_object_agg(cs.event_id::text, cs.status), '{}'::jsonb)
        FROM cell_status cs WHERE cs.member_id = am.id)
    ) ORDER BY CASE WHEN am.member_status = 'active' THEN 0 ELSE 1 END, COALESCE(ms.rate, 0) ASC), '[]'::jsonb)
      FROM grid_members am
      LEFT JOIN member_stats ms ON ms.member_id = am.id
      LEFT JOIN detractor_calc dc ON dc.member_id = am.id)
  ) INTO v_result;
  RETURN v_result;
END;
$function$
;

-- ============================================================
-- get_tribe_event_roster(p_event_id uuid)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_tribe_event_roster(p_event_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller RECORD;
  v_event  RECORD;
  v_event_tribe_id int;
  v_result JSON;
  v_has_attendance boolean;
  v_event_cancelled boolean;
BEGIN
  SELECT m.* INTO v_caller
  FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;

  v_event_tribe_id := public.resolve_tribe_id(v_event.initiative_id);
  v_event_cancelled := (v_event.status = 'cancelled');

  -- Access control: V4 baseline manage_event + residual tribe scope for tribe_leader
  IF NOT public.can_by_member(v_caller.id, 'manage_event') THEN
    RETURN json_build_object('error', 'Access denied');
  END IF;
  IF v_caller.operational_role = 'tribe_leader'
     AND v_event_tribe_id IS NOT NULL
     AND v_event_tribe_id IS DISTINCT FROM v_caller.tribe_id THEN
    RETURN json_build_object('error', 'Access denied');
  END IF;

  SELECT EXISTS(SELECT 1 FROM attendance WHERE event_id = p_event_id) INTO v_has_attendance;

  SELECT json_agg(row_to_json(q) ORDER BY q.name) INTO v_result
  FROM (
    SELECT
      m.id, m.name, m.photo_url, m.operational_role, m.designations,
      compute_legacy_role(m.operational_role, m.designations) AS role,
      compute_legacy_roles(m.operational_role, m.designations) AS roles,
      m.chapter,
      COALESCE(a.present, false) AS present,
      a.corrected_by IS NOT NULL AS was_corrected,
      v_event_cancelled AS event_cancelled
    FROM public.members m
    LEFT JOIN public.attendance a
      ON a.event_id = p_event_id AND a.member_id = m.id
    WHERE
      m.operational_role != 'guest'
      AND (
        CASE WHEN v_event.initiative_id IS NOT NULL AND v_event_tribe_id IS NULL THEN
          m.id IN (
            SELECT mm.id FROM members mm
            JOIN engagements eng ON eng.person_id = mm.person_id
            WHERE eng.initiative_id = v_event.initiative_id AND eng.status = 'active'
          )
          OR a.id IS NOT NULL

        WHEN v_event.type IN ('1on1', 'entrevista', 'parceria') AND v_has_attendance THEN
          a.id IS NOT NULL

        ELSE
          CASE COALESCE(v_event.audience_level, 'all')
            WHEN 'tribe' THEN
              m.current_cycle_active = true
              AND m.tribe_id = v_event_tribe_id
            WHEN 'leadership' THEN
              m.operational_role IN ('manager')
              OR 'sponsor'    = ANY(COALESCE(m.designations, '{}'))
              OR 'ambassador' = ANY(COALESCE(m.designations, '{}'))
              OR 'founder'    = ANY(COALESCE(m.designations, '{}'))
              OR 'co_gp'      = ANY(COALESCE(m.designations, '{}'))
            WHEN 'curators' THEN
              'curator' = ANY(COALESCE(m.designations, '{}'))
            ELSE
              m.current_cycle_active = true
              OR m.operational_role = 'manager'
              OR 'sponsor'    = ANY(COALESCE(m.designations, '{}'))
              OR 'ambassador' = ANY(COALESCE(m.designations, '{}'))
              OR 'curator'    = ANY(COALESCE(m.designations, '{}'))
              OR 'co_gp'      = ANY(COALESCE(m.designations, '{}'))
          END
        END
      )
  ) q;

  RETURN COALESCE(v_result, '[]'::json);
END;
$function$
;

-- ============================================================
-- list_ai_suggestions(p_application_id uuid, p_evaluation_type text, p_only_pending boolean)
-- ============================================================
CREATE OR REPLACE FUNCTION public.list_ai_suggestions(p_application_id uuid, p_evaluation_type text DEFAULT NULL::text, p_only_pending boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_app record;
  v_is_committee boolean;
  v_can_admin boolean;
  v_results jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT id, cycle_id INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error', 'application_not_found');
  END IF;

  v_is_committee := EXISTS (
    SELECT 1 FROM public.selection_committee
    WHERE cycle_id = v_app.cycle_id AND member_id = v_caller_id
  );
  v_can_admin := public.can_by_member(v_caller_id, 'manage_member');
  IF NOT (v_is_committee OR v_can_admin) THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'committee or manage_member');
  END IF;

  -- Light audit log (this surface exposes AI inputs — track access)
  PERFORM public._log_application_pii_access(
    p_application_id, v_caller_id,
    ARRAY['ai_suggestions'],
    'list_ai_suggestions:' || COALESCE(p_evaluation_type, 'all')
  );

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'evaluation_type', s.evaluation_type,
    'suggested_scores', s.suggested_scores,
    'suggested_criterion_notes', s.suggested_criterion_notes,
    'suggested_weighted_subtotal', s.suggested_weighted_subtotal,
    'suggested_overall_summary', s.suggested_overall_summary,
    'model_provider', s.model_provider,
    'model_name', s.model_name,
    'prompt_version', s.prompt_version,
    'generation_cost_usd', s.generation_cost_usd,
    'generation_latency_ms', s.generation_latency_ms,
    'used_in_evaluation_id', s.used_in_evaluation_id,
    'superseded_by', s.superseded_by,
    'generated_at', s.generated_at,
    'consumed_at', s.consumed_at,
    'is_pending', (s.used_in_evaluation_id IS NULL AND s.superseded_by IS NULL)
  ) ORDER BY s.generated_at DESC), '[]'::jsonb)
  INTO v_results
  FROM public.selection_evaluation_ai_suggestions s
  WHERE s.application_id = p_application_id
    AND (p_evaluation_type IS NULL OR s.evaluation_type = p_evaluation_type)
    AND (NOT p_only_pending OR (s.used_in_evaluation_id IS NULL AND s.superseded_by IS NULL));

  RETURN jsonb_build_object(
    'application_id', p_application_id,
    'evaluation_type_filter', p_evaluation_type,
    'only_pending', p_only_pending,
    'count', jsonb_array_length(v_results),
    'suggestions', v_results
  );
END;
$function$
;

-- ============================================================
-- manage_initiative_engagement(p_initiative_id uuid, p_person_id uuid, p_kind text, p_role text, p_action text)
-- ============================================================
CREATE OR REPLACE FUNCTION public.manage_initiative_engagement(p_initiative_id uuid, p_person_id uuid, p_kind text, p_role text, p_action text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_person_id uuid; v_initiative record; v_engagement record;
  v_org_id uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
  v_is_admin boolean; v_is_owner_of_initiative boolean; v_kind_allows_owner boolean;
BEGIN
  SELECT p.id INTO v_caller_person_id FROM persons p WHERE p.auth_id = auth.uid();
  IF v_caller_person_id IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  v_is_admin := can(v_caller_person_id, 'manage_member', 'initiative', p_initiative_id);
  IF NOT v_is_admin THEN
    v_is_owner_of_initiative := EXISTS (SELECT 1 FROM engagements e WHERE e.person_id = v_caller_person_id AND e.initiative_id = p_initiative_id AND e.status = 'active' AND (e.kind LIKE '%_owner' OR e.kind LIKE '%_coordinator' OR e.role IN ('owner','coordinator','lead')));
    v_kind_allows_owner := EXISTS (SELECT 1 FROM engagement_kinds ek WHERE ek.slug = p_kind AND ('owner' = ANY(ek.created_by_role) OR 'coordinator' = ANY(ek.created_by_role)));
    IF NOT (v_is_owner_of_initiative AND v_kind_allows_owner) THEN
      RETURN jsonb_build_object('error', 'Unauthorized', 'hint', CASE WHEN NOT v_is_owner_of_initiative THEN 'Caller is not active owner/coordinator of initiative' ELSE 'Engagement kind does not allow owner as creator' END);
    END IF;
  END IF;
  SELECT i.id, i.kind, i.status INTO v_initiative FROM initiatives i WHERE i.id = p_initiative_id;
  IF v_initiative IS NULL THEN RETURN jsonb_build_object('error', 'Initiative not found'); END IF;
  IF v_initiative.status NOT IN ('active', 'draft') THEN RETURN jsonb_build_object('error', 'Initiative is not active'); END IF;

  IF p_action = 'add' THEN
    IF NOT EXISTS (SELECT 1 FROM engagement_kinds ek WHERE ek.slug = p_kind AND v_initiative.kind = ANY(ek.initiative_kinds_allowed)) THEN
      RETURN jsonb_build_object('error', format('Engagement kind "%s" not allowed for initiative kind "%s"', p_kind, v_initiative.kind));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM persons WHERE id = p_person_id) THEN RETURN jsonb_build_object('error', 'Person not found'); END IF;
    IF EXISTS (SELECT 1 FROM engagements e WHERE e.person_id = p_person_id AND e.initiative_id = p_initiative_id AND e.status = 'active') THEN
      RETURN jsonb_build_object('error', 'Person already has active engagement in this initiative');
    END IF;
    INSERT INTO engagements (person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id)
    VALUES (p_person_id, p_initiative_id, p_kind, p_role, 'active', 'consent', v_caller_person_id,
      jsonb_build_object('source', 'manage_initiative_engagement', 'added_by', v_caller_person_id::text, 'invoked_as', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END), v_org_id)
    RETURNING * INTO v_engagement;
    RETURN jsonb_build_object('ok', true, 'action', 'added', 'engagement_id', v_engagement.id, 'authorized_as', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END);
  ELSIF p_action = 'remove' THEN
    UPDATE engagements SET status = 'expired', revoked_at = now(), revoked_by = v_caller_person_id, revoke_reason = 'Removed via manage_initiative_engagement', updated_at = now()
    WHERE person_id = p_person_id AND initiative_id = p_initiative_id AND status = 'active' RETURNING * INTO v_engagement;
    IF v_engagement IS NULL THEN RETURN jsonb_build_object('error', 'No active engagement found for this person'); END IF;
    RETURN jsonb_build_object('ok', true, 'action', 'removed', 'engagement_id', v_engagement.id);
  ELSIF p_action = 'update_role' THEN
    UPDATE engagements SET role = p_role, updated_at = now()
    WHERE person_id = p_person_id AND initiative_id = p_initiative_id AND status = 'active' RETURNING * INTO v_engagement;
    IF v_engagement IS NULL THEN RETURN jsonb_build_object('error', 'No active engagement found for this person'); END IF;
    RETURN jsonb_build_object('ok', true, 'action', 'role_updated', 'engagement_id', v_engagement.id, 'new_role', p_role);
  ELSE RETURN jsonb_build_object('error', format('Unknown action: %s', p_action));
  END IF;
END;
$function$
;

-- ============================================================
-- mark_member_present(p_event_id uuid, p_member_id uuid, p_present boolean)
-- ============================================================
CREATE OR REPLACE FUNCTION public.mark_member_present(p_event_id uuid, p_member_id uuid, p_present boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF v_caller_id = p_member_id THEN
    NULL;
  ELSIF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: can only mark own presence or requires manage_event permission';
  END IF;

  IF p_present THEN
    INSERT INTO public.attendance (event_id, member_id, present, excused)
    VALUES (p_event_id, p_member_id, true, false)
    ON CONFLICT (event_id, member_id) DO UPDATE SET
      present = true, excused = false, updated_at = now();
  ELSE
    -- p199-c (2026-05-19): p_present=false now DELETEs the attendance row
    -- (was UPSERT present=false). Aligns with admin_bulk_mark_attendance
    -- semantic where "tirar presenca" removes the registro.
    -- Edge case: rows previously marked as excused=true lose that flag on
    -- DELETE -- if dedicated excused-management is needed, use
    -- mark_member_excused() instead of toggling mark_member_present.
    DELETE FROM public.attendance WHERE event_id = p_event_id AND member_id = p_member_id;
  END IF;

  RETURN json_build_object('success', true);
END;
$function$
;

-- ============================================================
-- recompute_all_active_pert_cutoffs((no args))
-- ============================================================
CREATE OR REPLACE FUNCTION public.recompute_all_active_pert_cutoffs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cycle record;
  v_results jsonb := '[]'::jsonb;
  v_n int := 0;
  v_result jsonb;
BEGIN
  FOR v_cycle IN
    SELECT id, cycle_code, phase FROM public.selection_cycles
    WHERE phase IN ('evaluating', 'interviews', 'open_apps')
    ORDER BY created_at DESC
  LOOP
    v_result := public._compute_pert_cutoff_core(v_cycle.id, 'researcher', true, 'objective_score_avg', NULL);
    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'cycle_code', v_cycle.cycle_code,
      'phase', v_cycle.phase,
      'result', v_result
    ));
    v_n := v_n + 1;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'pert_cutoff_recompute_batch', 'selection_cycles', NULL,
    jsonb_build_object('cycles_processed', v_n, 'per_cycle', v_results),
    jsonb_build_object('source', 'recompute_all_active_pert_cutoffs')
  );

  RETURN jsonb_build_object('success', true, 'cycles_processed', v_n, 'per_cycle', v_results);
END;
$function$
;

-- ============================================================
-- register_own_presence(p_event_id uuid)
-- ============================================================
CREATE OR REPLACE FUNCTION public.register_own_presence(p_event_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_event_date date;
  v_event_ts timestamptz;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT date INTO v_event_date FROM public.events WHERE id = p_event_id;
  IF v_event_date IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'event_not_found');
  END IF;

  v_event_ts := v_event_date::timestamptz;

  -- Time window check: V4 manage_event holders bypass (subsumes V3 sa/manager/deputy_manager/tribe_leader)
  IF NOT public.can_by_member(v_member_id, 'manage_event'::text) THEN
    -- 48h window (was 24h)
    IF now() > v_event_ts + interval '48 hours' THEN
      RETURN json_build_object('success', false, 'error', 'checkin_window_expired',
        'message', 'O prazo de 48h para check-in expirou. Solicite ao gestor.');
    END IF;
    IF now() < v_event_ts - interval '2 hours' THEN
      RETURN json_build_object('success', false, 'error', 'checkin_too_early',
        'message', 'O check-in abre 2h antes do evento.');
    END IF;
  END IF;

  INSERT INTO public.attendance (event_id, member_id, checked_in_at)
  VALUES (p_event_id, v_member_id, now())
  ON CONFLICT (event_id, member_id)
  DO UPDATE SET checked_in_at = now();

  RETURN json_build_object('success', true, 'member_id', v_member_id);
END;
$function$
;

-- ============================================================
-- review_change_request(p_cr_id uuid, p_action text, p_notes text)
-- ============================================================
CREATE OR REPLACE FUNCTION public.review_change_request(p_cr_id uuid, p_action text, p_notes text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller record; v_mid uuid; v_cr record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id=auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  v_mid := v_caller.id;
  SELECT * INTO v_cr FROM change_requests WHERE id=p_cr_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','CR not found'); END IF;
  -- p178 ADR-0011 inline V4 refactor: top-level authority via can_by_member(manage_platform).
  -- Covers superadmin + manager + deputy_manager + co_gp (per engagement_kind_permissions seed).
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content').
  -- sponsor/chapter_liaison legacy paths preserved as fallback; full V3→V4
  -- sweep of the change_requests action surface is deferred to a dedicated ADR-0011 batch session.
  IF NOT can_by_member(v_mid, 'manage_platform') THEN
    IF can_by_member(v_mid, 'curate_content') THEN
      IF v_cr.cr_type='structural' AND p_action='approve' THEN
        RETURN jsonb_build_object('error','Curators cannot approve structural CRs'); END IF;
    ELSIF v_caller.operational_role IN ('sponsor','chapter_liaison') THEN NULL;
    ELSE RETURN jsonb_build_object('error','Unauthorized'); END IF;
  END IF;
  IF p_action='approve' THEN
    UPDATE change_requests SET status='approved',reviewed_by=v_mid,reviewed_at=now(),
      review_notes=COALESCE(p_notes,review_notes),
      approved_by_members=array_append(COALESCE(approved_by_members,'{}'),v_mid),
      approved_at=now(),updated_at=now() WHERE id=p_cr_id;
  ELSIF p_action='reject' THEN
    UPDATE change_requests SET status='rejected',reviewed_by=v_mid,reviewed_at=now(),
      review_notes=p_notes,updated_at=now() WHERE id=p_cr_id;
  ELSIF p_action='request_changes' THEN
    UPDATE change_requests SET status='under_review',reviewed_by=v_mid,reviewed_at=now(),
      review_notes=p_notes,updated_at=now() WHERE id=p_cr_id;
  ELSIF p_action='implement' THEN
    IF v_cr.status!='approved' THEN RETURN jsonb_build_object('error','Must be approved first'); END IF;
    UPDATE change_requests SET status='implemented',implemented_by=v_mid,implemented_at=now(),
      manual_version_to='R3',updated_at=now() WHERE id=p_cr_id;
  ELSIF p_action = 'withdraw' THEN
    IF v_cr.status NOT IN ('draft', 'submitted', 'under_review') THEN
      RETURN jsonb_build_object('error', 'Cannot withdraw approved/implemented CR'); END IF;
    UPDATE change_requests SET status = 'withdrawn', review_notes = COALESCE(p_notes, review_notes), updated_at = now() WHERE id = p_cr_id;
  ELSIF p_action = 'resubmit' THEN
    IF v_cr.status != 'under_review' THEN
      RETURN jsonb_build_object('error', 'Can only resubmit CRs under review'); END IF;
    UPDATE change_requests SET status = 'submitted', submitted_at = now(), review_notes = COALESCE(p_notes, review_notes), updated_at = now() WHERE id = p_cr_id;
  ELSE RETURN jsonb_build_object('error','Invalid action'); END IF;

  IF v_cr.submitted_by IS NOT NULL AND v_cr.submitted_by != v_mid THEN
    PERFORM create_notification(v_cr.submitted_by, 'cr_status_changed', 'change_request', p_cr_id, v_cr.title, v_mid);
  END IF;

  RETURN jsonb_build_object('success',true,'cr_number',v_cr.cr_number,'new_status',p_action);
END;
$function$
;

-- ============================================================
-- sign_volunteer_agreement(p_language text, p_signed_ip text, p_signed_user_agent text)
-- ============================================================
CREATE OR REPLACE FUNCTION public.sign_volunteer_agreement(p_language text DEFAULT 'pt-BR'::text, p_signed_ip text DEFAULT NULL::text, p_signed_user_agent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record; v_template record; v_cert_id uuid; v_code text; v_hash text;
  v_content jsonb; v_cycle int; v_existing uuid; v_issuer_id uuid; v_vep record;
  v_period_start date; v_period_end date;
  v_member_role_for_vep text; v_history record; v_source text;
  v_missing_fields text[] := '{}';
  v_engagement_updated boolean := false;
  v_chapter_cnpj text; v_chapter_legal_name text;
  v_ip inet := NULL;
BEGIN
  SELECT m.id, m.name, m.email, m.operational_role, m.pmi_id, m.chapter,
    m.phone, m.address, m.city, m.state, m.country, m.birth_date,
    t.name as tribe_name
  INTO v_member
  FROM members m LEFT JOIN tribes t ON t.id = public.get_member_tribe(m.id)
  WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  IF v_member.pmi_id IS NULL OR length(trim(v_member.pmi_id)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'pmi_id');
  END IF;
  IF v_member.phone IS NULL OR length(trim(v_member.phone)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'phone');
  END IF;
  IF v_member.address IS NULL OR length(trim(v_member.address)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'address');
  END IF;
  IF v_member.city IS NULL OR length(trim(v_member.city)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'city');
  END IF;
  IF v_member.state IS NULL OR length(trim(v_member.state)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'state');
  END IF;
  IF v_member.country IS NULL OR length(trim(v_member.country)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'country');
  END IF;
  IF v_member.birth_date IS NULL THEN
    v_missing_fields := array_append(v_missing_fields, 'birth_date');
  END IF;

  IF array_length(v_missing_fields, 1) > 0 THEN
    RETURN jsonb_build_object(
      'error', 'profile_incomplete',
      'message', 'Você precisa completar seu perfil antes de assinar o Termo de Voluntariado.',
      'missing_fields', to_jsonb(v_missing_fields),
      'profile_url', '/profile'
    );
  END IF;

  SELECT cr.cnpj, cr.legal_name INTO v_chapter_cnpj, v_chapter_legal_name
  FROM chapter_registry cr
  WHERE cr.chapter_code = v_member.chapter AND cr.is_active = true;

  IF v_chapter_cnpj IS NULL THEN
    SELECT cr.cnpj, cr.legal_name INTO v_chapter_cnpj, v_chapter_legal_name
    FROM chapter_registry cr
    WHERE cr.is_contracting_chapter = true AND cr.is_active = true
    LIMIT 1;
  END IF;

  IF v_chapter_cnpj IS NULL THEN
    v_chapter_cnpj := '06.065.645/0001-99';
    v_chapter_legal_name := 'PMI Goias';
  END IF;

  v_cycle := EXTRACT(YEAR FROM now())::int;
  SELECT id INTO v_existing FROM certificates
  WHERE member_id = v_member.id AND type = 'volunteer_agreement' AND cycle = v_cycle AND status = 'issued';
  IF v_existing IS NOT NULL THEN RETURN jsonb_build_object('error', 'already_signed', 'certificate_id', v_existing); END IF;

  SELECT * INTO v_template FROM governance_documents
  WHERE doc_type = 'volunteer_term_template' AND status = 'active'
  ORDER BY created_at DESC LIMIT 1;
  IF v_template.id IS NULL THEN RETURN jsonb_build_object('error', 'template_not_found'); END IF;

  SELECT id INTO v_issuer_id FROM members
  WHERE chapter = v_member.chapter AND 'chapter_board' = ANY(designations) AND is_active = true
  ORDER BY operational_role = 'sponsor' DESC LIMIT 1;
  IF v_issuer_id IS NULL THEN
    SELECT id INTO v_issuer_id FROM members WHERE operational_role = 'manager' AND is_active = true LIMIT 1;
  END IF;

  v_member_role_for_vep := CASE
    WHEN v_member.operational_role IN ('manager', 'deputy_manager') THEN 'manager'
    WHEN v_member.operational_role = 'tribe_leader' THEN 'leader'
    ELSE 'researcher'
  END;

  SELECT vo.* INTO v_vep FROM selection_applications sa
  JOIN vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
  WHERE lower(trim(sa.email)) = lower(trim(v_member.email))
    AND vo.role_default = v_member_role_for_vep
    AND EXTRACT(YEAR FROM vo.start_date) = v_cycle
  ORDER BY sa.created_at DESC LIMIT 1;

  IF v_vep.opportunity_id IS NOT NULL THEN
    v_period_start := v_vep.start_date; v_period_end := v_vep.end_date; v_source := 'application_match';
  ELSE
    SELECT vo.* INTO v_vep FROM selection_applications sa
    JOIN vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
    WHERE lower(trim(sa.email)) = lower(trim(v_member.email))
      AND EXTRACT(YEAR FROM vo.start_date) = v_cycle
    ORDER BY sa.created_at DESC LIMIT 1;
    IF v_vep.opportunity_id IS NOT NULL THEN
      v_period_start := v_vep.start_date; v_period_end := v_vep.end_date; v_source := 'application_year_match';
    ELSE
      SELECT cycle_code, cycle_start, cycle_end INTO v_history
      FROM member_cycle_history WHERE member_id = v_member.id
      ORDER BY cycle_start DESC LIMIT 1;
      IF v_history.cycle_code IS NOT NULL THEN
        v_period_start := v_history.cycle_start;
        v_period_end := (v_history.cycle_start + interval '12 months' - interval '1 day')::date;
        v_source := 'cycle_history:' || v_history.cycle_code;
      ELSE
        SELECT * INTO v_vep FROM vep_opportunities
        WHERE EXTRACT(YEAR FROM start_date) = v_cycle
          AND role_default = v_member_role_for_vep AND is_active = true
        ORDER BY start_date DESC LIMIT 1;
        IF v_vep.opportunity_id IS NOT NULL THEN
          v_period_start := v_vep.start_date; v_period_end := v_vep.end_date; v_source := 'founder_role_vep';
        ELSE
          RETURN jsonb_build_object('error', 'cannot_derive_period',
            'message', 'No application, cycle history, or matching VEP found. Admin must set period manually.',
            'member_id', v_member.id, 'member_name', v_member.name);
        END IF;
      END IF;
    END IF;
  END IF;

  v_content := jsonb_build_object(
    'template_id', v_template.id, 'template_version', v_template.version, 'template_title', v_template.title,
    'member_name', v_member.name, 'member_email', v_member.email, 'member_role', v_member.operational_role,
    'member_tribe', v_member.tribe_name, 'member_pmi_id', v_member.pmi_id, 'member_chapter', v_member.chapter,
    'member_phone', v_member.phone, 'member_address', v_member.address,
    'member_city', v_member.city, 'member_state', v_member.state,
    'member_country', v_member.country, 'member_birth_date', v_member.birth_date,
    'language', p_language, 'signed_at', now(),
    'chapter_cnpj', v_chapter_cnpj, 'chapter_name', v_chapter_legal_name,
    'vep_opportunity_id', v_vep.opportunity_id, 'vep_title', v_vep.title,
    'period_start', v_period_start::text, 'period_end', v_period_end::text,
    'period_source', v_source
  );

  v_code := 'TERM-' || EXTRACT(YEAR FROM now())::text || '-' || UPPER(SUBSTRING(gen_random_uuid()::text FROM 1 FOR 6));
  v_hash := encode(sha256(convert_to(v_content::text || v_member.id::text || now()::text || 'nucleo-ia-volunteer-salt', 'UTF8')), 'hex');

  BEGIN
    IF p_signed_ip IS NOT NULL AND length(trim(p_signed_ip)) > 0 THEN
      v_ip := p_signed_ip::inet;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL;
  END;

  INSERT INTO certificates (
    member_id, type, title, description, cycle, issued_at, issued_by, verification_code,
    period_start, period_end, function_role, language, status, signature_hash, content_snapshot, template_id,
    signed_ip, signed_user_agent
  ) VALUES (
    v_member.id, 'volunteer_agreement',
    CASE p_language WHEN 'en-US' THEN 'Volunteer Agreement — Cycle ' || v_cycle
      WHEN 'es-LATAM' THEN 'Acuerdo de Voluntariado — Ciclo ' || v_cycle
      ELSE 'Termo de Voluntariado — Ciclo ' || v_cycle END,
    v_template.description, v_cycle, now(), v_issuer_id, v_code,
    v_period_start::text, v_period_end::text,
    v_member.operational_role, p_language, 'issued', v_hash, v_content, v_template.id::text,
    v_ip, p_signed_user_agent
  ) RETURNING id INTO v_cert_id;

  UPDATE public.engagements
  SET agreement_certificate_id = v_cert_id
  WHERE person_id = (SELECT id FROM public.persons WHERE legacy_member_id = v_member.id)
    AND kind = 'volunteer'
    AND status = 'active'
    AND agreement_certificate_id IS NULL;

  IF FOUND THEN v_engagement_updated := true; END IF;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'volunteer_agreement_signed', 'certificate', v_cert_id,
    jsonb_build_object('verification_code', v_code, 'cycle', v_cycle, 'chapter', v_member.chapter,
      'chapter_cnpj', v_chapter_cnpj,
      'period_source', v_source, 'engagement_linked', v_engagement_updated,
      'signed_ip', v_ip::text, 'signed_user_agent', p_signed_user_agent));

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  SELECT m.id, 'volunteer_agreement_signed',
    v_member.name || ' assinou o Termo de Voluntariado',
    'Capitulo: ' || COALESCE(v_member.chapter, '—') || '. Codigo: ' || v_code,
    '/admin/certificates', 'certificate', v_cert_id,
    public._delivery_mode_for('volunteer_agreement_signed')
  FROM members m
  WHERE m.is_active = true AND m.id != v_member.id
    AND (m.operational_role = 'manager' OR m.is_superadmin = true
         OR ('chapter_board' = ANY(m.designations) AND m.chapter = v_member.chapter));

  RETURN jsonb_build_object('success', true, 'certificate_id', v_cert_id, 'verification_code', v_code,
    'signature_hash', v_hash, 'signed_at', now(),
    'period_start', v_period_start, 'period_end', v_period_end, 'period_source', v_source,
    'engagement_linked', v_engagement_updated,
    'chapter_cnpj', v_chapter_cnpj, 'chapter_name', v_chapter_legal_name);
END;
$function$
;

-- ============================================================
-- update_board_item(p_item_id uuid, p_fields jsonb)
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_board_item(p_item_id uuid, p_fields jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_board_id uuid;
  v_old record;
  v_caller record;
  v_board record;
  v_board_legacy_tribe_id int;
  v_is_gp boolean;
  v_is_leader boolean;
  v_is_card_owner boolean;
  v_is_board_admin boolean;
  v_is_board_editor boolean;
  v_is_comms_for_domain boolean;
  v_new_assignee uuid;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_old FROM board_items WHERE id = p_item_id;
  IF v_old.id IS NULL THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;

  v_board_id := v_old.board_id;
  SELECT * INTO v_board FROM project_boards WHERE id = v_board_id;

  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  -- p180 ADR-0011 V4: hybrid v_is_gp authority. V3 surface preserved
  -- (is_superadmin + operational_role + co_gp designation). V4 path added
  -- via can_by_member('manage_platform') — catalog covers volunteer × {co_gp,
  -- deputy_manager, manager} = same surface today. Defense-in-depth for cache
  -- drift / future seed expansion.
  v_is_gp := coalesce(v_caller.is_superadmin, false)
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR coalesce('co_gp' = ANY(v_caller.designations), false)
    OR public.can_by_member(v_caller.id, 'manage_platform');

  v_is_leader := v_caller.operational_role = 'tribe_leader'
    AND v_caller.tribe_id = v_board_legacy_tribe_id;

  v_is_card_owner := v_old.assignee_id = v_caller.id;

  v_is_board_admin := EXISTS (
    SELECT 1 FROM board_members bm
    WHERE bm.board_id = v_board.id AND bm.member_id = v_caller.id
    AND bm.board_role = 'admin'
  );
  v_is_board_editor := EXISTS (
    SELECT 1 FROM board_members bm
    WHERE bm.board_id = v_board.id AND bm.member_id = v_caller.id
    AND bm.board_role IN ('admin', 'editor')
  );

  -- New: comms team in communication domain (Item 02 + Item 03 fix)
  v_is_comms_for_domain := coalesce(v_board.domain_key, '') = 'communication' AND (
    v_caller.operational_role = 'communicator'
    OR coalesce('comms_team' = ANY(v_caller.designations), false)
    OR coalesce('comms_leader' = ANY(v_caller.designations), false)
    OR coalesce('comms_member' = ANY(v_caller.designations), false)
  );

  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
  IF NOT public.can_by_member(v_caller.id, 'write_board')
     AND NOT v_is_board_admin AND NOT v_is_card_owner AND NOT v_is_board_editor
     AND NOT v_is_comms_for_domain THEN
    IF NOT (
      coalesce(v_board.domain_key, '') = 'publications_submissions' AND (
        v_caller.operational_role IN ('tribe_leader', 'communicator')
        OR public.can_by_member(v_caller.id, 'curate_content')
        OR coalesce('co_gp' = ANY(v_caller.designations), false)
        OR coalesce('comms_leader' = ANY(v_caller.designations), false)
        OR coalesce('comms_member' = ANY(v_caller.designations), false)
      )
    ) THEN
      RAISE EXCEPTION 'Insufficient permissions to edit this card';
    END IF;
  END IF;

  IF p_fields ? 'baseline_date' THEN
    IF v_old.baseline_locked_at IS NOT NULL AND NOT v_is_gp THEN
      RAISE EXCEPTION 'Baseline is locked. Only GP can change it.';
    END IF;
    IF v_old.baseline_locked_at IS NOT NULL AND v_is_gp AND NOT (p_fields ? 'reason') THEN
      RAISE EXCEPTION 'Reason required to change locked baseline';
    END IF;
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin THEN
      RAISE EXCEPTION 'Only Leader or GP can change baseline';
    END IF;
  END IF;

  IF p_fields ? 'forecast_date' THEN
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin AND NOT v_is_card_owner AND NOT v_is_board_editor AND NOT v_is_comms_for_domain THEN
      RAISE EXCEPTION 'Only Leader, GP, card owner, or board editor can change forecast';
    END IF;
  END IF;

  IF p_fields ? 'assignee_id' THEN
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin AND NOT v_is_comms_for_domain THEN
      RAISE EXCEPTION 'Only Leader, GP, Board Admin, or comms team (in communication board) can change assignee';
    END IF;
  END IF;

  IF p_fields ? 'is_portfolio_item' THEN
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin THEN
      RAISE EXCEPTION 'Only Leader or GP can change portfolio flag';
    END IF;
  END IF;

  IF v_old.baseline_date IS NOT NULL
    AND v_old.baseline_locked_at IS NULL
    AND v_old.baseline_date <= CURRENT_DATE - 7
  THEN
    UPDATE board_items SET baseline_locked_at = now() WHERE id = p_item_id;
    v_old.baseline_locked_at := now();
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'baseline_locked', 'Auto-lock após 7 dias de grace period', v_caller.id);
  END IF;

  UPDATE board_items SET
    title = coalesce(p_fields->>'title', title),
    description = CASE WHEN p_fields ? 'description' THEN p_fields->>'description' ELSE description END,
    assignee_id = CASE WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NOT NULL
                       THEN (p_fields->>'assignee_id')::uuid
                       WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NULL THEN NULL
                       ELSE assignee_id END,
    reviewer_id = CASE WHEN p_fields ? 'reviewer_id' AND p_fields->>'reviewer_id' IS NOT NULL
                       THEN (p_fields->>'reviewer_id')::uuid
                       WHEN p_fields ? 'reviewer_id' AND p_fields->>'reviewer_id' IS NULL THEN NULL
                       ELSE reviewer_id END,
    tags = CASE WHEN p_fields ? 'tags' THEN ARRAY(SELECT jsonb_array_elements_text(p_fields->'tags')) ELSE tags END,
    labels = CASE WHEN p_fields ? 'labels' THEN p_fields->'labels' ELSE labels END,
    due_date = CASE WHEN p_fields ? 'due_date' AND p_fields->>'due_date' IS NOT NULL THEN (p_fields->>'due_date')::date
                    WHEN p_fields ? 'due_date' AND p_fields->>'due_date' IS NULL THEN NULL ELSE due_date END,
    baseline_date = CASE WHEN p_fields ? 'baseline_date' AND p_fields->>'baseline_date' IS NOT NULL THEN (p_fields->>'baseline_date')::date
                         WHEN p_fields ? 'baseline_date' AND p_fields->>'baseline_date' IS NULL THEN NULL ELSE baseline_date END,
    forecast_date = CASE WHEN p_fields ? 'forecast_date' AND p_fields->>'forecast_date' IS NOT NULL THEN (p_fields->>'forecast_date')::date
                         WHEN p_fields ? 'forecast_date' AND p_fields->>'forecast_date' IS NULL THEN NULL ELSE forecast_date END,
    is_portfolio_item = CASE WHEN p_fields ? 'is_portfolio_item' THEN (p_fields->>'is_portfolio_item')::boolean ELSE is_portfolio_item END,
    baseline_locked_at = CASE WHEN p_fields ? 'baseline_locked_at' AND p_fields->>'baseline_locked_at' IS NOT NULL
                               THEN (p_fields->>'baseline_locked_at')::timestamptz ELSE baseline_locked_at END,
    checklist = CASE WHEN p_fields ? 'checklist' THEN p_fields->'checklist' ELSE checklist END,
    attachments = CASE WHEN p_fields ? 'attachments' THEN p_fields->'attachments' ELSE attachments END,
    curation_status = coalesce(p_fields->>'curation_status', curation_status),
    curation_due_at = CASE WHEN p_fields ? 'curation_due_at' AND p_fields->>'curation_due_at' IS NOT NULL
                           THEN (p_fields->>'curation_due_at')::timestamptz ELSE curation_due_at END,
    updated_at = now()
  WHERE id = p_item_id;

  IF p_fields ? 'baseline_date' THEN
    IF v_old.baseline_date IS NULL AND p_fields->>'baseline_date' IS NOT NULL THEN
      INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
      VALUES (v_board_id, p_item_id, 'baseline_set', 'Baseline definida: ' || (p_fields->>'baseline_date'), v_caller.id);
    ELSIF v_old.baseline_date IS NOT NULL AND p_fields->>'baseline_date' IS NOT NULL
      AND v_old.baseline_date::text != p_fields->>'baseline_date' THEN
      INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
      VALUES (v_board_id, p_item_id, 'baseline_changed',
        v_old.baseline_date::text || ' → ' || (p_fields->>'baseline_date')
        || CASE WHEN p_fields ? 'reason' THEN ' | Razão: ' || (p_fields->>'reason') ELSE '' END, v_caller.id);
    END IF;
  END IF;

  IF p_fields ? 'forecast_date' AND p_fields->>'forecast_date' IS DISTINCT FROM v_old.forecast_date::text THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'forecast_changed',
      coalesce(v_old.forecast_date::text, 'null') || ' → ' || coalesce(p_fields->>'forecast_date', 'null'), v_caller.id);
  END IF;

  IF p_fields ? 'title' AND p_fields->>'title' IS DISTINCT FROM v_old.title THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'title_changed', 'Título alterado', v_caller.id);
  END IF;

  v_new_assignee := CASE WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NOT NULL
                         THEN (p_fields->>'assignee_id')::uuid
                         WHEN p_fields ? 'assignee_id' THEN NULL ELSE v_old.assignee_id END;
  IF v_new_assignee IS DISTINCT FROM v_old.assignee_id THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'assigned',
      'Atribuído a ' || coalesce((SELECT name FROM members WHERE id = v_new_assignee), 'ninguém'), v_caller.id);
  END IF;

  IF p_fields ? 'is_portfolio_item'
    AND (p_fields->>'is_portfolio_item')::boolean IS DISTINCT FROM v_old.is_portfolio_item THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'portfolio_flag_changed',
      CASE WHEN (p_fields->>'is_portfolio_item')::boolean THEN 'Marcado como entregável' ELSE 'Removido de entregáveis' END, v_caller.id);
  END IF;
END;
$function$
;
