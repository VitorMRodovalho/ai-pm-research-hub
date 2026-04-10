-- LGPD P3: Automated anonymization of inactive members (5+ years)
-- Legal basis: LGPD Art. 16 (dados pessoais devem ser eliminados após fim de tratamento)
-- Retention policy: 5 years of inactivity → PII is anonymized, aggregated contributions preserved
--
-- Contents:
--   1. Fix admin_anonymize_member (uses legacy column names full_name/avatar_url/bio)
--   2. list_anonymization_candidates — preview without side-effects
--   3. anonymize_inactive_members(p_dry_run, p_limit) — bulk anonymize eligible members
--   4. pg_cron job: monthly at 03:30 on day 1

-- ============================================================
-- 1. Fix admin_anonymize_member (legacy columns)
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

  -- Anonymize PII but preserve aggregate data (cycles, designations, contributions)
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

  -- Purge personal notifications + preferences
  DELETE FROM public.notifications WHERE member_id = p_member_id;
  DELETE FROM public.notification_preferences WHERE member_id = p_member_id;

  -- Anonymize selection applications linked by email
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
      'legal_basis', 'LGPD Lei 13.709/2018 Art. 18 — manual admin anonymization'
    ));

  RETURN jsonb_build_object('anonymized', true, 'member_id', p_member_id);
END;
$$;

-- ============================================================
-- 2. list_anonymization_candidates — dry-run preview
-- ============================================================
CREATE OR REPLACE FUNCTION public.list_anonymization_candidates(
  p_years int DEFAULT 5
)
RETURNS TABLE (
  member_id uuid,
  name text,
  email text,
  chapter text,
  last_seen_at timestamptz,
  updated_at timestamptz,
  inactivated_at timestamptz,
  offboarded_at timestamptz,
  inactivity_anchor timestamptz,
  years_inactive numeric
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT
    m.id,
    m.name,
    m.email,
    m.chapter,
    m.last_seen_at,
    m.updated_at,
    m.inactivated_at,
    m.offboarded_at,
    GREATEST(
      COALESCE(m.last_seen_at, 'epoch'::timestamptz),
      COALESCE(m.updated_at, 'epoch'::timestamptz),
      COALESCE(m.inactivated_at, 'epoch'::timestamptz),
      COALESCE(m.offboarded_at, 'epoch'::timestamptz),
      COALESCE(m.created_at, 'epoch'::timestamptz)
    ) AS inactivity_anchor,
    ROUND(
      EXTRACT(EPOCH FROM (now() - GREATEST(
        COALESCE(m.last_seen_at, 'epoch'::timestamptz),
        COALESCE(m.updated_at, 'epoch'::timestamptz),
        COALESCE(m.inactivated_at, 'epoch'::timestamptz),
        COALESCE(m.offboarded_at, 'epoch'::timestamptz),
        COALESCE(m.created_at, 'epoch'::timestamptz)
      ))) / 31557600.0
    , 2) AS years_inactive
  FROM public.members m
  WHERE m.anonymized_at IS NULL
    AND COALESCE(m.is_superadmin, false) = false
    AND COALESCE(m.current_cycle_active, false) = false
    AND COALESCE(m.is_active, false) = false
    AND GREATEST(
      COALESCE(m.last_seen_at, 'epoch'::timestamptz),
      COALESCE(m.updated_at, 'epoch'::timestamptz),
      COALESCE(m.inactivated_at, 'epoch'::timestamptz),
      COALESCE(m.offboarded_at, 'epoch'::timestamptz),
      COALESCE(m.created_at, 'epoch'::timestamptz)
    ) < (now() - make_interval(years => p_years))
  ORDER BY inactivity_anchor ASC;
$$;

REVOKE ALL ON FUNCTION public.list_anonymization_candidates(int) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_anonymization_candidates(int) TO service_role;

-- ============================================================
-- 3. anonymize_inactive_members — bulk job
-- ============================================================
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
          anonymized_by  = NULL,  -- NULL = automated
          updated_at     = now()
        WHERE id = v_candidate.member_id;

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
            'source', 'cron:anonymize_inactive_members'
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

REVOKE ALL ON FUNCTION public.anonymize_inactive_members(boolean, int, int) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymize_inactive_members(boolean, int, int) TO service_role;

-- ============================================================
-- 4. pg_cron: monthly, day 1, 03:30 UTC
-- ============================================================
SELECT cron.unschedule('lgpd-anonymize-inactive-monthly')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'lgpd-anonymize-inactive-monthly');

SELECT cron.schedule(
  'lgpd-anonymize-inactive-monthly',
  '30 3 1 * *',
  $cron$SELECT public.anonymize_inactive_members(p_dry_run := false, p_years := 5, p_limit := 500);$cron$
);

COMMENT ON FUNCTION public.anonymize_inactive_members(boolean, int, int) IS
  'LGPD Art. 16: automated anonymization of members with 5+ years of inactivity. Preserves aggregated contributions, removes PII. Runs monthly via pg_cron.';

COMMENT ON FUNCTION public.list_anonymization_candidates(int) IS
  'LGPD: preview members eligible for anonymization. No side effects. Service role only.';

NOTIFY pgrst, 'reload schema';
