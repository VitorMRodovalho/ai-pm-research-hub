-- Item 8 + Item 4 (handoff 25/Abr): fixes pragmáticos.
--
-- ITEM 8: attendance_rate 1.03 em get_tribe_dashboard. Root cause:
-- denominador conta membros CURRENTES ativos × meetings, mas numerador
-- pode incluir attendance de membros que saíram da tribo mas marcaram
-- presença quando estavam ativos. Guardrail: LEAST(rate, 1.0).
--
-- ITEM 4: events.meeting_link null cascade rule. Trigger BEFORE INSERT
-- herda tribes.meeting_link via legacy_tribe_id se NEW.meeting_link
-- está NULL. Aplica-se a TODOS event creators.

CREATE OR REPLACE FUNCTION public._events_inherit_meeting_link()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tribe_id int;
  v_link text;
BEGIN
  IF NEW.meeting_link IS NULL OR length(trim(NEW.meeting_link)) = 0 THEN
    IF NEW.initiative_id IS NOT NULL THEN
      SELECT i.legacy_tribe_id INTO v_tribe_id
      FROM public.initiatives i WHERE i.id = NEW.initiative_id;
      IF v_tribe_id IS NOT NULL THEN
        SELECT t.meeting_link INTO v_link
        FROM public.tribes t WHERE t.id = v_tribe_id;
        IF v_link IS NOT NULL AND length(trim(v_link)) > 0 THEN
          NEW.meeting_link := v_link;
        END IF;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_events_inherit_meeting_link ON public.events;
CREATE TRIGGER trg_events_inherit_meeting_link
  BEFORE INSERT ON public.events
  FOR EACH ROW
  EXECUTE FUNCTION public._events_inherit_meeting_link();

COMMENT ON FUNCTION public._events_inherit_meeting_link() IS
'Item 4 (handoff 25/Abr): se NEW.meeting_link IS NULL e events.initiative_id aponta para initiative com legacy_tribe_id, herda tribes.meeting_link. Cascade único a todos event creators (create_event, create_initiative_event, create_recurring_weekly_events, link_webinar_event). Resolve sintoma reportado por Ricardo.';

CREATE OR REPLACE FUNCTION public.exec_tribe_dashboard(p_tribe_id integer, p_cycle text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record; v_caller_tribe_id integer;
  v_tribe record; v_leader record; v_cycle_start date; v_result jsonb;
  v_tribe_initiative_id uuid;
  v_members_total int; v_members_active int; v_members_by_role jsonb; v_members_by_chapter jsonb; v_members_list jsonb;
  v_board record; v_prod_total int := 0; v_prod_by_status jsonb := '{}'::jsonb;
  v_articles_submitted int := 0; v_articles_approved int := 0; v_articles_published int := 0;
  v_curation_pending int := 0; v_avg_days_to_approval numeric := 0;
  v_attendance_rate numeric := 0; v_total_meetings int := 0; v_total_hours numeric := 0;
  v_avg_attendance numeric := 0; v_members_with_streak int := 0; v_members_inactive_30d int := 0;
  v_last_meeting_date date; v_next_meeting jsonb := '{}'::jsonb;
  v_tribe_total_xp int := 0; v_tribe_avg_xp numeric := 0;
  v_top_contributors jsonb := '[]'::jsonb; v_cpmai_certified int := 0;
  v_attendance_by_month jsonb := '[]'::jsonb; v_production_by_month jsonb := '[]'::jsonb;
  v_meeting_slots jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;
  v_caller_tribe_id := public.get_member_tribe(v_caller.id);

  IF v_caller_tribe_id IS DISTINCT FROM p_tribe_id
     AND NOT public.can_by_member(v_caller.id, 'manage_platform')
     AND NOT public.can_by_member(v_caller.id, 'view_chapter_dashboards') THEN
    RAISE EXCEPTION 'Unauthorized: cross-tribe view requires manage_platform or view_chapter_dashboards permission';
  END IF;

  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN RAISE EXCEPTION 'Tribe not found'; END IF;

  SELECT id INTO v_tribe_initiative_id
  FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id AND kind = 'research_tribe'
  LIMIT 1;

  v_cycle_start := COALESCE(
    (SELECT MIN(date) FROM public.events WHERE title ILIKE '%kick%off%' AND date >= '2026-01-01'),
    '2026-03-05'::date
  );
  SELECT id, name, photo_url INTO v_leader FROM public.members WHERE id = v_tribe.leader_member_id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('day_of_week', tms.day_of_week, 'time_start', tms.time_start, 'time_end', tms.time_end)), '[]'::jsonb)
  INTO v_meeting_slots
  FROM public.tribe_meeting_slots tms WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true;

  SELECT COUNT(*) INTO v_members_total
  FROM public.members m
  WHERE m.is_active = true
    AND EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = m.person_id
        AND e.kind = 'volunteer' AND e.status = 'active'
        AND e.initiative_id = v_tribe_initiative_id
    );

  SELECT COUNT(*) INTO v_members_active
  FROM public.members m
  WHERE m.is_active = true AND m.current_cycle_active = true
    AND EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = m.person_id
        AND e.kind = 'volunteer' AND e.status = 'active'
        AND e.initiative_id = v_tribe_initiative_id
    );

  SELECT COALESCE(jsonb_object_agg(role, cnt), '{}'::jsonb) INTO v_members_by_role
  FROM (
    SELECT m.operational_role AS role, COUNT(*) AS cnt
    FROM public.members m
    WHERE m.is_active = true
      AND EXISTS (
        SELECT 1 FROM public.engagements e
        WHERE e.person_id = m.person_id
          AND e.kind = 'volunteer' AND e.status = 'active'
          AND e.initiative_id = v_tribe_initiative_id
      )
    GROUP BY m.operational_role
  ) sub;

  SELECT COALESCE(jsonb_object_agg(ch, cnt), '{}'::jsonb) INTO v_members_by_chapter
  FROM (
    SELECT COALESCE(m.chapter, 'N/A') AS ch, COUNT(*) AS cnt
    FROM public.members m
    WHERE m.is_active = true
      AND EXISTS (
        SELECT 1 FROM public.engagements e
        WHERE e.person_id = m.person_id
          AND e.kind = 'volunteer' AND e.status = 'active'
          AND e.initiative_id = v_tribe_initiative_id
      )
    GROUP BY m.chapter
  ) sub;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', m.id, 'name', m.name, 'chapter', m.chapter, 'operational_role', m.operational_role,
      'xp_total', COALESCE((SELECT SUM(points) FROM public.gamification_points WHERE member_id = m.id), 0),
      'attendance_rate', LEAST(COALESCE(
        (SELECT ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(COUNT(*), 0), 2)
         FROM public.attendance a
         JOIN public.events e ON e.id = a.event_id
         JOIN public.initiatives i ON i.id = e.initiative_id
         WHERE a.member_id = m.id AND i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE), 0), 1.0),
      'cpmai_certified', COALESCE(m.cpmai_certified, false),
      'last_activity_at', GREATEST(m.updated_at, (SELECT MAX(a2.created_at) FROM public.attendance a2 WHERE a2.member_id = m.id))
    ) ORDER BY COALESCE((SELECT SUM(points) FROM public.gamification_points WHERE member_id = m.id), 0) DESC
  ), '[]'::jsonb) INTO v_members_list
  FROM public.members m
  WHERE m.is_active = true
    AND EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = m.person_id
        AND e.kind = 'volunteer' AND e.status = 'active'
        AND e.initiative_id = v_tribe_initiative_id
    );

  SELECT pb.* INTO v_board
  FROM public.project_boards pb
  JOIN public.initiatives i ON i.id = pb.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id AND pb.domain_key = 'research_delivery' AND pb.is_active = true
  LIMIT 1;

  IF v_board.id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_prod_total FROM public.board_items WHERE board_id = v_board.id;
    SELECT COALESCE(jsonb_object_agg(status, cnt), '{}'::jsonb) INTO v_prod_by_status
    FROM (SELECT status, COUNT(*) AS cnt FROM public.board_items WHERE board_id = v_board.id GROUP BY status) sub;
    SELECT COUNT(*) FILTER (WHERE curation_status IN ('submitted', 'under_review', 'approved', 'published')) INTO v_articles_submitted
    FROM public.board_items WHERE board_id = v_board.id;
    SELECT COUNT(*) FILTER (WHERE curation_status = 'approved') INTO v_articles_approved FROM public.board_items WHERE board_id = v_board.id;
    SELECT COUNT(*) FILTER (WHERE curation_status = 'published') INTO v_articles_published FROM public.board_items WHERE board_id = v_board.id;
    SELECT COUNT(*) FILTER (WHERE curation_status IN ('submitted', 'under_review')) INTO v_curation_pending FROM public.board_items WHERE board_id = v_board.id;
  END IF;

  SELECT COUNT(DISTINCT e.id), COALESCE(SUM(COALESCE(e.duration_actual, e.duration_minutes, 60)) / 60.0, 0)
  INTO v_total_meetings, v_total_hours
  FROM public.events e
  JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE;

  IF v_total_meetings > 0 AND v_members_active > 0 THEN
    SELECT LEAST(ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(v_members_active * v_total_meetings, 0), 2), 1.0)
    INTO v_attendance_rate
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE;

    SELECT ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(v_total_meetings, 0), 1)
    INTO v_avg_attendance
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE;
  END IF;

  SELECT MAX(e.date) INTO v_last_meeting_date
  FROM public.events e
  JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id AND e.date <= CURRENT_DATE;

  SELECT COUNT(*) INTO v_members_inactive_30d
  FROM public.members m
  WHERE m.is_active = true
    AND EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = m.person_id
        AND e.kind = 'volunteer' AND e.status = 'active'
        AND e.initiative_id = v_tribe_initiative_id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.attendance a JOIN public.events e2 ON e2.id = a.event_id
      WHERE a.member_id = m.id AND a.present = true AND e2.date >= (CURRENT_DATE - INTERVAL '30 days')
    );

  SELECT jsonb_build_object('day_of_week', tms.day_of_week, 'time_start', tms.time_start) INTO v_next_meeting
  FROM public.tribe_meeting_slots tms WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true LIMIT 1;

  SELECT COALESCE(SUM(gp.points), 0) INTO v_tribe_total_xp
  FROM public.gamification_points gp
  WHERE gp.member_id IN (
    SELECT m.id FROM public.members m
    WHERE m.is_active = true
      AND EXISTS (
        SELECT 1 FROM public.engagements e
        WHERE e.person_id = m.person_id
          AND e.kind = 'volunteer' AND e.status = 'active'
          AND e.initiative_id = v_tribe_initiative_id
      )
  );

  v_tribe_avg_xp := CASE WHEN v_members_active > 0 THEN ROUND(v_tribe_total_xp::numeric / v_members_active, 1) ELSE 0 END;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', sub.name, 'xp', sub.xp, 'rank', sub.rn)), '[]'::jsonb) INTO v_top_contributors
  FROM (
    SELECT m.name, SUM(gp.points) AS xp, ROW_NUMBER() OVER (ORDER BY SUM(gp.points) DESC) AS rn
    FROM public.gamification_points gp
    JOIN public.members m ON m.id = gp.member_id
    WHERE m.is_active = true
      AND EXISTS (
        SELECT 1 FROM public.engagements e
        WHERE e.person_id = m.person_id
          AND e.kind = 'volunteer' AND e.status = 'active'
          AND e.initiative_id = v_tribe_initiative_id
      )
    GROUP BY m.id, m.name
    ORDER BY xp DESC LIMIT 5
  ) sub;

  SELECT COUNT(*) INTO v_cpmai_certified
  FROM public.members m
  WHERE m.is_active = true AND m.cpmai_certified = true
    AND EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = m.person_id
        AND e.kind = 'volunteer' AND e.status = 'active'
        AND e.initiative_id = v_tribe_initiative_id
    );

  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', sub.month, 'rate', sub.rate) ORDER BY sub.month), '[]'::jsonb) INTO v_attendance_by_month
  FROM (SELECT TO_CHAR(e.date, 'YYYY-MM') AS month,
      LEAST(ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(COUNT(*), 0), 2), 1.0) AS rate
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
    GROUP BY TO_CHAR(e.date, 'YYYY-MM')) sub;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', sub.month, 'cards_created', sub.created, 'cards_completed', sub.completed) ORDER BY sub.month), '[]'::jsonb) INTO v_production_by_month
  FROM (SELECT TO_CHAR(bi.created_at, 'YYYY-MM') AS month, COUNT(*) AS created,
      COUNT(*) FILTER (WHERE bi.status = 'done') AS completed
    FROM public.board_items bi WHERE bi.board_id = v_board.id AND bi.created_at >= v_cycle_start
    GROUP BY TO_CHAR(bi.created_at, 'YYYY-MM')) sub;

  v_result := jsonb_build_object(
    'tribe', jsonb_build_object('id', v_tribe.id, 'name', v_tribe.name,
      'quadrant', v_tribe.quadrant, 'quadrant_name', v_tribe.quadrant_name,
      'leader', CASE WHEN v_leader.id IS NOT NULL THEN jsonb_build_object('id', v_leader.id, 'name', v_leader.name, 'avatar_url', v_leader.photo_url) ELSE NULL END,
      'meeting_slots', v_meeting_slots, 'whatsapp_url', v_tribe.whatsapp_url, 'drive_url', v_tribe.drive_url),
    'members', jsonb_build_object('total', v_members_total, 'active', v_members_active,
      'by_role', v_members_by_role, 'by_chapter', v_members_by_chapter, 'list', v_members_list),
    'production', jsonb_build_object('total_cards', v_prod_total, 'by_status', v_prod_by_status,
      'articles_submitted', v_articles_submitted, 'articles_approved', v_articles_approved,
      'articles_published', v_articles_published, 'curation_pending', v_curation_pending,
      'avg_days_to_approval', v_avg_days_to_approval),
    'engagement', jsonb_build_object('attendance_rate', v_attendance_rate, 'total_meetings', v_total_meetings,
      'total_hours', ROUND(v_total_hours, 1), 'avg_attendance_per_meeting', v_avg_attendance,
      'members_inactive_30d', v_members_inactive_30d, 'last_meeting_date', v_last_meeting_date, 'next_meeting', v_next_meeting),
    'gamification', jsonb_build_object('tribe_total_xp', v_tribe_total_xp, 'tribe_avg_xp', v_tribe_avg_xp,
      'top_contributors', v_top_contributors,
      'certification_progress', jsonb_build_object('cpmai_certified', v_cpmai_certified)),
    'trends', jsonb_build_object('attendance_by_month', v_attendance_by_month, 'production_by_month', v_production_by_month)
  );
  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
