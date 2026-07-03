-- =====================================================================================
-- #996 — get_affiliation_verification_queue: enrich each queue row with the PMI identity
--        panel (F-A). SPEC: docs/specs/SPEC_996_FILIACAO_JOURNEY.md §4.1.
--
-- WHAT CHANGES (body-only CREATE OR REPLACE — signature/return type unchanged = jsonb):
--   The queue already surfaced pmi_memberships + vep_status_raw + vep_last_seen_at from the
--   latest matching selection_application (the same Phase B source the seleção PMI tab uses).
--   #996 adds a `pmi_profile` sub-object per row so the Diretoria de Filiação can decide from
--   the row without opening the seleção: PMI ID (string), member since/until (service_first/
--   latest dates — the "Membro desde/até" already shown in the PMI tab), number of PMI service
--   history entries (service_history_count), and last VEP sync (pmi_data_fetched_at). All come
--   from the SAME LATERAL already joined for VEP — no N+1, no new endpoint (SPEC §4.1 recommended
--   extending this RPC over a per-row get_application_pmi_profile call).
--
--   No new columns are surfaced beyond what the seleção PMI tab already exposes to the same
--   office; membership_status stays UNUSED (it is 100% NULL / dead — SPEC §6 caveat).
--
-- INVARIANTS PRESERVED (not re-litigated):
--   - Function-anchored gate: filiacao_director designation OR can_by_member(manage_member);
--     fail-closed on auth.uid() NULL. Read audience == write audience (security review M-1, #659).
--   - LGPD Art. 37 nominal-read trail via log_pii_access_batch — the pii field list now also names
--     'membership_dates' since member since/until are surfaced (honest trail).
--   - Hardened grants (REVOKE public/anon; GRANT authenticated/service_role).
--   - Cohort predicate unchanged (pre-onboarding OR unverified OR never-verified active members).
--
-- ROLLBACK: re-apply migration 20260805000155 (the pre-#996 body).
-- =====================================================================================
CREATE OR REPLACE FUNCTION public.get_affiliation_verification_queue()
RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_caller_designations text[];
  v_result              jsonb;
  v_member_ids          uuid[];
BEGIN
  -- Auth-resolve + function-anchored gate (mirror verify_member_affiliation, mig 148).
  SELECT m.id, m.designations INTO v_caller_id, v_caller_designations
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  -- Least-privilege: read audience == write audience (filiacao_director OR manage_member). A bulk
  -- cohort dump must NOT be wider than the write gate (security review M-1, #659).
  IF NOT ('filiacao_director' = ANY(COALESCE(v_caller_designations, '{}'::text[])))
     AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: requires filiacao_director designation or platform manager authority';
  END IF;

  WITH cohort AS (
    SELECT
      m.id  AS member_id,
      m.name,
      m.email,
      m.chapter,
      m.operational_role,
      m.pmi_id_verified,
      COALESCE(pre.flag, false)  AS is_pre_onboarding,
      vep.vep_status_raw,
      vep.vep_last_seen_at,
      vep.pmi_memberships,
      vep.pmi_id,
      vep.service_first_start_date,
      vep.service_latest_end_date,
      vep.service_history_count,
      vep.pmi_data_fetched_at,
      aff.created_at            AS aff_created_at,
      aff.membership_active     AS aff_membership_active,
      aff.membership_expires_on AS aff_membership_expires_on,
      aff.method                AS aff_method,
      aff.chapter_verified      AS aff_chapter_verified
    FROM public.members m
    -- VEP + PMI membership detail from the latest matching application (shape from admin_list_members).
    LEFT JOIN LATERAL (
      SELECT a.vep_status_raw, a.vep_last_seen_at, a.pmi_memberships,
             a.pmi_id, a.service_first_start_date, a.service_latest_end_date,
             a.service_history_count, a.pmi_data_fetched_at
      FROM public.selection_applications a
      WHERE lower(a.email) = lower(m.email)
        AND a.vep_status_raw IS NOT NULL
      ORDER BY a.vep_last_seen_at DESC NULLS LAST
      LIMIT 1
    ) vep ON true
    -- #625 C0 pre-onboarding flag — VERBATIM from admin_list_members (mig 148).
    LEFT JOIN LATERAL (
      SELECT (
        m.member_status = 'active'
        AND EXISTS (
          SELECT 1 FROM public.engagements e
          WHERE e.person_id = m.person_id AND e.status = 'active'
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.engagements e
          JOIN public.engagement_kinds ek ON ek.slug = e.kind
          WHERE e.person_id = m.person_id AND e.status = 'active'
            AND (ek.requires_agreement IS NOT TRUE OR e.agreement_certificate_id IS NOT NULL)
        )
      ) AS flag
    ) pre ON true
    -- Latest verification from the append-only trail.
    LEFT JOIN LATERAL (
      SELECT mav.created_at, mav.membership_active, mav.membership_expires_on,
             mav.method, mav.chapter_verified
      FROM public.member_affiliation_verifications mav
      WHERE mav.member_id = m.id
      ORDER BY mav.created_at DESC
      LIMIT 1
    ) aff ON true
    WHERE m.member_status = 'active'
      AND (
        COALESCE(pre.flag, false)                                      -- pre-onboarding (urgent)
        OR COALESCE(m.pmi_id_verified, false) = false                  -- cache says unverified
        OR NOT EXISTS (                                                -- never verified at all
          SELECT 1 FROM public.member_affiliation_verifications mv
          WHERE mv.member_id = m.id
        )
      )
  )
  SELECT
    COALESCE(jsonb_agg(jsonb_build_object(
      'member_id', c.member_id,
      'name', c.name,
      'email', c.email,
      'chapter', c.chapter,
      'operational_role', c.operational_role,
      'is_pre_onboarding', c.is_pre_onboarding,
      'pmi_id_verified', COALESCE(c.pmi_id_verified, false),
      'vep_status_raw', c.vep_status_raw,
      'vep_last_seen_at', c.vep_last_seen_at,
      'pmi_memberships', COALESCE(c.pmi_memberships, '[]'::jsonb),
      -- #996 F-A: PMI identity panel from the same Phase B application row (NULL when the member
      -- has no VEP-enriched application — the office then fills in via sede_manual).
      'pmi_profile', CASE
        WHEN c.pmi_id IS NULL AND c.service_first_start_date IS NULL
             AND c.service_latest_end_date IS NULL AND c.service_history_count IS NULL
             AND c.pmi_data_fetched_at IS NULL
        THEN NULL
        ELSE jsonb_build_object(
          'pmi_id', c.pmi_id,
          'member_since', c.service_first_start_date,
          'member_until', c.service_latest_end_date,
          'volunteer_count', c.service_history_count,
          'last_sync', c.pmi_data_fetched_at
        )
      END,
      'latest_verification', CASE WHEN c.aff_created_at IS NULL THEN NULL ELSE jsonb_build_object(
        'created_at', c.aff_created_at,
        'membership_active', c.aff_membership_active,
        'membership_expires_on', c.aff_membership_expires_on,
        'method', c.aff_method,
        'chapter_verified', c.aff_chapter_verified
      ) END
    ) ORDER BY c.is_pre_onboarding DESC, c.name),
    '[]'::jsonb),
    ARRAY_AGG(c.member_id)
  INTO v_result, v_member_ids
  FROM cohort c;

  -- LGPD Art. 37 — nominal read of affiliation data by the office (SPEC §6.2.3(4)).
  -- #996: member since/until (service dates) are now surfaced → name them in the trail.
  PERFORM public.log_pii_access_batch(
    v_member_ids,
    ARRAY['pmi_id','chapter','membership_status','membership_dates'],
    'affiliation_verification_queue',
    'Diretoria de Filiação — leitura da fila de verificação de filiação');

  RETURN v_result;
END;
$function$;

-- Grants (defense in depth — internal gate already bars unauthorized callers).
REVOKE ALL ON FUNCTION public.get_affiliation_verification_queue() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_affiliation_verification_queue() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
