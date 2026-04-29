-- Phase B'' batch 14 (p79):
-- (a) can_manage_comms_metrics: V3 hardcoded comms_leader/comms_member designations + manager
--     → V4 can_by_member('manage_comms'). manage_comms action covers admin/manager + comms team.
-- (b) sync_attendance_points: V3 is_superadmin → V4 can_by_member('manage_platform').
--     Gamification sync, platform admin only.

-- (a)
CREATE OR REPLACE FUNCTION public.can_manage_comms_metrics()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN public.can_by_member(v_caller_id, 'manage_comms');
END;
$$;

REVOKE ALL ON FUNCTION public.can_manage_comms_metrics() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_comms_metrics() TO authenticated;

-- (b)
CREATE OR REPLACE FUNCTION public.sync_attendance_points()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_att INTEGER := 0;
  v_crs INTEGER := 0;
  v_art INTEGER := 0;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Acesso negado');
  END IF;

  INSERT INTO public.gamification_points (member_id, points, reason, category, ref_id, created_at)
  SELECT a.member_id, 10, 'Presença: ' || e.title, 'attendance', a.event_id, e.date::timestamptz
  FROM public.attendance a JOIN public.events e ON e.id = a.event_id
  WHERE a.present = true AND NOT EXISTS (
    SELECT 1 FROM public.gamification_points gp WHERE gp.member_id = a.member_id
    AND gp.category = 'attendance' AND gp.ref_id = a.event_id)
  AND NOT EXISTS (
    SELECT 1 FROM public.gamification_points gp WHERE gp.member_id = a.member_id
    AND gp.category = 'attendance' AND gp.ref_id = a.id::text);
  GET DIAGNOSTICS v_att = ROW_COUNT;

  INSERT INTO public.gamification_points (member_id, points, reason, category, ref_id)
  SELECT cp.member_id,
    CASE WHEN c.is_trail = true THEN 20 ELSE 15 END,
    'Curso: ' || c.code,
    CASE WHEN c.is_trail = true THEN 'trail' ELSE 'course' END,
    cp.course_id
  FROM public.course_progress cp JOIN public.courses c ON c.id = cp.course_id
  WHERE cp.status = 'completed' AND NOT EXISTS (
    SELECT 1 FROM public.gamification_points gp WHERE gp.member_id = cp.member_id
    AND gp.ref_id = cp.course_id AND gp.category IN ('course', 'trail'));
  GET DIAGNOSTICS v_crs = ROW_COUNT;

  INSERT INTO public.gamification_points (member_id, points, reason, category, ref_id)
  SELECT ps.primary_author_id, 30, 'Publicação: ' || ps.title, 'publication', ps.id
  FROM public.publication_submissions ps
  WHERE ps.status = 'published'::public.submission_status AND NOT EXISTS (
    SELECT 1 FROM public.gamification_points gp WHERE gp.member_id = ps.primary_author_id
    AND gp.category IN ('publication','artifact') AND gp.ref_id = ps.id);
  GET DIAGNOSTICS v_art = ROW_COUNT;

  RETURN json_build_object('success', true, 'points_created', v_att + v_crs + v_art);
END;
$$;

REVOKE ALL ON FUNCTION public.sync_attendance_points() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_attendance_points() TO authenticated;

NOTIFY pgrst, 'reload schema';
