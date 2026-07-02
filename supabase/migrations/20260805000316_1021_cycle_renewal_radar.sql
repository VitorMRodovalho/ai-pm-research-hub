-- #1021: cycle-close renewal radar — resolve VEP service-end by MEMBER (full email set), not only
-- by the FK-linked application, and surface a per-volunteer "renews? y/n/unknown" flag so the C3→C4
-- cohort turn (#1004) no longer needs a manual SQL cross-join.
--
-- Problem (grounded live 2026-07-01, 67 active volunteer engagements):
--   • 4 active volunteers have a VEP service_latest_end_date on an EMAIL-MATCHED application whose
--     row is NOT the one their engagement.selection_application_id points to (the FK link points at
--     an older/different app with a NULL date) → resolving service-end "by the linked app only"
--     leaves the renewal radar dark for them. Resolving by member email recovers all 4 with ZERO
--     data mutation.
--   • 13 active volunteers have NO service_latest_end_date on any of their applications → genuinely
--     unknown; the radar must say so honestly (not fabricate a date, not fall back to the uniform
--     volunteer_agreement cert period_end which MASKS the real heterogeneous VEP dates).
--
-- Identity resolution honors the platform's multi-email model (member_emails, p277 invariant R): the
-- service-end is resolved across the member's FULL email set (primary + alternates), not just the
-- primary. (Recovers 0 extra rows today but is the faithful "by member" resolution and avoids a
-- latent blind spot when an application was filed under an alternate email.)
--
-- This migration is behavior-additive; it reads domain data only — its single write is the LGPD
-- Art. 37 pii_access_log audit row (via log_pii_access_batch) for the in-app GP path:
--   • Adds ONE SECURITY DEFINER report RPC get_cycle_renewal_radar(p_as_of date). No table/column
--     change, no backfill, no FK repair (that data-repair is a separate operator task — #1021 ask 1/2;
--     the email resolution below makes it unnecessary for the radar to fire).
--   • The RPC returns member PII (name/email) → LGPD-gated on manage_member (in-app GP) OR
--     service_role/postgres (operator/cron via MCP), mirroring check_schema_invariants. Regular
--     authenticated members and anon are blocked.
--
-- Rows are per active volunteer ENGAGEMENT (matches #1004's access-by-engagement model); a member
-- with 2 active volunteer engagements appears twice — summary.distinct_members disambiguates.
--
-- resolved_service_end = MAX(service_latest_end_date) over ALL applications matched to the member's
-- email set (the furthest-out VEP commitment; the FK-linked app is one of them). service_end_source
-- distinguishes 'linked' (FK app already gave the furthest date) / 'email_matched' (a different app
-- did — recovered or improved) / 'unknown' (no date anywhere). renews_signal compares
-- resolved_service_end to p_as_of: 'active_future' (service continues past the turn), 'lapsing' (ends
-- at/before the turn — exit candidate to review), 'unknown' (no VEP date). renewal_link_present
-- surfaces the sparse forward selection_applications.renews_engagement_id confirmed-renewal signal.

CREATE OR REPLACE FUNCTION public.get_cycle_renewal_radar(p_as_of date DEFAULT CURRENT_DATE)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE  -- writes one LGPD Art. 37 pii_access_log row (the member email/name list is a nominal PII read)
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result    jsonb;
BEGIN
  -- LGPD dual-consumer gate (this RPC returns member PII):
  --   • in-app GP/manager  → auth.uid() set + can_by_member(manage_member)
  --   • operator/cron (MCP)→ service_role/postgres (already holds table-level read; the RPC just
  --     packages the cross-join). Blocks anon + authenticated non-GP.
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_member') THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_member action';
    END IF;
  ELSIF current_setting('role', true) NOT IN ('service_role', 'postgres')
        AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: authentication required';
  END IF;

  WITH active_vol AS (
    SELECT e.id            AS engagement_id,
           e.role,
           e.initiative_id,
           e.end_date      AS engagement_end_date,
           e.selection_application_id AS linked_app_id,
           e.agreement_certificate_id,
           m.id            AS member_id,
           m.name          AS member_name,
           m.email,
           m.operational_role,
           -- Full email set (primary + alternates) — faithful "by member" resolution (p277 inv. R).
           ( SELECT array_agg(DISTINCT lower(x)) FILTER (WHERE x IS NOT NULL)
             FROM ( SELECT m.email AS x
                    UNION
                    SELECT me.email FROM public.member_emails me WHERE me.member_id = m.id ) s
           )               AS email_set
    FROM public.engagements e
    JOIN public.members m ON m.person_id = e.person_id
    WHERE e.status = 'active' AND e.revoked_at IS NULL AND e.kind = 'volunteer'
  ),
  resolved AS (
    SELECT av.*,
           la.service_latest_end_date AS linked_service_end,
           em.email_max_end,
           em.email_max_end_cycle,
           cert.period_end AS cert_period_end,
           EXISTS (
             -- per-engagement precision: does a renewal application forward-link to THIS engagement?
             -- (an email-set match would false-positive for members holding two active engagements)
             SELECT 1 FROM public.selection_applications a
             WHERE a.renews_engagement_id = av.engagement_id
           ) AS renewal_link_present
    FROM active_vol av
    LEFT JOIN public.selection_applications la ON la.id = av.linked_app_id
    LEFT JOIN LATERAL (
      -- #1021 FIX: furthest VEP service-end across ALL apps matched to the member's email set (incl.
      -- the linked one), not just the FK-linked app. Carries the originating cycle for staleness judgement.
      SELECT a.service_latest_end_date AS email_max_end, sc.cycle_code AS email_max_end_cycle
      FROM public.selection_applications a
      LEFT JOIN public.selection_cycles sc ON sc.id = a.cycle_id
      WHERE lower(a.email) = ANY(av.email_set) AND a.service_latest_end_date IS NOT NULL
      ORDER BY a.service_latest_end_date DESC
      LIMIT 1
    ) em ON true
    LEFT JOIN public.certificates cert ON cert.id = av.agreement_certificate_id
  ),
  classified AS (
    SELECT r.*,
           r.email_max_end AS resolved_service_end,
           CASE
             WHEN r.email_max_end IS NULL THEN 'unknown'
             WHEN r.linked_service_end IS NOT NULL AND r.linked_service_end = r.email_max_end THEN 'linked'
             ELSE 'email_matched'
           END AS service_end_source,
           CASE
             WHEN r.email_max_end IS NULL THEN 'unknown'
             WHEN r.email_max_end <= p_as_of THEN 'lapsing'
             ELSE 'active_future'
           END AS renews_signal
    FROM resolved r
  )
  SELECT jsonb_build_object(
    'as_of', p_as_of,
    'summary', jsonb_build_object(
      'total_active_volunteer_engagements', count(*),
      'distinct_members',        count(DISTINCT member_id),
      'service_end_resolved',    count(*) FILTER (WHERE service_end_source <> 'unknown'),
      'recovered_by_email',      count(*) FILTER (WHERE service_end_source = 'email_matched'),
      'unknown',                 count(*) FILTER (WHERE service_end_source = 'unknown'),
      'lapsing',                 count(*) FILTER (WHERE renews_signal = 'lapsing'),
      'active_future',           count(*) FILTER (WHERE renews_signal = 'active_future'),
      'renewal_link_present',    count(*) FILTER (WHERE renewal_link_present)
    ),
    'members', COALESCE(jsonb_agg(
      jsonb_build_object(
        'member_id',            member_id,
        'member_name',          member_name,
        'email',                email,
        'role',                 role,
        'operational_role',     operational_role,
        'initiative_title',     (SELECT i.title FROM public.initiatives i WHERE i.id = classified.initiative_id),
        'engagement_end_date',  engagement_end_date,
        'linked_service_end',   linked_service_end,
        'resolved_service_end', resolved_service_end,
        'service_end_source',   service_end_source,
        'resolved_from_cycle',  CASE WHEN service_end_source = 'email_matched' THEN email_max_end_cycle ELSE NULL END,
        'cert_period_end',      cert_period_end,
        'renews_signal',        renews_signal,
        'renewal_link_present', renewal_link_present
      )
      ORDER BY
        CASE renews_signal WHEN 'lapsing' THEN 0 WHEN 'unknown' THEN 1 ELSE 2 END,
        member_name
    ), '[]'::jsonb)
  ) INTO v_result
  FROM classified;

  -- LGPD Art. 37: instrument the nominal PII read (member name/email list), matching every other
  -- list-reader RPC that returns member email (get_tribe_member_contacts, admin_list_members_with_pii,
  -- #999 verify_member_affiliations_bulk). Silently no-ops for the service_role/operator path
  -- (auth.uid() NULL → returns 0) and for an empty cohort (empty array → returns 0).
  PERFORM public.log_pii_access_batch(
    ARRAY(SELECT DISTINCT (elem->>'member_id')::uuid FROM jsonb_array_elements(v_result->'members') elem),
    ARRAY['name','email','operational_role','service_latest_end_date'],
    'get_cycle_renewal_radar',
    'cycle-turn renewal report as_of ' || p_as_of::text
  );

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.get_cycle_renewal_radar(date) IS
  '#1021 — cycle-close renewal radar. Per active volunteer engagement: VEP service-end resolved by '
  'the member email set (MAX across all matched applications, not only the FK-linked app) + renews? '
  'active_future/lapsing/unknown flag vs p_as_of. LGPD-gated (manage_member OR service_role/postgres); '
  'logs the nominal PII read via log_pii_access_batch (Art. 37). Reads domain data only — the '
  'backfill/link-repair for the unknown/unlinked cases is a separate operator task. Consumed by the '
  '#1004 cycle-turn cohort procedure.';

REVOKE ALL ON FUNCTION public.get_cycle_renewal_radar(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_cycle_renewal_radar(date) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
