-- Phase B'' batch 17.4: remove_event_showcase V3 → V4 can_by_member('manage_event')
-- Same V3/V4 mapping as register_event_showcase
-- Impact: V3=8, V4=8 (clean match)
CREATE OR REPLACE FUNCTION public.remove_event_showcase(p_showcase_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_event'::text) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM event_showcases WHERE id = p_showcase_id) THEN
    RETURN jsonb_build_object('error', 'Showcase not found');
  END IF;

  DELETE FROM gamification_points WHERE ref_id = p_showcase_id AND category = 'showcase';
  DELETE FROM event_showcases WHERE id = p_showcase_id;

  RETURN jsonb_build_object('success', true, 'removed_id', p_showcase_id);
END;
$function$;
