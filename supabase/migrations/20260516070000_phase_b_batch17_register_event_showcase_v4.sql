-- Phase B'' batch 17.3: register_event_showcase V3 → V4 can_by_member('manage_event')
-- V3: is_superadmin OR operational_role IN ('manager','deputy_manager','tribe_leader')
-- V4: manage_event (covers volunteer manager/deputy_manager/leader/co_gp/comms_leader + others + sa)
-- Impact: V3=8, V4=8 (clean match)
CREATE OR REPLACE FUNCTION public.register_event_showcase(p_event_id uuid, p_member_id uuid, p_showcase_type text, p_title text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_duration_min integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_showcase_id uuid;
  v_xp int;
  v_count int;
  v_type_label text;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_event'::text) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- Validate member is present at event
  IF NOT EXISTS (SELECT 1 FROM attendance WHERE event_id = p_event_id AND member_id = p_member_id) THEN
    RETURN jsonb_build_object('error', 'Member must be present at the event');
  END IF;

  -- Max 2 showcases per member per event
  SELECT count(*) INTO v_count FROM event_showcases
  WHERE event_id = p_event_id AND member_id = p_member_id;
  IF v_count >= 2 THEN
    RETURN jsonb_build_object('error', 'Maximum 2 showcases per member per meeting');
  END IF;

  -- XP mapping
  v_xp := CASE p_showcase_type
    WHEN 'case_study' THEN 25
    WHEN 'tool_review' THEN 20
    WHEN 'prompt_week' THEN 20
    WHEN 'quick_insight' THEN 15
    WHEN 'awareness' THEN 15
    ELSE 15
  END;

  -- Type label for reason
  v_type_label := CASE p_showcase_type
    WHEN 'case_study' THEN 'Case de Sucesso'
    WHEN 'tool_review' THEN 'Review de Ferramenta'
    WHEN 'prompt_week' THEN 'Prompt da Semana'
    WHEN 'quick_insight' THEN 'Insight Rápido'
    WHEN 'awareness' THEN 'Sensibilização'
    ELSE p_showcase_type
  END;

  -- Insert showcase
  INSERT INTO event_showcases (event_id, member_id, showcase_type, title, notes, duration_min, registered_by)
  VALUES (p_event_id, p_member_id, p_showcase_type, p_title, p_notes, p_duration_min::smallint, v_caller.id)
  RETURNING id INTO v_showcase_id;

  -- Insert gamification points
  INSERT INTO gamification_points (member_id, points, reason, category, ref_id)
  VALUES (p_member_id, v_xp,
    'Showcase: ' || v_type_label || COALESCE(' — ' || p_title, ''),
    'showcase', v_showcase_id);

  RETURN jsonb_build_object(
    'id', v_showcase_id,
    'member_id', p_member_id,
    'showcase_type', p_showcase_type,
    'xp_awarded', v_xp
  );
END;
$function$;
