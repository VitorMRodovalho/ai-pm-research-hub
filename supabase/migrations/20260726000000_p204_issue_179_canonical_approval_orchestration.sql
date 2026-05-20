-- p204 / Issue #179 — Canonical approval orchestration for volunteer lifecycle
-- Phase 3 of P202_VOLUNTEER_LIFECYCLE_REMEDIATION_SPEC.md
--
-- INTENT
-- ──────
-- Eliminate state drift between `admin_update_application` (live UI) and
-- `finalize_decisions` (committee bulk path). Today neither RPC guarantees:
--   - V4 person upsert + members.person_id linkage;
--   - V4 engagement row with selection_application_id;
--   - Idempotency on re-approval / reactivation.
--
-- Production evidence (p202 SQL audit pack):
--   - 38 approved/converted applications, 1 with no matching member row (Adalberto
--     Neris, application eb9c4795-5a75-4184-83c0-318bace1a1b5, status='converted',
--     role_applied='leader'). #180 backfills this case via the canonical RPC.
--   - 16 active+requires_agreement engagements without certificate (operational
--     queue — surfaced by #177 `get_pending_agreement_engagements()`).
--   - `auth_engagements.is_authoritative` is COMPUTED — engagements created with
--     `agreement_certificate_id IS NULL` AND kind requires_agreement remain
--     non-authoritative until counter-signature (Herlon-class invariant preserved).
--
-- DESIGN
-- ──────
-- 1. New `approve_selection_application(p_application_id uuid, p_decision jsonb)`
--    is the canonical contract. Side-effects in order:
--      a. Auth (can_by_member('manage_platform'))
--      b. Read application + status guard
--      c. Find or create `members` row (UNIQUE email) + Op B operational_role promote
--      d. Find or create `persons` row + link `members.person_id`
--      e. Find or create `engagements` row (kind='volunteer', role from role_applied,
--         status='active', legal_basis='contract_volunteer',
--         selection_application_id=<app_id>, agreement_certificate_id=NULL when
--         requires_agreement=true). Idempotent: skip if active engagement exists for
--         same person+kind; backfill selection_application_id if missing.
--      f. Seed canonical onboarding (is_required=true) + cycle-specific onboarding
--         (from selection_cycles.onboarding_steps JSONB)
--      g. check_pre_onboarding_auto_steps
--      h. Notification (create_notification 7-arg variant — title/body/link)
--      i. Audit trail (data_anomaly_log with anomaly_type='selection_approval_canonical')
--
-- 2. `admin_update_application` retains its public contract (4 frontend callers
--    in src/pages/admin/selection.astro) but DELEGATES to the canonical RPC when
--    transitioning to status='approved'. Non-approve transitions (screening,
--    rejected, waitlist) unchanged.
--
-- 3. `finalize_decisions` (committee bulk) also delegates per-decision when the
--    decision is 'approved'. The diversity snapshot at loop end is preserved.
--    Conversion (researcher → leader) flow unchanged because conversion doesn't
--    flip status to approved on its own — it only stages role_applied.
--
-- BACKWARDS COMPAT
-- ────────────────
-- - `admin_update_application` return shape preserved (success/old_status/
--   new_status/onboarding_seeded/role_promoted/promoted_to). When delegating, the
--   canonical RPC's extended return is merged in. Frontend reads only
--   `data?.error` + `data?.success` so additive keys are safe.
-- - `finalize_decisions` aggregate counters unchanged (approved/rejected/etc).
--
-- INVARIANTS PRESERVED
-- ────────────────────
-- - Herlon-class pending: engagement.agreement_certificate_id stays NULL for
--   kinds requiring agreement → is_authoritative=false in auth_engagements view.
-- - Members are anchored to a single email (UNIQUE constraint); lookup uses
--   case-insensitive lower(email).
-- - operational_role promotion gated to non-active legacy roles + member_status='active'
--   to avoid trigger override (same gate as existing logic).
--
-- ROLLBACK
-- ────────
-- DROP FUNCTION public.approve_selection_application(uuid, jsonb);
-- Restore prior admin_update_application + finalize_decisions bodies from
-- pg_get_functiondef captured in /home/vitormrodovalho/projects/ai-pm-research-hub
-- migration headers (see admin_update_application historical migrations).
-- Note: rollback alone does NOT remove members/persons/engagements rows created
-- by canonical calls — those persist (correct: they represent real state).
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Canonical approval RPC
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.approve_selection_application(
  p_application_id uuid,
  p_decision jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
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
  -- (a) Auth: caller must be authenticated + V4 manage_platform.
  SELECT id, name, person_id, organization_id
    INTO v_caller_id, v_caller_name, v_caller_person_id, v_caller_org_id
  FROM public.members WHERE auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- (b) Read application + status guard.
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

  -- Compute target operational_role from application (legacy cache).
  v_target_role := CASE
    WHEN v_app.role_applied = 'leader'     THEN 'tribe_leader'
    WHEN v_app.role_applied = 'researcher' THEN 'researcher'
    ELSE NULL
  END;

  -- (c) Find or create member.
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
    -- Reactivate existing member if inactive.
    UPDATE public.members SET
      is_active = true,
      current_cycle_active = true,
      updated_at = now()
    WHERE id = v_member_id
      AND (is_active = false OR current_cycle_active = false);

    -- Op B parity: promote operational_role from non-active legacy roles.
    -- Gate to member_status='active' to avoid trigger override on observer/alumni.
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

  -- (d) Find or create person + link members.person_id.
  IF v_person_id IS NULL THEN
    -- Try lookup by email first (a person row may exist orphan of member).
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

  -- (e) Find or create engagement.
  -- Engagement role: bound to known volunteer roles; safe default 'researcher'.
  v_engagement_role := CASE
    WHEN v_app.role_applied IN ('leader', 'researcher', 'coordinator', 'manager') THEN v_app.role_applied
    ELSE 'researcher'
  END;

  SELECT sc.end_date INTO v_cycle_end_date
  FROM public.selection_cycles sc WHERE sc.id = v_app.cycle_id;

  SELECT ek.default_duration_days, ek.requires_agreement
    INTO v_default_days, v_requires_agreement
  FROM public.engagement_kinds ek WHERE ek.slug = v_engagement_kind;

  -- Idempotent: skip if active engagement for same person+kind already exists.
  -- Backfill selection_application_id when missing.
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

  -- (f) Seed canonical onboarding (is_required=true).
  INSERT INTO public.onboarding_progress (application_id, member_id, step_key, status, metadata)
  SELECT p_application_id, v_member_id, s.id, 'pending', '{}'::jsonb
  FROM public.onboarding_steps s
  WHERE s.is_required = true
    AND NOT EXISTS (
      SELECT 1 FROM public.onboarding_progress op
      WHERE op.member_id = v_member_id AND op.step_key = s.id
    );
  GET DIAGNOSTICS v_seeded_count = ROW_COUNT;

  -- Cycle-specific onboarding (from selection_cycles.onboarding_steps JSONB).
  INSERT INTO public.onboarding_progress (application_id, member_id, step_key, status, sla_deadline)
  SELECT p_application_id, v_member_id, (step->>'key'), 'pending',
         now() + ((step->>'sla_days')::int || ' days')::interval
  FROM public.selection_cycles sc, jsonb_array_elements(sc.onboarding_steps) AS step
  WHERE sc.id = v_app.cycle_id
    AND NOT EXISTS (
      SELECT 1 FROM public.onboarding_progress
      WHERE member_id = v_member_id AND step_key = (step->>'key')
    );

  -- (g) Pre-onboarding auto steps.
  PERFORM public.check_pre_onboarding_auto_steps(v_member_id);

  -- (h) Notification (7-arg variant: recipient/type/title/body/link/source_type/source_id).
  PERFORM public.create_notification(
    v_member_id,
    'selection_approved',
    'Parabéns! Você foi aprovado no Núcleo IA',
    'Sua candidatura foi aprovada. Acesse a plataforma para iniciar o onboarding.',
    '/onboarding',
    'selection_application',
    p_application_id
  );

  -- (i) Audit trail.
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
$$;

REVOKE ALL ON FUNCTION public.approve_selection_application(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_selection_application(uuid, jsonb) TO authenticated;

COMMENT ON FUNCTION public.approve_selection_application(uuid, jsonb) IS
'Canonical approval orchestration for volunteer lifecycle (Issue #179, p204). Idempotent. Creates/reactivates members + persons + volunteer engagement, seeds onboarding, sends notification, writes audit trail. agreement_certificate_id stays NULL when kind requires_agreement → engagement appears in get_pending_agreement_engagements() queue until counter-signature unlocks is_authoritative.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. admin_update_application delegates to canonical on approve transition.
--    Signature + return shape preserved (4 frontend callers in selection.astro).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_update_application(
  p_application_id uuid,
  p_data jsonb
) RETURNS json
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

  -- Update application fields (status + optional metadata).
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

  -- Delegate to canonical RPC on approve transition.
  IF v_new_status = 'approved' AND v_old_status <> 'approved' THEN
    -- Partner chapter check (flag, not block) — kept here because canonical RPC
    -- intentionally stays narrow (doesn't manage tag-level signals).
    IF NOT EXISTS (
      SELECT 1 FROM public.selection_membership_snapshots sms
      WHERE sms.application_id = p_application_id AND sms.is_partner_chapter = true
    ) THEN
      UPDATE public.selection_applications
      SET tags = array_append(tags, 'no_partner_chapter')
      WHERE id = p_application_id AND NOT ('no_partner_chapter' = ANY(tags));
    END IF;

    v_canonical_result := public.approve_selection_application(p_application_id, p_data);

    -- Surface canonical errors but preserve admin_update_application's return shape.
    IF (v_canonical_result->>'success') IS DISTINCT FROM 'true' THEN
      RETURN json_build_object(
        'error',         coalesce(v_canonical_result->>'error', 'Canonical approval failed'),
        'old_status',    v_old_status,
        'new_status',    v_new_status,
        'canonical',     v_canonical_result
      );
    END IF;

    v_member_id      := (v_canonical_result->>'member_id')::uuid;
    v_seeded_count   := coalesce((v_canonical_result->>'onboarding_seeded')::int, 0);
    v_promoted       := coalesce((v_canonical_result->>'role_promoted')::boolean, false);
    v_target_role    := v_canonical_result->>'promoted_to';
  END IF;

  -- Audit (legacy data_anomaly_log row preserved for analytics continuity).
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
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. finalize_decisions delegates to canonical per-decision when status='approved'.
--    Diversity snapshot preserved at loop end. Conversion path unchanged.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.finalize_decisions(
  p_cycle_id uuid,
  p_decisions jsonb
) RETURNS json
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
  -- Auth: committee lead (resource) or platform admin (V4 manage_platform).
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

    -- Conversion flow (researcher → leader) — does NOT approve on its own.
    -- Status flips to 'converted'; canonical RPC may be called later via
    -- admin_update_application or finalize_decisions in a separate pass.
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

      -- Notify with conversion offer.
      PERFORM public.create_notification(
        m.id, 'selection_conversion_offer',
        'Proposta de conversão de papel',
        'O comitê identificou seu perfil para o papel de ' || v_convert_to || '. Acesse a plataforma para mais detalhes.',
        '/admin/selection', 'selection_application', v_app_id
      ) FROM public.members m WHERE lower(m.email) = lower(v_app.email);

      CONTINUE;
    END IF;

    -- Normal decision update.
    UPDATE public.selection_applications SET
      status     = v_status,
      feedback   = coalesce(v_feedback, feedback),
      updated_at = now()
    WHERE id = v_app_id;

    IF v_status = 'approved' THEN
      v_approved_count := v_approved_count + 1;

      -- Partner chapter flag (same pattern as admin_update_application).
      IF NOT EXISTS (
        SELECT 1 FROM public.selection_membership_snapshots
        WHERE application_id = v_app_id AND is_partner_chapter = true
      ) THEN
        UPDATE public.selection_applications SET tags = array_append(tags, 'no_partner_chapter')
        WHERE id = v_app_id AND NOT ('no_partner_chapter' = ANY(tags));
      END IF;

      -- Delegate to canonical.
      v_canonical_result := public.approve_selection_application(v_app_id, '{}'::jsonb);

      IF (v_canonical_result->>'success') = 'true' THEN
        v_member_id         := (v_canonical_result->>'member_id')::uuid;
        v_promoted_this_app := coalesce((v_canonical_result->>'role_promoted')::boolean, false);
        v_target_role       := v_canonical_result->>'promoted_to';
        IF (v_canonical_result->>'member_created')::boolean THEN
          v_created_members := v_created_members + 1;
        END IF;
        IF v_promoted_this_app THEN
          v_promoted_count := v_promoted_count + 1;
        END IF;
      END IF;

    ELSIF v_status = 'rejected' THEN
      v_rejected_count := v_rejected_count + 1;
    ELSIF v_status = 'waitlist' THEN
      v_waitlisted_count := v_waitlisted_count + 1;
    END IF;

    -- Audit per-decision.
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

  -- Diversity snapshot (preserved verbatim from prior body).
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
$function$;

NOTIFY pgrst, 'reload schema';

COMMIT;
