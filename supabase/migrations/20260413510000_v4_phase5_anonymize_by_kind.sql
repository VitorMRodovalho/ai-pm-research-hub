-- ============================================================================
-- V4 Phase 5 — Migration 2/3: Kind-aware anonymization
-- ADR: ADR-0008 (Per-Kind Engagement Lifecycle with Explicit LGPD Basis)
-- Rollback: DROP FUNCTION public.anonymize_by_engagement_kind(boolean, int);
--           (legacy anonymize_inactive_members still works as fallback)
-- ============================================================================

-- Ensure persons has anonymized_at column
ALTER TABLE public.persons ADD COLUMN IF NOT EXISTS anonymized_at timestamptz;
COMMENT ON COLUMN public.persons.anonymized_at IS 'V4/ADR-0008: When person PII was anonymized';
CREATE INDEX IF NOT EXISTS idx_persons_anonymized ON public.persons(anonymized_at) WHERE anonymized_at IS NULL;

-- V4 anonymization: iterates engagement_kinds, uses retention_days_after_end
-- and anonymization_policy per kind. Replaces the global 5-year hardcode.
--
-- Logic per engagement:
--   1. Find offboarded/expired engagements where (end_date + retention) < now()
--   2. If ALL engagements for a person are past retention → anonymize the person
--   3. Policy: 'anonymize' scrubs PII, 'delete' removes person, 'retain_for_legal' skips
--
-- The legacy anonymize_inactive_members() remains as backup for members
-- without engagements (pre-V4 data). Both can coexist.

CREATE OR REPLACE FUNCTION public.anonymize_by_engagement_kind(
  p_dry_run boolean DEFAULT true,
  p_limit int DEFAULT 500
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_person record;
  v_count int := 0;
  v_skipped int := 0;
  v_results jsonb := '[]'::jsonb;
  v_errors jsonb := '[]'::jsonb;
  v_has_active boolean;
  v_strictest_policy text;
BEGIN
  -- Find persons where ALL engagements are past retention
  FOR v_person IN
    SELECT
      p.id AS person_id,
      p.name AS person_name,
      p.legacy_member_id,
      -- The "strictest" policy wins: retain_for_legal > anonymize > delete
      CASE
        WHEN bool_or(ek.anonymization_policy = 'retain_for_legal') THEN 'retain_for_legal'
        WHEN bool_or(ek.anonymization_policy = 'anonymize') THEN 'anonymize'
        ELSE 'delete'
      END AS effective_policy,
      max(e.end_date + make_interval(days => COALESCE(ek.retention_days_after_end, 1825))) AS latest_retention_end,
      count(*) AS engagement_count
    FROM public.persons p
    JOIN public.engagements e ON e.person_id = p.id
    JOIN public.engagement_kinds ek ON ek.slug = e.kind
    WHERE p.anonymized_at IS NULL
      AND e.status IN ('offboarded', 'expired')
      AND e.end_date IS NOT NULL
      AND (e.end_date + make_interval(days => COALESCE(ek.retention_days_after_end, 1825))) < CURRENT_DATE
    GROUP BY p.id, p.name, p.legacy_member_id
    -- Only if NO active/suspended engagements remain
    HAVING NOT EXISTS (
      SELECT 1 FROM public.engagements e2
      WHERE e2.person_id = p.id AND e2.status IN ('active', 'suspended')
    )
    ORDER BY max(e.end_date) ASC
    LIMIT p_limit
  LOOP
    BEGIN
      v_strictest_policy := v_person.effective_policy;

      IF v_strictest_policy = 'retain_for_legal' THEN
        v_skipped := v_skipped + 1;
        v_results := v_results || jsonb_build_object(
          'person_id', v_person.person_id,
          'action', 'retained',
          'reason', 'retain_for_legal policy'
        );
        CONTINUE;
      END IF;

      IF NOT p_dry_run THEN
        -- Anonymize person record
        UPDATE public.persons SET
          name = 'Pessoa Anonimizada #' || SUBSTR(v_person.person_id::text, 1, 8),
          email = 'anon_' || SUBSTR(v_person.person_id::text, 1, 8) || '@removed.local',
          auth_id = NULL,
          anonymized_at = now()
        WHERE id = v_person.person_id;

        -- Anonymize legacy member if exists
        IF v_person.legacy_member_id IS NOT NULL THEN
          UPDATE public.members SET
            name           = 'Membro Anonimizado #' || SUBSTR(v_person.legacy_member_id::text, 1, 8),
            email          = 'anon_' || SUBSTR(v_person.legacy_member_id::text, 1, 8) || '@removed.local',
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
          WHERE id = v_person.legacy_member_id;

          DELETE FROM public.notifications WHERE member_id = v_person.legacy_member_id;
          DELETE FROM public.notification_preferences WHERE member_id = v_person.legacy_member_id;
        END IF;

        -- Mark all engagements as anonymized
        UPDATE public.engagements SET
          status = 'anonymized',
          updated_at = now()
        WHERE person_id = v_person.person_id;

        -- If policy is 'delete' and no legal hold, hard-delete person
        -- (engagement FK ON DELETE CASCADE handles engagements)
        IF v_strictest_policy = 'delete' THEN
          DELETE FROM public.persons WHERE id = v_person.person_id;
        END IF;

        -- Audit trail
        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
        VALUES (NULL, 'lgpd_v4_anonymization', 'person', v_person.person_id,
          jsonb_build_object(
            'policy', v_strictest_policy,
            'engagement_count', v_person.engagement_count,
            'retention_end', v_person.latest_retention_end,
            'legacy_member_id', v_person.legacy_member_id,
            'legal_basis', 'LGPD Art. 16 — retention limit per engagement_kind (ADR-0008)',
            'source', 'cron:anonymize_by_engagement_kind'
          ));
      END IF;

      v_count := v_count + 1;
      v_results := v_results || jsonb_build_object(
        'person_id', v_person.person_id,
        'action', v_strictest_policy,
        'retention_end', v_person.latest_retention_end,
        'engagements', v_person.engagement_count
      );

    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object(
        'person_id', v_person.person_id,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'processed', v_count,
    'skipped', v_skipped,
    'results', v_results,
    'errors', v_errors,
    'executed_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.anonymize_by_engagement_kind(boolean, int) IS
  'V4/ADR-0008: Kind-aware anonymization. Uses retention_days_after_end and anonymization_policy per engagement_kind. Coexists with legacy anonymize_inactive_members().';

REVOKE ALL ON FUNCTION public.anonymize_by_engagement_kind(boolean, int) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymize_by_engagement_kind(boolean, int) TO service_role;

-- Schedule monthly (same window as legacy, 15 min after)
SELECT cron.schedule(
  'v4-anonymize-by-kind-monthly',
  '45 3 1 * *',
  $cron$SELECT public.anonymize_by_engagement_kind(p_dry_run := false, p_limit := 500);$cron$
);

NOTIFY pgrst, 'reload schema';
