-- p228 #260 W2 Leaf 2: selection_interview_overdue type + daily cron
--
-- Per p227 W2 audit (Q6 + Finding D): 11+ stale `selection_interviews` rows
-- (scheduled_at < NOW(), conducted_at IS NULL) with no automated cleanup or
-- follow-up notification. Live census 2026-05-23 shows 18 stale rows across
-- 2 distinct interviewers — surfaces only in admin queries today.
--
-- This migration:
--   1. Extends `_delivery_mode_for` helper with `selection_interview_overdue`
--      → `digest_weekly` (admin-facing per PM Policy Matrix Amendment D).
--   2. Adds `selection_interview_overdue` catalog entry (catalog file edit ships
--      in the same PR).
--   3. Creates `_selection_interview_overdue_cron()` SECDEF RPC that emits one
--      notification per (interview, interviewer) pair, idempotent on a 7-day
--      window. Recipient = each uuid in `selection_interviews.interviewer_ids[]`.
--   4. Schedules `pg_cron` job `selection-interview-overdue-daily` at 14:00 UTC.
--
-- Scope guards:
--   - Only fires for interviews with `status IN ('scheduled', 'rescheduled')`
--     AND `conducted_at IS NULL` AND `scheduled_at < NOW() - INTERVAL '24 hours'`
--     (24h grace prevents alerting same-day interviews running late).
--   - Skips interviews with no interviewer_ids (DISTINCT UNNEST excludes empty arrays).
--   - Per-recipient idempotency: NOT EXISTS check against notification created in
--     last 7 days for the same (interview_id, recipient_id, type).
--
-- Notification routing: helper returns `digest_weekly` → bundled into Saturday
-- digest via existing W2 send-weekly-member-digest EF infra. No email spam.
--
-- Source attribution: source_type='selection_interview' + source_id=interview.id
-- for traceability + future selective replay/dedupe queries.

-- 1. Helper extension — add selection_interview_overdue
CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
SET search_path TO ''
AS $function$
  SELECT CASE p_type
    WHEN 'volunteer_agreement_signed'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    WHEN 'certificate_ready'             THEN 'transactional_immediate'
    WHEN 'member_offboarded'             THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_advanced'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_chain_approved'   THEN 'transactional_immediate'
    WHEN 'ip_ratification_awaiting_members' THEN 'transactional_immediate'
    WHEN 'webinar_status_confirmed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_completed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_cancelled'      THEN 'transactional_immediate'
    WHEN 'weekly_card_digest_member'     THEN 'transactional_immediate'
    WHEN 'governance_cr_new'             THEN 'transactional_immediate'
    WHEN 'governance_cr_vote'            THEN 'transactional_immediate'
    WHEN 'governance_cr_approved'        THEN 'transactional_immediate'
    WHEN 'sponsor_finance_entry_logged'  THEN 'transactional_immediate'
    WHEN 'governance_manual_proposed'    THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d7_urgent'  THEN 'transactional_immediate'
    -- p153 OPP-153.1: project_charter (TAP) notifications
    WHEN 'project_charter_invite'        THEN 'transactional_immediate'
    WHEN 'project_charter_approved'      THEN 'transactional_immediate'
    -- p159 S#1 T1 (2026-05-14): selection_termo_due é o "email principal" pós-VEP-Active
    WHEN 'selection_termo_due'           THEN 'transactional_immediate'
    -- p228 #260 W2 Leaf 1 (2026-05-23): Selection funnel Policy Matrix
    WHEN 'selection_approved'            THEN 'transactional_immediate'
    WHEN 'selection_interview_scheduled' THEN 'transactional_immediate'
    WHEN 'peer_review_requested'         THEN 'transactional_immediate'
    WHEN 'selection_evaluation_complete' THEN 'suppress'
    WHEN 'selection_interview_noshow'    THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 2 (2026-05-23): admin reminder for overdue interviews
    WHEN 'selection_interview_overdue'   THEN 'digest_weekly'
    -- (end p228)
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

-- 2. Cron RPC — idempotent overdue scanner
CREATE OR REPLACE FUNCTION public._selection_interview_overdue_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $func$
DECLARE
  v_inserted_count int := 0;
  v_run_at timestamptz := now();
BEGIN
  -- One row per (interview, interviewer) pair. 7-day idempotency guard.
  WITH stale_pairs AS (
    SELECT si.id           AS interview_id,
           si.application_id,
           si.scheduled_at,
           recipient_uuid   AS recipient_id,
           sa.email         AS applicant_email,
           sa.applicant_name AS applicant_name,
           sa.first_name    AS applicant_first_name,
           sa.last_name     AS applicant_last_name,
           EXTRACT(DAY FROM now() - si.scheduled_at)::int AS days_overdue
    FROM public.selection_interviews si
    CROSS JOIN LATERAL unnest(si.interviewer_ids) AS recipient_uuid
    JOIN public.selection_applications sa ON sa.id = si.application_id
    WHERE si.conducted_at IS NULL
      AND si.status IN ('scheduled', 'rescheduled')
      AND si.scheduled_at IS NOT NULL
      AND si.scheduled_at < now() - interval '24 hours'
      AND recipient_uuid IS NOT NULL
  ),
  to_insert AS (
    SELECT sp.*
    FROM stale_pairs sp
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.notifications n
      WHERE n.type = 'selection_interview_overdue'
        AND n.source_type = 'selection_interview'
        AND n.source_id = sp.interview_id
        AND n.recipient_id = sp.recipient_id
        AND n.created_at > now() - interval '7 days'
    )
  ),
  inserted AS (
    INSERT INTO public.notifications (
      recipient_id,
      type,
      title,
      body,
      link,
      source_type,
      source_id,
      delivery_mode
    )
    SELECT
      ti.recipient_id,
      'selection_interview_overdue',
      'Entrevista de seleção em atraso',
      format(
        'Entrevista com %s agendada para %s (%s dia%s atrás) ainda não foi marcada como conduzida. Atualize o status em /admin/selection.',
        COALESCE(
          NULLIF(trim(ti.applicant_name), ''),
          NULLIF(trim(ti.applicant_first_name || ' ' || COALESCE(ti.applicant_last_name, '')), ''),
          ti.applicant_email,
          'candidato'
        ),
        to_char(ti.scheduled_at AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
        ti.days_overdue,
        CASE WHEN ti.days_overdue = 1 THEN '' ELSE 's' END
      ),
      '/admin/selection/applications/' || ti.application_id::text,
      'selection_interview',
      ti.interview_id,
      public._delivery_mode_for('selection_interview_overdue')
    FROM to_insert ti
    RETURNING 1
  )
  SELECT count(*)::int INTO v_inserted_count FROM inserted;

  RETURN jsonb_build_object(
    'success', true,
    'inserted', v_inserted_count,
    'run_at', v_run_at,
    'idempotency_window_days', 7,
    'overdue_grace_hours', 24
  );
END;
$func$;

REVOKE ALL ON FUNCTION public._selection_interview_overdue_cron() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._selection_interview_overdue_cron() TO service_role;

COMMENT ON FUNCTION public._selection_interview_overdue_cron() IS
'p228 #260 W2 Leaf 2: cron-driven admin alert for overdue selection interviews. '
'Scans selection_interviews WHERE status IN (scheduled,rescheduled) AND '
'scheduled_at < NOW() - 24h AND conducted_at IS NULL. Emits one notification per '
'(interview, interviewer) pair with 7-day idempotency window. Returns jsonb with '
'inserted count + run timestamp. Routes via _delivery_mode_for -> digest_weekly.';

-- 3. pg_cron schedule — daily 14:00 UTC (11:00 BRT)
-- Idempotent: unschedule prior version if it exists, then schedule fresh.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'selection-interview-overdue-daily') THEN
    PERFORM cron.unschedule('selection-interview-overdue-daily');
  END IF;
END $$;

SELECT cron.schedule(
  'selection-interview-overdue-daily',
  '0 14 * * *',
  $cron$ SELECT public._selection_interview_overdue_cron() $cron$
);

NOTIFY pgrst, 'reload schema';
