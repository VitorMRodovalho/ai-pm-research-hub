-- p277 / #419 (ADR-0100) metric 3 — PR3a: get_tribe_stats.attendance_rate → canonical ENGAGEMENT.
--
-- SPEC docs/specs/SPEC_419_M3_ATTENDANCE_TWO_METRIC.md, surface [4] (tribe gamification tab). The tribe
-- attendance_rate used a members×events denominator and counted NON-EXCUSED recorded rows (present + absent,
-- not present-only) — so it conflated "rows on file" with "attended" over an inflated denominator. Now the
-- tribe headline rate DELEGATES to get_attendance_engagement_summary('tribe', p_tribe_id) (PR1 foundation):
-- AVG-of-member engagement rates over the tribe's operational cohort (eligible denominator, present numerator,
-- excused-excluded, cycles.is_current). No inline rate re-impl (delegation only — PR10 p175 gate).
--
-- ANTES -> DEPOIS (per-tribe, live): tribe2 ~99% -> 51.7%, tribe5 -> 92.7%, tribe1 -> 90.7%, tribe4 -> 88.4%,
-- tribe8 -> 79.4%, tribe6 -> 77.9%, tribe7 -> 75.0%. The old ~99% was the inflated members×events recorded model.
--
-- COHORT NOTE: attendance_rate now uses the V4 get_member_tribe cohort (canonical, ADR-0007); member_count
-- still uses the legacy members.tribe_id (that is the tribe-roster metric #4, converged later). The two can
-- differ by members whose legacy tribe_id has no active 'volunteer' tribe engagement (e.g. Roberto Macêdo,
-- tribe 8) — intentional: attendance_rate is V4-canonical, roster is metric 4.
--
-- LEFT UNCHANGED (separate concerns, tracked): top_contributors[].rate is a tribe-event-scoped leaderboard
-- (not the canonical overall engagement) and still counts via the `att` CTE (present+absent) — a present-
-- detection follow-up; impact_hours is metric 2. Only the headline attendance_rate converges here.
--
-- ROLLBACK: re-CREATE get_tribe_stats with the members×events attendance_rate body.

CREATE OR REPLACE FUNCTION public.get_tribe_stats(p_tribe_id integer)
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH cycle AS (SELECT cycle_start FROM cycles WHERE is_current LIMIT 1),
  tribe_members AS (
    SELECT id FROM members WHERE tribe_id = p_tribe_id AND is_active AND current_cycle_active
  ),
  tribe_events AS (
    SELECT e.id, e.duration_minutes
    FROM events e
    JOIN initiatives i ON i.id = e.initiative_id
    CROSS JOIN cycle c
    WHERE i.legacy_tribe_id = p_tribe_id AND e.type = 'tribo'
      AND e.date >= c.cycle_start AND e.date <= current_date
  ),
  att AS (
    SELECT a.event_id, a.member_id FROM attendance a
    JOIN tribe_events te ON te.id = a.event_id
    WHERE a.excused IS NOT TRUE
  ),
  tribe_boards AS (
    SELECT bi.id, bi.status FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    JOIN initiatives i ON i.id = pb.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id
  )
  SELECT json_build_object(
    'member_count', (SELECT count(*) FROM tribe_members),
    'events_held', (SELECT count(*) FROM tribe_events),
    'attendance_rate', ROUND((public.get_attendance_engagement_summary('tribe', p_tribe_id) ->> 'avg_rate')::numeric * 100, 1),
    'impact_hours', (SELECT coalesce(round(sum(te.duration_minutes * sub.c)::numeric / 60, 1), 0)
      FROM tribe_events te JOIN (SELECT event_id, count(*) c FROM att GROUP BY event_id) sub ON sub.event_id = te.id),
    'cards_backlog', (SELECT count(*) FROM tribe_boards WHERE status = 'backlog'),
    'cards_in_progress', (SELECT count(*) FROM tribe_boards WHERE status = 'in_progress'),
    'cards_review', (SELECT count(*) FROM tribe_boards WHERE status = 'review'),
    'cards_done', (SELECT count(*) FROM tribe_boards WHERE status = 'done'),
    'top_contributors', (SELECT coalesce(json_agg(row_to_json(r) ORDER BY r.att_count DESC), '[]')
      FROM (
        SELECT m.name, count(a2.event_id) as att_count,
          round(count(a2.event_id)::numeric / NULLIF((SELECT count(*) FROM tribe_events), 0) * 100, 0) as rate
        FROM tribe_members tm
        JOIN members m ON m.id = tm.id
        LEFT JOIN att a2 ON a2.member_id = tm.id
        GROUP BY m.name
      ) r
    )
  );
$function$;

NOTIFY pgrst, 'reload schema';
