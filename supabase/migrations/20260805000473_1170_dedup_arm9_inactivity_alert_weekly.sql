-- #1170: dedup arm9_inactivity_alert to the intended weekly cadence.
--
-- Symptom (measured live 2026-07-21): arm9_inactivity_alert produced 5-57 rows/day
-- at scattered times for the 2 manage_platform admins, delivery_mode=digest_weekly,
-- 0 emailed. Heavy in-app noise + digest bloat.
--
-- Root: arm9 is produced ONLY by detect_inactive_members(p_dry_run=false). The only
-- scheduled caller is the weekly cron (jobid 40, Mon 12:00 UTC), yet the audit trail
-- (admin_audit_log 'arm9.inactivity_detection_run') shows dozens of dry_run=false runs
-- per day from a REST/direct caller not present in the current frontend (the admin
-- island calls dry_run=true and never inserts). Exact rogue caller unconfirmed.
--
-- Fix is caller-agnostic and lives in the function: suppress the notification for any
-- recipient who already received an arm9 alert in the last 6 days, collapsing the
-- fan-out to at most ~1 alert per admin per week (the weekly cron's intended cadence),
-- regardless of how often (or by whom) the detector is invoked. The alert body only
-- points to the live /admin/members?filter=inactive_candidates dashboard, so a slightly
-- stale count within the window is immaterial. The window is 6 (not 7) days on purpose:
-- consecutive Monday cron runs are exactly 7 days apart, so a 7-day window would clip
-- the legitimate weekly alert by the few seconds the prior run took to insert. Only this
-- WHERE clause changed; the rest of the body is byte-identical to the live definition
-- (pg_get_functiondef).
--
-- Second statement: _test_detect_inactive_with_threshold (the hermetic INSERT-path test
-- helper) is updated to clear recent arm9 alerts before the real dry_run=false call,
-- guarded by a side-effect-free dry-run probe, so the dedup above does not make the
-- contract test detect-inactive-members-non-dry-run.test.mjs (#3) flakily fail its
-- managers_notified>0 assertion when prod already holds recent arm9 rows.

CREATE OR REPLACE FUNCTION public.detect_inactive_members(p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_threshold int;
  v_candidates jsonb := '[]'::jsonb;
  v_count int := 0;
  v_notified int := 0;
  v_cron_context boolean;
BEGIN
  -- #684: role-GUC discriminator (current_user is always the SECDEF owner under SECDEF).
  v_cron_context := NOT public._request_is_rest_caller();

  IF NOT v_cron_context AND auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF NOT v_cron_context THEN
    PERFORM 1 FROM public.members
    WHERE auth_id = auth.uid()
      AND public.can_by_member(id, 'manage_member');
    IF NOT FOUND THEN RAISE EXCEPTION 'Unauthorized: requires manage_member'; END IF;
  END IF;

  SELECT COALESCE((value::text)::int, 180) INTO v_threshold
  FROM public.site_config WHERE key = 'inactivity_threshold_days';
  v_threshold := COALESCE(v_threshold, 180);

  WITH inactive AS (
    SELECT
      m.id AS member_id,
      m.name,
      m.email,
      m.tribe_id,
      m.chapter,
      m.created_at AS member_created_at,
      (SELECT MAX(a.checked_in_at) FROM public.attendance a
        WHERE a.member_id = m.id AND a.present = true) AS last_attendance_at,
      m.updated_at AS last_member_update_at
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.is_active = true
      AND m.anonymized_at IS NULL
      AND m.name <> 'VP Desenvolvimento Profissional (PMI-GO)'
      -- Exclude very recent joins (need at least threshold days history)
      AND m.created_at < (now() - make_interval(days => v_threshold))
      -- Either no attendance ever, OR last attendance older than threshold
      AND NOT EXISTS (
        SELECT 1 FROM public.attendance a
        WHERE a.member_id = m.id AND a.present = true
          AND a.checked_in_at > (now() - make_interval(days => v_threshold))
      )
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'member_id', member_id,
    'name', name,
    'chapter', chapter,
    'tribe_id', tribe_id,
    'last_attendance_at', last_attendance_at,
    'days_since_last_attendance',
      CASE WHEN last_attendance_at IS NULL
        THEN EXTRACT(DAY FROM now() - member_created_at)::int
        ELSE EXTRACT(DAY FROM now() - last_attendance_at)::int
      END
  )), '[]'::jsonb), COALESCE(COUNT(*), 0)
  INTO v_candidates, v_count
  FROM inactive;

  -- p179 ADR-0011 V4: notify admins via manage_platform capability
  -- (replaces operational_role IN ('manager','deputy_manager')).
  IF NOT p_dry_run AND v_count > 0 THEN
    INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT mgr.id,
           'arm9_inactivity_alert',
           v_count || ' membro(s) sem atividade há mais de ' || v_threshold || ' dias',
           'Considerar transição para status inactive. Lista disponível em /admin/members?filter=inactive_candidates',
           '/admin/members?filter=inactive_candidates',
           'arm9_inactivity_detection',
           NULL
    FROM public.members mgr
    WHERE mgr.is_active = true
      AND can_by_member(mgr.id, 'manage_platform')
      -- #1170: collapse to the weekly cadence. Suppress if this recipient already
      -- received an arm9 alert in the last 6 days, so a runaway caller cannot spam
      -- the in-app inbox (was 5-57 alerts/day/admin). 6 (not 7) days keeps the weekly
      -- Monday cron alert from clipping itself at the exact 7-day boundary.
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = mgr.id
          AND n.type = 'arm9_inactivity_alert'
          AND n.created_at > (now() - interval '6 days')
      );
    GET DIAGNOSTICS v_notified = ROW_COUNT;

    -- p180 fix: target_type='system_event' explicit. p179 passed NULL which
    -- overrides column DEFAULT 'member' and triggers NOT NULL violation.
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'arm9.inactivity_detection_run', 'system_event', NULL,
      jsonb_build_object('threshold_days', v_threshold, 'candidates_count', v_count, 'managers_notified', v_notified),
      jsonb_build_object('dry_run', false, 'source', 'cron_or_manual')
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'threshold_days', v_threshold,
    'candidates_count', v_count,
    'candidates', v_candidates,
    'managers_notified', v_notified,
    'dry_run', p_dry_run
  );
END $function$;


CREATE OR REPLACE FUNCTION public._test_detect_inactive_with_threshold(p_threshold integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_old_value jsonb;
  v_result jsonb;
BEGIN
  -- Defense: service_role only (matches detect_inactive_members cron-bypass check).
  -- Phrasing aligned with ADR-0011 canonical hasAuthGate set (p187 MED-186.F).
  IF current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: _test_detect_inactive_with_threshold requires service_role';
  END IF;

  IF p_threshold < 0 THEN
    RAISE EXCEPTION 'p_threshold must be >= 0 (got %)', p_threshold;
  END IF;

  -- Snapshot current site_config value
  SELECT value INTO v_old_value
    FROM public.site_config
   WHERE key = 'inactivity_threshold_days';

  -- Override
  UPDATE public.site_config
     SET value = to_jsonb(p_threshold)
   WHERE key = 'inactivity_threshold_days';

  -- Run real function inside a nested PL/pgSQL exception block so we can restore
  -- site_config even if detect_inactive_members raises. (This is a BEGIN/EXCEPTION
  -- frame, not a SQL SAVEPOINT statement — PG implicitly creates a subtransaction
  -- savepoint for the frame, but the SAVEPOINT/RELEASE keywords are not issued.)
  BEGIN
    -- #1170: detect_inactive_members now dedups arm9_inactivity_alert to a 6-day
    -- window. The hermetic INSERT-path test asserts managers_notified>0, which the
    -- dedup would defeat whenever prod already holds recent arm9 rows. Probe with a
    -- side-effect-free dry_run (candidates_count only) and, ONLY when candidates
    -- exist under the override, clear recent arm9 so the real dry_run=false call is
    -- not suppressed. The probe guard keeps the misuse path (threshold with no
    -- candidates, no tx=rollback) from ever deleting committed rows.
    IF (public.detect_inactive_members(p_dry_run := true)->>'candidates_count')::int > 0 THEN
      DELETE FROM public.notifications
       WHERE type = 'arm9_inactivity_alert'
         AND created_at > (now() - interval '6 days');
    END IF;
    v_result := public.detect_inactive_members(p_dry_run := false);
  EXCEPTION WHEN OTHERS THEN
    UPDATE public.site_config
       SET value = v_old_value
     WHERE key = 'inactivity_threshold_days';
    RAISE;
  END;

  -- Defensive restore (belt+suspenders for cases where caller forgot tx=rollback)
  UPDATE public.site_config
     SET value = v_old_value
   WHERE key = 'inactivity_threshold_days';

  RETURN v_result;
END;
$function$;
