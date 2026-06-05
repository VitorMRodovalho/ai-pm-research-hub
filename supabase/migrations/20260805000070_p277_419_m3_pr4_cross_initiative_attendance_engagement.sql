-- p277 / #419 (ADR-0100) metric 3 — PR4: exec_cross_initiative_comparison attendance → ENGAGEMENT.
--
-- SPEC docs/specs/SPEC_419_M3_ATTENDANCE_TWO_METRIC.md, surface [6] (admin cross-tribe comparison).
-- Two changes (body otherwise byte-faithful; no inline body comments to avoid the PR3b Phase-C drift):
--   1. v_cycle_start: '2026-03-01' literal → cycles.is_current (D10 / §2.1 window invariant; the literal
--      equals the current cycle_start so 0 number change today — forward-defense).
--   2. per-initiative 'attendance_rate': members×events recorded denominator → for tribe-bridged initiatives
--      (t.id = legacy_tribe_id non-null) delegate to get_attendance_engagement_summary('tribe', t.id);
--      native initiatives (t.id NULL) → NULL (N/A, per ADR-0100 §2.4 — no recorded-math fallback).
-- Companion frontend change (CrossTribeWidget.tsx): drop the now-unneeded Math.min(.,100) clamp
-- (engagement is 0..1 by construction) + keep null → '—'.
--
-- NOTE: get_admin_dashboard + get_kpi_dashboard were in the SPEC's PR4 surface list but neither computes an
-- attendance RATE (admin = 60-day inactivity ALERT; kpi = hours/CPMAI/pilots/articles/webinars/chapters) —
-- so this PR is the only attendance-rate converge for surface [5]/[6]. Recorded in the §7 audit trail.
--
-- LEFT UNCHANGED (other metrics): members_inactive_30d, total_hours, meetings_count, total_xp, avg_xp.
--
-- ROLLBACK: re-CREATE with the members×events attendance_rate + '2026-03-01' literal.

CREATE OR REPLACE FUNCTION public.exec_cross_initiative_comparison(p_kind text DEFAULT 'research_tribe'::text, p_cycle text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_cycle_start date := (SELECT cycle_start FROM public.cycles WHERE is_current = true LIMIT 1);
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  SELECT jsonb_build_object(
    'initiatives', (
      SELECT jsonb_agg(row_obj ORDER BY sort_kind, sort_tribe, sort_title)
      FROM (
        SELECT
          i.kind AS sort_kind,
          COALESCE(t.id, 9999) AS sort_tribe,
          i.title AS sort_title,
          jsonb_build_object(
            'initiative_id', i.id,
            'initiative_kind', i.kind,
            'initiative_title', i.title,
            'tribe_id', t.id,
            'tribe_name', t.name,
            'quadrant', t.quadrant_name,
            'leader', (
              SELECT m.name FROM public.members m
              WHERE m.id = COALESCE(
                t.leader_member_id,
                (SELECT em.id
                 FROM public.engagements en
                 JOIN public.members em ON em.person_id = en.person_id
                 WHERE en.initiative_id = i.id
                   AND en.status = 'active'
                   AND en.kind ~ '(coordinator|owner|leader|manager)'
                 ORDER BY en.created_at ASC
                 LIMIT 1)
              )
            ),
            'member_count', (
              SELECT COUNT(*) FROM public.members m
              WHERE m.is_active
                AND EXISTS (
                  SELECT 1 FROM public.engagements en
                  WHERE en.person_id = m.person_id
                    AND en.initiative_id = i.id
                    AND en.status = 'active'
                    AND en.kind != 'observer'
                )
            ),
            'members_inactive_30d', (
              SELECT COUNT(*) FROM public.members m
              WHERE m.is_active
                AND EXISTS (
                  SELECT 1 FROM public.engagements en
                  WHERE en.person_id = m.person_id
                    AND en.initiative_id = i.id
                    AND en.status = 'active'
                    AND en.kind != 'observer'
                )
                AND m.id NOT IN (
                  SELECT DISTINCT a.member_id FROM public.attendance a
                  JOIN public.events ev ON ev.id = a.event_id
                  WHERE ev.date >= (current_date - 30) AND ev.date <= CURRENT_DATE
                    AND ev.initiative_id = i.id  -- p194 GAP-194.A: strict scope (PM Option A)
                )
            ),
            'total_cards', (
              SELECT COUNT(*) FROM public.board_items bi
              JOIN public.project_boards pb ON pb.id = bi.board_id
              WHERE pb.initiative_id = i.id
            ),
            'cards_completed', (
              SELECT COUNT(*) FROM public.board_items bi
              JOIN public.project_boards pb ON pb.id = bi.board_id
              WHERE pb.initiative_id = i.id
                AND bi.status IN ('done','approved','published')
            ),
            'articles_submitted', (
              SELECT COUNT(*) FROM public.board_lifecycle_events ble
              JOIN public.board_items bi ON bi.id = ble.item_id
              JOIN public.project_boards pb ON pb.id = bi.board_id
              WHERE pb.initiative_id = i.id
                AND ble.action = 'submission'
            ),
            'attendance_rate', CASE WHEN t.id IS NOT NULL THEN COALESCE((public.get_attendance_engagement_summary('tribe', t.id) ->> 'avg_rate')::numeric, 0) ELSE NULL END,
            'total_hours', (
              SELECT COALESCE(SUM(ev.duration_minutes / 60.0), 0)
              FROM public.attendance a JOIN public.events ev ON ev.id = a.event_id
              WHERE a.member_id IN (
                SELECT m5.id FROM public.members m5
                WHERE m5.is_active
                  AND EXISTS (
                    SELECT 1 FROM public.engagements en5
                    WHERE en5.person_id = m5.person_id
                      AND en5.initiative_id = i.id
                      AND en5.status = 'active'
                      AND en5.kind != 'observer'
                  )
              )
              AND ev.date >= v_cycle_start AND ev.date <= CURRENT_DATE
              AND ev.initiative_id = i.id  -- p194 GAP-192.C: strict scope (PM Option B)
            ),
            'meetings_count', (
              SELECT COUNT(*) FROM public.events ev
              WHERE ev.initiative_id = i.id
                AND ev.date >= v_cycle_start AND ev.date <= CURRENT_DATE
            ),
            'total_xp', (
              SELECT COALESCE(SUM(gp.points), 0) FROM public.gamification_points gp
              WHERE gp.member_id IN (
                SELECT m6.id FROM public.members m6
                WHERE m6.is_active
                  AND EXISTS (
                    SELECT 1 FROM public.engagements en6
                    WHERE en6.person_id = m6.person_id
                      AND en6.initiative_id = i.id
                      AND en6.status = 'active'
                      AND en6.kind != 'observer'
                  )
              )
            ),
            'avg_xp', (
              SELECT COALESCE(ROUND(AVG(sub.total)::numeric, 1), 0)
              FROM (
                SELECT SUM(gp.points) AS total
                FROM public.gamification_points gp
                WHERE gp.member_id IN (
                  SELECT m7.id FROM public.members m7
                  WHERE m7.is_active
                    AND EXISTS (
                      SELECT 1 FROM public.engagements en7
                      WHERE en7.person_id = m7.person_id
                        AND en7.initiative_id = i.id
                        AND en7.status = 'active'
                        AND en7.kind != 'observer'
                    )
                )
                GROUP BY gp.member_id
              ) sub
            ),
            'last_meeting_date', (
              SELECT MAX(ev.date) FROM public.events ev
              WHERE ev.initiative_id = i.id AND ev.date <= CURRENT_DATE
            ),
            'days_since_last_meeting', (
              SELECT EXTRACT(DAY FROM now() - MAX(ev.date)::timestamp)::int
              FROM public.events ev
              WHERE ev.initiative_id = i.id AND ev.date <= CURRENT_DATE
            )
          ) AS row_obj
        FROM public.initiatives i
        LEFT JOIN public.tribes t ON t.id = i.legacy_tribe_id
        WHERE p_kind IS NULL OR i.kind = p_kind
      ) src
    ),
    'kinds_present', (
      SELECT array_to_json(ARRAY(SELECT DISTINCT i.kind FROM public.initiatives i ORDER BY i.kind))::jsonb
    ),
    'generated_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
