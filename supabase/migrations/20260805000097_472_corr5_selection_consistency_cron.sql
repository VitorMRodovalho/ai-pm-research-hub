-- ============================================================================
-- #472 correction #5 — selection-pipeline CONSISTENCY / DETECTION cron
-- ----------------------------------------------------------------------------
-- corr-4 (migration 20260805000090) AUTO-HEALS the common status clobber
-- (recompute_application_status, forward-only + terminal-safe, daily 13:00 UTC).
-- This is the complementary DETECTION + ALERT layer: it surfaces the divergences
-- the recompute can NOT auto-fix (forward-only-blocked / ambiguous), plus the
-- data-integrity anomalies that need a human, and it writes a structured report
-- to admin_audit_log every day.
--
-- DESIGN — must NOT cry wolf (the #472 / "measure before asserting" discipline):
--   • INTEGRITY anomalies (alert-worthy, high-confidence) — these are unambiguous
--     bugs a human should see:
--       a. scored_not_advanced       — interview_score set but status behind a
--                                       final/decided stage (recompute couldn't
--                                       forward-fix it).
--       b. interview_completed_app_behind — a completed/conducted interview row but
--                                       the app is still pre-interview.
--       c. interview_phase_no_row    — status interview_scheduled/interview_done
--                                       but NO selection_interviews row. (final_eval
--                                       with no row is EXCLUDED — a manual/off-platform
--                                       final with interview_score + no live row is
--                                       legitimate, exactly what recompute treats as
--                                       final_eval, so flagging it would be a false
--                                       positive.)
--       d. orphan_interview_row      — a live (non-cancelled/noshow) interview row
--                                       whose app is still pre-interview.
--       e. unmatched_calendar_bookings_7d — a booking arrived but matched NO
--                                       application (B1 recurrence). Reads BOTH the
--                                       RPC-path audit action and the webhook-path
--                                       one (the webhook logs unmatched in corr-1).
--   • DISPATCH GAP (informational ONLY, never alerted): candidates still awaiting
--     their interview link (status interview_pending/interview_scheduled) with no
--     selection_dispatch_url_log row. This is NOISY — cycle 4's interview links went
--     out via the email CAMPAIGN (campaign_recipients / Resend), which does NOT write
--     dispatch_url_log, so candidates who DID receive their link have no dispatch row.
--     Surfaced as a count for awareness; it does NOT trigger leads. (interview_done/
--     final_eval are excluded — the interview already happened.)
--
-- selection_topic_views: investigated and INTENTIONALLY left in place (see the
-- COMMENT ON TABLE below). It is NOT dead engagement tracking — it is the
-- interview-topics opt-in log (written by log_topic_view via the profile-completion
-- token, read by get_application_ai_analysis_runs, RLS committee-read). Engagement
-- open/click tracking is a SEPARATE concern that lives in campaign_recipients.
--
-- ROLLBACK:
--   DROP FUNCTION public._selection_consistency_cron();
--   DROP FUNCTION public.selection_consistency_report(uuid);
--   SELECT cron.unschedule('selection-consistency-check-daily');
--   (read-only detection — no data backfill is destructive.)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.selection_consistency_report(p_cycle_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_pre_interview text[] := ARRAY['submitted','screening','objective_eval','objective_cutoff'];
  v_decided text[] := ARRAY['final_eval','interview_done','approved','rejected','converted',
                            'withdrawn','cancelled','waitlist','interview_noshow'];
  v_a jsonb; v_b jsonb; v_c jsonb; v_d jsonb; v_e jsonb; v_disp jsonb;
  v_a_n int; v_b_n int; v_c_n int; v_d_n int; v_e_n int; v_disp_n int;
  v_distinct_apps int;  -- DISTINCT applications across A/B/C/D (B ⊆ D → a plain sum double-counts)
BEGIN
  -- Auth: authenticated callers need manage_platform; a no-JWT context
  -- (pg_cron / service_role) is the self-running path and is allowed.
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: manage_platform required';
    END IF;
  END IF;

  -- open/active cycles only (or the one requested), so we never alarm on closed cycles.
  -- a. scored but not advanced past a final/decided stage
  WITH oa AS (
    SELECT a.* FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE c.status IN ('open','active')
      AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
  ),
  rows_a AS (
    SELECT a.id, a.applicant_name, a.status, a.interview_score
    FROM oa a
    WHERE a.interview_score IS NOT NULL
      AND a.status <> ALL (v_decided)
  )
  SELECT count(*), COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.applicant_name) FILTER (WHERE r.rn <= 10), '[]'::jsonb)
  INTO v_a_n, v_a
  FROM (SELECT *, row_number() OVER (ORDER BY applicant_name) AS rn FROM rows_a) r;

  -- b. completed/conducted interview row but app still pre-interview
  WITH rows_b AS (
    SELECT DISTINCT a.id, a.applicant_name, a.status
    FROM public.selection_interviews si
    JOIN public.selection_applications a ON a.id = si.application_id
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE c.status IN ('open','active')
      AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
      AND (si.status = 'completed' OR si.conducted_at IS NOT NULL)
      AND a.status = ANY (v_pre_interview)
  )
  SELECT count(*), COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.applicant_name) FILTER (WHERE r.rn <= 10), '[]'::jsonb)
  INTO v_b_n, v_b
  FROM (SELECT *, row_number() OVER (ORDER BY applicant_name) AS rn FROM rows_b) r;

  -- c. status interview_scheduled/interview_done but NO interview row
  --    (final_eval excluded — manual off-platform final is legitimate)
  WITH rows_c AS (
    SELECT a.id, a.applicant_name, a.status
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE c.status IN ('open','active')
      AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
      AND a.status IN ('interview_scheduled','interview_done')
      AND NOT EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id)
  )
  SELECT count(*), COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.applicant_name) FILTER (WHERE r.rn <= 10), '[]'::jsonb)
  INTO v_c_n, v_c
  FROM (SELECT *, row_number() OVER (ORDER BY applicant_name) AS rn FROM rows_c) r;

  -- d. live interview row but app still pre-interview (orphan)
  WITH rows_d AS (
    SELECT DISTINCT a.id, a.applicant_name, a.status
    FROM public.selection_interviews si
    JOIN public.selection_applications a ON a.id = si.application_id
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE c.status IN ('open','active')
      AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
      AND si.status NOT IN ('cancelled','noshow')
      AND a.status = ANY (v_pre_interview)
  )
  SELECT count(*), COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.applicant_name) FILTER (WHERE r.rn <= 10), '[]'::jsonb)
  INTO v_d_n, v_d
  FROM (SELECT *, row_number() OVER (ORDER BY applicant_name) AS rn FROM rows_d) r;

  -- e. calendar bookings that matched no application in the last 7 days
  --    (both the dead-RPC path and the live-webhook path log this action)
  WITH rows_e AS (
    SELECT l.metadata->>'calendar_event_id' AS calendar_event_id,
           l.changes->>'guest_email' AS guest_email,
           l.created_at
    FROM public.admin_audit_log l
    WHERE l.action IN ('arm116.calendar_booking_unmatched','calendar_booking_unmatched')
      AND l.created_at >= now() - interval '7 days'
  )
  SELECT count(*), COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FILTER (WHERE r.rn <= 10), '[]'::jsonb)
  INTO v_e_n, v_e
  FROM (SELECT *, row_number() OVER (ORDER BY created_at DESC) AS rn FROM rows_e) r;

  -- DISTINCT affected applications across A/B/C/D — the human-facing "how many
  -- candidates are broken". The per-class counts above overlap (B ⊆ D: every
  -- completed/conducted row is also a live row), so summing them would double-count
  -- a single broken application. This recomputes the same predicates as a set.
  WITH oa AS (
    SELECT a.id, a.status, a.interview_score
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE c.status IN ('open','active')
      AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
  ),
  iv AS (
    SELECT si.application_id,
           bool_or(si.status = 'completed' OR si.conducted_at IS NOT NULL) AS has_done,
           bool_or(si.status NOT IN ('cancelled','noshow'))                AS has_live
    FROM public.selection_interviews si
    GROUP BY si.application_id
  )
  SELECT count(DISTINCT o.id) INTO v_distinct_apps
  FROM oa o
  LEFT JOIN iv ON iv.application_id = o.id
  WHERE (o.interview_score IS NOT NULL AND o.status <> ALL (v_decided))                          -- A
     OR (COALESCE(iv.has_done, false) AND o.status = ANY (v_pre_interview))                       -- B
     OR (o.status IN ('interview_scheduled','interview_done') AND iv.application_id IS NULL)      -- C
     OR (COALESCE(iv.has_live, false) AND o.status = ANY (v_pre_interview));                      -- D

  -- dispatch gap — INFORMATIONAL ONLY (the campaign path bypasses dispatch_url_log).
  -- Scoped to interview_pending/interview_scheduled — the statuses where the link is
  -- still operationally needed; interview_done/final_eval are excluded because the
  -- interview already occurred so a missing dispatch row there is stale history.
  SELECT count(*) INTO v_disp_n
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE c.status IN ('open','active')
    AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
    AND a.status IN ('interview_pending','interview_scheduled')
    AND NOT EXISTS (SELECT 1 FROM public.selection_dispatch_url_log d WHERE d.application_id = a.id);
  v_disp := jsonb_build_object(
    'count', v_disp_n,
    'note', 'INFORMATIONAL — interview links may have gone out via the email campaign '
            || '(campaign_recipients/Resend), which does not write selection_dispatch_url_log. '
            || 'Not an alert; cross-check campaign delivery before acting.'
  );

  RETURN jsonb_build_object(
    'success', true,
    'scope', COALESCE(p_cycle_id::text, 'all open/active cycles'),
    'integrity_anomalies', jsonb_build_object(
      'scored_not_advanced',            jsonb_build_object('count', v_a_n, 'samples', v_a),
      'interview_completed_app_behind', jsonb_build_object('count', v_b_n, 'samples', v_b),
      'interview_phase_no_row',         jsonb_build_object('count', v_c_n, 'samples', v_c),
      'orphan_interview_row',           jsonb_build_object('count', v_d_n, 'samples', v_d),
      'unmatched_calendar_bookings_7d', jsonb_build_object('count', v_e_n, 'samples', v_e)
    ),
    'dispatch_gap_informational', jsonb_build_object('qualified_no_dispatch_log', v_disp),
    -- total = DISTINCT broken applications (A/B/C/D, deduplicated — B ⊆ D) + unmatched
    -- bookings (E, which are bookings, not applications, so additive). The per-class
    -- counts above are an overlapping breakdown; this is the non-double-counted headline.
    'affected_applications_distinct', v_distinct_apps,
    'integrity_anomaly_total', (v_distinct_apps + v_e_n),
    'has_integrity_anomaly', (v_distinct_apps + v_e_n) > 0
  );
END;
$function$;

-- ── detection cron wrapper ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._selection_consistency_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_report jsonb;
  v_total int;
  v_lead record;
  v_summary text;
BEGIN
  v_report := public.selection_consistency_report(NULL);
  v_total := COALESCE((v_report->>'integrity_anomaly_total')::int, 0);

  -- always record the report (observability) — admin-scoped audit log
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'selection.consistency_check', 'system', NULL,
    jsonb_build_object('integrity_anomaly_total', v_total),
    v_report
  );

  -- alert leads ONLY on high-confidence integrity anomalies (never on the dispatch gap)
  IF v_total > 0 THEN
    v_summary := v_total || ' anomalia(s) de integridade na pipeline de seleção '
      || '(candidato pontuado sem avançar / entrevista concluída com app atrás / '
      || 'fase de entrevista sem linha / linha órfã / agendamento sem match). '
      || 'Detalhes no relatório (admin_audit_log selection.consistency_check). Revise em /admin/selection.';

    FOR v_lead IN
      SELECT DISTINCT sc.member_id
      FROM public.selection_committee sc
      JOIN public.selection_cycles c ON c.id = sc.cycle_id
      WHERE c.status IN ('open','active')
        AND sc.role = 'lead'
        AND sc.member_id IS NOT NULL
    LOOP
      -- 7-arg overload: (p_recipient_id, p_type, p_title, p_body, p_link, p_source_type, p_source_id)
      PERFORM public.create_notification(
        v_lead.member_id,
        'selection_consistency_anomaly',
        'Inconsistências detectadas na pipeline de seleção',
        v_summary,
        '/admin/selection',
        'system',
        NULL::uuid
      );
    END LOOP;
  END IF;

  RETURN v_report;
END;
$function$;

-- ── grant ladder ────────────────────────────────────────────────────────────
-- SERVICE_ROLE ONLY on both: the cron (service_role) is the sole consumer, and the
-- report returns applicant_name samples. The internal manage_platform gate is kept
-- as defense-in-depth, but the surface is not exposed to `authenticated` (minimal
-- privilege) — any future on-demand admin call should route through a manage_platform
-- -gated MCP tool (service_role), not a direct authenticated grant.
REVOKE ALL ON FUNCTION public.selection_consistency_report(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.selection_consistency_report(uuid) TO service_role;

REVOKE ALL ON FUNCTION public._selection_consistency_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._selection_consistency_cron() TO service_role;

-- ── schedule: daily 13:30 UTC — AFTER the 13:00 recompute (corr-4) so the report
--    reflects the post-heal state and only surfaces what recompute could not fix.
--    cron.schedule UPSERTS by job name (idempotent re-run), same as mig 090. ──
SELECT cron.schedule(
  'selection-consistency-check-daily',
  '30 13 * * *',
  $cron$SELECT public._selection_consistency_cron()$cron$
);

-- ── selection_topic_views: document the real purpose (corr-5 finding). It is NOT
--    dead engagement tracking — it is the interview-topics opt-in log. Kept as-is. ──
COMMENT ON TABLE public.selection_topic_views IS
  'Interview-topics opt-in log for selection candidates. Written by log_topic_view() '
  'via the profile-completion onboarding token (source_type=pmi_application); read by '
  'the committee RPC get_application_ai_analysis_runs(). RLS: committee-read only '
  '(selection_topic_views_committee_read), no direct insert/update/delete. NOT a dead '
  'engagement tracker — link open/click engagement is a separate concern in '
  'campaign_recipients (Resend). #472 corr-5: investigated, intentionally retained.';

NOTIFY pgrst, 'reload schema';
