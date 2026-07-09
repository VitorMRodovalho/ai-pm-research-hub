-- #1224 (PR 1, backend foundation) — derive the member's ENTRY CHAPTER from the applicant's
-- PMI enrichment snapshot at approval time, instead of stamping the legacy 'Outro' and waiting
-- for a VEP re-sync (which stalls on pmi_id reconciliation, #1130).
--
-- SSOT of the chapter is `selection_applications.pmi_memberships` (jsonb array of
--   {chapterName, expiryDate}) — the PMI VEP enrichment — NOT free text nor auto-declaration
-- (PM direction 2026-07-09, issue #1224). `membership_status` is a null-trap (NULL for the whole
-- C4 cohort); "PMI-active" is derived from expiryDate >= today. `resolve_br_chapter_code` (mig 364)
-- already maps "<State>, Brazil Chapter" / aliases ("Amazônia Chapter") to the registry code and
-- returns NULL for "PMI Global" / non-BR.
--
-- This migration adds:
--   1. classify_entry_chapter(pmi_memberships, community_profile_private, pmi_data_fetched_at)
--      -> {bucket, active_br_codes} — the pure, testable classifier (the 3 diagnostic situations).
--   2. get_entry_chapter_diagnosis(cycle) — admin/service read surface over the approved cohort
--      (feeds admin visibility now; the diagnostic nudge/email in PR 2 will reuse it).
--   3. approve_selection_application — ADDITIVE derivation block: after member+person exist,
--      classify the applicant's pmi_memberships; upsert every ACTIVE BR affiliation
--      (source='pmi_vep'); when exactly one active BR chapter, set members.entry_chapter_code
--      (unambiguous → governance entry). >1 active is left for member self-declaration
--      (set_my_entry_chapter as tie-break); 0 active leaves the honest legacy 'Outro'
--      (the diagnostic routes the regularization action, not a silent wrong chapter).
--
-- The members.chapter trigger (mig 195, ADR-0104 Wave 3b-ii) does the rest: an upserted primary
-- affiliation (T2) or a set entry_chapter_code (T1) overwrites the default 'Outro' → 'PMI-XX'.
-- Invariant U stays satisfied (exactly one primary): a single upsert becomes the provisional
-- primary; multiple upserts leave exactly one provisional primary.
--
-- Grounding (live 2026-07-09, cycle 08c1e301, status=approved): 49 approved; 40 with
-- pmi_memberships; 3 community_profile_private; 3 pmi_data_fetched_at NULL; 6 fetched-but-no-BR.
--
-- ROLLBACK: restore approve_selection_application body from
--   supabase/migrations/20260805000374_1197_member_chapter_from_application_declaration.sql;
--   DROP FUNCTION public.get_entry_chapter_diagnosis(uuid);
--   DROP FUNCTION public.classify_entry_chapter(jsonb, boolean, timestamptz);

-- ── 1. Pure classifier: pmi_memberships → {bucket, active_br_codes} ──────────────────────────────
-- STABLE (reads chapter_registry via resolve_br_chapter_code + CURRENT_DATE). Buckets:
--   'resolved'        exactly one active BR chapter (unambiguous entry)
--   'ambiguous'       more than one active BR chapter (needs self-declaration tie-break)
--   'profile_private' no active BR chapter AND community.pmi.org profile is private
--   'no_fetch'        no active BR chapter AND enrichment was never fetched (no profile)
--   'not_affiliated'  enrichment fetched, public, but no active BR chapter (regularize)
-- Precedence: a resolvable active BR chapter always wins; otherwise the 3 "why missing" cases.
-- Active = expiryDate NULL, unparseable, or (parsed 'DD Mon YYYY') >= today. Unparseable dates are
-- treated as active (assert the FACT rather than silently drop a chapter on a format surprise).
CREATE OR REPLACE FUNCTION public.classify_entry_chapter(
  p_pmi_memberships          jsonb,
  p_community_profile_private boolean,
  p_pmi_data_fetched_at      timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_codes text[];
BEGIN
  SELECT array_agg(DISTINCT code ORDER BY code) INTO v_codes
  FROM (
    SELECT public.resolve_br_chapter_code(m->>'chapterName') AS code,
           m->>'expiryDate' AS exp
    FROM jsonb_array_elements(COALESCE(p_pmi_memberships, '[]'::jsonb)) AS m
  ) x
  WHERE code IS NOT NULL
    AND (
      exp IS NULL
      OR exp !~ '^\s*\d{1,2}\s+[A-Za-z]{3,}\s+\d{4}\s*$'   -- unparseable → treat as active
      OR to_date(exp, 'DD Mon YYYY') >= CURRENT_DATE
    );

  IF v_codes IS NOT NULL AND array_length(v_codes, 1) >= 1 THEN
    RETURN jsonb_build_object(
      'bucket', CASE WHEN array_length(v_codes, 1) > 1 THEN 'ambiguous' ELSE 'resolved' END,
      'active_br_codes', to_jsonb(v_codes)
    );
  END IF;

  RETURN jsonb_build_object(
    'bucket', CASE
      WHEN COALESCE(p_community_profile_private, false) THEN 'profile_private'
      WHEN p_pmi_data_fetched_at IS NULL              THEN 'no_fetch'
      ELSE 'not_affiliated'
    END,
    'active_br_codes', '[]'::jsonb
  );
END;
$function$;

COMMENT ON FUNCTION public.classify_entry_chapter(jsonb, boolean, timestamptz) IS
  '#1224 — pure diagnostic classifier for the entry chapter. Returns {bucket, active_br_codes} from the PMI enrichment snapshot (pmi_memberships) + profile flags. Buckets: resolved | ambiguous | profile_private | no_fetch | not_affiliated. Active = expiryDate>=today. SSOT is the enrichment, not free text (PM #1224).';

REVOKE ALL ON FUNCTION public.classify_entry_chapter(jsonb, boolean, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.classify_entry_chapter(jsonb, boolean, timestamptz) TO authenticated, service_role;

-- ── 2. Admin/service diagnosis over the approved cohort of a selection cycle ─────────────────────
-- Defaults to the current selection cycle. manage_platform-gated for authenticated callers; also
-- callable by service_role/postgres (cron/tests) — mirrors the check_schema_invariants auth guard.
CREATE OR REPLACE FUNCTION public.get_entry_chapter_diagnosis(p_cycle_id uuid DEFAULT NULL)
RETURNS TABLE(
  application_id     uuid,
  member_id          uuid,
  applicant_name     text,
  bucket             text,
  active_br_codes    text[],
  entry_chapter_code text,
  member_chapter     text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id  uuid := p_cycle_id;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: get_entry_chapter_diagnosis requires manage_platform';
    END IF;
  ELSIF current_setting('role', true) NOT IN ('service_role', 'postgres')
        AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: get_entry_chapter_diagnosis requires authentication';
  END IF;

  IF v_cycle_id IS NULL THEN
    SELECT sc.id INTO v_cycle_id
    FROM public.selection_cycles sc
    ORDER BY sc.created_at DESC
    LIMIT 1;
  END IF;

  RETURN QUERY
  SELECT
    sa.id,
    m.id,
    sa.applicant_name,
    (cls->>'bucket')::text,
    ARRAY(SELECT jsonb_array_elements_text(cls->'active_br_codes')),
    m.entry_chapter_code,
    m.chapter
  FROM public.selection_applications sa
  LEFT JOIN public.members m ON lower(m.email) = lower(sa.email)
  CROSS JOIN LATERAL public.classify_entry_chapter(
    sa.pmi_memberships, sa.community_profile_private, sa.pmi_data_fetched_at
  ) AS cls
  WHERE sa.cycle_id = v_cycle_id
    AND sa.status = 'approved'
  ORDER BY sa.applicant_name;
END;
$function$;

COMMENT ON FUNCTION public.get_entry_chapter_diagnosis(uuid) IS
  '#1224 — admin/service diagnosis of entry-chapter state over a selection cycle''s approved cohort (defaults to current cycle). Per applicant: classifier bucket + active BR codes + derived member chapter. manage_platform-gated; service_role/postgres allowed (cron/tests). PR 2 nudge/email reuses this.';

REVOKE ALL ON FUNCTION public.get_entry_chapter_diagnosis(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_entry_chapter_diagnosis(uuid) TO authenticated, service_role;

-- ── 3. approve_selection_application — additive derivation block ─────────────────────────────────
-- Body reproduced verbatim from mig 374 (#1197) with the #1224 derivation block inserted after the
-- person is ensured (v_person_id guaranteed non-NULL) and before engagement provisioning.
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
  v_classify         jsonb;
  v_br_codes         text[];
  v_code             text;
  v_entry_derived    text;
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

  SELECT sc.close_date
    INTO v_cycle_end_date
  FROM public.selection_cycles sc
  WHERE sc.id = v_app.cycle_id;

  IF v_cycle_end_date IS NOT NULL AND v_cycle_end_date < CURRENT_DATE THEN
    v_cycle_end_date := NULL;
  END IF;

  v_member_chapter := COALESCE(
    NULLIF(trim(v_app.chapter), ''),
    'Outro'
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

  IF v_person_id IS NOT NULL THEN
    v_classify := public.classify_entry_chapter(
      v_app.pmi_memberships, v_app.community_profile_private, v_app.pmi_data_fetched_at
    );
    v_br_codes := ARRAY(SELECT jsonb_array_elements_text(v_classify->'active_br_codes'));

    IF v_br_codes IS NOT NULL AND array_length(v_br_codes, 1) >= 1 THEN
      FOREACH v_code IN ARRAY v_br_codes LOOP
        PERFORM public.upsert_chapter_affiliation(v_person_id, v_code, 'pmi_vep', false);
      END LOOP;

      IF array_length(v_br_codes, 1) = 1 THEN
        v_entry_derived := v_br_codes[1];
        UPDATE public.members
        SET entry_chapter_code = v_entry_derived, updated_at = now()
        WHERE id = v_member_id AND entry_chapter_code IS DISTINCT FROM v_entry_derived;
      END IF;
    END IF;
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
          ELSE 'no_chapter_declared'
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
        ELSE 'no_chapter_declared'
      END,
      'chapter_diagnosis',      v_classify->>'bucket',
      'chapter_active_br_codes', COALESCE(v_classify->'active_br_codes', '[]'::jsonb),
      'entry_chapter_derived',   v_entry_derived
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
    'member_chapter',     v_member_chapter,
    'chapter_diagnosis',      v_classify->>'bucket',
    'chapter_active_br_codes', COALESCE(v_classify->'active_br_codes', '[]'::jsonb),
    'entry_chapter_derived',   v_entry_derived
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.approve_selection_application(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_selection_application(uuid, jsonb) TO authenticated, service_role;

COMMENT ON FUNCTION public.approve_selection_application(uuid, jsonb) IS
  'Canonical post-approval provisioning (member + person + engagement + onboarding). #1197: member chapter derives from the applicant''s declaration. #1224: entry chapter is DERIVED from the applicant''s pmi_memberships enrichment (active BR chapters via resolve_br_chapter_code) — exactly one active → entry_chapter_code; >1 → self-declaration tie-break; 0 → honest ''Outro'' + diagnostic.';

NOTIFY pgrst, 'reload schema';
