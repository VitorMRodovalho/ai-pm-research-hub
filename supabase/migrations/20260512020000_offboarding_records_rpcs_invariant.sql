-- Migration: #91 G3 Part 2 — invariant L + anonymize free-text + 4 RPCs
-- Depends on: 20260512010000_member_offboarding_records (table + RLS + trigger + backfill)
--
-- Contents:
--   1. check_schema_invariants() extension — adds L_offboarding_record_present
--   2. admin_anonymize_member + anonymize_inactive_members — clear free-text PII (LGPD Art. 16)
--   3. RPCs:
--      - record_offboarding_interview(member_id, interview content + return interest)
--      - get_member_offboarding_record(member_id)
--      - list_offboarding_records(reason_category?, since?, until?, limit?)
--      - get_offboarding_dashboard()
--
-- Rollback:
--   (revert check_schema_invariants to drop L_offboarding_record_present)
--   (revert admin_anonymize_member + anonymize_inactive_members to drop offboarding free-text clear)
--   DROP FUNCTION IF EXISTS public.record_offboarding_interview(uuid, text, text, boolean, text, text, text, boolean, text[]);
--   DROP FUNCTION IF EXISTS public.get_member_offboarding_record(uuid);
--   DROP FUNCTION IF EXISTS public.list_offboarding_records(text, timestamptz, timestamptz, int);
--   DROP FUNCTION IF EXISTS public.get_offboarding_dashboard();

-- ============================================================
-- 1. Invariant L_offboarding_record_present
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_schema_invariants()
RETURNS TABLE(invariant_name text, description text, severity text, violation_count integer, sample_ids uuid[])
LANGUAGE plpgsql
SECURITY DEFINER
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
    WHERE member_status = 'alumni'
      AND operational_role IS DISTINCT FROM 'alumni'
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'A1_alumni_role_consistency'::text,
         'member_status=alumni must coerce operational_role=alumni (B7 trigger)'::text,
         'high'::text,
         COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'observer'
      AND operational_role NOT IN ('observer', 'guest', 'none')
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'A2_observer_role_consistency'::text,
         'member_status=observer must coerce operational_role IN (observer,guest,none) (B7 trigger)'::text,
         'high'::text,
         COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH computed AS (
    SELECT m.id AS member_id,
      CASE
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'leader')         THEN 'tribe_leader'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'comms_leader')   THEN 'tribe_leader'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator')) THEN 'researcher'
        WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
        WHEN bool_or(ae.kind = 'observer')      THEN 'observer'
        WHEN bool_or(ae.kind = 'alumni')        THEN 'alumni'
        WHEN bool_or(ae.kind = 'sponsor')       THEN 'sponsor'
        WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
        WHEN bool_or(ae.kind = 'candidate')     THEN 'candidate'
        ELSE 'guest'
      END AS expected_role
    FROM public.members m
    LEFT JOIN public.auth_engagements ae
      ON ae.person_id = m.person_id AND ae.is_authoritative = true
    WHERE m.member_status = 'active'
      AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
    GROUP BY m.id
  ),
  drift AS (
    SELECT c.member_id FROM computed c
    JOIN public.members m ON m.id = c.member_id
    WHERE m.operational_role IS DISTINCT FROM c.expected_role
  )
  SELECT 'A3_active_role_engagement_derivation'::text,
         'active member operational_role must equal priority-ladder derivation from active engagements (cache trigger)'::text,
         'high'::text,
         COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE ((member_status = 'active' AND is_active = false)
        OR (member_status IN ('observer','alumni','inactive') AND is_active = true))
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'B_is_active_status_mismatch'::text,
         'members.is_active must match member_status mapping (active=true, terminal=false)'::text,
         'low'::text,
         COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive')
      AND designations IS NOT NULL
      AND array_length(designations, 1) > 0
  )
  SELECT 'C_designations_in_terminal_status'::text,
         'members.designations must be empty when member_status is observer/alumni/inactive'::text,
         'low'::text,
         COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    JOIN public.persons p ON p.id = m.person_id
    WHERE m.auth_id IS NOT NULL AND p.auth_id IS NOT NULL
      AND m.auth_id IS DISTINCT FROM p.auth_id
  )
  SELECT 'D_auth_id_mismatch_person_member'::text,
         'persons.auth_id and members.auth_id must agree when both are set (ghost resolution sync)'::text,
         'medium'::text,
         COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ae.engagement_id AS e_id FROM public.auth_engagements ae
    JOIN public.members m ON m.person_id = ae.person_id
    WHERE ae.status = 'active'
      AND m.member_status IN ('observer','alumni','inactive')
      AND ae.kind NOT IN ('observer','alumni','external_signer','sponsor','chapter_board','partner_contact')
  )
  SELECT 'E_engagement_active_with_terminal_member'::text,
         'engagement.status=active is inconsistent with member.member_status in (observer/alumni/inactive) unless kind matches'::text,
         'high'::text,
         COUNT(*)::integer,
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
         'low'::text,
         COUNT(*)::integer,
         (SELECT array_agg(initiative_id ORDER BY initiative_id) FROM (SELECT initiative_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
    WHERE gd.current_version_id IS NOT NULL
      AND (dv.id IS NULL OR dv.locked_at IS NULL)
  )
  SELECT 'J_current_version_published'::text,
         'governance_documents.current_version_id must point to a document_versions row with locked_at IS NOT NULL (Phase IP-1).'::text,
         'high'::text,
         COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.operational_role = 'external_signer'
      AND NOT EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id = m.person_id AND ae.kind = 'external_signer'
          AND ae.status = 'active' AND ae.is_authoritative = true
      )
  )
  SELECT 'K_external_signer_integrity'::text,
         'members.operational_role=external_signer must have an active auth_engagements row with kind=external_signer (Phase IP-1).'::text,
         'high'::text,
         COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- L_offboarding_record_present (#91 G3): every offboarded member must have a stub record
  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.member_status IN ('alumni','observer','inactive')
      AND m.anonymized_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.member_offboarding_records r WHERE r.member_id = m.id
      )
  )
  SELECT 'L_offboarding_record_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have a member_offboarding_records row (#91 G3 trigger).'::text,
         'high'::text,
         COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

END;
$function$;

-- ============================================================
-- 2. Anonymize: clear offboarding free-text (LGPD Art. 16)
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_anonymize_member(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_target_email text;
  v_target_name text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members
  WHERE auth_id = auth.uid() AND is_superadmin = true;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: only superadmin can anonymize members';
  END IF;

  -- ADR-0011 defense-in-depth: also require manage_member action
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: superadmin must also have manage_member engagement';
  END IF;

  SELECT email, name INTO v_target_email, v_target_name
  FROM public.members WHERE id = p_member_id;

  IF v_target_email IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  UPDATE public.members SET
    name           = 'Membro Anonimizado #' || SUBSTR(p_member_id::text, 1, 8),
    email          = 'anon_' || SUBSTR(p_member_id::text, 1, 8) || '@removed.local',
    phone          = NULL,
    phone_encrypted = NULL,
    pmi_id         = NULL,
    pmi_id_encrypted = NULL,
    linkedin_url   = NULL,
    photo_url      = NULL,
    credly_url     = NULL,
    credly_badges  = NULL,
    address        = NULL,
    city           = NULL,
    birth_date     = NULL,
    state          = NULL,
    country        = NULL,
    signature_url  = NULL,
    secondary_emails = NULL,
    last_active_pages = NULL,
    auth_id        = NULL,
    secondary_auth_ids = NULL,
    is_active      = false,
    member_status  = 'archived',
    anonymized_at  = now(),
    anonymized_by  = v_caller_id,
    updated_at     = now()
  WHERE id = p_member_id;

  -- LGPD Art. 16 — clear free-text PII from offboarding record (preserve aggregate cols)
  UPDATE public.member_offboarding_records SET
    reason_detail              = NULL,
    exit_interview_full_text   = NULL,
    return_window_suggestion   = NULL,
    lessons_learned            = NULL,
    recommendation_for_future  = NULL,
    attachment_urls            = '{}'::text[],
    updated_at                 = now()
  WHERE member_id = p_member_id;

  DELETE FROM public.notifications WHERE member_id = p_member_id;
  DELETE FROM public.notification_preferences WHERE member_id = p_member_id;

  UPDATE public.selection_applications SET
    applicant_name    = 'Candidato Anonimizado',
    email             = 'anon@removed.local',
    phone             = NULL,
    linkedin_url      = NULL,
    resume_url        = NULL,
    motivation_letter = NULL
  WHERE email = v_target_email;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'lgpd_manual_anonymization', 'member', p_member_id,
    jsonb_build_object(
      'anonymized_at', now(),
      'original_name_hash', md5(COALESCE(v_target_name, '')),
      'legal_basis', 'LGPD Lei 13.709/2018 Art. 18 — manual admin anonymization',
      'offboarding_record_cleared', true
    ));

  RETURN jsonb_build_object('anonymized', true, 'member_id', p_member_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.anonymize_inactive_members(
  p_dry_run boolean DEFAULT true,
  p_years int DEFAULT 5,
  p_limit int DEFAULT 500
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_candidate record;
  v_count int := 0;
  v_skipped int := 0;
  v_ids uuid[] := '{}';
  v_errors jsonb := '[]'::jsonb;
BEGIN
  FOR v_candidate IN
    SELECT * FROM public.list_anonymization_candidates(p_years) LIMIT p_limit
  LOOP
    BEGIN
      IF NOT p_dry_run THEN
        UPDATE public.members SET
          name           = 'Membro Anonimizado #' || SUBSTR(v_candidate.member_id::text, 1, 8),
          email          = 'anon_' || SUBSTR(v_candidate.member_id::text, 1, 8) || '@removed.local',
          phone          = NULL,
          phone_encrypted = NULL,
          pmi_id         = NULL,
          pmi_id_encrypted = NULL,
          linkedin_url   = NULL,
          photo_url      = NULL,
          credly_url     = NULL,
          credly_badges  = NULL,
          address        = NULL,
          city           = NULL,
          birth_date     = NULL,
          state          = NULL,
          country        = NULL,
          signature_url  = NULL,
          secondary_emails = NULL,
          last_active_pages = NULL,
          auth_id        = NULL,
          secondary_auth_ids = NULL,
          is_active      = false,
          member_status  = 'archived',
          anonymized_at  = now(),
          anonymized_by  = NULL,
          updated_at     = now()
        WHERE id = v_candidate.member_id;

        -- LGPD Art. 16 — clear free-text PII from offboarding record
        UPDATE public.member_offboarding_records SET
          reason_detail              = NULL,
          exit_interview_full_text   = NULL,
          return_window_suggestion   = NULL,
          lessons_learned            = NULL,
          recommendation_for_future  = NULL,
          attachment_urls            = '{}'::text[],
          updated_at                 = now()
        WHERE member_id = v_candidate.member_id;

        DELETE FROM public.notifications WHERE member_id = v_candidate.member_id;
        DELETE FROM public.notification_preferences WHERE member_id = v_candidate.member_id;

        UPDATE public.selection_applications SET
          applicant_name    = 'Candidato Anonimizado',
          email             = 'anon@removed.local',
          phone             = NULL,
          linkedin_url      = NULL,
          resume_url        = NULL,
          motivation_letter = NULL
        WHERE email = v_candidate.email;

        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
        VALUES (NULL, 'lgpd_automated_anonymization', 'member', v_candidate.member_id,
          jsonb_build_object(
            'anonymized_at', now(),
            'years_inactive', v_candidate.years_inactive,
            'inactivity_anchor', v_candidate.inactivity_anchor,
            'retention_years', p_years,
            'legal_basis', 'LGPD Lei 13.709/2018 Art. 16 — retention limit reached',
            'source', 'cron:anonymize_inactive_members',
            'offboarding_record_cleared', true
          ));
      END IF;

      v_count := v_count + 1;
      v_ids := array_append(v_ids, v_candidate.member_id);
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object(
        'member_id', v_candidate.member_id,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'years_threshold', p_years,
    'processed', v_count,
    'skipped', v_skipped,
    'member_ids', to_jsonb(v_ids),
    'errors', v_errors,
    'executed_at', now()
  );
END;
$$;

-- ============================================================
-- 3. RPC — record_offboarding_interview (admin enriches stub)
-- ============================================================
CREATE OR REPLACE FUNCTION public.record_offboarding_interview(
  p_member_id                  uuid,
  p_exit_interview_full_text   text DEFAULT NULL,
  p_exit_interview_source      text DEFAULT NULL,
  p_return_interest            boolean DEFAULT NULL,
  p_return_window_suggestion   text DEFAULT NULL,
  p_lessons_learned            text DEFAULT NULL,
  p_recommendation_for_future  text DEFAULT NULL,
  p_referred_by_tribe_leader   boolean DEFAULT NULL,
  p_attachment_urls            text[] DEFAULT NULL,
  p_reason_category_code       text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_record_id uuid;
  v_can_manage boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  SELECT public.can_by_member(v_caller_id, 'manage_member') INTO v_can_manage;
  IF NOT v_can_manage THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member action';
  END IF;

  -- Validate optional source enum
  IF p_exit_interview_source IS NOT NULL
     AND p_exit_interview_source NOT IN ('whatsapp','email','verbal','google_form','other') THEN
    RAISE EXCEPTION 'Invalid exit_interview_source: must be whatsapp|email|verbal|google_form|other';
  END IF;

  -- Validate optional category
  IF p_reason_category_code IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.offboard_reason_categories WHERE code = p_reason_category_code) THEN
    RAISE EXCEPTION 'Invalid reason_category_code: not in offboard_reason_categories';
  END IF;

  UPDATE public.member_offboarding_records SET
    exit_interview_full_text   = COALESCE(p_exit_interview_full_text, exit_interview_full_text),
    exit_interview_source      = COALESCE(p_exit_interview_source, exit_interview_source),
    return_interest            = COALESCE(p_return_interest, return_interest),
    return_window_suggestion   = COALESCE(p_return_window_suggestion, return_window_suggestion),
    lessons_learned            = COALESCE(p_lessons_learned, lessons_learned),
    recommendation_for_future  = COALESCE(p_recommendation_for_future, recommendation_for_future),
    referred_by_tribe_leader   = COALESCE(p_referred_by_tribe_leader, referred_by_tribe_leader),
    attachment_urls            = COALESCE(p_attachment_urls, attachment_urls),
    reason_category_code       = COALESCE(p_reason_category_code, reason_category_code),
    updated_at                 = now()
  WHERE member_id = p_member_id
  RETURNING id INTO v_record_id;

  IF v_record_id IS NULL THEN
    RAISE EXCEPTION 'Offboarding record not found for member_id %', p_member_id;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'offboarding.interview_updated', 'member', p_member_id,
    jsonb_build_object(
      'record_id', v_record_id,
      'fields_set', jsonb_build_object(
        'exit_interview_full_text', p_exit_interview_full_text IS NOT NULL,
        'exit_interview_source',    p_exit_interview_source IS NOT NULL,
        'return_interest',          p_return_interest IS NOT NULL,
        'return_window_suggestion', p_return_window_suggestion IS NOT NULL,
        'lessons_learned',          p_lessons_learned IS NOT NULL,
        'recommendation_for_future',p_recommendation_for_future IS NOT NULL,
        'referred_by_tribe_leader', p_referred_by_tribe_leader IS NOT NULL,
        'attachment_urls',          p_attachment_urls IS NOT NULL,
        'reason_category_code',     p_reason_category_code IS NOT NULL
      )
    ));

  RETURN jsonb_build_object('updated', true, 'record_id', v_record_id, 'member_id', p_member_id);
END;
$$;

COMMENT ON FUNCTION public.record_offboarding_interview(uuid, text, text, boolean, text, text, text, boolean, text[], text) IS
  '#91 G3 — admin updates rich exit interview content for an offboarded member. Coalesces NULLs to preserve existing values. Requires can_by_member(manage_member). Logs to admin_audit_log.';

-- ============================================================
-- 4. RPC — get_member_offboarding_record
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_member_offboarding_record(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_can_view boolean;
  v_record   public.member_offboarding_records%ROWTYPE;
  v_member   record;
  v_category record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  SELECT * INTO v_record FROM public.member_offboarding_records WHERE member_id = p_member_id;
  IF v_record.id IS NULL THEN
    RETURN jsonb_build_object('found', false, 'member_id', p_member_id);
  END IF;

  -- Privacy gate: superadmin OR self OR offboarded_by OR manage_member
  v_can_view :=
    EXISTS (SELECT 1 FROM public.members WHERE id = v_caller_id AND is_superadmin = true)
    OR (v_record.member_id = v_caller_id)
    OR (v_record.offboarded_by = v_caller_id)
    OR public.can_by_member(v_caller_id, 'manage_member');

  IF NOT v_can_view THEN
    RAISE EXCEPTION 'Unauthorized: cannot view this offboarding record';
  END IF;

  SELECT id, name, chapter, member_status, operational_role
  INTO v_member FROM public.members WHERE id = p_member_id;

  IF v_record.reason_category_code IS NOT NULL THEN
    SELECT code, label_pt, label_en, is_volunteer_fault, preserves_return_eligibility
    INTO v_category FROM public.offboard_reason_categories
    WHERE code = v_record.reason_category_code;
  END IF;

  RETURN jsonb_build_object(
    'found', true,
    'record', jsonb_build_object(
      'id', v_record.id,
      'member_id', v_record.member_id,
      'offboarded_at', v_record.offboarded_at,
      'offboarded_by', v_record.offboarded_by,
      'reason_category_code', v_record.reason_category_code,
      'reason_category_label_pt', v_category.label_pt,
      'reason_detail', v_record.reason_detail,
      'exit_interview_full_text', v_record.exit_interview_full_text,
      'exit_interview_source', v_record.exit_interview_source,
      'return_interest', v_record.return_interest,
      'return_window_suggestion', v_record.return_window_suggestion,
      'tribe_id_at_offboard', v_record.tribe_id_at_offboard,
      'chapter_at_offboard', v_record.chapter_at_offboard,
      'cycle_code_at_offboard', v_record.cycle_code_at_offboard,
      'lessons_learned', v_record.lessons_learned,
      'recommendation_for_future', v_record.recommendation_for_future,
      'referred_by_tribe_leader', v_record.referred_by_tribe_leader,
      'attachment_urls', to_jsonb(v_record.attachment_urls),
      'created_at', v_record.created_at,
      'updated_at', v_record.updated_at
    ),
    'member', jsonb_build_object(
      'id', v_member.id,
      'name', v_member.name,
      'chapter', v_member.chapter,
      'member_status', v_member.member_status,
      'operational_role', v_member.operational_role
    )
  );
END;
$$;

COMMENT ON FUNCTION public.get_member_offboarding_record(uuid) IS
  '#91 G3 — single offboarding record + member context. RLS-mirroring privacy gate (superadmin OR self OR offboarded_by OR manage_member).';

-- ============================================================
-- 5. RPC — list_offboarding_records (admin/DPO scan)
-- ============================================================
CREATE OR REPLACE FUNCTION public.list_offboarding_records(
  p_reason_category text DEFAULT NULL,
  p_since           timestamptz DEFAULT NULL,
  p_until           timestamptz DEFAULT NULL,
  p_limit           int DEFAULT 50
)
RETURNS TABLE (
  record_id                 uuid,
  member_id                 uuid,
  member_name               text,
  member_chapter            text,
  member_status             text,
  offboarded_at             timestamptz,
  offboarded_by             uuid,
  reason_category_code      text,
  reason_category_label_pt  text,
  has_full_interview        boolean,
  return_interest           boolean,
  tribe_id_at_offboard      integer,
  cycle_code_at_offboard    text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member action';
  END IF;

  RETURN QUERY
  SELECT
    r.id AS record_id,
    r.member_id,
    m.name AS member_name,
    m.chapter AS member_chapter,
    m.member_status,
    r.offboarded_at,
    r.offboarded_by,
    r.reason_category_code,
    c.label_pt AS reason_category_label_pt,
    (r.exit_interview_full_text IS NOT NULL) AS has_full_interview,
    r.return_interest,
    r.tribe_id_at_offboard,
    r.cycle_code_at_offboard
  FROM public.member_offboarding_records r
  JOIN public.members m ON m.id = r.member_id
  LEFT JOIN public.offboard_reason_categories c ON c.code = r.reason_category_code
  WHERE (p_reason_category IS NULL OR r.reason_category_code = p_reason_category)
    AND (p_since IS NULL OR r.offboarded_at >= p_since)
    AND (p_until IS NULL OR r.offboarded_at <= p_until)
  ORDER BY r.offboarded_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 500));
END;
$$;

COMMENT ON FUNCTION public.list_offboarding_records(text, timestamptz, timestamptz, int) IS
  '#91 G3 — admin scan of offboarding records. Filters by category + date range. Excludes free-text fields (use get_member_offboarding_record for detail). Requires manage_member.';

-- ============================================================
-- 6. RPC — get_offboarding_dashboard (analytics)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_offboarding_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_total int;
  v_with_interview int;
  v_return_interest int;
  v_by_category jsonb;
  v_by_chapter jsonb;
  v_by_cycle jsonb;
  v_recent jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member action';
  END IF;

  SELECT
    count(*),
    count(*) FILTER (WHERE exit_interview_full_text IS NOT NULL),
    count(*) FILTER (WHERE return_interest = true)
  INTO v_total, v_with_interview, v_return_interest
  FROM public.member_offboarding_records;

  SELECT jsonb_agg(jsonb_build_object(
    'reason_category_code', sub.reason_category_code,
    'reason_category_label_pt', sub.label_pt,
    'count', sub.cnt
  ) ORDER BY sub.cnt DESC, sub.reason_category_code)
  INTO v_by_category
  FROM (
    SELECT r.reason_category_code, c.label_pt, count(*)::int AS cnt
    FROM public.member_offboarding_records r
    LEFT JOIN public.offboard_reason_categories c ON c.code = r.reason_category_code
    GROUP BY r.reason_category_code, c.label_pt
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'chapter', sub.chapter,
    'count', sub.cnt
  ) ORDER BY sub.cnt DESC, sub.chapter)
  INTO v_by_chapter
  FROM (
    SELECT chapter_at_offboard AS chapter, count(*)::int AS cnt
    FROM public.member_offboarding_records
    WHERE chapter_at_offboard IS NOT NULL
    GROUP BY chapter_at_offboard
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'cycle_code', sub.cycle,
    'count', sub.cnt
  ) ORDER BY sub.cycle DESC NULLS LAST)
  INTO v_by_cycle
  FROM (
    SELECT cycle_code_at_offboard AS cycle, count(*)::int AS cnt
    FROM public.member_offboarding_records
    GROUP BY cycle_code_at_offboard
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'member_id', r.member_id,
    'member_name', m.name,
    'chapter', m.chapter,
    'offboarded_at', r.offboarded_at,
    'reason_category_code', r.reason_category_code,
    'has_full_interview', r.exit_interview_full_text IS NOT NULL
  ) ORDER BY r.offboarded_at DESC)
  INTO v_recent
  FROM public.member_offboarding_records r
  JOIN public.members m ON m.id = r.member_id
  WHERE r.offboarded_at >= now() - interval '90 days';

  RETURN jsonb_build_object(
    'total_records', v_total,
    'with_full_interview', v_with_interview,
    'with_return_interest', v_return_interest,
    'interview_completion_pct', ROUND(100.0 * v_with_interview / NULLIF(v_total, 0), 1),
    'by_reason_category', COALESCE(v_by_category, '[]'::jsonb),
    'by_chapter', COALESCE(v_by_chapter, '[]'::jsonb),
    'by_cycle', COALESCE(v_by_cycle, '[]'::jsonb),
    'recent_90d', COALESCE(v_recent, '[]'::jsonb),
    'generated_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.get_offboarding_dashboard() IS
  '#91 G3 — admin/DPO dashboard: totals + by category/chapter/cycle + last 90d. Requires manage_member.';

-- ============================================================
-- 7. Permissions (REVOKE PUBLIC; GRANT EXECUTE only via authenticated where appropriate)
-- ============================================================
REVOKE ALL ON FUNCTION public.record_offboarding_interview(uuid, text, text, boolean, text, text, text, boolean, text[], text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_member_offboarding_record(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_offboarding_records(text, timestamptz, timestamptz, int) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_offboarding_dashboard() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.record_offboarding_interview(uuid, text, text, boolean, text, text, text, boolean, text[], text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_member_offboarding_record(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_offboarding_records(text, timestamptz, timestamptz, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_offboarding_dashboard() TO authenticated;

NOTIFY pgrst, 'reload schema';
