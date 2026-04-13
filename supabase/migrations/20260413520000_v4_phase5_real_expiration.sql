-- ============================================================================
-- V4 Phase 5 — Migration 3/3: Real engagement expiration + notifications
-- ADR: ADR-0008 (Per-Kind Engagement Lifecycle with Explicit LGPD Basis)
-- Rollback: SELECT cron.unschedule('v4_engagement_expiration');
--           DROP FUNCTION public.v4_expire_engagements();
--           DROP FUNCTION public.v4_notify_expiring_engagements();
--           (shadow function remains as fallback)
-- ============================================================================

-- Real expiration: reads auto_expire_behavior per kind
-- - 'suspend': set status='suspended' (reversible, keeps access paused)
-- - 'offboard': set status='offboarded' (final, triggers retention countdown)
-- - 'notify_only': log only, manual action required

CREATE OR REPLACE FUNCTION public.v4_expire_engagements()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_suspended int := 0;
  v_offboarded int := 0;
  v_notified int := 0;
  v_details jsonb := '[]'::jsonb;
  v_engagement record;
BEGIN
  FOR v_engagement IN
    SELECT
      e.id AS engagement_id,
      e.person_id,
      p.name AS person_name,
      e.kind,
      e.role,
      e.end_date,
      ek.auto_expire_behavior,
      ek.renewable,
      i.title AS initiative_title
    FROM public.engagements e
    JOIN public.persons p ON p.id = e.person_id
    JOIN public.engagement_kinds ek ON ek.slug = e.kind
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.status = 'active'
      AND e.end_date IS NOT NULL
      AND e.end_date < CURRENT_DATE
  LOOP
    CASE v_engagement.auto_expire_behavior
      WHEN 'suspend' THEN
        UPDATE public.engagements SET status = 'suspended', updated_at = now()
        WHERE id = v_engagement.engagement_id;
        v_suspended := v_suspended + 1;

      WHEN 'offboard' THEN
        UPDATE public.engagements SET status = 'offboarded', updated_at = now()
        WHERE id = v_engagement.engagement_id;
        v_offboarded := v_offboarded + 1;

      WHEN 'notify_only' THEN
        v_notified := v_notified + 1;
    END CASE;

    v_details := v_details || jsonb_build_object(
      'engagement_id', v_engagement.engagement_id,
      'person_name', v_engagement.person_name,
      'kind', v_engagement.kind,
      'role', v_engagement.role,
      'end_date', v_engagement.end_date,
      'action', v_engagement.auto_expire_behavior,
      'renewable', v_engagement.renewable
    );
  END LOOP;

  -- Audit log
  IF (v_suspended + v_offboarded + v_notified) > 0 THEN
    INSERT INTO public.admin_audit_log (action, actor_id, target_type, metadata)
    VALUES (
      'v4_engagement_expiration',
      NULL,
      'engagement',
      jsonb_build_object(
        'mode', 'real',
        'suspended', v_suspended,
        'offboarded', v_offboarded,
        'notify_only', v_notified,
        'details', v_details,
        'run_at', now()
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'mode', 'real',
    'suspended', v_suspended,
    'offboarded', v_offboarded,
    'notify_only', v_notified,
    'total', v_suspended + v_offboarded + v_notified,
    'run_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.v4_expire_engagements() IS
  'V4/ADR-0008: Real engagement expiration. Reads auto_expire_behavior per kind: suspend, offboard, or notify_only.';

-- Notification function: warns members N days before expiry
CREATE OR REPLACE FUNCTION public.v4_notify_expiring_engagements()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_count int := 0;
  v_engagement record;
BEGIN
  FOR v_engagement IN
    SELECT
      e.id AS engagement_id,
      e.person_id,
      p.legacy_member_id,
      p.name AS person_name,
      e.kind,
      e.role,
      e.end_date,
      ek.notify_before_expiry_days,
      ek.renewable,
      ek.display_name AS kind_name,
      i.title AS initiative_title
    FROM public.engagements e
    JOIN public.persons p ON p.id = e.person_id
    JOIN public.engagement_kinds ek ON ek.slug = e.kind
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.status = 'active'
      AND e.end_date IS NOT NULL
      AND ek.notify_before_expiry_days IS NOT NULL
      AND e.end_date BETWEEN CURRENT_DATE AND (CURRENT_DATE + make_interval(days => ek.notify_before_expiry_days))
      -- Don't re-notify: check if already notified for this engagement+date window
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = p.legacy_member_id
          AND n.type = 'engagement_expiring'
          AND n.source_id = e.id
          AND n.created_at > (now() - interval '7 days')
      )
  LOOP
    -- Create notification for member
    IF v_engagement.legacy_member_id IS NOT NULL THEN
      INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id)
      VALUES (
        v_engagement.legacy_member_id,
        'engagement_expiring',
        'Vínculo expirando: ' || v_engagement.kind_name,
        CASE
          WHEN v_engagement.renewable THEN
            'Seu vínculo como ' || v_engagement.kind_name ||
            COALESCE(' na ' || v_engagement.initiative_title, '') ||
            ' expira em ' || v_engagement.end_date || '. Contate a gestão para renovação.'
          ELSE
            'Seu vínculo como ' || v_engagement.kind_name ||
            COALESCE(' na ' || v_engagement.initiative_title, '') ||
            ' expira em ' || v_engagement.end_date || '.'
        END,
        'engagement',
        v_engagement.engagement_id
      );
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'notifications_sent', v_count,
    'run_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.v4_notify_expiring_engagements() IS
  'V4/ADR-0008: Sends notifications to members whose engagements expire within notify_before_expiry_days.';

-- Replace shadow cron with real expiration
SELECT cron.unschedule('v4_engagement_expiration_shadow')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'v4_engagement_expiration_shadow');

SELECT cron.schedule(
  'v4_engagement_expiration',
  '0 3 * * *',
  $$SELECT public.v4_expire_engagements()$$
);

-- Notification cron: daily at 08:00 UTC (business hours BR)
SELECT cron.schedule(
  'v4_engagement_expiry_notify',
  '0 8 * * *',
  $$SELECT public.v4_notify_expiring_engagements()$$
);

NOTIFY pgrst, 'reload schema';
