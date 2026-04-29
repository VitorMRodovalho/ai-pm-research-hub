-- Phase B'' batch 20.3: get_onboarding_dashboard V3 admin gate → V4 can_by_member('manage_platform')
-- V3: is_superadmin OR operational_role IN ('manager','deputy_manager')
-- V4: manage_platform (covers sa + manager/deputy_manager/co_gp)
-- Impact: V3=2, V4=2 (clean match; +co_gp parity)
CREATE OR REPLACE FUNCTION public.get_onboarding_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public, pg_temp'
AS $function$
DECLARE v_caller_id uuid; v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform'::text) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
      'fully_onboarded', (SELECT count(DISTINCT m.id) FROM members m
        WHERE m.is_active AND m.current_cycle_active
        AND NOT EXISTS (SELECT 1 FROM onboarding_steps s JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = m.id WHERE s.is_required AND op.status != 'completed')
        AND EXISTS (SELECT 1 FROM onboarding_progress op2 WHERE op2.member_id = m.id)),
      'not_started', (SELECT count(DISTINCT m.id) FROM members m
        WHERE m.is_active AND m.current_cycle_active
        AND NOT EXISTS (SELECT 1 FROM onboarding_progress op WHERE op.member_id = m.id AND op.status = 'completed'))
    ),
    'members', (SELECT jsonb_agg(row_to_json(t) ORDER BY t.completed_count ASC, t.name) FROM (
      SELECT m.id, m.name, m.photo_url, m.chapter, m.tribe_id,
        (SELECT count(*) FROM onboarding_progress op WHERE op.member_id = m.id AND op.status = 'completed' AND op.step_key IN (SELECT id FROM onboarding_steps)) AS completed_count,
        (SELECT count(*) FROM onboarding_steps WHERE is_required) AS total_steps,
        (SELECT max(op.updated_at) FROM onboarding_progress op WHERE op.member_id = m.id) AS last_activity
      FROM members m WHERE m.is_active AND m.current_cycle_active
    ) t)
  ) INTO v_result;
  RETURN v_result;
END; $function$;
