-- ARM-9 Features G4: inactivity detection cron
-- Threshold configurável via site_config.inactivity_threshold_days (default 180)
-- detect_inactive_members() finds active members with no attendance in N days,
-- notifies managers proposing transition to inactive. Manager decides via UI.

INSERT INTO public.site_config (key, value)
VALUES ('inactivity_threshold_days', to_jsonb(180))
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.detect_inactive_members(p_dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_threshold int;
  v_candidates jsonb := '[]'::jsonb;
  v_count int := 0;
  v_notified int := 0;
  v_cron_context boolean;
BEGIN
  v_cron_context := (current_setting('role', true) IN ('service_role','postgres')
                     OR current_user IN ('postgres','supabase_admin'));

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
      m.id AS member_id, m.name, m.email, m.tribe_id, m.chapter,
      m.created_at AS member_created_at,
      (SELECT MAX(a.checked_in_at) FROM public.attendance a
        WHERE a.member_id = m.id AND a.present = true) AS last_attendance_at,
      m.updated_at AS last_member_update_at
    FROM public.members m
    WHERE m.member_status = 'active' AND m.is_active = true AND m.anonymized_at IS NULL
      AND m.name <> 'VP Desenvolvimento Profissional (PMI-GO)'
      AND m.created_at < (now() - make_interval(days => v_threshold))
      AND NOT EXISTS (
        SELECT 1 FROM public.attendance a
        WHERE a.member_id = m.id AND a.present = true
          AND a.checked_in_at > (now() - make_interval(days => v_threshold))
      )
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'member_id', member_id, 'name', name, 'chapter', chapter, 'tribe_id', tribe_id,
    'last_attendance_at', last_attendance_at,
    'days_since_last_attendance',
      CASE WHEN last_attendance_at IS NULL
        THEN EXTRACT(DAY FROM now() - member_created_at)::int
        ELSE EXTRACT(DAY FROM now() - last_attendance_at)::int
      END
  )), '[]'::jsonb), COALESCE(COUNT(*), 0)
  INTO v_candidates, v_count
  FROM inactive;

  IF NOT p_dry_run AND v_count > 0 THEN
    INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT mgr.id,
           'arm9_inactivity_alert',
           v_count || ' membro(s) sem atividade há mais de ' || v_threshold || ' dias',
           'Considerar transição para status inactive. Lista disponível em /admin/members?filter=inactive_candidates',
           '/admin/members?filter=inactive_candidates',
           'arm9_inactivity_detection', NULL
    FROM public.members mgr
    WHERE mgr.is_active = true AND mgr.operational_role IN ('manager','deputy_manager');
    GET DIAGNOSTICS v_notified = ROW_COUNT;

    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (NULL, 'arm9.inactivity_detection_run', NULL, NULL,
      jsonb_build_object('threshold_days', v_threshold, 'candidates_count', v_count, 'managers_notified', v_notified),
      jsonb_build_object('dry_run', false, 'source', 'cron_or_manual'));
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'threshold_days', v_threshold,
    'candidates_count', v_count, 'candidates', v_candidates,
    'managers_notified', v_notified, 'dry_run', p_dry_run
  );
END $$;

REVOKE ALL ON FUNCTION public.detect_inactive_members(boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.detect_inactive_members(boolean) TO authenticated, service_role;

COMMENT ON FUNCTION public.detect_inactive_members(boolean) IS
'ARM-9 Features G4. Finds active members with no attendance in inactivity_threshold_days (default 180, configurable via site_config). Returns candidates list. If p_dry_run=false, notifies managers proposing transition. Cron-context aware (ADR-0028).';

DO $$ BEGIN PERFORM cron.unschedule('detect-inactive-members-weekly');
EXCEPTION WHEN OTHERS THEN NULL; END $$;

SELECT cron.schedule(
  'detect-inactive-members-weekly',
  '0 12 * * 1',
  $$SELECT public.detect_inactive_members(p_dry_run := false);$$
);

NOTIFY pgrst, 'reload schema';
