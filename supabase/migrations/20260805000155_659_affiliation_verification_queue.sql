-- =====================================================================================
-- #659 — get_affiliation_verification_queue: cohort-read RPC for the Diretoria de Filiação panel
-- SPEC: docs/specs/SPEC_625_AFFILIATION_VERIFICATION_LOOP.md (Pasta Diretoria de Filiação, §5 F1)
-- Epic: #660 (Jornada Onboarding) step 2. Builds the read surface for the already-shipped
--       #647 F1 write loop (verify_member_affiliation / _bulk / attestation trigger).
-- ADRs: 0004 (organization_id) · 0007 (can_by_member) · 0076 (PMI/VEP) · GC-162 (RLS/LGPD)
--
-- AUTHORITY IS FUNCTION-ANCHORED, NOT PERSON-ANCHORED (PM 2026-06-12): access follows the
--   `filiacao_director` designation (the office of the Diretoria de Filiação), never a named
--   individual — so reassigning the office reassigns access with zero code change. Gate = the
--   office (designation `filiacao_director`, Path 2) OR can_by_member(caller,'manage_member').
--   This is a BULK cohort read, so its audience matches the WRITE gate (verify_member_affiliation)
--   EXACTLY — deliberately TIGHTER than the per-member get_member_affiliation_status, which keeps
--   view_internal_analytics for single-row point lookups (security review M-1, #659).
--   No new seed in engagement_kind_permissions (anti-pattern; V4_AUTHORITY_MODEL.md).
--
-- COHORT = active members still needing affiliation verification: pre-onboarding (the urgent
--   guest→active gate) OR pmi_id_verified=false OR never verified. Verified+active members drop out.
--   pmi_memberships (chapter+expiry, jsonb) is surfaced from selection_applications so the office
--   sees the federated-gate data (BR chapter "em dia") that admin_list_members does not expose.
--   When a candidate keeps the PMI community private OR is not yet affiliated, the detail is
--   absent — by design the office fills/checks it manually via verify_member_affiliation (sede_manual).
--
-- LGPD Art. 37: nominal read of affiliation data by the office is logged (log_pii_access_batch),
--   per SPEC §6.2.3(4) — this trail is the evidence the LIA (Art. 7º IX) requires. Read-only RPC;
--   the F1b attestation trigger gates WRITES only, so listing the queue needs no attestation.
--
-- NOT STABLE: PERFORMs the volatile pii-log INSERT (matches get_member_affiliation_status, which
--   is also unmarked + PERFORMs log_pii_access).
--
-- ROLLBACK: DROP FUNCTION IF EXISTS public.get_affiliation_verification_queue();
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
      aff.created_at            AS aff_created_at,
      aff.membership_active     AS aff_membership_active,
      aff.membership_expires_on AS aff_membership_expires_on,
      aff.method                AS aff_method,
      aff.chapter_verified      AS aff_chapter_verified
    FROM public.members m
    -- VEP + PMI membership detail from the latest matching application (shape from admin_list_members).
    LEFT JOIN LATERAL (
      SELECT a.vep_status_raw, a.vep_last_seen_at, a.pmi_memberships
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
  PERFORM public.log_pii_access_batch(
    v_member_ids,
    ARRAY['pmi_id','chapter','membership_status'],
    'affiliation_verification_queue',
    'Diretoria de Filiação — leitura da fila de verificação de filiação');

  RETURN v_result;
END;
$function$;

-- Grants (defense in depth — internal gate already bars unauthorized callers).
-- NB: the project ALTER DEFAULT PRIVILEGES auto-grants PUBLIC+anon on new public functions;
-- the REVOKE below + a live proacl check keep this hardened like its siblings.
REVOKE ALL ON FUNCTION public.get_affiliation_verification_queue() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_affiliation_verification_queue() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
