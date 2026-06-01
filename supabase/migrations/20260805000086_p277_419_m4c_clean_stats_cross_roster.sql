-- p277 / #419 (ADR-0100) metric 4 — PR4-C-clean: converge the remaining member-cohort RPCs onto
-- the canonical roster primitive (v_initiative_roster / get_initiative_roster_count, shipped PR4-A mig 082).
--
-- THREE functions, each same-signature CREATE OR REPLACE; ONLY the member-cohort sites change. The
-- non-cohort sections are byte-identical to the live definers (mechanically diffed).
--
-- 1) get_tribe_stats(integer)            — tribe_members CTE (path E: members.tribe_id ∧ is_active ∧
--    current_cycle_active) → v_initiative_roster; member_count → get_initiative_roster_count(resolve_
--    initiative_id(tribe)). The roster member-SET == path-E SET for every tribe today (verified:
--    in_roster_not_pathE=0 ∧ in_pathE_not_roster=0, no NULL-member rows, no person↔member fan-out),
--    so member_count AND top_contributors are byte-identical → 0 VISIBLE DELTA. Pure structural hardening
--    (the path was correct-by-coincidence; now correct-by-construction, single source).
--
-- 2) get_initiative_stats(uuid)          — NATIVE branch only (bridged initiatives delegate to
--    get_tribe_stats, unchanged). init_members CTE (active engagement, NO role filter) → roster
--    (role<>'observer'). Visible delta: ONLY the "Mesa Redonda Universidade de Vassouras" congress
--    7→4 (drops 3 role=observer: Fabricio, Leticia, Vitor) — member_count + top_contributors; its
--    attendance_rate stays NULL (0 events). All other native initiatives unchanged.
--
-- 3) exec_cross_initiative_comparison(text,text) — the per-initiative cohort predicate
--    "m.is_active AND EXISTS(engagements ... kind <> 'observer')" repeated 5× (member_count,
--    members_inactive_30d, total_hours, total_xp, avg_xp) → the canonical roster. The kind axis is the
--    bug: it drops members whose kind='observer' but role<>'observer'. Converging ALL 5 keeps the
--    response internally consistent (member_count, total_xp, avg_xp now describe the SAME cohort) and
--    matches the already-shipped exec_tribe_dashboard (tribe-8 total_xp 2535→2815, avg 469.2).
--    Visible deltas (verified live, cycle_3): tribe 8 5→6 (+Roberto curator), LATAM LIM 3→5
--    (+Fabricio, +Sarah reviewers), Grupo CPMAI 3→4 (+Welma reviewer); Mesa Redonda 4→4 (identical
--    set). All other initiatives byte-identical. The leader-name lookup (en.kind ~ regex) is a
--    separate concern (leader identification, not member counting) — left untouched.
--
-- This kills three live cross-surface forks: today get_initiative_stats vs exec_cross disagree on the
-- native initiatives (Mesa 7 vs 4, LATAM 5 vs 3, Grupo 4 vs 3); after this they all read the canonical
-- roster and agree.
--
-- SCOPE: only the member-cohort axis. get_tribe_gamification (M4-C/M5 overlap), get_member_tribe
-- (M4-F axis), and all XP ORDER BY (metric 5) are left for their own PRs.
-- Cross-ref: SPEC_419_M4_M8_CANONICAL_METRICS.md §M4.5/§M4.6; ADR-0100 §2.2; issue #419.
-- Rollback: re-apply the prior CREATE OR REPLACE bodies (mig captures of get_tribe_stats /
-- get_initiative_stats / exec_cross_initiative_comparison from before this migration).

-- ── 1) get_tribe_stats(integer) ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_tribe_stats(p_tribe_id integer)
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH cycle AS (SELECT cycle_start FROM cycles WHERE is_current LIMIT 1),
  tribe_members AS (
    SELECT DISTINCT vir.member_id AS id
    FROM v_initiative_roster vir
    WHERE vir.legacy_tribe_id = p_tribe_id AND vir.member_id IS NOT NULL
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
    'member_count', public.get_initiative_roster_count(public.resolve_initiative_id(p_tribe_id)),
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

-- ── 2) get_initiative_stats(uuid) ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_initiative_stats(p_initiative_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tribe_id int;
BEGIN
  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_stats(v_tribe_id);
  END IF;

  RETURN (
    WITH cycle AS (SELECT cycle_start FROM cycles WHERE is_current LIMIT 1),
    init_members AS (
      SELECT DISTINCT vir.member_id AS id, vir.name
      FROM v_initiative_roster vir
      WHERE vir.initiative_id = p_initiative_id AND vir.member_id IS NOT NULL
    ),
    init_events AS (
      SELECT e.id, COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes
      FROM events e, cycle c
      WHERE e.initiative_id = p_initiative_id AND e.date >= c.cycle_start AND e.date <= current_date
    ),
    att AS (
      SELECT a.event_id, a.member_id FROM attendance a
      JOIN init_events ie ON ie.id = a.event_id
      WHERE a.present = true AND a.excused IS NOT TRUE
    ),
    init_boards AS (
      SELECT bi.id, bi.status FROM board_items bi
      JOIN project_boards pb ON pb.id = bi.board_id
      WHERE pb.initiative_id = p_initiative_id
    )
    SELECT json_build_object(
      'member_count', public.get_initiative_roster_count(p_initiative_id),
      'events_held', (SELECT count(*) FROM init_events),
      'attendance_rate', (SELECT round(
        count(a.*)::numeric / NULLIF((SELECT count(*) FROM init_members) * (SELECT count(*) FROM init_events), 0) * 100, 0
      ) FROM att a),
      'impact_hours', (SELECT coalesce(round(sum(ie.duration_minutes * sub.c)::numeric / 60, 1), 0)
        FROM init_events ie JOIN (SELECT event_id, count(*) c FROM att GROUP BY event_id) sub ON sub.event_id = ie.id),
      'cards_backlog', (SELECT count(*) FROM init_boards WHERE status = 'backlog'),
      'cards_in_progress', (SELECT count(*) FROM init_boards WHERE status = 'in_progress'),
      'cards_review', (SELECT count(*) FROM init_boards WHERE status = 'review'),
      'cards_done', (SELECT count(*) FROM init_boards WHERE status = 'done'),
      'top_contributors', (SELECT coalesce(json_agg(row_to_json(r) ORDER BY r.att_count DESC), '[]')
        FROM (
          SELECT im.name, count(a2.event_id) as att_count,
            round(count(a2.event_id)::numeric / NULLIF((SELECT count(*) FROM init_events), 0) * 100, 0) as rate
          FROM init_members im
          LEFT JOIN att a2 ON a2.member_id = im.id
          GROUP BY im.name
        ) r
      )
    )
  );
END;
$function$;

-- ── 3) exec_cross_initiative_comparison(text,text) ──────────────────────────────────────────────────
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
            'member_count', public.get_initiative_roster_count(i.id),
            'members_inactive_30d', (
              SELECT COUNT(*) FROM public.members m
              WHERE m.id IN (
                  SELECT member_id FROM public.v_initiative_roster
                  WHERE initiative_id = i.id AND member_id IS NOT NULL
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
                SELECT member_id FROM public.v_initiative_roster
                WHERE initiative_id = i.id AND member_id IS NOT NULL
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
                SELECT member_id FROM public.v_initiative_roster
                WHERE initiative_id = i.id AND member_id IS NOT NULL
              )
            ),
            'avg_xp', (
              SELECT COALESCE(ROUND(AVG(sub.total)::numeric, 1), 0)
              FROM (
                SELECT SUM(gp.points) AS total
                FROM public.gamification_points gp
                WHERE gp.member_id IN (
                  SELECT member_id FROM public.v_initiative_roster
                  WHERE initiative_id = i.id AND member_id IS NOT NULL
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
