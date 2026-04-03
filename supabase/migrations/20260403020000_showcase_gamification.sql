-- Showcase / Protagonismo em Reuniões Gerais
-- New gamification category to reward members who present at general meetings
-- Table, RPCs, CHECK constraint, VIEW update

BEGIN;

-- 1. Table event_showcases
CREATE TABLE IF NOT EXISTS public.event_showcases (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id      uuid NOT NULL REFERENCES public.events(id),
  member_id     uuid NOT NULL REFERENCES public.members(id),
  showcase_type text NOT NULL CHECK (showcase_type IN (
    'case_study', 'tool_review', 'prompt_week', 'quick_insight', 'awareness'
  )),
  title         text,
  notes         text,
  duration_min  smallint,
  registered_by uuid REFERENCES public.members(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE(event_id, member_id, showcase_type)
);

ALTER TABLE public.event_showcases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "event_showcases_select" ON public.event_showcases
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "event_showcases_manage" ON public.event_showcases
  FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM members WHERE auth_id = auth.uid()
      AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager','tribe_leader')))
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM members WHERE auth_id = auth.uid()
      AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager','tribe_leader')))
  );

-- 2. Add 'showcase' to gamification_points CHECK constraint
ALTER TABLE public.gamification_points DROP CONSTRAINT IF EXISTS gamification_points_category_check;
ALTER TABLE public.gamification_points ADD CONSTRAINT gamification_points_category_check
  CHECK (category = ANY (ARRAY[
    'attendance', 'course', 'artifact', 'bonus',
    'trail', 'cert_pmi_senior', 'cert_cpmai', 'cert_pmi_mid',
    'cert_pmi_practitioner', 'cert_pmi_entry', 'specialization',
    'knowledge_ai_pm', 'badge', 'showcase'
  ]));

-- 3. RPC register_event_showcase
-- XP: case_study=25, tool_review=20, prompt_week=20, quick_insight=15, awareness=15
-- Rules: member must be present, max 2 per member per event
CREATE OR REPLACE FUNCTION public.register_event_showcase(
  p_event_id uuid, p_member_id uuid, p_showcase_type text,
  p_title text DEFAULT NULL, p_notes text DEFAULT NULL, p_duration_min int DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_caller record;
  v_showcase_id uuid;
  v_xp int;
  v_count int;
  v_type_label text;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF v_caller.is_superadmin IS NOT TRUE
     AND v_caller.operational_role NOT IN ('manager', 'deputy_manager', 'tribe_leader') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM attendance WHERE event_id = p_event_id AND member_id = p_member_id) THEN
    RETURN jsonb_build_object('error', 'Member must be present at the event');
  END IF;

  SELECT count(*) INTO v_count FROM event_showcases
  WHERE event_id = p_event_id AND member_id = p_member_id;
  IF v_count >= 2 THEN
    RETURN jsonb_build_object('error', 'Maximum 2 showcases per member per meeting');
  END IF;

  v_xp := CASE p_showcase_type
    WHEN 'case_study' THEN 25 WHEN 'tool_review' THEN 20
    WHEN 'prompt_week' THEN 20 WHEN 'quick_insight' THEN 15
    WHEN 'awareness' THEN 15 ELSE 15
  END;

  v_type_label := CASE p_showcase_type
    WHEN 'case_study' THEN 'Case de Sucesso' WHEN 'tool_review' THEN 'Review de Ferramenta'
    WHEN 'prompt_week' THEN 'Prompt da Semana' WHEN 'quick_insight' THEN 'Insight Rápido'
    WHEN 'awareness' THEN 'Sensibilização' ELSE p_showcase_type
  END;

  INSERT INTO event_showcases (event_id, member_id, showcase_type, title, notes, duration_min, registered_by)
  VALUES (p_event_id, p_member_id, p_showcase_type, p_title, p_notes, p_duration_min::smallint, v_caller.id)
  RETURNING id INTO v_showcase_id;

  INSERT INTO gamification_points (member_id, points, reason, category, ref_id)
  VALUES (p_member_id, v_xp,
    'Showcase: ' || v_type_label || COALESCE(' — ' || p_title, ''),
    'showcase', v_showcase_id);

  RETURN jsonb_build_object('id', v_showcase_id, 'member_id', p_member_id,
    'showcase_type', p_showcase_type, 'xp_awarded', v_xp);
END;
$$;
GRANT EXECUTE ON FUNCTION register_event_showcase TO authenticated;

-- 4. RPC remove_event_showcase
CREATE OR REPLACE FUNCTION public.remove_event_showcase(p_showcase_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_caller record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF v_caller.is_superadmin IS NOT TRUE
     AND v_caller.operational_role NOT IN ('manager', 'deputy_manager', 'tribe_leader') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM event_showcases WHERE id = p_showcase_id) THEN
    RETURN jsonb_build_object('error', 'Showcase not found');
  END IF;
  DELETE FROM gamification_points WHERE ref_id = p_showcase_id AND category = 'showcase';
  DELETE FROM event_showcases WHERE id = p_showcase_id;
  RETURN jsonb_build_object('success', true, 'removed_id', p_showcase_id);
END;
$$;
GRANT EXECUTE ON FUNCTION remove_event_showcase TO authenticated;

-- 5. Update gamification_leaderboard VIEW (DROP + CREATE — adds showcase_points)
DROP VIEW IF EXISTS public.gamification_leaderboard;
CREATE VIEW public.gamification_leaderboard AS
WITH current_cycle AS (
  SELECT cycles.cycle_start FROM cycles WHERE cycles.is_current = true LIMIT 1
)
SELECT m.id AS member_id, m.name, m.chapter, m.photo_url, m.operational_role, m.designations,
  COALESCE(sum(gp.points), 0)::integer AS total_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category = 'attendance'), 0)::integer AS attendance_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category IN ('trail','course','knowledge_ai_pm')), 0)::integer AS learning_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category IN ('cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry')), 0)::integer AS cert_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category IN ('badge','specialization')), 0)::integer AS badge_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category = 'artifact'), 0)::integer AS artifact_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category IN ('trail','course','knowledge_ai_pm')), 0)::integer AS course_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category = 'showcase'), 0)::integer AS showcase_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category NOT IN ('attendance','trail','course','knowledge_ai_pm','cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry','badge','specialization','artifact','showcase')), 0)::integer AS bonus_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category = 'attendance' AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_attendance_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category IN ('trail','course','knowledge_ai_pm') AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_course_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category = 'artifact' AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_artifact_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category = 'showcase' AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_showcase_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category NOT IN ('attendance','trail','course','knowledge_ai_pm','cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry','badge','specialization','artifact','showcase') AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_bonus_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category IN ('trail','course','knowledge_ai_pm') AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_learning_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category IN ('cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry') AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_cert_points,
  COALESCE(sum(gp.points) FILTER (WHERE gp.category IN ('badge','specialization') AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_badge_points
FROM members m LEFT JOIN gamification_points gp ON gp.member_id = m.id
WHERE m.current_cycle_active = true
GROUP BY m.id, m.name, m.chapter, m.photo_url, m.operational_role, m.designations;
GRANT SELECT ON public.gamification_leaderboard TO authenticated;

-- 6. Update get_event_detail to include showcases
CREATE OR REPLACE FUNCTION public.get_event_detail(p_event_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_caller record; v_event record; v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  SELECT * INTO v_event FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Event not found'); END IF;
  IF v_event.visibility = 'gp_only' AND v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager', 'deputy_manager') THEN RETURN jsonb_build_object('error', 'Restricted content'); END IF;
  IF v_event.visibility = 'leadership' AND v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager', 'deputy_manager', 'tribe_leader') THEN RETURN jsonb_build_object('error', 'Restricted content'); END IF;
  SELECT jsonb_build_object(
    'event', jsonb_build_object('id', v_event.id, 'title', v_event.title, 'date', v_event.date, 'type', v_event.type, 'tribe_id', v_event.tribe_id, 'duration_minutes', v_event.duration_minutes, 'duration_actual', v_event.duration_actual, 'meeting_link', v_event.meeting_link, 'is_recorded', v_event.is_recorded, 'youtube_url', v_event.youtube_url, 'recording_url', v_event.recording_url, 'recording_type', v_event.recording_type, 'visibility', v_event.visibility),
    'agenda', jsonb_build_object('text', v_event.agenda_text, 'url', v_event.agenda_url, 'posted_at', v_event.agenda_posted_at, 'posted_by', (SELECT m.name FROM members m WHERE m.id = v_event.agenda_posted_by)),
    'minutes', jsonb_build_object('text', v_event.minutes_text, 'url', v_event.minutes_url, 'posted_at', v_event.minutes_posted_at, 'posted_by', (SELECT m.name FROM members m WHERE m.id = v_event.minutes_posted_by)),
    'action_items', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', ai.id, 'description', ai.description, 'assignee_id', ai.assignee_id, 'assignee_name', COALESCE(ai.assignee_name, am.name), 'due_date', ai.due_date, 'status', ai.status, 'carried_to_event_id', ai.carried_to_event_id) ORDER BY ai.created_at), '[]'::jsonb) FROM meeting_action_items ai LEFT JOIN members am ON am.id = ai.assignee_id WHERE ai.event_id = p_event_id AND ai.status != 'cancelled'),
    'attendance', jsonb_build_object('present_count', (SELECT COUNT(*) FROM attendance WHERE event_id = p_event_id), 'members', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', a.member_id, 'name', m.name, 'present', true, 'excused', COALESCE(a.excused, false))), '[]'::jsonb) FROM attendance a JOIN members m ON m.id = a.member_id WHERE a.event_id = p_event_id)),
    'showcases', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', es.id, 'member_id', es.member_id, 'member_name', m.name, 'showcase_type', es.showcase_type, 'title', es.title, 'duration_min', es.duration_min) ORDER BY es.created_at), '[]'::jsonb) FROM event_showcases es JOIN members m ON m.id = es.member_id WHERE es.event_id = p_event_id)
  ) INTO v_result;
  RETURN v_result;
END;
$$;

NOTIFY pgrst, 'reload schema';
COMMIT;
