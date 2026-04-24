-- Migration: #91 G3 — member_offboarding_records (rich exit interview capture)
-- Issue: status_change_reason é curto demais para capturar exit interview rico (ex.
--        Lorena com 102 chars, Lídia com 178 chars + áudios WhatsApp pendentes).
--        Sem estrutura analítica para "quantos alumni por motivo? quantos querem voltar?".
--
-- Schema:
--   member_offboarding_records (15 fields, 1:1 com members terminal-status)
--   - 5 decisões PM aprovadas (2026-04-25 p45):
--     1. Auto-stub trigger (cria row no offboard, nunca perde metadata)
--     2. RLS: superadmin OR offboarded_by OR member_self pode ler exit_interview_full_text
--     3. Backfill 23 offboards existentes (offboarded_at + offboarded_by + reason; full_text NULL)
--     4. LGPD anonymization 5y limpa free-text (Art. 16)
--     5. Invariant L_offboarding_record_present (toda transition→terminal deve ter row)
--
-- Rollback:
--   DROP TRIGGER IF EXISTS trg_offboarding_stub ON public.members;
--   DROP FUNCTION IF EXISTS public._offboarding_create_stub();
--   DROP TABLE IF EXISTS public.member_offboarding_records;
--   (revert check_schema_invariants to drop L_offboarding_record_present)
--   (revert admin_anonymize_member + anonymize_inactive_members to drop offboarding free-text clear)

-- ============================================================
-- 1. Table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.member_offboarding_records (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id                   uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  offboarded_at               timestamptz NOT NULL,
  offboarded_by               uuid REFERENCES public.members(id) ON DELETE SET NULL,

  reason_category_code        text REFERENCES public.offboard_reason_categories(code),
  reason_detail               text,

  exit_interview_full_text    text,
  exit_interview_source       text CHECK (exit_interview_source IN
                                 ('whatsapp','email','verbal','google_form','other')),

  return_interest             boolean,
  return_window_suggestion    text,

  tribe_id_at_offboard        integer,
  chapter_at_offboard         text,
  cycle_code_at_offboard      text,

  lessons_learned             text,
  recommendation_for_future   text,
  referred_by_tribe_leader    boolean,
  attachment_urls             text[] DEFAULT '{}'::text[],

  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT member_offboarding_records_member_id_unique UNIQUE (member_id)
);

CREATE INDEX IF NOT EXISTS member_offboarding_records_offboarded_at_idx
  ON public.member_offboarding_records (offboarded_at DESC);
CREATE INDEX IF NOT EXISTS member_offboarding_records_reason_category_idx
  ON public.member_offboarding_records (reason_category_code)
  WHERE reason_category_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS member_offboarding_records_return_interest_idx
  ON public.member_offboarding_records (return_interest)
  WHERE return_interest = true;

COMMENT ON TABLE public.member_offboarding_records IS
  '#91 G3 — rich exit interview capture (1:1 with members terminal-status). Auto-stubbed by trigger; admin enriches with interview content via record_offboarding_interview RPC.';

-- ============================================================
-- 2. updated_at trigger
-- ============================================================
CREATE OR REPLACE FUNCTION public._offboarding_records_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = 'public', 'pg_temp'
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_offboarding_records_updated_at ON public.member_offboarding_records;
CREATE TRIGGER trg_offboarding_records_updated_at
BEFORE UPDATE ON public.member_offboarding_records
FOR EACH ROW
EXECUTE FUNCTION public._offboarding_records_set_updated_at();

-- ============================================================
-- 3. RLS — superadmin OR offboarded_by OR member_self can read full text;
--          superadmin OR manage_member can write
-- ============================================================
ALTER TABLE public.member_offboarding_records ENABLE ROW LEVEL SECURITY;

-- SELECT: privacy-tiered
DROP POLICY IF EXISTS "offboarding_records_select_authorized" ON public.member_offboarding_records;
CREATE POLICY "offboarding_records_select_authorized"
ON public.member_offboarding_records
FOR SELECT
TO authenticated
USING (
  -- superadmin
  EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.auth_id = auth.uid() AND m.is_superadmin = true
  )
  -- self
  OR EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.id = member_offboarding_records.member_id AND m.auth_id = auth.uid()
  )
  -- offboarded_by (the admin who registered the offboard)
  OR EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.id = member_offboarding_records.offboarded_by AND m.auth_id = auth.uid()
  )
  -- manage_member authority (admin/GP/DM)
  OR public.rls_can('manage_member')
);

-- INSERT: only via trigger (service_role) or RPC with manage_member auth
DROP POLICY IF EXISTS "offboarding_records_insert_admin" ON public.member_offboarding_records;
CREATE POLICY "offboarding_records_insert_admin"
ON public.member_offboarding_records
FOR INSERT
TO authenticated
WITH CHECK (public.rls_can('manage_member'));

-- UPDATE: manage_member or self (member can update own return_interest etc.)
DROP POLICY IF EXISTS "offboarding_records_update_authorized" ON public.member_offboarding_records;
CREATE POLICY "offboarding_records_update_authorized"
ON public.member_offboarding_records
FOR UPDATE
TO authenticated
USING (
  public.rls_can('manage_member')
  OR EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.id = member_offboarding_records.member_id AND m.auth_id = auth.uid()
  )
)
WITH CHECK (
  public.rls_can('manage_member')
  OR EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.id = member_offboarding_records.member_id AND m.auth_id = auth.uid()
  )
);

-- DELETE: superadmin only (audit preservation)
DROP POLICY IF EXISTS "offboarding_records_delete_superadmin" ON public.member_offboarding_records;
CREATE POLICY "offboarding_records_delete_superadmin"
ON public.member_offboarding_records
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.auth_id = auth.uid() AND m.is_superadmin = true
  )
);

-- ============================================================
-- 4. Auto-stub trigger on member_status transition to terminal
-- ============================================================
CREATE OR REPLACE FUNCTION public._offboarding_create_stub()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_inferred_category text;
  v_reason_text       text;
  v_chapter           text;
  v_cycle_code        text;
BEGIN
  -- Defense-in-depth: only stub when entering terminal status
  IF NEW.member_status NOT IN ('alumni','observer','inactive') THEN
    RETURN NEW;
  END IF;

  -- Skip if record already exists (admin path may have inserted via RPC first)
  IF EXISTS (
    SELECT 1 FROM public.member_offboarding_records
    WHERE member_id = NEW.id
  ) THEN
    RETURN NEW;
  END IF;

  -- Best-effort category inference from prefix pattern "category: detail"
  -- (admin_offboard_member RPC writes status_change_reason in this format)
  v_reason_text := COALESCE(NEW.status_change_reason, '');
  v_inferred_category := NULL;
  IF v_reason_text ~ '^[a-z_]+:\s' THEN
    v_inferred_category := SPLIT_PART(v_reason_text, ':', 1);
    -- Validate against known categories
    IF NOT EXISTS (
      SELECT 1 FROM public.offboard_reason_categories WHERE code = v_inferred_category
    ) THEN
      v_inferred_category := NULL;
    END IF;
  END IF;

  -- Snapshot chapter + cycle (denormalized for analytics survival on member edits)
  v_chapter := NEW.chapter;
  SELECT cycle_code INTO v_cycle_code
  FROM public.cycles
  WHERE is_current = true
  ORDER BY cycle_start DESC
  LIMIT 1;

  INSERT INTO public.member_offboarding_records (
    member_id,
    offboarded_at,
    offboarded_by,
    reason_category_code,
    reason_detail,
    tribe_id_at_offboard,
    chapter_at_offboard,
    cycle_code_at_offboard
  ) VALUES (
    NEW.id,
    COALESCE(NEW.offboarded_at, now()),
    NEW.offboarded_by,
    v_inferred_category,
    NULLIF(TRIM(v_reason_text), ''),
    NEW.tribe_id,
    v_chapter,
    v_cycle_code
  );

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public._offboarding_create_stub() IS
  '#91 G3 — auto-stub member_offboarding_records when member transitions to alumni/observer/inactive. Idempotent (skips if record exists). Best-effort category inference from status_change_reason prefix.';

DROP TRIGGER IF EXISTS trg_offboarding_stub ON public.members;
CREATE TRIGGER trg_offboarding_stub
AFTER UPDATE OF member_status ON public.members
FOR EACH ROW
WHEN (
  OLD.member_status IS DISTINCT FROM NEW.member_status
  AND NEW.member_status IN ('alumni','observer','inactive')
)
EXECUTE FUNCTION public._offboarding_create_stub();

COMMENT ON TRIGGER trg_offboarding_stub ON public.members IS
  '#91 G3 — auto-stub offboarding record on terminal status transition.';

-- ============================================================
-- 5. Backfill 23 existing offboards (idempotent, two-pass)
--    Pass 1: members with offboarded_at populated (recent, p41 tracked)
--    Pass 2: legacy alumni from 2026-03-24 batch cleanup (offboarded_at NULL,
--            uses audit_log timestamp as proxy)
-- ============================================================
WITH backfill_data AS (
  SELECT
    m.id AS member_id,
    m.offboarded_at,
    m.offboarded_by,
    (CASE
       WHEN m.status_change_reason ~ '^[a-z_]+:\s'
            AND EXISTS (
              SELECT 1 FROM public.offboard_reason_categories oc
              WHERE oc.code = SPLIT_PART(m.status_change_reason, ':', 1)
            )
       THEN SPLIT_PART(m.status_change_reason, ':', 1)
       ELSE NULL
     END) AS reason_category_code,
    NULLIF(TRIM(COALESCE(m.status_change_reason,'')), '') AS reason_detail,
    m.tribe_id AS tribe_id_at_offboard,
    m.chapter AS chapter_at_offboard
  FROM public.members m
  WHERE m.member_status IN ('alumni','observer','inactive')
    AND m.offboarded_at IS NOT NULL
    AND m.anonymized_at IS NULL
)
INSERT INTO public.member_offboarding_records (
  member_id, offboarded_at, offboarded_by,
  reason_category_code, reason_detail,
  tribe_id_at_offboard, chapter_at_offboard
)
SELECT
  bd.member_id, bd.offboarded_at, bd.offboarded_by,
  bd.reason_category_code, bd.reason_detail,
  bd.tribe_id_at_offboard, bd.chapter_at_offboard
FROM backfill_data bd
ON CONFLICT (member_id) DO NOTHING;

-- Pass 2: legacy (offboarded_at NULL → use audit_log timestamp proxy)
WITH legacy_offboards AS (
  SELECT
    m.id AS member_id,
    COALESCE(
      (SELECT max(a.created_at) FROM public.admin_audit_log a
        WHERE a.target_id = m.id AND a.action = 'member.status_transition'),
      m.updated_at,
      now()
    ) AS offboarded_at,
    NULL::uuid AS offboarded_by,
    NULL::text AS reason_category_code,
    NULLIF(TRIM(COALESCE(m.status_change_reason,'')), '') AS reason_detail,
    m.tribe_id AS tribe_id_at_offboard,
    m.chapter AS chapter_at_offboard
  FROM public.members m
  WHERE m.member_status IN ('alumni','observer','inactive')
    AND m.offboarded_at IS NULL
    AND m.anonymized_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.member_offboarding_records r WHERE r.member_id = m.id
    )
)
INSERT INTO public.member_offboarding_records (
  member_id, offboarded_at, offboarded_by,
  reason_category_code, reason_detail,
  tribe_id_at_offboard, chapter_at_offboard
)
SELECT * FROM legacy_offboards
ON CONFLICT (member_id) DO NOTHING;

-- ============================================================
-- 6. Invariant L_offboarding_record_present
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

  -- New invariant: every offboarded member must have a stub record (#91 G3)
  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.member_status IN ('alumni','observer','inactive')
      AND m.offboarded_at IS NOT NULL
      AND m.anonymized_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.member_offboarding_records r WHERE r.member_id = m.id
      )
  )
  SELECT 'L_offboarding_record_present'::text,
         'members in alumni/observer/inactive (offboarded_at NOT NULL, not anonymized) must have a member_offboarding_records row (#91 G3 trigger).'::text,
         'high'::text,
         COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

END;
$function$;

-- ============================================================
-- 7. Extend anonymization to clear offboarding free-text (LGPD Art. 16)
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

NOTIFY pgrst, 'reload schema';
