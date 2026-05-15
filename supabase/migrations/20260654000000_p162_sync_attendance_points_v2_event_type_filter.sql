-- p162 Track C — sync_attendance_points: event.type filter + config-driven base_points
-- PM directive: only ritual meetings pay (tribo|geral|lideranca|kickoff).
-- Exclude: 1on1, entrevista, parceria, evento_externo, webinar (audience-event, not ritual).
-- ADR-0081 alignment: lookup base_points from gamification_rules (forward-only) instead of hardcoded 10.
--
-- Narrowed scope (v3): legacy course/trail + publication blocks split out due to type-cast bugs
-- (uuid vs integer comparing gp.ref_id vs cp.course_id) that aborted entire function. Those blocks
-- can be re-added in separate RPC when type fix lands (tracked as backlog P162-LEGACY-XP).
--
-- Companion DML (run separately via execute_sql, not in this migration):
--   DELETE FROM gamification_points WHERE category='attendance' AND ref_id IN (
--     SELECT a.event_id OR a.id FROM attendance a JOIN events e ON e.id=a.event_id
--     WHERE e.type IN ('1on1','entrevista','parceria','evento_externo','webinar')
--   );  -- removed 9 over-pay rows (3 parceria, 5 1on1, 1 entrevista) = 90 pts
--   SELECT sync_attendance_points();  -- backfilled 217 rows (77 geral, 135 tribo, 5 lideranca)

CREATE OR REPLACE FUNCTION public.sync_attendance_points()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_att INTEGER := 0;
  v_attendance_pts INTEGER;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Acesso negado');
  END IF;

  SELECT base_points INTO v_attendance_pts
  FROM public.gamification_rules
  WHERE slug = 'attendance' AND active = true AND effective_from <= now()
  ORDER BY effective_from DESC LIMIT 1;
  IF v_attendance_pts IS NULL THEN v_attendance_pts := 10; END IF;

  INSERT INTO public.gamification_points (member_id, points, reason, category, ref_id, created_at)
  SELECT a.member_id, v_attendance_pts, 'Presença: ' || e.title, 'attendance', a.event_id, e.date::timestamptz
  FROM public.attendance a JOIN public.events e ON e.id = a.event_id
  WHERE a.present = true
    AND e.type IN ('tribo','geral','lideranca','kickoff')
    AND (e.status IS NULL OR e.status != 'cancelled')
    AND NOT EXISTS (
      SELECT 1 FROM public.gamification_points gp WHERE gp.member_id = a.member_id
      AND gp.category = 'attendance' AND gp.ref_id = a.event_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.gamification_points gp WHERE gp.member_id = a.member_id
      AND gp.category = 'attendance' AND gp.ref_id = a.id);
  GET DIAGNOSTICS v_att = ROW_COUNT;

  RETURN json_build_object('success', true, 'attendance_inserted', v_att, 'pts_per_event', v_attendance_pts);
END;
$function$;

COMMENT ON FUNCTION public.sync_attendance_points() IS
'Sync attendance XP only (config-driven from gamification_rules) for ritual meetings (tribo|geral|lideranca|kickoff). p162 Track C: scope narrowed — legacy course/trail + publication blocks split out (type-cast bugs uuid vs integer; backlog P162-LEGACY-XP). Skips cancelled events + already-paid (both ref_id formats). Ver ADR-0081 + memory/feedback_audit_rpc_insert_vs_table_columns.md.';

NOTIFY pgrst, 'reload schema';

-- Rollback: restore prior body (which had course/trail/publication blocks); but they fail at runtime
-- so rollback is symbolic — keep this version unless backlog P162-LEGACY-XP fix lands.
