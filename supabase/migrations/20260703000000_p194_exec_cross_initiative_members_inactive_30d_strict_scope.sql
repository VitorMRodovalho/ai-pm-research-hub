-- ============================================================
-- p194 GAP-194.A: exec_cross_initiative_comparison members_inactive_30d strict scope
-- ============================================================
-- WHAT: members_inactive_30d NOT IN attendance subquery now filters by
-- `ev.initiative_id = i.id`.
--
-- WHY (PM decision Option A "strict scope (parallel GAP-192.C)", p194):
-- Empirical audit revealed the same anti-pattern that motivated GAP-192.C's
-- total_hours fix: the attendance NOT IN subquery for members_inactive_30d did
-- not scope `ev.initiative_id = i.id`. A workgroup member who attended a
-- research_tribe event in the last 30 days counted as "active" for the
-- workgroup, producing optimistic (deflated) inactive counts.
--
-- POST-DEPLOY EMPIRICAL VALIDATION (verified inline):
--   Comitê de Curadoria:    3 members  0 → 3 inactive
--   LATAM LIM Congress:     3 members  1 → 3
--   Publicações WG:         9 members  0 → 9
--   Hub Comunicação WG:     3 members  0 → 3
--   Newsletter WG:          1 member   0 → 1
--   Prep CPMAI study:       2 members  0 → 2
--   All 7 research_tribes:  unchanged (current behavior == strict, delta=0,
--                           members attend own tribe events naturally)
--
-- New semantic: "members who did NOT attend any event scoped to THIS initiative
-- in the last 30 days". Apples-to-apples with GAP-192.C total_hours; consistent
-- per-initiative engagement signal cross-kind. Workgroups/committees with no
-- own events show 100% inactive (honest — meetings-based metric tautologically
-- maxes when initiative has no meetings).
--
-- ADR-0042 authority gate UNCHANGED. Function signature UNCHANGED. Only the
-- NOT IN inner subquery within members_inactive_30d adds one line:
-- `AND ev.initiative_id = i.id`.
--
-- ROLLBACK: re-apply migration 20260702000000_p194_exec_cross_initiative_total_hours_strict_scope.sql
-- body (which has total_hours strict but members_inactive_30d unscoped).
-- ============================================================

CREATE OR REPLACE FUNCTION public.exec_cross_initiative_comparison(p_kind text DEFAULT 'research_tribe'::text, p_cycle text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_cycle_start date := '2026-03-01';
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
            'attendance_rate', (
              SELECT COALESCE(
                ROUND(
                  COUNT(*) FILTER (WHERE EXISTS (
                    SELECT 1 FROM public.attendance a2
                    WHERE a2.event_id = ev.id
                      AND a2.member_id IN (
                        SELECT m2.id FROM public.members m2
                        WHERE m2.is_active
                          AND EXISTS (
                            SELECT 1 FROM public.engagements en2
                            WHERE en2.person_id = m2.person_id
                              AND en2.initiative_id = i.id
                              AND en2.status = 'active'
                              AND en2.kind != 'observer'
                          )
                      )
                  ))::numeric
                  / NULLIF(
                    (
                      SELECT COUNT(*)::numeric FROM public.members m4
                      WHERE m4.is_active
                        AND EXISTS (
                          SELECT 1 FROM public.engagements en4
                          WHERE en4.person_id = m4.person_id
                            AND en4.initiative_id = i.id
                            AND en4.status = 'active'
                            AND en4.kind != 'observer'
                        )
                    ) * COUNT(DISTINCT ev.id), 0)
                , 2), 0)
              FROM public.events ev
              WHERE (ev.initiative_id = i.id
                     OR (i.kind = 'research_tribe' AND ev.initiative_id IS NULL))
                AND ev.date >= v_cycle_start AND ev.date <= CURRENT_DATE
            ),
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
