-- ============================================================================
-- V4 Phase 4 — Migration 5/5: daily expiration shadow trigger
-- ADR: ADR-0007 (Authority as Derived Grant from Active Engagements)
-- Rollback: SELECT cron.unschedule('v4_engagement_expiration_shadow');
--           DROP FUNCTION public.v4_expire_engagements_shadow();
-- ============================================================================

-- Shadow mode: logs which engagements WOULD be expired, but does NOT change status.
-- After 2 weeks of shadow validation, cutover to actually expire them.

CREATE OR REPLACE FUNCTION public.v4_expire_engagements_shadow()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_expired_count integer;
  v_details jsonb;
BEGIN
  -- Find engagements that should be expired
  SELECT count(*), COALESCE(jsonb_agg(jsonb_build_object(
    'engagement_id', e.id,
    'person_name', p.name,
    'kind', e.kind,
    'role', e.role,
    'end_date', e.end_date,
    'initiative', i.title
  )), '[]'::jsonb)
  INTO v_expired_count, v_details
  FROM public.engagements e
  JOIN public.persons p ON p.id = e.person_id
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.status = 'active'
    AND e.end_date IS NOT NULL
    AND e.end_date < CURRENT_DATE;

  -- Log to admin_audit_log (shadow only, no status change)
  IF v_expired_count > 0 THEN
    INSERT INTO public.admin_audit_log (action, actor_id, target_type, metadata)
    VALUES (
      'v4_expiration_shadow',
      NULL,
      'engagement',
      jsonb_build_object(
        'mode', 'shadow',
        'would_expire_count', v_expired_count,
        'details', v_details,
        'run_at', now()
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'mode', 'shadow',
    'would_expire', v_expired_count,
    'run_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.v4_expire_engagements_shadow() IS 'V4: Shadow expiration — logs expired engagements without changing status. Activate real expiration after 2-week validation.';

-- Schedule daily at 03:00 UTC (shadow mode)
SELECT cron.schedule(
  'v4_engagement_expiration_shadow',
  '0 3 * * *',
  $$SELECT public.v4_expire_engagements_shadow()$$
);

NOTIFY pgrst, 'reload schema';
