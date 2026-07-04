-- #1103: role-scoped onboarding steps (tribe_leader-specific journey)
-- Plano da virada C4 §5.2. Adds onboarding_steps.applies_to_role (NULL = all roles,
-- preserves current behavior for the 7 existing steps) + 4 leader steps + makes every
-- seed/read path role-aware. Without this, get_my_onboarding (and 4 other paths) would
-- leak the leader steps to EVERY member (researchers included), inflating denominators
-- and blocking researcher "all_complete".
--
-- Owner decision 2026-07-04: ALL members with operational_role='tribe_leader' receive
-- the leader steps (no completion guard) — the 6 active C3 leaders included.

BEGIN;

-- 1. Column: NULL = applies to all roles (default; keeps the 7 existing steps unchanged)
ALTER TABLE public.onboarding_steps
  ADD COLUMN IF NOT EXISTS applies_to_role text[];

COMMENT ON COLUMN public.onboarding_steps.applies_to_role IS
  '#1103: NULL = step applies to every role (default). Non-null text[] = only members whose operational_role is in this array receive/see the step (e.g. {tribe_leader}).';

-- 2. DRY predicate reused by every seed/read path (single source of truth for the rule)
CREATE OR REPLACE FUNCTION public.onboarding_step_applies(
  p_applies_to_role text[], p_member_role text
) RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  PARALLEL SAFE
  SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT p_applies_to_role IS NULL
      OR COALESCE(p_member_role, 'researcher') = ANY(p_applies_to_role);
$$;

COMMENT ON FUNCTION public.onboarding_step_applies(text[], text) IS
  '#1103: canonical predicate — does an onboarding step (applies_to_role) apply to a member (operational_role)? NULL applies_to_role = all roles.';

-- 3. Seed the 4 tribe_leader steps (idempotent). step_order continues after the 7 base steps.
INSERT INTO public.onboarding_steps
  (id, step_order, label_pt, label_en, label_es,
   description_pt, description_en, description_es, icon, is_required, applies_to_role)
VALUES
  ('leader_refine_theme', 8,
   'Refine o tema da sua tribo', 'Refine your tribe theme', 'Refina el tema de tu tribu',
   'Descreva o tema em 1 parágrafo, escolha o quadrante (1–4) e a vertical quando aplicável.',
   'Describe the theme in 1 paragraph, choose the quadrant (1–4) and the vertical when applicable.',
   'Describe el tema en 1 párrafo, elige el cuadrante (1–4) y la vertical cuando aplique.',
   '🎯', true, ARRAY['tribe_leader']),
  ('leader_roadmap', 9,
   'Monte o roadmap 6/12/18 meses', 'Build the 6/12/18-month roadmap', 'Arma el roadmap 6/12/18 meses',
   'Programe os artefatos da tribo nos horizontes de 6, 12 e 18 meses.',
   'Schedule your tribe artifacts across the 6, 12 and 18-month horizons.',
   'Programa los artefactos de tu tribu en los horizontes de 6, 12 y 18 meses.',
   '🗺️', true, ARRAY['tribe_leader']),
  ('leader_capture_video', 10,
   'Grave o vídeo de captação', 'Record your recruitment video', 'Graba tu video de captación',
   'Grave um vídeo curto de captação; o link fica registrado na página da tribo.',
   'Record a short recruitment video; the link is stored on your tribe page.',
   'Graba un video corto de captación; el enlace queda en la página de tu tribu.',
   '🎬', true, ARRAY['tribe_leader']),
  ('leader_review_tribe', 11,
   'Revise as pendências da tribo', 'Review your tribe backlog', 'Revisa los pendientes de tu tribu',
   'Revise cards, membros e pastas do Drive herdados antes do kickoff.',
   'Review inherited cards, members and Drive folders before kickoff.',
   'Revisa cards, miembros y carpetas de Drive heredados antes del kickoff.',
   '📋', true, ARRAY['tribe_leader'])
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 4. Role-aware rewrites of the 5 read/seed paths + 1 completion guard.
--    consume_onboarding_token is a false positive (references selection_cycles.onboarding_steps
--    jsonb column, not the table) — left untouched.
-- ---------------------------------------------------------------------------

-- 4a. get_my_onboarding — auto-seed + counts + steps list all role-scoped
CREATE OR REPLACE FUNCTION public.get_my_onboarding()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_member_role text;
  v_has_req_agreement_engagement boolean;
  v_result jsonb;
BEGIN
  SELECT id, operational_role INTO v_member_id, v_member_role
  FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  -- #322 close-review: mirror the approve_selection_application forward guard here.
  SELECT EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.members m ON m.id = v_member_id
    JOIN public.engagement_kinds ek ON ek.slug = e.kind
    WHERE e.person_id = m.person_id
      AND e.status = 'active'
      AND ek.requires_agreement = true
  ) INTO v_has_req_agreement_engagement;

  -- Auto-generate progress rows (guarded: volunteer_term only with an active
  -- requires_agreement engagement; #1103: only steps that apply to this member's role)
  INSERT INTO onboarding_progress (member_id, step_key, status)
  SELECT v_member_id, s.id, 'pending'
  FROM onboarding_steps s
  WHERE NOT EXISTS (SELECT 1 FROM onboarding_progress op WHERE op.member_id = v_member_id AND op.step_key = s.id)
    AND NOT (s.id = 'volunteer_term' AND NOT v_has_req_agreement_engagement)
    AND public.onboarding_step_applies(s.applies_to_role, v_member_role);

  SELECT jsonb_build_object(
    'member_id', v_member_id,
    'total_steps', (SELECT count(*) FROM onboarding_steps s
      WHERE s.is_required AND public.onboarding_step_applies(s.applies_to_role, v_member_role)),
    'completed_steps', (SELECT count(*) FROM onboarding_progress
      WHERE member_id = v_member_id AND status IN ('completed', 'skipped')
        AND step_key IN (SELECT id FROM onboarding_steps s
          WHERE public.onboarding_step_applies(s.applies_to_role, v_member_role))),
    'all_complete', (NOT EXISTS (
      SELECT 1 FROM onboarding_steps s
      JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = v_member_id
      WHERE s.is_required AND op.status NOT IN ('completed', 'skipped')
        AND public.onboarding_step_applies(s.applies_to_role, v_member_role)
    )),
    'steps', (SELECT jsonb_agg(row_to_json(t) ORDER BY t.step_order) FROM (
      SELECT s.id AS step_id, s.step_order, s.label_pt, s.label_en, s.label_es,
        s.description_pt, s.description_en, s.description_es, s.icon, s.is_required,
        COALESCE(op.status, 'pending') AS status, op.completed_at, op.metadata
      FROM onboarding_steps s
      LEFT JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = v_member_id
      WHERE public.onboarding_step_applies(s.applies_to_role, v_member_role)
      ORDER BY s.step_order
    ) t)
  ) INTO v_result;
  RETURN v_result;
END; $function$;

-- 4b. approve_selection_application — role-scoped seed (one WHERE clause added)
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
  v_cycle_contracting_chapter text;
  v_member_chapter   text;
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

  SELECT sc.close_date, sc.contracting_chapter
    INTO v_cycle_end_date, v_cycle_contracting_chapter
  FROM public.selection_cycles sc
  WHERE sc.id = v_app.cycle_id;

  IF v_cycle_end_date IS NOT NULL AND v_cycle_end_date < CURRENT_DATE THEN
    v_cycle_end_date := NULL;
  END IF;

  v_member_chapter := COALESCE(
    NULLIF(trim(v_app.chapter), ''),
    NULLIF(trim(v_cycle_contracting_chapter), ''),
    'Nao informado'
  );

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
      v_app.applicant_name, v_app.email, v_app.pmi_id, v_member_chapter,
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

  SELECT ek.default_duration_days, ek.requires_agreement
    INTO v_default_days, v_requires_agreement
  FROM public.engagement_kinds ek WHERE ek.slug = v_engagement_kind;

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
        'application_status', v_app.status,
        'chapter_source', CASE
          WHEN NULLIF(trim(v_app.chapter), '') IS NOT NULL THEN 'application'
          WHEN NULLIF(trim(v_cycle_contracting_chapter), '') IS NOT NULL THEN 'cycle_contracting_chapter'
          ELSE 'fallback'
        END,
        'member_chapter', v_member_chapter
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

  -- #1103: only seed steps that apply to this member's role (tribe_leader gets the
  -- leader steps + base steps; researcher gets base steps only).
  INSERT INTO public.onboarding_progress (application_id, member_id, step_key, status, metadata)
  SELECT p_application_id, v_member_id, s.id, 'pending', '{}'::jsonb
  FROM public.onboarding_steps s
  WHERE s.is_required = true
    AND NOT (s.id = 'volunteer_term' AND NOT COALESCE(v_requires_agreement, FALSE))
    AND public.onboarding_step_applies(s.applies_to_role, COALESCE(v_target_role, 'researcher'))
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
      'Parabens! Voce foi aprovado no Nucleo IA',
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
      'agreement_pending',  v_requires_agreement,
      'member_chapter',     v_member_chapter,
      'chapter_source',     CASE
        WHEN NULLIF(trim(v_app.chapter), '') IS NOT NULL THEN 'application'
        WHEN NULLIF(trim(v_cycle_contracting_chapter), '') IS NOT NULL THEN 'cycle_contracting_chapter'
        ELSE 'fallback'
      END
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
    'agreement_pending',  v_requires_agreement,
    'member_chapter',     v_member_chapter
  );
END;
$function$;

-- 4c. get_onboarding_dashboard — per-member role-scoped denominators
CREATE OR REPLACE FUNCTION public.get_onboarding_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller_id uuid; v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform'::text) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
      'fully_onboarded', (SELECT count(DISTINCT m.id) FROM members m
        WHERE m.is_active AND m.current_cycle_active
        AND NOT EXISTS (SELECT 1 FROM onboarding_steps s JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = m.id
          WHERE s.is_required AND op.status != 'completed'
            AND public.onboarding_step_applies(s.applies_to_role, m.operational_role))
        AND EXISTS (SELECT 1 FROM onboarding_progress op2 WHERE op2.member_id = m.id)),
      'not_started', (SELECT count(DISTINCT m.id) FROM members m
        WHERE m.is_active AND m.current_cycle_active
        AND NOT EXISTS (SELECT 1 FROM onboarding_progress op WHERE op.member_id = m.id AND op.status = 'completed'))
    ),
    'members', (SELECT jsonb_agg(row_to_json(t) ORDER BY t.completed_count ASC, t.name) FROM (
      SELECT m.id, m.name, m.photo_url, m.chapter, m.tribe_id,
        (SELECT count(*) FROM onboarding_progress op WHERE op.member_id = m.id AND op.status = 'completed'
          AND op.step_key IN (SELECT id FROM onboarding_steps s WHERE public.onboarding_step_applies(s.applies_to_role, m.operational_role))) AS completed_count,
        (SELECT count(*) FROM onboarding_steps s WHERE s.is_required
          AND public.onboarding_step_applies(s.applies_to_role, m.operational_role)) AS total_steps,
        (SELECT max(op.updated_at) FROM onboarding_progress op WHERE op.member_id = m.id) AS last_activity
      FROM members m WHERE m.is_active AND m.current_cycle_active
    ) t)
  ) INTO v_result;
  RETURN v_result;
END; $function$;

-- 4d. get_candidate_onboarding_progress — role-scoped onboarding totals
CREATE OR REPLACE FUNCTION public.get_candidate_onboarding_progress(p_member_id uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_mid uuid;
  v_caller uuid;
  v_member_role text;
  v_result json;
BEGIN
  SELECT id INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  v_mid := COALESCE(p_member_id, v_caller);

  IF v_mid <> v_caller
     AND NOT public.can_by_member(v_caller, 'write', NULL, NULL)
     AND NOT public.can_by_member(v_caller, 'manage_member', NULL, NULL) THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT operational_role INTO v_member_role FROM members WHERE id = v_mid;

  -- First run auto-detection
  PERFORM check_pre_onboarding_auto_steps(v_mid);

  SELECT json_build_object(
    'member_id', v_mid,
    'steps', coalesce((
      SELECT json_agg(json_build_object(
        'step_key', op.step_key,
        'status', op.status,
        'completed_at', op.completed_at,
        'sla_deadline', op.sla_deadline,
        'xp', coalesce((op.metadata->>'xp')::int, 0),
        'phase', coalesce(op.metadata->>'phase', 'onboarding')
      ) ORDER BY
        CASE op.step_key
          WHEN 'create_account' THEN 1
          WHEN 'complete_profile' THEN 2
          WHEN 'setup_credly' THEN 3
          WHEN 'explore_platform' THEN 4
          WHEN 'read_blog' THEN 5
          WHEN 'start_pmi_certs' THEN 6
          WHEN 'code_of_conduct' THEN 7
          WHEN 'volunteer_term' THEN 8
          WHEN 'vep_acceptance' THEN 9
          WHEN 'first_meeting' THEN 10
          WHEN 'meet_tribe' THEN 11
          WHEN 'start_trail' THEN 12
          ELSE 99
        END
      )
      FROM onboarding_progress op
      WHERE op.member_id = v_mid
    ), '[]'::json),
    'pre_onboarding', json_build_object(
      'total', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding'),
      'completed', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding' AND status = 'completed'),
      'xp_earned', coalesce((SELECT sum((metadata->>'xp')::int) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding' AND status = 'completed'), 0),
      'xp_total', coalesce((SELECT sum((metadata->>'xp')::int) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding'), 0)
    ),
    'onboarding', json_build_object(
      'total', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid
        AND step_key IN (SELECT id FROM onboarding_steps s WHERE public.onboarding_step_applies(s.applies_to_role, v_member_role))),
      'completed', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid
        AND step_key IN (SELECT id FROM onboarding_steps s WHERE public.onboarding_step_applies(s.applies_to_role, v_member_role))
        AND status IN ('completed', 'skipped'))
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- 4e. _trg_record_onboarding_complete_milestone — role-scoped "all complete" check
--     (search_path='' — everything must be fully qualified)
CREATE OR REPLACE FUNCTION public._trg_record_onboarding_complete_milestone()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_all_complete boolean;
  v_member_role text;
BEGIN
  IF NEW.member_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('completed', 'skipped') THEN RETURN NEW; END IF;
  SELECT operational_role INTO v_member_role FROM public.members WHERE id = NEW.member_id;
  SELECT NOT EXISTS (
    SELECT 1 FROM public.onboarding_steps s
    WHERE s.is_required
      AND public.onboarding_step_applies(s.applies_to_role, v_member_role)
      AND (
        EXISTS (SELECT 1 FROM public.onboarding_progress op
                WHERE op.step_key = s.id AND op.member_id = NEW.member_id
                  AND op.status NOT IN ('completed', 'skipped'))
        OR (s.id <> 'volunteer_term'
            AND NOT EXISTS (SELECT 1 FROM public.onboarding_progress op
                            WHERE op.step_key = s.id AND op.member_id = NEW.member_id))
      )
  ) INTO v_all_complete;
  IF v_all_complete THEN
    PERFORM public.record_milestone(NEW.member_id, 'onboarding_complete', 'onboarding', NEW.id,
      jsonb_build_object('via', 'onboarding_progress_trigger'));
  END IF;
  RETURN NEW;
END; $function$;

-- 4f. complete_onboarding_step — defense-in-depth: caller can only complete a step
--     that applies to their role (a researcher cannot complete leader steps)
CREATE OR REPLACE FUNCTION public.complete_onboarding_step(p_step_id text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_member_role text;
BEGIN
  SELECT id, operational_role INTO v_member_id, v_member_role FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  IF NOT EXISTS (
    SELECT 1 FROM onboarding_steps s
    WHERE s.id = p_step_id
      AND public.onboarding_step_applies(s.applies_to_role, v_member_role)
  ) THEN
    RETURN jsonb_build_object('error', 'Invalid step'); END IF;
  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at, metadata, updated_at)
  VALUES (v_member_id, p_step_id, 'completed', now(), p_metadata, now())
  ON CONFLICT (member_id, step_key) DO UPDATE SET
    status = 'completed', completed_at = now(),
    metadata = COALESCE(p_metadata, onboarding_progress.metadata), updated_at = now();
  RETURN jsonb_build_object('success', true, 'step_id', p_step_id);
END; $function$;

COMMIT;

NOTIFY pgrst, 'reload schema';
