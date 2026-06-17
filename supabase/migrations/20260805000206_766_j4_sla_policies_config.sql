-- #766 J4 (SLA/cadence configurable) — PR 1/2: config foundation.
-- Externalizes the 4 real SLA windows that were hardcoded in the selection crons
-- into a config table (sla_policies) so the GP can tune them via update_sla_policy
-- (PR 2 = admin UI) WITHOUT a deploy. Scope decided with PM: only the 4 true SLAs.
-- Dedup windows (7d interview idempotency, 20h digest) and the 365d apto-a-assinar
-- lookback STAY hardcoded (they are not SLAs). Pre-onboarding step deadlines
-- ([7,14,14,14,30]) stay hardcoded / tuned per-cycle (interval cannot hold an array).
--
-- The 4 policy_keys (seed value = current hardcoded value, proven by parity test):
--   interview_overdue_grace  = 24 hours  (job48 _selection_interview_overdue_cron)
--   stuck_scheduled_grace    = 48 hours  (job52 _selection_stuck_scheduled_rescue_cron)
--   reschedule_nudge_initial = 3 days    (job33 process_pending_reschedule_nudges, 1st literal)
--   reschedule_nudge_repeat  = 3 days    (job33 process_pending_reschedule_nudges, 2nd literal)
--
-- No schema invariant (config is mutable). Crons SELECT value_interval once at run
-- start (never in a loop) with a hardcoded fallback if the row is missing.
--
-- ROLLBACK:
--   -- Restore prior cron bodies from migrations 20260805000009 / 20260805000107 /
--   -- 20260516510002, then:
--   DROP FUNCTION IF EXISTS public.update_sla_policy(text, interval);
--   DROP TABLE IF EXISTS public.sla_policies;
--   NOTIFY pgrst, 'reload schema';

-- 1. Config table (outside ADR-0013 log taxonomy: this is configuration, not a log).
CREATE TABLE IF NOT EXISTS public.sla_policies (
  policy_key     text PRIMARY KEY,
  value_interval interval NOT NULL CHECK (value_interval > interval '0'),
  category       text NOT NULL CHECK (category IN ('sla','idempotency','lookback')),
  description    text,
  min_interval   interval,
  max_interval   interval,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  updated_by     uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

COMMENT ON TABLE public.sla_policies IS
  'Configuration table (outside ADR-0013 log taxonomy): tunable SLA/cadence windows for selection crons, editable by GP via update_sla_policy without a deploy (#766 J4). One row = one named window; crons SELECT value_interval at run start with a hardcoded fallback. min/max_interval are optional guardrails enforced by update_sla_policy.';

-- 2. RLS: any authenticated user may read the (non-PII) windows; writes only via
--    the SECURITY DEFINER update_sla_policy RPC (no direct INSERT/UPDATE/DELETE policy).
ALTER TABLE public.sla_policies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sla_policies_select_authenticated ON public.sla_policies;
CREATE POLICY sla_policies_select_authenticated ON public.sla_policies
  FOR SELECT TO authenticated USING (true);

-- 3. Seed the 4 SLA windows at parity with the current hardcoded values.
--    ON CONFLICT DO NOTHING is intentional: existing rows (e.g. a value the GP later
--    tuned via update_sla_policy) are preserved. Re-running this migration does NOT
--    restore parity — that would need a manual UPDATE.
INSERT INTO public.sla_policies (policy_key, value_interval, category, description) VALUES
  ('interview_overdue_grace', interval '24 hours', 'sla',
   'Grace after a scheduled interview start before the interviewer is nudged it is overdue (job48 _selection_interview_overdue_cron).'),
  ('stuck_scheduled_grace', interval '48 hours', 'sla',
   'Grace after a scheduled interview before a stuck interview_scheduled application is auto-rescued (job52 _selection_stuck_scheduled_rescue_cron).'),
  ('reschedule_nudge_initial', interval '3 days', 'sla',
   'Delay after a reschedule request before the first nudge email (job33 process_pending_reschedule_nudges).'),
  ('reschedule_nudge_repeat', interval '3 days', 'sla',
   'Minimum delay between reschedule nudge emails after the first (job33 process_pending_reschedule_nudges).')
ON CONFLICT (policy_key) DO NOTHING;

-- 4. update_sla_policy — the only write path. Gated by can_by_member(manage_platform).
--    Stores auth.uid() in updated_by (FK -> auth.users(id), NOT members.id).
CREATE OR REPLACE FUNCTION public.update_sla_policy(p_key text, p_value interval)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_member_id uuid;
  v_row public.sla_policies;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL OR NOT public.can_by_member(v_member_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_row FROM public.sla_policies WHERE policy_key = p_key;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unknown policy_key', 'policy_key', p_key);
  END IF;
  IF p_value IS NULL OR p_value <= interval '0' THEN
    RETURN jsonb_build_object('error', 'value must be a positive interval');
  END IF;
  IF v_row.min_interval IS NOT NULL AND p_value < v_row.min_interval THEN
    RETURN jsonb_build_object('error', 'value below min_interval', 'min_interval', v_row.min_interval::text);
  END IF;
  IF v_row.max_interval IS NOT NULL AND p_value > v_row.max_interval THEN
    RETURN jsonb_build_object('error', 'value above max_interval', 'max_interval', v_row.max_interval::text);
  END IF;

  UPDATE public.sla_policies
  SET value_interval = p_value, updated_at = now(), updated_by = auth.uid()
  WHERE policy_key = p_key;

  RETURN jsonb_build_object('success', true, 'policy_key', p_key, 'value_interval', p_value::text);
END; $fn$;
REVOKE ALL ON FUNCTION public.update_sla_policy(text, interval) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_sla_policy(text, interval) TO authenticated;

-- 5. Rewire the 3 crons to read their window from sla_policies (fallback = old literal).
CREATE OR REPLACE FUNCTION public._selection_interview_overdue_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_inserted_count int := 0;
  v_run_at timestamptz := now();
  v_overdue_grace interval;
BEGIN
  SELECT value_interval INTO v_overdue_grace FROM public.sla_policies WHERE policy_key = 'interview_overdue_grace';
  IF v_overdue_grace IS NULL THEN v_overdue_grace := interval '24 hours'; END IF;

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
      AND si.scheduled_at < now() - v_overdue_grace
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
    'overdue_grace_hours', EXTRACT(EPOCH FROM v_overdue_grace) / 3600
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public._selection_stuck_scheduled_rescue_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_app record;
  v_rescued int := 0;
  v_errors int := 0;
  v_run_at timestamptz := now();
  v_grace interval;
BEGIN
  SELECT value_interval INTO v_grace FROM public.sla_policies WHERE policy_key = 'stuck_scheduled_grace';
  IF v_grace IS NULL THEN v_grace := interval '48 hours'; END IF;

  FOR v_app IN
    SELECT a.id AS app_id
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE a.status = 'interview_scheduled'        -- matches the rescue RPC status guard
      AND c.status = 'open'
      AND EXISTS (
        SELECT 1 FROM public.selection_interviews si
        WHERE si.application_id = a.id
          AND si.status = 'scheduled'
          AND si.conducted_at IS NULL
          AND si.scheduled_at IS NOT NULL
          AND si.scheduled_at < now() - v_grace
      )
    ORDER BY a.updated_at ASC                     -- oldest-stuck first
    LIMIT 20                                       -- small-cohort cap
  LOOP
    -- Per-row subtransaction: a single failure (e.g. CUTOFF_NO_BOOKING_URL on re-dispatch,
    -- which rolls that rescue back atomically) never aborts the run.
    BEGIN
      PERFORM public.selection_rescue_stuck_interview(v_app.app_id);
      v_rescued := v_rescued + 1;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
    END;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'selection.stuck_rescue_cron_run', 'system', NULL,
    jsonb_build_object('rescued_count', v_rescued, 'error_count', v_errors),
    jsonb_build_object(
      'rescued_count', v_rescued,
      'error_count', v_errors,
      'run_at', v_run_at,
      'grace_hours', EXTRACT(EPOCH FROM v_grace) / 3600,
      'limit', 20
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'rescued_count', v_rescued,
    'error_count', v_errors,
    'run_at', v_run_at
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.process_pending_reschedule_nudges()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_app record;
  v_cycle record;
  v_first_name text;
  v_booking_url text;
  v_nudges_sent int := 0;
  v_errors jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
  v_processed jsonb := '[]'::jsonb;
  v_nudge_initial interval;
  v_nudge_repeat interval;
BEGIN
  SELECT value_interval INTO v_nudge_initial FROM public.sla_policies WHERE policy_key = 'reschedule_nudge_initial';
  IF v_nudge_initial IS NULL THEN v_nudge_initial := interval '3 days'; END IF;
  SELECT value_interval INTO v_nudge_repeat FROM public.sla_policies WHERE policy_key = 'reschedule_nudge_repeat';
  IF v_nudge_repeat IS NULL THEN v_nudge_repeat := interval '3 days'; END IF;

  -- Cron-context auth bypass (no JWT). Aligns with ADR-0028 amendment p89 pattern.
  -- This RPC is only invoked by pg_cron (no human callers) so explicit role gate
  -- would never pass; we trust the scheduler context.
  IF auth.role() IS NOT NULL AND auth.role() NOT IN ('service_role') AND auth.uid() IS NOT NULL THEN
    -- A real user is calling — they must have manage_member
    IF NOT public.can_by_member(
      (SELECT id FROM public.members WHERE auth_id = auth.uid()),
      'manage_member'
    ) THEN
      RAISE EXCEPTION 'Unauthorized: cron RPC requires manage_member or service_role';
    END IF;
  END IF;

  FOR v_app IN
    SELECT a.id, a.applicant_name, a.email, a.cycle_id,
           a.interview_reschedule_reason,
           a.interview_reschedule_requested_at,
           a.interview_reschedule_last_nudged_at
    FROM public.selection_applications a
    WHERE a.interview_status = 'needs_reschedule'
      AND a.interview_reschedule_requested_at IS NOT NULL
      AND a.interview_reschedule_requested_at < now() - v_nudge_initial
      AND (
        a.interview_reschedule_last_nudged_at IS NULL
        OR a.interview_reschedule_last_nudged_at < now() - v_nudge_repeat
      )
      AND a.status IN ('interview_pending', 'interview_scheduled')
  LOOP
    v_first_name := split_part(v_app.applicant_name, ' ', 1);

    SELECT interview_booking_url INTO v_cycle
    FROM public.selection_cycles
    WHERE id = v_app.cycle_id;

    v_booking_url := COALESCE(
      v_cycle.interview_booking_url,
      'https://calendar.app.google/gh9WjefjcmisVLoh7'  -- PM 2026-05-05 fallback
    );

    BEGIN
      PERFORM public.campaign_send_one_off(
        p_template_slug := 'interview_reschedule_nudge',
        p_to_email := v_app.email,
        p_variables := jsonb_build_object(
          'first_name', v_first_name,
          'reason', COALESCE(v_app.interview_reschedule_reason, '—'),
          'booking_url', v_booking_url
        ),
        p_metadata := jsonb_build_object(
          'source', 'process_pending_reschedule_nudges',
          'application_id', v_app.id,
          'reschedule_requested_at', v_app.interview_reschedule_requested_at,
          'last_nudged_at_before', v_app.interview_reschedule_last_nudged_at,
          'days_pending', EXTRACT(EPOCH FROM (now() - v_app.interview_reschedule_requested_at)) / 86400.0
        )
      );

      UPDATE public.selection_applications
      SET interview_reschedule_last_nudged_at = now()
      WHERE id = v_app.id;

      v_nudges_sent := v_nudges_sent + 1;
      v_processed := v_processed || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'days_since_request', EXTRACT(EPOCH FROM (now() - v_app.interview_reschedule_requested_at)) / 86400.0
      );

    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_object(
        'application_id', v_app.id,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'nudges_sent', v_nudges_sent,
    'processed', v_processed,
    'errors', v_errors,
    'run_at', now()
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
