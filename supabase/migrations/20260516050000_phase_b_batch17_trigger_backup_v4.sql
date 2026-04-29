-- Phase B'' batch 17.2: trigger_backup V3 sa-only → V4 can_by_member('manage_platform')
-- V3: is_superadmin = true
-- V4: manage_platform (covers sa + manager/deputy_manager/co_gp)
-- Impact: V3=2 sa, V4=2 (clean match in current state)
CREATE OR REPLACE FUNCTION public.trigger_backup()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL OR NOT public.can_by_member(v_member_id, 'manage_platform'::text) THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  INSERT INTO admin_audit_log (actor_id, action, target_type, metadata)
  VALUES (v_member_id, 'backup_triggered', 'system',
    jsonb_build_object('trigger', 'manual', 'timestamp', now()));

  RETURN jsonb_build_object('success', true, 'message', 'Backup triggered. Check R2 in ~2 minutes.');
END;
$function$;
