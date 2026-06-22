-- #785 PR-3 — Confidential initiative visibility gate (RPC layer).
--
-- PR-1 (20260805000231) added initiatives.visibility + rls_can_see_initiative().
-- PR-2 (20260805000232) added the 8 RESTRICTIVE RLS SELECT policies + 2 SECDEF
--   resolvers (rls_can_see_board, rls_can_see_artifact_link) + the AJ invariant.
-- PR-3 (this) gates the SECURITY DEFINER read/list RPCs that BYPASS RLS, so a
--   confidential initiative's existence / board / cards / events / artifacts /
--   deliverables / drive-links never leak through an RPC to a non-engaged member.
--   Decision PM #2: curation surfaces EXCLUDE confidential by default (a curator
--   without an engagement on the confidential initiative does not see it).
--   Public aggregates exclude confidential from their initiative counts.
--
-- Path: rls_can_see_initiative() returns TRUE for 'standard' and for a NULL
--   initiative_id, so every non-confidential code path is behaviour-neutral. Only
--   confidential initiatives (none in prod at ship time) change: invisible to the
--   non-engaged; GP (manage_platform) + superadmin still see (decision PM #1).
--   board→initiative and event→initiative resolution uses the PR-2 SECDEF resolvers
--   (rls_can_see_board / rls_can_see_artifact_link) so it bypasses RLS.
--
-- DDL only: CREATE OR REPLACE of existing SECDEF functions; NO signature change.
-- Bodies reproduced verbatim from pg_get_functiondef + a single gate each, so the
-- Phase-C body-hash gate stays green (live prosrc == this file's CREATE block).
--
-- Out of scope (documented no-ops): list_initiative_boards /
--   search_initiative_board_items delegate to list_project_boards / search_board_items
--   (covered transitively). get_public_impact_data counts no initiatives by visibility
--   (aggregate hours don't reveal a confidential initiative's existence). Weekly digests
--   (get_weekly_member_digest / get_weekly_tribe_digest) are already scoped to insiders
--   (own assignee_id / tribe) or gated to leader/co-leader/manage_member.

-- =====================================================================
-- SECTION 1 — Listing / discovery RPCs
-- =====================================================================

CREATE OR REPLACE FUNCTION public.list_initiatives(p_kind text DEFAULT NULL::text, p_status text DEFAULT NULL::text)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT jsonb_build_object(
    'id', i.id,
    'kind', i.kind,
    'title', i.title,
    'description', i.description,
    'status', i.status,
    'metadata', i.metadata,
    'parent_initiative_id', i.parent_initiative_id,
    'legacy_tribe_id', i.legacy_tribe_id,
    'created_at', i.created_at,
    'member_count', (SELECT count(*) FROM engagements e WHERE e.initiative_id = i.id AND e.status = 'active'),
    'kind_display_name', ik.display_name,
    'kind_config', jsonb_build_object(
      'display_name', ik.display_name,
      'icon', ik.icon,
      'icon_emoji', ik.icon_emoji,
      'has_board', ik.has_board,
      'has_meeting_notes', ik.has_meeting_notes,
      'has_deliverables', ik.has_deliverables,
      'has_attendance', ik.has_attendance,
      'has_certificate', ik.has_certificate
    )
  )
  FROM public.initiatives i
  JOIN public.initiative_kinds ik ON ik.slug = i.kind
  WHERE i.organization_id = public.auth_org()
    AND public.rls_can_see_initiative(i.id)  -- #785 PR-3: confidential gate
    AND (p_kind IS NULL OR i.kind = p_kind)
    AND (p_status IS NULL OR i.status = p_status)
  ORDER BY i.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_open_initiatives()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_results jsonb;
BEGIN
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'initiative_id', i.id,
    'title', i.title,
    'kind', i.kind,
    'join_policy', i.join_policy,
    'status', i.status,
    'description', i.description,
    'has_active_engagement',
      EXISTS (SELECT 1 FROM public.engagements e
              WHERE e.person_id = v_caller_person_id
                AND e.initiative_id = i.id
                AND e.status = 'active'),
    'has_pending_invitation',
      EXISTS (SELECT 1 FROM public.initiative_invitations ii
              WHERE ii.invitee_member_id = v_caller_member_id
                AND ii.initiative_id = i.id
                AND ii.status = 'pending')
  ) ORDER BY i.created_at DESC)
  INTO v_results
  FROM public.initiatives i
  WHERE i.status = 'active'
    AND i.join_policy IN ('request_to_join', 'open')
    AND public.rls_can_see_initiative(i.id);  -- #785 PR-3: confidential gate

  RETURN COALESCE(v_results, '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_project_boards(p_tribe_id integer DEFAULT NULL::integer)
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      pb.id, pb.board_name,
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      pb.source, pb.columns, pb.is_active,
      pb.board_scope, pb.domain_key, pb.cycle_scope, pb.created_at,
      (SELECT count(*) FROM public.board_items bi WHERE bi.board_id = pb.id) AS item_count
    FROM public.project_boards pb
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    WHERE pb.is_active IS TRUE
      AND public.rls_can_see_initiative(pb.initiative_id)  -- #785 PR-3: confidential gate
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
    ORDER BY
      CASE pb.board_scope WHEN 'global' THEN 0 WHEN 'operational' THEN 1 ELSE 2 END,
      pb.created_at DESC
  ) r;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_tribe_deliverables(p_tribe_id integer, p_cycle_code text DEFAULT NULL::text)
 RETURNS SETOF tribe_deliverables
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Reader: gate via rls_is_member; returns empty set for unauthenticated callers.
  -- Avoids RAISE EXCEPTION pattern so the ADR-0011 contract matcher doesn't flag this
  -- reader RPC as an unguarded auth gate.
  IF NOT rls_is_member() THEN RETURN; END IF;

  RETURN QUERY
    SELECT td.* FROM public.tribe_deliverables td
    LEFT JOIN public.initiatives i ON i.id = td.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id
      AND public.rls_can_see_initiative(td.initiative_id)  -- #785 PR-3: confidential gate
      AND (p_cycle_code IS NULL OR td.cycle_code = p_cycle_code)
    ORDER BY td.due_date ASC NULLS LAST, td.created_at DESC;
END; $function$;

CREATE OR REPLACE FUNCTION public.list_meeting_artifacts(p_limit integer DEFAULT 100, p_tribe_id integer DEFAULT NULL::integer)
 RETURNS SETOF meeting_artifacts
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT ma.* FROM public.meeting_artifacts ma
  LEFT JOIN public.initiatives i ON i.id = ma.initiative_id
  WHERE ma.is_published = true
    AND public.rls_can_see_artifact_link(ma.initiative_id, ma.event_id)  -- #785 PR-3: confidential gate
    AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id OR ma.initiative_id IS NULL)
  ORDER BY ma.meeting_date DESC LIMIT p_limit;
$function$;

CREATE OR REPLACE FUNCTION public.list_initiative_meeting_artifacts(p_limit integer DEFAULT 100, p_initiative_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF meeting_artifacts
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF p_initiative_id IS NOT NULL THEN
    PERFORM public.assert_initiative_capability(p_initiative_id, 'has_meeting_notes');
  END IF;

  RETURN QUERY
    SELECT *
    FROM public.meeting_artifacts ma
    WHERE ma.is_published = true
      AND public.rls_can_see_artifact_link(ma.initiative_id, ma.event_id)  -- #785 PR-3: confidential gate
      AND (
        p_initiative_id IS NULL
        OR ma.initiative_id = p_initiative_id
        OR ma.initiative_id IS NULL
      )
    ORDER BY ma.meeting_date DESC
    LIMIT p_limit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.search_board_items(p_query text, p_tribe_id integer DEFAULT NULL::integer)
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member_id uuid;
  v_tribe_id integer;
BEGIN
  SELECT id, tribe_id INTO v_member_id, v_tribe_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'auth_required'; END IF;

  IF p_tribe_id IS NULL THEN p_tribe_id := v_tribe_id; END IF;

  RETURN QUERY
  SELECT row_to_json(r)
  FROM (
    SELECT bi.id, bi.title, bi.description, bi.status, bi.tags, bi.due_date, bi.assignee_id
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    JOIN initiatives i ON i.id = pb.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id
      AND public.rls_can_see_initiative(i.id)  -- #785 PR-3: confidential gate
      AND bi.status != 'archived'
      AND (bi.title ILIKE '%' || p_query || '%' OR bi.description ILIKE '%' || p_query || '%')
    ORDER BY bi.updated_at DESC
    LIMIT 20
  ) r;
END;
$function$;

CREATE OR REPLACE FUNCTION public.search_hub_resources(p_query text, p_asset_type text DEFAULT NULL::text, p_limit integer DEFAULT 15)
 RETURNS TABLE(id uuid, title text, description text, url text, asset_type text, source text, tags text[], tribe_id integer, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND m.is_active = true
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.title,
    r.description,
    r.url,
    r.asset_type,
    r.source,
    r.tags,
    i.legacy_tribe_id AS tribe_id,
    r.created_at
  FROM hub_resources r
  LEFT JOIN initiatives i ON i.id = r.initiative_id
  WHERE r.is_active = true
    AND public.rls_can_see_initiative(r.initiative_id)  -- #785 PR-3: confidential gate
    AND (
      r.title ILIKE '%' || p_query || '%'
      OR r.description ILIKE '%' || p_query || '%'
      OR EXISTS (
        SELECT 1 FROM unnest(r.tags) t WHERE t ILIKE '%' || p_query || '%'
      )
    )
    AND (p_asset_type IS NULL OR r.asset_type = p_asset_type)
  ORDER BY
    CASE WHEN r.title ILIKE '%' || p_query || '%' THEN 0 ELSE 1 END,
    r.created_at DESC
  LIMIT p_limit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_initiative_events(p_tribe_id integer DEFAULT NULL::integer, p_initiative_id uuid DEFAULT NULL::uuid, p_types text[] DEFAULT NULL::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_has_minutes boolean DEFAULT NULL::boolean, p_has_recording boolean DEFAULT NULL::boolean, p_has_attendance boolean DEFAULT NULL::boolean, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_is_admin boolean;
  v_is_stakeholder boolean;
  v_clamped_limit int;
  v_resolved_from date;
  v_resolved_to date;
  v_total int;
  v_result jsonb;
  v_target_tribe int;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  v_is_admin := public.can_by_member(v_caller_id, 'manage_member');
  v_is_stakeholder := public.can_by_member(v_caller_id, 'manage_partner');

  -- Resolve target tribe (may be NULL = no filter)
  IF p_initiative_id IS NOT NULL THEN
    SELECT legacy_tribe_id INTO v_target_tribe
    FROM public.initiatives WHERE id = p_initiative_id;
  ELSE
    v_target_tribe := p_tribe_id;
  END IF;

  -- Authorization tiering (spec)
  IF v_is_admin THEN
    NULL;  -- admin sees all
  ELSIF v_is_stakeholder AND v_target_tribe IS NULL THEN
    NULL;  -- sponsor/liaison sees general events only (filter applied below)
  ELSIF v_caller_role = 'tribe_leader' AND (v_target_tribe IS NULL OR v_target_tribe = v_caller_tribe) THEN
    NULL;  -- TL of target tribe
  ELSIF v_caller_role IN ('researcher', 'chapter_board') AND v_target_tribe = v_caller_tribe THEN
    NULL;  -- researcher in target tribe
  ELSE
    RETURN jsonb_build_object('error', 'Unauthorized: insufficient access to requested events');
  END IF;

  -- Clamp + defaults
  v_clamped_limit := greatest(1, least(200, coalesce(p_limit, 50)));
  v_resolved_from := coalesce(p_date_from, current_date - interval '90 days');
  v_resolved_to := coalesce(p_date_to, current_date);

  WITH base AS (
    SELECT
      e.id, e.date, e.time_start, e.type, e.title,
      e.duration_minutes, e.duration_actual, e.meeting_link,
      e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) > 0 AS has_minutes,
      e.minutes_posted_at,
      e.youtube_url, e.recording_url, e.is_recorded, e.recording_type,
      e.nature, e.created_at,
      i.legacy_tribe_id AS tribe_id,
      i.id AS initiative_id,
      i.title AS initiative_title,
      (SELECT count(*) FROM public.attendance a WHERE a.event_id = e.id) AS attendance_count,
      (SELECT count(*) FROM public.attendance a WHERE a.event_id = e.id AND a.present = true) AS attendance_present_count,
      (SELECT count(*) FROM public.event_showcases s WHERE s.event_id = e.id) AS showcase_count,
      (SELECT count(*) FROM public.meeting_action_items m WHERE m.event_id = e.id AND m.status NOT IN ('done', 'cancelled')) AS action_items_open
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_resolved_from
      AND e.date <= v_resolved_to
      AND public.rls_can_see_initiative(i.id)  -- #785 PR-3: confidential gate
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
      AND (p_initiative_id IS NULL OR i.id = p_initiative_id)
      AND (p_types IS NULL OR e.type = ANY(p_types))
      -- Stakeholder restriction: sees only general events when no target tribe
      AND (NOT (v_is_stakeholder AND NOT v_is_admin) OR e.type IN ('geral', 'kickoff', 'lideranca'))
  ),
  filtered AS (
    SELECT * FROM base
    WHERE
      (p_has_minutes IS NULL OR base.has_minutes = p_has_minutes)
      AND (p_has_recording IS NULL OR (base.youtube_url IS NOT NULL OR base.recording_url IS NOT NULL) = p_has_recording)
      AND (p_has_attendance IS NULL OR (base.attendance_count > 0) = p_has_attendance)
  )
  SELECT
    count(*)::int,
    coalesce(jsonb_agg(jsonb_build_object(
      'id', f.id,
      'date', f.date,
      'time_start', f.time_start,
      'type', f.type,
      'title', f.title,
      'duration_minutes', f.duration_minutes,
      'duration_actual', f.duration_actual,
      'meeting_link', f.meeting_link,
      'minutes_text_present', f.has_minutes,
      'minutes_posted_at', f.minutes_posted_at,
      'youtube_url', f.youtube_url,
      'recording_url', f.recording_url,
      'is_recorded', f.is_recorded,
      'recording_type', f.recording_type,
      'tribe_id', f.tribe_id,
      'initiative_id', f.initiative_id,
      'initiative_title', f.initiative_title,
      'attendance_count', f.attendance_count,
      'attendance_present_count', f.attendance_present_count,
      'showcase_count', f.showcase_count,
      'action_items_open', f.action_items_open,
      'nature', f.nature
    ) ORDER BY f.date DESC, f.time_start DESC NULLS LAST), '[]'::jsonb)
  INTO v_total, v_result
  FROM (
    SELECT * FROM filtered
    ORDER BY date DESC, time_start DESC NULLS LAST
    OFFSET p_offset
    LIMIT v_clamped_limit
  ) f;

  RETURN jsonb_build_object(
    'total_count', v_total,
    'limit', v_clamped_limit,
    'offset', p_offset,
    'date_from', v_resolved_from,
    'date_to', v_resolved_to,
    'events', v_result
  );
END;
$function$;

-- =====================================================================
-- SECTION 2 — Detail RPCs (single initiative / board / card / event)
-- =====================================================================

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

  -- #785 PR-3: confidential gate (same 'not found' response — do not leak existence)
  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
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
  -- #785 PR-3: confidential gate (covers both the tribe-delegated and standalone paths)
  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

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

CREATE OR REPLACE FUNCTION public.get_initiative_drive_links(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_initiative record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT id, title, kind INTO v_initiative
  FROM public.initiatives WHERE id = p_initiative_id;
  IF v_initiative.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Initiative not found');
  END IF;

  -- #785 PR-3: confidential gate (same 'not found' response — do not leak existence)
  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RETURN jsonb_build_object('error', 'Initiative not found');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'drive_folder_id', l.drive_folder_id,
    'drive_folder_url', l.drive_folder_url,
    'drive_folder_name', l.drive_folder_name,
    'link_purpose', l.link_purpose,
    'linked_by_name', m.name,
    'linked_at', l.linked_at
  ) ORDER BY
    CASE l.link_purpose
      WHEN 'workspace' THEN 1
      WHEN 'shared_resources' THEN 2
      WHEN 'minutes' THEN 3
      WHEN 'archive' THEN 4
      ELSE 5
    END,
    l.linked_at DESC
  ), '[]'::jsonb)
  INTO v_result
  FROM public.initiative_drive_links l
  LEFT JOIN public.members m ON m.id = l.linked_by
  WHERE l.initiative_id = p_initiative_id AND l.unlinked_at IS NULL;

  RETURN jsonb_build_object(
    'initiative_id', p_initiative_id,
    'initiative_title', v_initiative.title,
    'initiative_kind', v_initiative.kind,
    'drive_links', v_result,
    'fetched_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_initiative_board_summary(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_board_id uuid;
  v_counts jsonb;
  v_recent jsonb;
  v_total integer;
BEGIN
  -- #785 PR-3: confidential gate (same 'no board linked' response — do not leak existence)
  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RETURN jsonb_build_object('error', 'No board linked');
  END IF;

  SELECT pb.id INTO v_board_id
  FROM project_boards pb
  WHERE pb.initiative_id = p_initiative_id AND pb.is_active = true
  LIMIT 1;

  IF v_board_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No board linked');
  END IF;

  -- Count by status
  SELECT coalesce(jsonb_object_agg(s.status, s.cnt), '{}'::jsonb), coalesce(sum(s.cnt), 0)
  INTO v_counts, v_total
  FROM (
    SELECT status, count(*)::int as cnt
    FROM board_items
    WHERE board_id = v_board_id AND status != 'archived'
    GROUP BY status
  ) s;

  -- Recent 10 items
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id, 'title', r.title, 'status', r.status,
    'due_date', r.due_date, 'assignee_id', r.assignee_id
  )), '[]'::jsonb)
  INTO v_recent
  FROM (
    SELECT id, title, status, due_date, assignee_id
    FROM board_items
    WHERE board_id = v_board_id AND status != 'archived'
    ORDER BY created_at DESC LIMIT 10
  ) r;

  RETURN jsonb_build_object(
    'board_id', v_board_id,
    'total', v_total,
    'by_status', v_counts,
    'recent', v_recent
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_board(p_board_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  -- #785 PR-3: confidential gate (board→initiative via SECDEF resolver, bypasses RLS)
  IF NOT public.rls_can_see_board(p_board_id) THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
    'board', (
      SELECT jsonb_build_object(
        'id', b.id,
        'board_name', b.board_name,
        'tribe_id', public.resolve_tribe_id(b.initiative_id),
        'source', b.source,
        'columns', b.columns,
        'is_active', b.is_active,
        'domain_key', b.domain_key,
        'board_scope', b.board_scope,
        'cycle_scope', b.cycle_scope
      )
      FROM project_boards b WHERE b.id = p_board_id
    ),
    'items', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'title', i.title,
          'description', i.description,
          'status', i.status,
          'assignee_id', i.assignee_id,
          'assignee_name', am.name,
          'reviewer_id', i.reviewer_id,
          'reviewer_name', rm.name,
          'tags', i.tags,
          'labels', i.labels,
          'due_date', i.due_date,
          'baseline_date', i.baseline_date,
          'forecast_date', i.forecast_date,
          'actual_completion_date', i.actual_completion_date,
          'mirror_source_id', i.mirror_source_id,
          'mirror_target_id', i.mirror_target_id,
          'is_mirror', i.is_mirror,
          'position', i.position,
          'attachments', i.attachments,
          'checklist', i.checklist,
          'curation_status', i.curation_status,
          'curation_due_at', i.curation_due_at,
          'cycle', i.cycle,
          'source_card_id', i.source_card_id,
          'source_board', i.source_board,
          'created_at', i.created_at,
          'updated_at', i.updated_at,
          'assignments', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
              'member_id', bia.member_id,
              'name', bm.name,
              'avatar_url', bm.photo_url,
              'role', bia.role
            ) ORDER BY
              CASE bia.role WHEN 'author' THEN 0 WHEN 'reviewer' THEN 1 WHEN 'curation_reviewer' THEN 2 ELSE 3 END,
              bia.assigned_at
            )
            FROM board_item_assignments bia
            JOIN members bm ON bm.id = bia.member_id
            WHERE bia.item_id = i.id
          ), '[]'::jsonb)
        ) ORDER BY i.position
      ), '[]'::jsonb)
      FROM board_items i
      LEFT JOIN members am ON am.id = i.assignee_id
      LEFT JOIN members rm ON rm.id = i.reviewer_id
      WHERE i.board_id = p_board_id
        AND i.status <> 'archived'
    )
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_card_detail(p_card_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_card record;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN NULL; END IF;

  SELECT * INTO v_card FROM board_items WHERE id = p_card_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Card not found: %', p_card_id; END IF;

  -- #785 PR-3: confidential gate (board→initiative; same 'not found' to avoid leaking existence)
  IF NOT public.rls_can_see_board(v_card.board_id) THEN
    RAISE EXCEPTION 'Card not found: %', p_card_id;
  END IF;

  RETURN jsonb_build_object(
    'card', to_jsonb(v_card),
    'board', (
      SELECT jsonb_build_object(
        'id', pb.id,
        'name', pb.board_name,
        'initiative_id', pb.initiative_id,
        'domain_key', pb.domain_key
      )
      FROM project_boards pb WHERE pb.id = v_card.board_id
    ),
    'assignee', (
      SELECT jsonb_build_object('id', m.id, 'name', m.name, 'operational_role', m.operational_role)
      FROM members m WHERE m.id = v_card.assignee_id
    ),
    'reviewer', (
      SELECT jsonb_build_object('id', m.id, 'name', m.name)
      FROM members m WHERE m.id = v_card.reviewer_id
    ),
    'checklist', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ci.id,
        'text', ci.text,
        'is_completed', ci.is_completed,
        'position', ci.position,
        'assigned_to', ci.assigned_to,
        'assigned_to_name', (SELECT m.name FROM members m WHERE m.id = ci.assigned_to),
        'target_date', ci.target_date,
        'completed_at', ci.completed_at,
        'completed_by', ci.completed_by,
        'assigned_at', ci.assigned_at
      ) ORDER BY ci.position, ci.created_at)
      FROM board_item_checklists ci WHERE ci.board_item_id = p_card_id
    ), '[]'::jsonb),
    'assignments', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', ba.member_id,
        'member_name', (SELECT m.name FROM members m WHERE m.id = ba.member_id),
        'role', ba.role,
        'assigned_at', ba.assigned_at
      ))
      FROM board_item_assignments ba WHERE ba.item_id = p_card_id
    ), '[]'::jsonb),
    'timeline', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'action', ble.action,
        'reason', ble.reason,
        'actor_member_id', ble.actor_member_id,
        'actor_name', (SELECT m.name FROM members m WHERE m.id = ble.actor_member_id),
        'created_at', ble.created_at,
        'previous_status', ble.previous_status,
        'new_status', ble.new_status
      ) ORDER BY ble.created_at DESC)
      FROM (
        SELECT * FROM board_lifecycle_events
        WHERE item_id = p_card_id
        ORDER BY created_at DESC
        LIMIT 10
      ) ble
    ), '[]'::jsonb)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_meeting_detail(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- #785 PR-3: confidential gate (event→initiative; SECDEF bypasses RLS so this subquery is safe)
  IF NOT public.rls_can_see_initiative((SELECT e.initiative_id FROM events e WHERE e.id = p_event_id)) THEN
    RETURN jsonb_build_object('error', 'Event not found');
  END IF;

  SELECT jsonb_build_object(
    'event', jsonb_build_object(
      'id', e.id, 'title', e.title, 'date', e.date, 'type', e.type,
      'tribe_id', i.legacy_tribe_id,
      'tribe_name', i.title,
      'duration_minutes', e.duration_minutes, 'time_start', e.time_start,
      'meeting_link', e.meeting_link,
      'youtube_url', e.youtube_url, 'recording_url', e.recording_url,
      'agenda_text', e.agenda_text,
      'minutes_text', e.minutes_text,
      'notes', e.notes
    ),
    'attendance', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', a.member_id, 'member_name', m.name,
        'present', a.present, 'excused', a.excused
      ) ORDER BY m.name)
      FROM attendance a JOIN members m ON m.id = a.member_id
      WHERE a.event_id = e.id
    ), '[]'::jsonb),
    'attendee_count', (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true)
  ) INTO v_result
  FROM events e
  LEFT JOIN initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_event_id;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('error', 'Event not found');
  END IF;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_near_events(p_member_id uuid, p_window_hours integer DEFAULT 2)
 RETURNS TABLE(event_id uuid, event_title text, event_date date, event_type text, duration_minutes integer, already_checked_in boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tribe_id int;
BEGIN
  SELECT m.tribe_id INTO v_tribe_id
  FROM public.members m WHERE m.id = p_member_id;

  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.date,
    e.type,
    e.duration_minutes,
    EXISTS(
      SELECT 1 FROM public.attendance a
      WHERE a.event_id = e.id AND a.member_id = p_member_id
    )
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.date::timestamptz BETWEEN
        now() - (p_window_hours || ' hours')::interval
    AND now() + (p_window_hours || ' hours')::interval
    AND (e.initiative_id IS NULL OR i.legacy_tribe_id = v_tribe_id)
    AND public.rls_can_see_initiative(e.initiative_id)  -- #785 PR-3: confidential gate
  ORDER BY e.date ASC
  LIMIT 3;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_recent_events(p_days_back integer DEFAULT 30, p_days_forward integer DEFAULT 7)
 RETURNS TABLE(id uuid, date date, type text, title text, tribe_id integer, tribe_name text, headcount bigint, duration_minutes integer, duration_actual integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    e.id, e.date, e.type, e.title, i.legacy_tribe_id,
    i.title AS tribe_name,
    (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present) AS headcount,
    e.duration_minutes, e.duration_actual
  FROM events e
  LEFT JOIN initiatives i ON i.id = e.initiative_id
  WHERE e.date BETWEEN current_date - p_days_back AND current_date + p_days_forward
    AND public.rls_can_see_initiative(e.initiative_id)  -- #785 PR-3: confidential gate
  ORDER BY e.date DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_agenda_smart(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_event record;
  v_initiative record;
  v_legacy_tribe_id int;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  SELECT e.id, e.title, e.date, e.type, e.duration_minutes, e.meeting_link,
         e.initiative_id, e.agenda_text, e.agenda_url, e.time_start
  INTO v_event FROM public.events e WHERE e.id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  -- #785 PR-3: confidential gate (event→initiative)
  IF NOT public.rls_can_see_initiative(v_event.initiative_id) THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  IF v_event.initiative_id IS NOT NULL THEN
    SELECT i.id, i.title, i.kind, i.legacy_tribe_id
    INTO v_initiative FROM public.initiatives i WHERE i.id = v_event.initiative_id;
    v_legacy_tribe_id := v_initiative.legacy_tribe_id;
  END IF;

  v_result := jsonb_build_object(
    'event', jsonb_build_object(
      'id', v_event.id,
      'title', v_event.title,
      'date', v_event.date,
      'time_start', v_event.time_start,
      'type', v_event.type,
      'duration_minutes', v_event.duration_minutes,
      'meeting_link', v_event.meeting_link,
      'agenda_text', v_event.agenda_text,
      'agenda_url', v_event.agenda_url
    ),
    'initiative', CASE WHEN v_initiative.id IS NOT NULL THEN
      jsonb_build_object('id', v_initiative.id, 'title', v_initiative.title,
        'kind', v_initiative.kind, 'legacy_tribe_id', v_initiative.legacy_tribe_id)
    ELSE NULL END,

    'carry_forward_actions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', mai.id,
        'event_id', mai.event_id,
        'event_title', e2.title,
        'event_date', e2.date,
        'description', mai.description,
        'kind', mai.kind,
        'assignee_name', mai.assignee_name,
        'assignee_id', mai.assignee_id,
        'due_date', mai.due_date,
        'days_overdue', CASE
          WHEN mai.due_date IS NOT NULL AND mai.due_date < CURRENT_DATE
          THEN (CURRENT_DATE - mai.due_date)
          ELSE 0 END,
        'days_open', GREATEST(0, EXTRACT(DAY FROM (now() - mai.created_at))::int),
        'board_item_id', mai.board_item_id
      ) ORDER BY
        CASE WHEN mai.due_date < CURRENT_DATE THEN 0 ELSE 1 END,
        mai.due_date NULLS LAST,
        mai.created_at DESC)
      FROM public.meeting_action_items mai
      JOIN public.events e2 ON e2.id = mai.event_id
      WHERE mai.resolved_at IS NULL
        AND e2.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND e2.id <> p_event_id
        AND e2.date < v_event.date
        AND mai.created_at >= (now() - interval '90 days')
        AND mai.kind IN ('action','followup')
    ), '[]'::jsonb),

    'at_risk_cards', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'curation_status', bi.curation_status,
        'assignee_id', bi.assignee_id,
        'assignee_name', am.name,
        'due_date', bi.due_date,
        'forecast_date', bi.forecast_date,
        'baseline_date', bi.baseline_date,
        'days_since_update', GREATEST(0, EXTRACT(DAY FROM (now() - bi.updated_at))::int),
        'tags', bi.tags,
        'risk_reasons', jsonb_strip_nulls(jsonb_build_object(
          'forecast_slip', CASE WHEN bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
            AND bi.forecast_date > bi.baseline_date + INTERVAL '7 days'
            THEN (bi.forecast_date - bi.baseline_date) ELSE NULL END,
          'stale_days', CASE WHEN bi.updated_at < now() - interval '14 days'
            AND bi.status NOT IN ('done', 'archived')
            THEN EXTRACT(DAY FROM (now() - bi.updated_at))::int ELSE NULL END
        ))
      ) ORDER BY bi.updated_at ASC)
      FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.members am ON am.id = bi.assignee_id
      WHERE pb.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND pb.is_active = true
        AND bi.status NOT IN ('done','archived')
        AND (
          (bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
            AND bi.forecast_date > bi.baseline_date + INTERVAL '7 days')
          OR bi.updated_at < now() - interval '14 days'
        )
      LIMIT 30
    ), '[]'::jsonb),

    'relevant_kpis', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'kpi_target_id', akt.id,
        'kpi_key', akt.kpi_key,
        'kpi_label_pt', akt.kpi_label_pt,
        'category', akt.category,
        'target_value', akt.target_value,
        'current_value', akt.current_value,
        'baseline_value', akt.baseline_value,
        'attainment_pct', CASE WHEN akt.target_value IS NOT NULL AND akt.target_value <> 0
          THEN ROUND((COALESCE(akt.current_value, 0) / akt.target_value * 100)::numeric, 1)
          ELSE NULL END,
        'status_color', CASE
          WHEN akt.target_value IS NULL OR akt.target_value = 0 THEN 'gray'
          WHEN COALESCE(akt.current_value, 0) >= akt.target_value * 0.9 THEN 'green'
          WHEN COALESCE(akt.current_value, 0) >= akt.target_value * 0.7 THEN 'yellow'
          ELSE 'red' END,
        'weight', tkc.weight,
        'icon', akt.icon
      ) ORDER BY
        CASE WHEN COALESCE(akt.current_value, 0) < akt.target_value * 0.7 THEN 0 ELSE 1 END,
        akt.display_order)
      FROM public.tribe_kpi_contributions tkc
      JOIN public.annual_kpi_targets akt ON akt.id = tkc.kpi_target_id
      WHERE tkc.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND akt.target_value IS NOT NULL
        AND COALESCE(akt.current_value, 0) < akt.target_value * 0.9
    ), '[]'::jsonb),

    'showcase_candidates', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', m.id,
        'name', m.name,
        'photo_url', m.photo_url,
        'engagement_kind', ae.kind,
        'recent_completed_cards', (
          SELECT COUNT(*) FROM public.board_items bi
          JOIN public.project_boards pb ON pb.id = bi.board_id
          WHERE bi.assignee_id = m.id
            AND pb.initiative_id = v_event.initiative_id
            AND bi.status = 'done'
            AND bi.actual_completion_date >= CURRENT_DATE - INTERVAL '60 days'
        ),
        'has_unshowcased_artifact', EXISTS (
          SELECT 1 FROM public.board_items bi
          JOIN public.project_boards pb ON pb.id = bi.board_id
          WHERE bi.assignee_id = m.id
            AND pb.initiative_id = v_event.initiative_id
            AND bi.status = 'done'
            AND bi.actual_completion_date >= CURRENT_DATE - INTERVAL '60 days'
            AND NOT EXISTS (
              SELECT 1 FROM public.event_showcases es
              WHERE es.board_item_id = bi.id
                AND es.created_at >= CURRENT_DATE - INTERVAL '90 days'
            )
        )
      ) ORDER BY m.name)
      FROM public.members m
      JOIN public.persons p ON p.legacy_member_id = m.id
      JOIN public.auth_engagements ae ON ae.person_id = p.id
      WHERE m.is_active = true
        AND ae.is_authoritative = true
        AND ae.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.board_items bi2
          JOIN public.project_boards pb2 ON pb2.id = bi2.board_id
          WHERE bi2.assignee_id = m.id
            AND pb2.initiative_id = v_event.initiative_id
            AND bi2.status = 'done'
            AND bi2.actual_completion_date >= CURRENT_DATE - INTERVAL '60 days'
        )
    ), '[]'::jsonb),

    'at_risk_deliverables', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', td.id,
        'title', td.title,
        'cycle_code', td.cycle_code,
        'status', td.status,
        'assigned_member_id', td.assigned_member_id,
        'assignee_name', tdm.name,
        'due_date', td.due_date,
        'days_to_due', CASE WHEN td.due_date IS NOT NULL
          THEN (td.due_date - CURRENT_DATE) ELSE NULL END
      ) ORDER BY td.due_date NULLS LAST)
      FROM public.tribe_deliverables td
      LEFT JOIN public.members tdm ON tdm.id = td.assigned_member_id
      WHERE td.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND td.status NOT IN ('done','cancelled')
        AND (
          td.due_date IS NULL
          OR td.due_date <= CURRENT_DATE + INTERVAL '14 days'
        )
    ), '[]'::jsonb),

    'generated_at', now()
  );

  RETURN v_result;
END;
$function$;

-- =====================================================================
-- SECTION 3 — Curation surfaces (decision PM #2: EXCLUDE confidential)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.get_curation_cross_board()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN coalesce((
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', i.id,
        'board_id', i.board_id,
        'board_name', b.board_name,
        'tribe_id', public.resolve_tribe_id(b.initiative_id),
        'domain_key', b.domain_key,
        'title', i.title,
        'description', i.description,
        'status', i.status,
        'assignee_id', i.assignee_id,
        'assignee_name', am.name,
        'reviewer_id', i.reviewer_id,
        'reviewer_name', rm.name,
        'tags', i.tags,
        'labels', i.labels,
        'due_date', i.due_date,
        'attachments', i.attachments,
        'checklist', i.checklist,
        'curation_status', i.curation_status,
        'curation_due_at', i.curation_due_at,
        'cycle', i.cycle,
        'created_at', i.created_at,
        'updated_at', i.updated_at
      ) ORDER BY
        CASE i.curation_status
          WHEN 'draft' THEN 0
          WHEN 'review' THEN 1
          WHEN 'approved' THEN 2
          WHEN 'rejected' THEN 3
        END,
        i.updated_at DESC
    )
    FROM board_items i
    JOIN project_boards b ON b.id = i.board_id
    LEFT JOIN members am ON am.id = i.assignee_id
    LEFT JOIN members rm ON rm.id = i.reviewer_id
    WHERE b.is_active = true
      AND i.status <> 'archived'
      AND public.rls_can_see_initiative(b.initiative_id)  -- #785 PR-3: curation excludes confidential
  ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_curation_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.can_by_member(v_member_id, 'curate_content')
          OR public.can_by_member(v_member_id, 'write_board')) THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  SELECT jsonb_build_object(
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id, 'title', bi.title, 'description', bi.description,
        'status', bi.status, 'curation_status', bi.curation_status,
        'curation_due_at', bi.curation_due_at, 'board_id', bi.board_id,
        'board_name', pb.board_name, 'tribe_id', i.legacy_tribe_id, 'tribe_name', i.title,
        'assignee_id', bi.assignee_id, 'assignee_name', am.name,
        'reviewer_id', bi.reviewer_id, 'reviewer_name', rm.name,
        'tags', bi.tags, 'attachments', bi.attachments,
        'created_at', bi.created_at, 'updated_at', bi.updated_at,
        'review_count', (SELECT count(*) FROM curation_review_log crl WHERE crl.board_item_id = bi.id AND crl.review_round = (SELECT coalesce(max(ble.review_round), 1) FROM board_lifecycle_events ble WHERE ble.item_id = bi.id AND ble.action = 'reviewer_assigned')),
        'reviews_approved', (SELECT count(DISTINCT crl.curator_id) FROM curation_review_log crl WHERE crl.board_item_id = bi.id AND crl.decision = 'approved' AND crl.review_round = (SELECT coalesce(max(ble.review_round), 1) FROM board_lifecycle_events ble WHERE ble.item_id = bi.id AND ble.action = 'reviewer_assigned')),
        'reviewers_required', COALESCE(sc.reviewers_required, 2),
        'sla_status', CASE
          WHEN bi.curation_due_at IS NULL THEN 'no_sla'
          WHEN bi.curation_due_at < now() THEN 'overdue'
          WHEN bi.curation_due_at < now() + interval '2 days' THEN 'warning'
          ELSE 'on_time'
        END,
        'review_history', (
          SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', crl2.id, 'curator_name', cm.name, 'decision', crl2.decision,
            'feedback', crl2.feedback_notes, 'scores', crl2.criteria_scores,
            'completed_at', crl2.completed_at
          ) ORDER BY crl2.completed_at DESC), '[]'::jsonb)
          FROM curation_review_log crl2
          LEFT JOIN members cm ON cm.id = crl2.curator_id
          WHERE crl2.board_item_id = bi.id
        )
      ) ORDER BY
        CASE
          WHEN bi.curation_due_at IS NOT NULL AND bi.curation_due_at < now() THEN 0
          WHEN bi.curation_due_at IS NOT NULL AND bi.curation_due_at < now() + interval '2 days' THEN 1
          ELSE 2
        END,
        bi.curation_due_at ASC NULLS LAST
      )
      FROM board_items bi
      JOIN project_boards pb ON pb.id = bi.board_id
      LEFT JOIN initiatives i ON i.id = pb.initiative_id
      LEFT JOIN members am ON am.id = bi.assignee_id
      LEFT JOIN members rm ON rm.id = bi.reviewer_id
      LEFT JOIN board_sla_config sc ON sc.board_id = bi.board_id
      WHERE bi.curation_status = 'curation_pending'
        AND bi.status <> 'archived'
        AND pb.is_active = true
        AND public.rls_can_see_initiative(pb.initiative_id)  -- #785 PR-3: curation excludes confidential
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'total_pending', (SELECT count(*) FROM board_items bi2 JOIN project_boards pb2 ON pb2.id = bi2.board_id WHERE bi2.curation_status = 'curation_pending' AND bi2.status <> 'archived' AND pb2.is_active = true AND public.rls_can_see_initiative(pb2.initiative_id)),
      'overdue', (SELECT count(*) FROM board_items bi3 JOIN project_boards pb3 ON pb3.id = bi3.board_id WHERE bi3.curation_status = 'curation_pending' AND bi3.curation_due_at < now() AND bi3.status <> 'archived' AND pb3.is_active = true AND public.rls_can_see_initiative(pb3.initiative_id))
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_curation_pending_board_items()
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  -- #245/#185: curation authority = curate_content (designation-derived) OR write_board (admin/manager/tribe-lead).
  IF NOT (public.can_by_member(v_member_id, 'curate_content')
          OR public.can_by_member(v_member_id, 'write_board')) THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      bi.id, bi.title, bi.description, bi.status,
      bi.curation_status, bi.assignee_id, bi.reviewer_id,
      bi.due_date, bi.curation_due_at, bi.board_id,
      i.legacy_tribe_id AS tribe_id, i.title AS tribe_name,
      am.name AS assignee_name, rm.name AS reviewer_name,
      bi.created_at, bi.updated_at, bi.attachments,
      (SELECT count(*) FROM public.curation_review_log crl WHERE crl.board_item_id = bi.id) AS review_count,
      (SELECT json_agg(json_build_object(
        'id', crl2.id, 'curator_name', cm.name,
        'decision', crl2.decision, 'feedback', crl2.feedback_notes,
        'scores', crl2.criteria_scores, 'completed_at', crl2.completed_at
       ) ORDER BY crl2.completed_at DESC)
       FROM public.curation_review_log crl2
       LEFT JOIN public.members cm ON cm.id = crl2.curator_id
       WHERE crl2.board_item_id = bi.id
      ) AS review_history
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    LEFT JOIN public.members am ON am.id = bi.assignee_id
    LEFT JOIN public.members rm ON rm.id = bi.reviewer_id
    WHERE bi.curation_status = 'curation_pending'
      AND bi.status <> 'archived'
      AND pb.is_active = true
      AND public.rls_can_see_initiative(pb.initiative_id)  -- #785 PR-3: curation excludes confidential
    ORDER BY bi.curation_due_at ASC NULLS LAST, bi.updated_at DESC
  ) r;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_pending_curation(p_table text DEFAULT 'all'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member_id uuid; v_result jsonb := '[]'::jsonb; v_resources jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  -- #245/#185: curation authority = curate_content (designation-derived) OR write.
  IF NOT (public.can_by_member(v_member_id, 'curate_content')
          OR public.can_by_member(v_member_id, 'write')) THEN RAISE EXCEPTION 'Insufficient permissions'; END IF;

  -- ADR-0012 archival: artifacts branch removed. publication_submissions flow via approval_chains.
  IF p_table IN ('all', 'hub_resources') THEN
    SELECT COALESCE(jsonb_agg(row_to_json(r)), '[]'::jsonb) INTO v_resources
    FROM (
      SELECT h.id, h.title, h.url, h.asset_type AS type, h.source, h.tags,
             h.curation_status, h.trello_card_id, h.cycle_code AS cycle,
             h.created_at, NULL::text AS author_name,
             i.title AS tribe_name,
             'hub_resources' AS _table,
             public.suggest_tags(h.title, h.asset_type, h.cycle_code) AS suggested_tags
      FROM public.hub_resources h
      LEFT JOIN public.initiatives i ON i.id = h.initiative_id
      WHERE h.source IS DISTINCT FROM 'manual'
        AND h.curation_status IN ('draft','pending_review')
        AND public.rls_can_see_initiative(h.initiative_id)  -- #785 PR-3: curation excludes confidential
      ORDER BY h.created_at DESC LIMIT 200
    ) r;
    v_result := v_result || COALESCE(v_resources, '[]'::jsonb);
  END IF;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.assign_curation_reviewer(p_item_id uuid, p_reviewer_id uuid, p_round integer DEFAULT 1)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller   members%rowtype;
  v_reviewer members%rowtype;
  v_item     board_items%rowtype;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- ADR-0041: strict V4 catalog (committee work)
  IF NOT public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review';
  END IF;

  SELECT * INTO v_reviewer FROM members WHERE id = p_reviewer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Reviewer not found'; END IF;
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content').
  -- Target-user check (reviewer, not caller). co_gp legacy path preserved as V3.
  IF NOT (
    public.can_by_member(p_reviewer_id, 'curate_content')
    OR 'co_gp' = ANY(coalesce(v_reviewer.designations, array[]::text[]))
  ) THEN
    RAISE EXCEPTION 'Reviewer must have curate_content authority or co_gp designation';
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;

  -- #785 PR-3: confidential gate (curator without engagement cannot act on confidential items)
  IF NOT public.rls_can_see_board(v_item.board_id) THEN
    RAISE EXCEPTION 'Item not found';
  END IF;

  IF p_reviewer_id = v_item.assignee_id THEN
    IF NOT EXISTS (
      SELECT 1 FROM board_lifecycle_events
      WHERE item_id = p_item_id AND action = 'reviewer_assigned'
        AND review_round = p_round AND actor_member_id IS DISTINCT FROM p_reviewer_id
    ) THEN
      RAISE EXCEPTION 'Cannot designate item author as sole reviewer';
    END IF;
  END IF;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id, review_round)
  VALUES (v_item.board_id, p_item_id, 'reviewer_assigned',
    'Revisor designado: ' || v_reviewer.name, v_caller.id, p_round);
END;
$function$;

-- =====================================================================
-- SECTION 4 — Public aggregates (exclude confidential from counts)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.get_homepage_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN jsonb_build_object(
    -- #625 C1 (homepage instance): same exclusion as get_public_platform_stats.active_members.
    'members', (
      SELECT count(*) FROM members m
      WHERE m.is_active AND m.current_cycle_active
        AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
    ),
    'observers', (SELECT count(*) FROM members WHERE member_status = 'observer'),
    'alumni', (SELECT count(*) FROM members WHERE member_status = 'alumni'),
    'tribes', (SELECT count(*) FROM tribes WHERE is_active),
    'initiatives', (
      SELECT count(*) FROM initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
        AND visibility <> 'confidential'  -- #785 PR-3: aggregate excludes confidential
    ),
    'total_initiatives', (
      SELECT count(*) FROM initiatives WHERE status = 'active'
        AND visibility <> 'confidential'  -- #785 PR-3: aggregate excludes confidential
    ),
    'active_leaders', (
      SELECT count(DISTINCT person_id) FROM auth_engagements
      WHERE status = 'active' AND role IN ('leader', 'co_leader', 'co_gp')
    ),
    -- #481: canonical signed-chapter count (was count(DISTINCT members.chapter)=7 incl noise)
    'chapters', (public.get_chapter_metrics()->>'signed')::int,
    -- ADR-0100 #419 metric 1: impact_hours = the single canonical source (was an inline 4th formula).
    -- round() keeps the hero's integer display; cycle_report reads this value and auto-converges.
    'impact_hours', round(public.get_impact_hours_canonical())
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_platform_stats()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT json_build_object(
    -- #625 C1 (homepage instance): pre-onboarding cohort excluded -- "Pesquisadores ativos"
    -- counts only members OPERATING in the current cycle.
    'active_members', (
      SELECT COUNT(*) FROM public.members m
      WHERE m.is_active AND m.current_cycle_active
        AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
    ),
    'total_tribes', (SELECT COUNT(*) FROM public.tribes WHERE is_active),
    'total_initiatives', (
      SELECT count(*) FROM public.initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
        AND visibility <> 'confidential'  -- #785 PR-3: aggregate excludes confidential
    ),
    -- Cycle 4: community verticals (ADR-0103) surfaced as a live counter.
    'total_verticals', (
      SELECT count(*) FROM public.initiatives
      WHERE kind = 'community_vertical' AND status = 'active'
        AND visibility <> 'confidential'  -- #785 PR-3: aggregate excludes confidential
    ),
    -- #481: canonical signed-chapter count.
    'total_chapters', (public.get_chapter_metrics()->>'signed')::int,
    'total_events', (SELECT COUNT(*) FROM public.events WHERE date >= '2026-01-01'),
    'total_resources', (SELECT COUNT(*) FROM public.hub_resources WHERE is_active),
    'retention_rate', (
      SELECT ROUND(
        COUNT(*) FILTER (WHERE m.current_cycle_active)::numeric /
        NULLIF(COUNT(*) FILTER (WHERE m.is_active OR m.member_status = 'alumni'), 0) * 100, 1
      )
      FROM public.members m
      WHERE m.member_status IN ('active','alumni','observer')
        AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
    ),
    -- R2 (Ciclo 4): canonical impact-hours, shared with the hero headline (single denominator).
    'impact_hours', round(public.get_impact_hours_canonical())
  );
$function$;

NOTIFY pgrst, 'reload schema';
