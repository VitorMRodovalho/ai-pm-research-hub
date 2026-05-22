-- ============================================================================
-- p219 — WATCH-257.B: normalize legacy contract_volunteer → contract
-- ADR: ADR-0006 (Person + Engagement) / LGPD Art. 7 V (contract as legal basis)
--
-- Purpose:
--   PR #263 (p218 WATCH-257.A) made engagements.legal_basis check constraint
--   additive — accepts BOTH `contract` (LGPD-canonical) AND `contract_volunteer`
--   (legacy from migration 20260413320000). 46 legacy rows + 2 producer RPCs
--   still output `contract_volunteer`, perpetuating the asymmetry on every
--   new engagement created via:
--     - approve_selection_application (canonical selection→engagement conversion)
--     - seed_member_engagement_by_role (template-based onboarding seed)
--
--   This migration:
--   (1) Normalizes 46 existing legacy rows → `contract`
--   (2) Updates approve_selection_application RPC: v_legal_basis default → `contract`
--   (3) Updates seed_member_engagement_by_role RPC: literal → `contract`
--   (4) Sanity DO block fails loud if (a) any row still `contract_volunteer`,
--       or (b) any RPC body still contains the literal.
--
-- Scope (per PM, p219 Path B): rows + 2 producer RPCs. Constraint stays
--   additive — `contract_volunteer` value still LEGAL in DB (just not produced
--   by canonical paths). Path C (DROP value from constraint) deferred.
--
-- Rollback:
--   -- Revert RPCs to prior bodies (see migration history); revert rows is
--   -- problematic since the literal value is still accepted — just UPDATE back
--   -- targeting the engagement IDs captured in admin_audit_log target_id where
--   -- action='watch_257_b_normalize_engagement_legal_basis'.
-- ============================================================================

-- ════════════════════════════════════════════════════════════════════════
-- (1) BACKFILL: 46 legacy rows → 'contract' (LGPD-canonical)
-- ════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_affected int;
BEGIN
  WITH updated AS (
    UPDATE public.engagements
    SET legal_basis = 'contract'
    WHERE legal_basis = 'contract_volunteer'
    RETURNING id, person_id
  ),
  audit_insert AS (
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    SELECT
      NULL::uuid,
      'watch_257_b_normalize_engagement_legal_basis',
      'engagement',
      u.id,
      jsonb_build_object(
        'engagement_id', u.id,
        'person_id', u.person_id,
        'legal_basis_before', 'contract_volunteer',
        'legal_basis_after', 'contract',
        'migration', '20260803000004',
        'reason', 'LGPD Art. 7 V canonical (PR #263 made constraint additive; Path B normalizes producers + rows)'
      )
    FROM updated u
    RETURNING target_id
  )
  SELECT count(*) INTO v_affected FROM audit_insert;

  RAISE NOTICE 'WATCH-257.B normalize: % engagements rows updated contract_volunteer → contract', v_affected;
END$$;

-- ════════════════════════════════════════════════════════════════════════
-- (2) approve_selection_application — canonical selection→engagement RPC
--      Only change: v_legal_basis text := 'contract_volunteer' → 'contract'
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

-- ════════════════════════════════════════════════════════════════════════
-- (3) seed_member_engagement_by_role — template-based onboarding seed RPC
--      Only change: literal 'contract_volunteer' → 'contract'
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.seed_member_engagement_by_role(p_person_id uuid, p_template_slug text, p_initiative_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_person_id uuid;
  v_caller_org uuid;
  v_target_org uuid;
  v_template engagement_seed_templates%ROWTYPE;
  v_engagement_spec jsonb;
  v_kind text;
  v_role text;
  v_scope text;
  v_target_initiative_id uuid;
  v_new_id uuid;
  v_created_ids uuid[] := ARRAY[]::uuid[];
  v_skipped_count int := 0;
  v_invalid_kinds_roles text[] := ARRAY[]::text[];
BEGIN
  SELECT id, person_id, organization_id INTO v_caller_id, v_caller_person_id, v_caller_org
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'unauthorized', 'detail', 'requires manage_member');
  END IF;

  SELECT m.organization_id INTO v_target_org
  FROM public.members m WHERE m.person_id = p_person_id;
  IF v_target_org IS NULL THEN
    SELECT organization_id INTO v_target_org
    FROM public.persons WHERE id = p_person_id;
  END IF;
  IF v_target_org IS NULL THEN
    RETURN jsonb_build_object('error', 'person_not_found');
  END IF;
  IF v_target_org != v_caller_org THEN
    RETURN jsonb_build_object('error', 'person_not_in_caller_org');
  END IF;

  SELECT * INTO v_template
  FROM public.engagement_seed_templates t
  WHERE t.slug = p_template_slug
    AND t.active = true
    AND (t.organization_id = v_caller_org OR t.organization_id IS NULL)
  ORDER BY t.organization_id NULLS LAST
  LIMIT 1;

  IF v_template.id IS NULL THEN
    RETURN jsonb_build_object('error', 'template_not_found', 'detail', 'no active template with slug: ' || p_template_slug);
  END IF;

  FOR v_engagement_spec IN SELECT * FROM jsonb_array_elements(v_template.engagements)
  LOOP
    v_kind := v_engagement_spec->>'kind';
    v_role := v_engagement_spec->>'role';
    v_scope := v_engagement_spec->>'scope';

    IF v_scope = 'initiative' AND p_initiative_id IS NULL THEN
      RETURN jsonb_build_object(
        'error', 'initiative_id_required',
        'detail', format('template item kind=%s role=%s scope=initiative requires p_initiative_id', v_kind, v_role)
      );
    END IF;

    v_target_initiative_id := CASE
      WHEN v_scope = 'initiative' THEN p_initiative_id
      ELSE NULL
    END;

    IF NOT EXISTS (
      SELECT 1 FROM public.engagement_kind_permissions
      WHERE kind = v_kind AND role = v_role
    ) THEN
      v_invalid_kinds_roles := array_append(v_invalid_kinds_roles, v_kind || '/' || v_role);
      CONTINUE;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.engagements
      WHERE person_id = p_person_id
        AND kind = v_kind
        AND role = v_role
        AND status = 'active'
        AND (
          (v_target_initiative_id IS NULL AND initiative_id IS NULL)
          OR initiative_id = v_target_initiative_id
        )
    ) THEN
      v_skipped_count := v_skipped_count + 1;
      CONTINUE;
    END IF;

    INSERT INTO public.engagements (
      person_id, organization_id, initiative_id, kind, role, status,
      start_date, legal_basis, granted_by, metadata
    ) VALUES (
      p_person_id, v_caller_org, v_target_initiative_id,
      v_kind, v_role, 'active',
      CURRENT_DATE, 'contract', v_caller_person_id,
      jsonb_build_object(
        'seeded_via', 'seed_member_engagement_by_role',
        'template_slug', p_template_slug,
        'template_id', v_template.id,
        'seeded_at', now()
      )
    ) RETURNING id INTO v_new_id;

    v_created_ids := array_append(v_created_ids, v_new_id);
  END LOOP;

  IF cardinality(v_invalid_kinds_roles) > 0 THEN
    RETURN jsonb_build_object(
      'error', 'invalid_template_items',
      'detail', 'kind/role combos sem permissions seeded: ' || array_to_string(v_invalid_kinds_roles, ', '),
      'engagements_created', cardinality(v_created_ids),
      'engagement_ids', to_jsonb(v_created_ids)
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'template_slug', p_template_slug,
    'template_id', v_template.id,
    'engagements_created', cardinality(v_created_ids),
    'engagements_skipped', v_skipped_count,
    'engagement_ids', to_jsonb(v_created_ids)
  );
END;
$function$;

-- ════════════════════════════════════════════════════════════════════════
-- (4) SANITY: 0 legacy rows + 0 RPC bodies with literal
-- ════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_row_count int;
  v_rpc_count int;
BEGIN
  SELECT count(*) INTO v_row_count
  FROM public.engagements WHERE legal_basis = 'contract_volunteer';
  IF v_row_count <> 0 THEN
    RAISE EXCEPTION 'WATCH-257.B sanity FAIL: % engagements rows still have legal_basis=contract_volunteer', v_row_count;
  END IF;

  SELECT count(*) INTO v_rpc_count
  FROM pg_proc
  WHERE pronamespace = 'public'::regnamespace
    AND proname IN ('approve_selection_application', 'seed_member_engagement_by_role')
    AND prosrc ~ 'contract_volunteer';
  IF v_rpc_count <> 0 THEN
    RAISE EXCEPTION 'WATCH-257.B sanity FAIL: % canonical RPC bodies still contain contract_volunteer literal', v_rpc_count;
  END IF;

  RAISE NOTICE 'WATCH-257.B sanity OK: 0 legacy rows + 0 RPC bodies with literal.';
END$$;

NOTIFY pgrst, 'reload schema';
