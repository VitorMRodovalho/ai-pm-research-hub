-- Phase B'' Pacote N corrective (p63 ext): revert get_onboarding_dashboard
-- to V3 gate. The Pacote N migration `20260426220602` shifted which body
-- findFunctionBody() in selection-onboarding-diversity.test.mjs picks up,
-- breaking 5 tests that expected the rich-body shape from older migration
-- `20260319100027_w124_phase4_onboarding_diversity.sql`. Production
-- already had the simpler body (drift), but tests were passing on the
-- older migration's rich body via concat ordering.
--
-- Decision: defer get_onboarding_dashboard from Pacote N until a
-- separate effort reconciles body drift (rich vs simple) AND gate (V4).
-- Restore V3 gate via CREATE OR REPLACE with original body.
-- Tests in selection-onboarding-diversity.test.mjs realigned to match
-- production body (drift acknowledged in comment).

DROP FUNCTION IF EXISTS public.get_onboarding_dashboard();
CREATE OR REPLACE FUNCTION public.get_onboarding_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public, pg_temp'
AS $$
DECLARE v_caller record; v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager','deputy_manager')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

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
END; $$;

COMMENT ON FUNCTION public.get_onboarding_dashboard() IS
  'V3 gate (deferred from Pacote N p63 ext): test body drift between rich-body migration `20260319100027` and simpler production body needs reconciliation before V4 conversion. Currently restored to V3 to preserve selection-onboarding-diversity.test.mjs contract.';

NOTIFY pgrst, 'reload schema';
