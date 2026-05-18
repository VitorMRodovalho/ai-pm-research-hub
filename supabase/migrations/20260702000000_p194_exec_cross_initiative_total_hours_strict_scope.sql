-- ============================================================
-- p194 GAP-192.C: exec_cross_initiative_comparison total_hours strict scope
-- ============================================================
-- WHAT: total_hours subquery now filters by `ev.initiative_id = i.id`.
--
-- WHY (PM decision Option B "strict scope all kinds", p194):
-- Empirical audit revealed pre-p194 V4 attributed cross-initiative attendance
-- hours to each initiative the member belonged to:
--   - Workgroups/committees/congress/study_group: 21h, 40h, 180.5h, 52.3h
--     etc. despite having ZERO events scoped to those initiatives (their
--     members attended geral/tribo events of other initiatives, and those
--     hours were summed up under the workgroup name).
--   - Research_tribes: ~30-60h inflated vs V3 actual (geral + kickoff hours
--     attributed via member attendance without initiative scope filter).
--
-- New semantic: "hours of events scoped to this initiative that initiative
-- members attended (non-observer)". Cross-kind apples-to-apples comparison.
-- Workgroups/committees correctly show 0h when they have no scoped events.
-- Research_tribes parity vs V3 actual is exact for T06 (102=102) and T02
-- (45=45); other tribes within ±2-16h drift (V3 includes ALL attendees +
-- excludes excused + filters e.type='tribo'; V4 strict counts non-observer
-- engagement members without those exclusions).
--
-- POST-DEPLOY EMPIRICAL VALIDATION (verified inline):
--   T06 ROI:        V3=102 → V4=102 (delta 0)   exact
--   T02 Agentes:    V3=45  → V4=45  (delta 0)   exact
--   T08 Inclusão:   V3=49  → V4=53  (delta +4)
--   T04 Cultura:    V3=51  → V4=67.5 (delta +16.5)
--   T01 Radar:      V3=35  → V4=31  (delta -4)
--   T07 Governança: V3=31  → V4=29  (delta -2)
--   T05 Talentos:   V3=29  → V4=24.5 (delta -4.5)
--   Comitê Curadoria, Publicações WG, Hub WG, Newsletter WG, LATAM LIM: 0h
--     (was 40, 180.5, 52.3, 29, 21 respectively — inflation eliminated)
--   Prep CPMAI:     2h (was 19.2)
--
-- ADR-0042 authority gate UNCHANGED (manage_platform | view_chapter_dashboards).
-- Function signature UNCHANGED. Only the inner total_hours subquery WHERE adds
-- one line: `AND ev.initiative_id = i.id`.
--
-- ROLLBACK: re-apply migration 20260700000000_p192_exec_cross_initiative_comparison.sql
-- body which omits the strict scope filter.
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
