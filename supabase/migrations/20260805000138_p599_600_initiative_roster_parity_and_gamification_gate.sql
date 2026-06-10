-- Migration: 20260805000138_p599_600_initiative_roster_parity_and_gamification_gate
-- Issues: #599 + #600 (#419 M4 residuals, surfaced by the 2026-06-08 backlog QA/QC audit; PR #471 review)
-- Refs: ADR-0100 (canonical metrics / G6 participants-only axis), ADR-0007 (fail-closed authority),
--       siblings #465/#468 (ungated SECDEF reads class). Bodies regenerated from LIVE prosrc
--       (2026-06-10) per the export_my_data drift lesson — edits are minimal and marked.
--
-- WHAT
--   1. #599 — get_initiative_detail.member_count: was a raw count of ALL active engagements
--      (observers included), diverging from the roster/gamification surfaces on the same page
--      (participants-only v_initiative_roster). Now sourced from the canonical M4 helper
--      get_initiative_roster_count(p_initiative_id) — the same denominator
--      get_tribe_gamification uses. engagement_summary keeps the FULL breakdown by kind/role
--      (observers visible and labeled there — that is the intentional place for them).
--   2. #600 — get_initiative_gamification standalone branch: gated only on "is some member",
--      so ANY authenticated member could read ANY standalone initiative's roster (names +
--      per-pillar XP). Now mirrors the tribe path's gate: caller has an ACTIVE engagement on
--      p_initiative_id (any role/kind — initiative insiders, observers included) OR
--      can_by_member('view_internal_analytics'). Fail-closed default per ADR-0007; a wider
--      visibility policy, if desired, is a PM ratification tracked in the PR.
--
-- NOTES (council 2026-06-10, wf_f3f4e7a3)
--   * resolve_tribe_id runs BEFORE the auth gate by design (p576): it returns only a nullable
--     integer (no PII) and the tribe path carries its own gate inside get_tribe_gamification.
--   * The #600 gate compares e.person_id = v_caller.person_id — members with person_id IS NULL
--     (legacy unlinked records) are denied fail-closed on the standalone branch. Live count at
--     ship time: 0 active members without person_id; if a support ticket ever surfaces this,
--     populate the persons bridge (or grant view_internal_analytics) rather than widening here.
--
-- ROLLBACK
--   Restore both bodies from their previous captures:
--     get_initiative_detail        — 20260805000089 (p277 419 M4 cohort roster)
--     get_initiative_gamification  — 20260805000132 (p576 perf batch)
--
-- After apply: NOTIFY pgrst, 'reload schema'.

-- ============================================================================
-- 1. #599 — header member_count = canonical participants-only roster count
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_initiative_detail(p_initiative_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_initiative record;
  v_kind_config jsonb;
  v_board_id uuid;
  v_leader jsonb;
  v_member_count integer;
  v_engagement_summary jsonb;
  v_user_engagement jsonb;
  v_caller_person_id uuid;
BEGIN
  SELECT p.id INTO v_caller_person_id
  FROM persons p WHERE p.auth_id = auth.uid();

  SELECT i.id, i.title, i.kind, i.status, i.description,
         i.legacy_tribe_id, i.metadata, i.created_at
  INTO v_initiative
  FROM initiatives i WHERE i.id = p_initiative_id;

  IF v_initiative IS NULL THEN
    RETURN jsonb_build_object('error', 'Initiative not found');
  END IF;

  SELECT jsonb_build_object(
    'slug', ik.slug, 'display_name', ik.display_name, 'icon', ik.icon,
    'has_board', ik.has_board, 'has_meeting_notes', ik.has_meeting_notes,
    'has_deliverables', ik.has_deliverables, 'has_attendance', ik.has_attendance,
    'has_certificate', ik.has_certificate,
    'allowed_engagement_kinds', ik.allowed_engagement_kinds
  ) INTO v_kind_config
  FROM initiative_kinds ik WHERE ik.slug = v_initiative.kind;

  SELECT pb.id INTO v_board_id
  FROM project_boards pb
  WHERE pb.initiative_id = p_initiative_id AND pb.is_active = true LIMIT 1;

  SELECT jsonb_build_object(
    'person_id', p.id, 'name', COALESCE(p.name, m.name),
    'photo_url', COALESCE(p.photo_url, m.photo_url), 'role', e.role
  ) INTO v_leader
  FROM engagements e
  JOIN persons p ON p.id = e.person_id
  LEFT JOIN members m ON m.id = p.legacy_member_id
  WHERE e.initiative_id = p_initiative_id AND e.status = 'active' AND e.role = 'leader'
  LIMIT 1;

  -- #599 (#419 M4 residual): header count = canonical participants-only roster
  -- (v_initiative_roster via the M4 helper), the same denominator the roster and
  -- gamification surfaces use — so the page header agrees with the stat cards.
  -- Observers remain visible (and labeled) in engagement_summary below: that
  -- breakdown intentionally covers ALL active engagements by kind/role.
  v_member_count := public.get_initiative_roster_count(p_initiative_id);

  SELECT coalesce(jsonb_agg(row_to_json(s)), '[]'::jsonb) INTO v_engagement_summary
  FROM (
    SELECT e.kind, e.role, count(*) as count
    FROM engagements e
    WHERE e.initiative_id = p_initiative_id AND e.status = 'active'
    GROUP BY e.kind, e.role ORDER BY e.kind, e.role
  ) s;

  IF v_caller_person_id IS NOT NULL THEN
    SELECT jsonb_build_object(
      'engagement_id', e.id, 'kind', e.kind, 'role', e.role,
      'status', e.status, 'start_date', e.start_date
    ) INTO v_user_engagement
    FROM engagements e
    WHERE e.initiative_id = p_initiative_id AND e.person_id = v_caller_person_id AND e.status = 'active'
    LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'initiative', jsonb_build_object(
      'id', v_initiative.id, 'title', v_initiative.title, 'kind', v_initiative.kind,
      'status', v_initiative.status, 'description', v_initiative.description,
      'legacy_tribe_id', v_initiative.legacy_tribe_id, 'created_at', v_initiative.created_at,
      'metadata', COALESCE(v_initiative.metadata, '{}'::jsonb)
    ),
    'kind_config', v_kind_config, 'board_id', v_board_id, 'leader', v_leader,
    'member_count', v_member_count, 'engagement_summary', v_engagement_summary,
    'user_engagement', v_user_engagement
  );
END;
$function$;

-- ACL unchanged but restated for single-file auditability (CREATE OR REPLACE preserves it;
-- explicit restate is restore-safe — council lesson from p569-s3).
REVOKE ALL ON FUNCTION public.get_initiative_detail(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_initiative_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_initiative_detail(uuid) TO service_role;

-- ============================================================================
-- 2. #600 — standalone gamification branch gains the initiative-scoped gate
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_initiative_gamification(p_initiative_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_tribe_id int;
  v_result jsonb;
  v_cycle_start date;
  v_member_ids uuid[];
  v_stats jsonb := '{}'::jsonb;
  v_attendance jsonb := '{}'::jsonb;
  v_trail_total int;
BEGIN
  -- #576 (item 5): resolve routing FIRST so tribe-backed initiatives delegate to
  -- get_tribe_gamification (which runs its own auth gate) without a redundant
  -- members-by-auth_id fetch here. The standalone path authenticates below.
  -- Output is identical: a non-member still gets 'Unauthorized' either way.
  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_gamification(v_tribe_id);
  END IF;

  -- standalone (non-tribe) initiative path: authenticate the caller.
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  -- #600 (#419 M4 residual, sibling of #465/#468): initiative-scoped authority gate —
  -- mirrors get_tribe_gamification's gate (tribe member OR view_internal_analytics).
  -- Without it ANY authenticated member could read ANY standalone initiative's roster
  -- (names + per-pillar XP). Membership = any ACTIVE engagement on the initiative
  -- (observers included — they are initiative insiders; the participants-only filter
  -- applies to who is LISTED, not who may view). Fail-closed default per ADR-0007.
  IF NOT (
    EXISTS (
      SELECT 1 FROM engagements e
      WHERE e.initiative_id = p_initiative_id
        AND e.status = 'active'
        AND e.person_id = v_caller.person_id
    )
    OR public.can_by_member(v_caller.id, 'view_internal_analytics')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;

  SELECT array_agg(DISTINCT m.id) INTO v_member_ids
  FROM v_initiative_roster vir JOIN members m ON m.id = vir.member_id
  WHERE vir.initiative_id = p_initiative_id;

  -- #425: streak / active-cycle coaching signals (SSOT), guarded for non-active viewers.
  IF v_member_ids IS NOT NULL THEN
    BEGIN
      SELECT COALESCE(jsonb_object_agg(s.member_id::text, jsonb_build_object(
               'current_streak', s.current_streak_count,
               'longest_streak', s.longest_streak_count,
               'active_cycles', s.active_cycles_count
             )), '{}'::jsonb)
      INTO v_stats
      FROM public.get_member_gamification_stats(v_member_ids) s;
    EXCEPTION WHEN insufficient_privilege OR invalid_parameter_value THEN
      -- non-active viewer (insufficient_privilege) or >200-member cap
      -- (invalid_parameter_value): degrade gracefully to zeroed streaks. Any
      -- OTHER error propagates (schema drift / programming bugs must surface).
      v_stats := '{}'::jsonb;
    END;

    -- #576: batch attendance_rate (was get_attendance_rate per member = N+1).
    SELECT COALESCE(jsonb_object_agg(ar.member_id::text, ar.rate), '{}'::jsonb)
    INTO v_attendance
    FROM (
      SELECT a.member_id,
        ROUND(
          count(*) FILTER (WHERE a.present = true)::numeric
          / NULLIF(count(*) FILTER (WHERE a.excused IS NOT TRUE), 0), 2) AS rate
      FROM attendance a
      JOIN events e ON e.id = a.event_id
      WHERE a.member_id = ANY(v_member_ids)
        AND e.date >= v_cycle_start
        AND e.date <= CURRENT_DATE
        AND e.status IS DISTINCT FROM 'cancelled'
        AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
      GROUP BY a.member_id
    ) ar;
  END IF;

  v_trail_total := (SELECT count(*) FROM courses WHERE is_trail = true);

  WITH init_members AS MATERIALIZED (
    SELECT DISTINCT m.id, m.name, m.cpmai_certified, m.credly_badges
    FROM v_initiative_roster vir
    JOIN members m ON m.id = vir.member_id
    WHERE vir.initiative_id = p_initiative_id
  ),
  points_per_member AS (
    SELECT
      gp.member_id,
      SUM(gp.points)::int AS total_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gp.created_at >= v_cycle_start), 0)::int AS cycle_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'presenca'), 0)::int AS attendance_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%'), 0)::int AS cert_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.slug = 'badge'), 0)::int AS badge_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'trilha'), 0)::int AS learning_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'producao'), 0)::int AS producao_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'curadoria'), 0)::int AS curadoria_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'champions'), 0)::int AS champions_points,
      MAX(gp.created_at) AS last_activity_ts
    FROM gamification_points gp
    JOIN init_members im ON im.id = gp.member_id
    LEFT JOIN gamification_rules gr
      ON gr.organization_id = gp.organization_id
     AND gr.slug = gp.category
    GROUP BY gp.member_id
  ),
  member_data AS MATERIALIZED (
    SELECT im.id, im.name,
           COALESCE(p.total_points, 0) AS total_points,
           COALESCE(p.cycle_points, 0) AS cycle_points,
           COALESCE(p.attendance_points, 0) AS attendance_points,
           COALESCE(p.cert_points, 0) AS cert_points,
           COALESCE(p.badge_points, 0) AS badge_points,
           COALESCE(p.learning_points, 0) AS learning_points,
           COALESCE(p.producao_points, 0) AS producao_points,
           COALESCE(p.curadoria_points, 0) AS curadoria_points,
           COALESCE(p.champions_points, 0) AS champions_points,
           COALESCE(jsonb_array_length(im.credly_badges), 0) AS credly_badge_count,
           COALESCE(im.cpmai_certified, false) AS has_cpmai,
           p.last_activity_ts AS last_activity_ts,
           (SELECT count(*) FROM course_progress cp
             WHERE cp.member_id = im.id AND cp.status = 'completed'
               AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)) AS trail_progress
    FROM init_members im
    LEFT JOIN points_per_member p ON p.member_id = im.id
  ),
  v_members AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', md.id, 'name', md.name,
      'total_points', md.total_points, 'cycle_points', md.cycle_points,
      'attendance_points', md.attendance_points, 'cert_points', md.cert_points,
      'badge_points', md.badge_points, 'learning_points', md.learning_points,
      'producao_points', md.producao_points, 'curadoria_points', md.curadoria_points,
      'champions_points', md.champions_points,
      'credly_badge_count', md.credly_badge_count,
      'has_cpmai', md.has_cpmai,
      'trail_progress', md.trail_progress,
      -- #576: attendance_rate from the pre-batched map (value identical to the
      -- prior per-member public.get_attendance_rate(md.id, v_cycle_start) call).
      'attendance_rate', (v_attendance -> md.id::text),
      'current_streak', COALESCE((v_stats -> md.id::text ->> 'current_streak')::int, 0),
      'longest_streak', COALESCE((v_stats -> md.id::text ->> 'longest_streak')::int, 0),
      'active_cycles', COALESCE((v_stats -> md.id::text ->> 'active_cycles')::int, 0),
      -- #576: last_activity folded into points_per_member's MAX(created_at).
      'last_activity', to_char(md.last_activity_ts, 'YYYY-MM-DD'),
      'trail_courses', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'course_id', c.id, 'code', c.code, 'name', c.name, 'tier', c.tier,
          'status', COALESCE(cp.status, 'missing')
        ) ORDER BY c.sort_order), '[]'::jsonb)
        FROM courses c
        LEFT JOIN course_progress cp ON cp.course_id = c.id AND cp.member_id = md.id
        WHERE c.is_trail = true
      )
    ) ORDER BY md.total_points DESC), '[]'::jsonb) AS members_json
    FROM member_data md
  ),
  v_trend AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'xp', month_xp) ORDER BY month), '[]'::jsonb) AS trend_json
    FROM (
      SELECT date_trunc('month', gp.created_at) AS month, SUM(gp.points) AS month_xp
      FROM gamification_points gp
      JOIN init_members im ON im.id = gp.member_id
      WHERE gp.created_at >= v_cycle_start
      GROUP BY date_trunc('month', gp.created_at)
    ) sub
  ),
  v_trail AS (
    SELECT ROUND(AVG(member_pct), 2) AS pct FROM (
      SELECT (
        SELECT count(*) FROM course_progress cp
        WHERE cp.member_id = im.id AND cp.status = 'completed'
          AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)
      )::numeric / NULLIF(v_trail_total, 0) AS member_pct
      FROM init_members im
    ) s
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_xp', COALESCE((SELECT SUM(total_points) FROM member_data), 0),
      'avg_xp', CASE WHEN (SELECT count(*) FROM member_data) > 0
                THEN ROUND((SELECT SUM(total_points) FROM member_data)::numeric / (SELECT count(*) FROM member_data))
                ELSE 0 END,
      'tribe_rank', NULL,
      'cert_coverage', CASE WHEN (SELECT count(*) FROM member_data) > 0
                       THEN ROUND((SELECT count(*) FROM member_data WHERE has_cpmai OR credly_badge_count > 0)::numeric / (SELECT count(*) FROM member_data), 2)
                       ELSE 0 END,
      'trail_completion', COALESCE((SELECT pct FROM v_trail), 0)
    ),
    'members', (SELECT members_json FROM v_members),
    'tribe_ranking', '[]'::jsonb,
    'monthly_trend', (SELECT trend_json FROM v_trend)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- ACL unchanged but restated (same rationale as above).
REVOKE ALL ON FUNCTION public.get_initiative_gamification(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_initiative_gamification(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_initiative_gamification(uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
