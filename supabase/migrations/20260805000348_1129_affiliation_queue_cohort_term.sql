-- =====================================================================================
-- #1129 — get_affiliation_verification_queue: cohort view (C4-novo × C3-carryover ×
--          não-seleção) + volunteer-term validity, DERIVED reliably from
--          engagement/selection → cycle. NEVER members.cycles (50/89 active have an empty
--          array — see memory reference-members-cycles-unreliable-cohort-source + #1129).
--
-- Body-only CREATE OR REPLACE (signature/return jsonb UNCHANGED). Extends the #996 body with,
-- per row:
--   'cohort_class'      : 'current_selection' | 'carryover' | 'non_selection'
--   'cohort_cycle_code' : resolved selection cycle_code (e.g. 'cycle4-2026') or NULL
--   'cohort_role'       : role_applied from the resolved selection application or NULL
--   'term_end_date'     : the active agreement-term engagement end_date (volunteer-term boundary) or NULL
--   'term_status'       : 'valid' | 'expiring' | 'expired' | 'none'  (vs CURRENT_DATE)
--
-- WHY (the trap this closes, grounded live 2026-07-06): the queue showed 37 "pré-onboarding" with no
--   cohort recorte and no term validity, so a validator could not tell that of the 45 current-cycle
--   approved members only 35 sit in the pré-onboarding default tab (10 hidden), nor which C3-carryover
--   terms lapse end-of-2026. Live derivation reconciles: current_selection=45, carryover=21,
--   non_selection=23 (total queue 89); all 21 carryover terms end 2026-12 (the renewal wave).
--
-- DERIVATION (mirrors get_cycle_renewal_radar #1021 — resolve across the member's FULL email set,
-- because engagements.selection_application_id can FK-point at an older/different app):
--   * current selection cycle = the selection_cycles row tied to the CURRENT operational cycle
--     (public.cycles.is_current) by cycle number, latest open_date. Fully dynamic — no hardcoded
--     cycle_code; survives C4→C5 (cycles.is_current flips, this follows).
--   * sel = the member's most-relevant approved/converted selection application across the email set,
--     preferring the current cycle:
--       - current-cycle app  → cohort_class='current_selection'   (the "C4-novo" bucket)
--       - only prior linkage → cohort_class='carryover'           (the "C3-carryover" bucket)
--       - no linkage at all  → cohort_class='non_selection'       (board/speaker/sponsor/…)
--   * term = the active engagement whose kind.requires_agreement=true (the volunteer term); its
--     end_date is the term boundary. 'expiring' window = 180 days (~one renewal cycle; cycles are
--     ~6-month and cycle_4.cycle_end is still open/NULL, so a fixed window is used rather than the
--     cycle end). The raw term_end_date is always surfaced so the office can sort/filter to a precise
--     horizon regardless of the bucket threshold.
--
-- INVARIANTS PRESERVED (locked by 659/996 tests — NOT weakened):
--   - Function-anchored gate (filiacao_director OR can_by_member(manage_member)); fail-closed on NULL uid.
--   - Read audience == write audience (no view_internal_analytics arm).
--   - LGPD Art. 37 log_pii_access_batch trail (cohort/term are DERIVED from selection/engagement data
--     the office already reads — no new raw identity column is surfaced, so the field list is unchanged).
--   - Hardened grants (REVOKE public/anon; GRANT authenticated/service_role).
--
-- ROLLBACK: re-apply migration 20260805000328 (the pre-#1129 body).
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
  v_current_cycle_id    uuid;
  v_term_soon_days      int := 180;  -- ~one renewal cycle (cycle_4.cycle_end open); raw date also surfaced
BEGIN
  -- Auth-resolve + function-anchored gate (mirror verify_member_affiliation, mig 148).
  SELECT m.id, m.designations INTO v_caller_id, v_caller_designations
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  -- Least-privilege: read audience == write audience (filiacao_director OR manage_member).
  IF NOT ('filiacao_director' = ANY(COALESCE(v_caller_designations, '{}'::text[])))
     AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: requires filiacao_director designation or platform manager authority';
  END IF;

  -- Current selection cycle, tied to the current operational cycle by number (dynamic — no hardcoded
  -- cycle_code; survives C4→C5). selection_cycles has no is_current column; two selection rows can be
  -- status='open' at once, so we anchor on cycles.is_current, then take the latest open_date.
  SELECT sc.id INTO v_current_cycle_id
  FROM public.selection_cycles sc
  WHERE regexp_replace(sc.cycle_code, '\D', '', 'g')
        LIKE (SELECT regexp_replace(c.cycle_code, '\D', '', 'g') FROM public.cycles c WHERE c.is_current LIMIT 1) || '%'
  ORDER BY sc.open_date DESC NULLS LAST
  LIMIT 1;

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
      aff.chapter_verified      AS aff_chapter_verified,
      -- #1129 cohort (by email set; current-cycle preferred)
      sel.sel_cycle_code,
      sel.sel_role,
      sel.sel_is_current,
      sel.has_selection,
      -- #1129 term validity
      term.term_end_date
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
    -- #1129 cohort: most-relevant approved/converted selection application across the member's full
    -- email set (primary + member_emails), preferring the current cycle. NULL row ⇒ non_selection.
    LEFT JOIN LATERAL (
      SELECT sc.cycle_code                     AS sel_cycle_code,
             a.role_applied                    AS sel_role,
             (a.cycle_id = v_current_cycle_id) AS sel_is_current,
             true                              AS has_selection
      FROM public.selection_applications a
      JOIN public.selection_cycles sc ON sc.id = a.cycle_id
      WHERE a.status IN ('approved','converted')
        AND ( lower(a.email) = lower(m.email)
              OR lower(a.email) IN (SELECT lower(me.email) FROM public.member_emails me WHERE me.member_id = m.id) )
      ORDER BY (a.cycle_id = v_current_cycle_id) DESC, sc.open_date DESC NULLS LAST
      LIMIT 1
    ) sel ON true
    -- #1129 term boundary: the active agreement-requiring engagement's end_date (volunteer term).
    LEFT JOIN LATERAL (
      SELECT e.end_date AS term_end_date
      FROM public.engagements e
      JOIN public.engagement_kinds ek ON ek.slug = e.kind
      WHERE e.person_id = m.person_id
        AND e.status = 'active'
        AND ek.requires_agreement = true
      ORDER BY e.end_date DESC NULLS LAST
      LIMIT 1
    ) term ON true
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
      -- #1129 cohort + volunteer-term validity
      'cohort_class', CASE
        WHEN NOT COALESCE(c.has_selection, false) THEN 'non_selection'
        WHEN c.sel_is_current THEN 'current_selection'
        ELSE 'carryover'
      END,
      'cohort_cycle_code', c.sel_cycle_code,
      'cohort_role', c.sel_role,
      'term_end_date', c.term_end_date,
      'term_status', CASE
        WHEN c.term_end_date IS NULL THEN 'none'
        WHEN c.term_end_date < CURRENT_DATE THEN 'expired'
        WHEN c.term_end_date <= CURRENT_DATE + (v_term_soon_days || ' days')::interval THEN 'expiring'
        ELSE 'valid'
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

  -- LGPD Art. 37 — nominal read of affiliation data by the office (SPEC §6.2.3(4)). cohort/term are
  -- derived from selection/engagement data the office already reads; no new raw identity column.
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
