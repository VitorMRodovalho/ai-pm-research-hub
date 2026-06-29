-- ============================================================================
-- Onda 2 — ADR-0111 amendment: extend view_aggregate_analytics from 8 -> 12 RPCs.
--
-- Adds the external institutional auditor's aggregate action to 4 chapter/comms RPCs,
-- WITH k-anonymity small-cell suppression so the EXTERNAL auditor never receives
-- re-identifying detail for a tiny chapter (live: 3 chapters have 1 active member;
-- members.chapter has no enum/CHECK). The auditor lawful basis (RoPA/LIA §2.3/§8 of
-- docs/legal/INSTITUTIONAL_AUDITOR_COOPERATION_AND_PROVISIONING.md) conditions aggregate
-- disclosure on small-cell suppression — this migration implements it in code (k=5),
-- not merely as a process commitment.
--
-- Per-RPC:
--   - exec_chapter_dashboard       : gate OR view_aggregate_analytics; external auditor gets a
--                                    suppressed marker when the chapter active cohort < 5.
--   - exec_chapter_comparison      : gate OR view_aggregate_analytics; external auditor gets
--                                    chapters with < 5 active members collapsed into "Outros (<5 ativos)".
--   - get_chapter_selection_summary: gate OR view_aggregate_analytics (output = count(*) + cycle
--                                    metadata only; no member breakdown, no small-cell exposure).
--   - comms_metrics_latest_by_channel: gate OR (inline) view_aggregate_analytics; the opaque
--                                    ingestion-controlled `payload` jsonb is NULLed on the auditor
--                                    path (forward-defense) — only the comms team receives it.
--
-- "External auditor" = holds view_aggregate_analytics AND NOT view_internal_analytics. Internal
-- controllers (GP / chapter_liaison / sponsor via view_internal_analytics or manage_platform) get
-- the full detail unchanged — behavior-neutral (verified live: 0 current members hold the action).
--
-- Bodies below are the LITERAL post-apply definitions (SSOT for the Phase-C drift gate; file==live).
-- Cross-ref: ADR-0111 (§ Amendment), GOVERNANCE_CHANGELOG (2026-06-29), PERMISSIONS_MATRIX §2.1,
-- docs/legal/INSTITUTIONAL_AUDITOR_COOPERATION_AND_PROVISIONING.md, tests/contracts/institutional-auditor-aggregate-scope.test.mjs.
-- Security: per-RPC adversarial PII/authority review (8 agents, 2026-06-29) — small-cell finding
-- on exec_chapter_dashboard/comparison resolved by the suppression implemented here.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.exec_chapter_dashboard(p_chapter text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_result jsonb;
  v_year_start date;
  v_members jsonb;
  v_production jsonb;
  v_engagement jsonb;
  v_certification jsonb;
BEGIN
  -- ACL: V4 view_internal_analytics OR own-chapter access (Path Y per ADR-0030)
  SELECT m.id, m.chapter INTO v_caller_id, v_caller_chapter
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'authentication_required');
  END IF;

  IF NOT (
    public.can_by_member(v_caller_id, 'view_internal_analytics')
    OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')
    OR v_caller_chapter = p_chapter
  ) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- k-anonymity small-cell suppression (RoPA/LIA s2.3/s8, ADR-0111 amendment): an EXTERNAL
  -- aggregate auditor (holds view_aggregate_analytics but NOT view_internal_analytics) must not
  -- receive re-identifying detail for a chapter whose active cohort is below k (5). Internal
  -- controllers are unaffected -- full detail unchanged (behavior-neutral for the live admin UI).
  IF public.can_by_member(v_caller_id, 'view_aggregate_analytics')
     AND NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    DECLARE v_active_n int;
    BEGIN
      SELECT count(*) FILTER (WHERE current_cycle_active) INTO v_active_n
      FROM public.members WHERE chapter = p_chapter;
      IF COALESCE(v_active_n, 0) < 5 THEN
        RETURN jsonb_build_object(
          'chapter', p_chapter, 'suppressed', true,
          'reason', 'small_cell_below_threshold', 'threshold', 5);
      END IF;
    END;
  END IF;

  -- Temporal anchor (year kickoff)
  v_year_start := make_date(EXTRACT(year FROM now())::int, 1, 1);
  BEGIN
    SELECT date INTO v_year_start
    FROM public.events
    WHERE type = 'general'
      AND title ILIKE '%kick%off%'
      AND EXTRACT(year FROM date) = EXTRACT(year FROM now())
    ORDER BY date ASC
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_year_start := make_date(EXTRACT(year FROM now())::int, 1, 1);
  END;
  v_year_start := COALESCE(v_year_start, make_date(EXTRACT(year FROM now())::int, 1, 1));

  -- Members
  SELECT jsonb_build_object(
    'total', count(*),
    'active', count(*) FILTER (WHERE current_cycle_active),
    'by_role', COALESCE((SELECT jsonb_object_agg(operational_role, cnt) FROM (SELECT operational_role, count(*) cnt FROM public.members WHERE chapter = p_chapter AND current_cycle_active GROUP BY operational_role) sub), '{}'::jsonb),
    'tribes', COALESCE((SELECT jsonb_agg(DISTINCT t.name) FROM public.members m2 JOIN public.tribes t ON t.id = m2.tribe_id WHERE m2.chapter = p_chapter AND m2.current_cycle_active), '[]'::jsonb)
  ) INTO v_members
  FROM public.members
  WHERE chapter = p_chapter;

  -- Production
  BEGIN
    SELECT jsonb_build_object(
      'articles_in_pipeline', count(*) FILTER (WHERE bi.curation_status IS NOT NULL AND bi.curation_status != 'draft'),
      'articles_published', count(*) FILTER (WHERE bi.curation_status = 'approved'),
      'board_items_total', count(*)
    ) INTO v_production
    FROM public.board_item_assignments bia
    JOIN public.members m ON m.id = bia.member_id
    JOIN public.board_items bi ON bi.id = bia.item_id
    WHERE m.chapter = p_chapter AND bi.created_at >= v_year_start;
  EXCEPTION WHEN OTHERS THEN
    v_production := jsonb_build_object('articles_in_pipeline', 0, 'articles_published', 0, 'board_items_total', 0);
  END;

  -- Engagement
  BEGIN
    SELECT jsonb_build_object(
      'attendance_events', count(DISTINCT a.event_id),
      'total_hours', COALESCE(round(SUM(e.duration_actual / 60.0)::numeric, 1), 0),
      'members_present', count(DISTINCT a.member_id)
    ) INTO v_engagement
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    JOIN public.members m ON m.id = a.member_id
    WHERE m.chapter = p_chapter AND e.date >= v_year_start AND a.present = true;
  EXCEPTION WHEN OTHERS THEN
    v_engagement := jsonb_build_object('attendance_events', 0, 'total_hours', 0, 'members_present', 0);
  END;

  -- Certification
  SELECT jsonb_build_object(
    'cpmai_certified', count(*) FILTER (WHERE cpmai_certified),
    'total_active', count(*)
  ) INTO v_certification
  FROM public.members
  WHERE chapter = p_chapter AND current_cycle_active;

  v_result := jsonb_build_object(
    'chapter', p_chapter,
    'members', v_members,
    'production', v_production,
    'engagement', v_engagement,
    'certification', v_certification
  );

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_chapter_selection_summary(p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_chapter text;
BEGIN
  SELECT m.id, m.chapter INTO v_caller_id, v_caller_chapter
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- V4 gate (mirrors get_chapter_dashboard): cross-chapter for view_internal_analytics OR the
  -- external aggregate auditor (view_aggregate_analytics, ADR-0111 amendment), else own chapter.
  IF public.can_by_member(v_caller_id, 'view_internal_analytics')
     OR public.can_by_member(v_caller_id, 'view_aggregate_analytics') THEN
    v_chapter := COALESCE(p_chapter, v_caller_chapter);
  ELSIF p_chapter IS NULL OR p_chapter = v_caller_chapter THEN
    v_chapter := v_caller_chapter;
  ELSE
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF v_chapter IS NULL THEN
    RETURN jsonb_build_object('error', 'No chapter specified');
  END IF;

  RETURN jsonb_build_object(
    'open', (
      SELECT jsonb_build_object(
        'cycle_code', sc.cycle_code,
        'title', sc.title,
        'close_date', sc.close_date,
        'booking_url', sc.interview_booking_url,
        'open_apps', (SELECT count(*) FROM public.selection_applications sa WHERE sa.cycle_id = sc.id)
      )
      FROM public.selection_cycles sc
      WHERE sc.contracting_chapter = v_chapter AND sc.status = 'open'
      ORDER BY sc.created_at DESC LIMIT 1
    ),
    'last', (
      SELECT jsonb_build_object('title', sc.title, 'close_date', sc.close_date)
      FROM public.selection_cycles sc
      WHERE sc.contracting_chapter = v_chapter
      ORDER BY sc.created_at DESC LIMIT 1
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.comms_metrics_latest_by_channel(p_days integer DEFAULT 14)
 RETURNS TABLE(metric_date date, channel text, audience bigint, reach bigint, engagement numeric, leads bigint, source text, updated_at timestamp with time zone, payload jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with latest as (
    select max(metric_date) as d
    from public.comms_metrics_daily
  )
  select
    c.metric_date,
    c.channel,
    c.audience,
    c.reach,
    c.engagement_rate as engagement,
    c.leads,
    c.source,
    c.updated_at,
    -- ADR-0111 amendment forward-defense: payload is an opaque ingestion-controlled jsonb; only the
    -- comms team (can_view_comms_analytics) receives it. The external aggregate auditor gets NULL.
    case when public.can_view_comms_analytics() then c.payload else null end as payload
  from public.comms_metrics_daily c
  where (public.can_view_comms_analytics()
         or public.can_by_member((select id from public.members where auth_id = auth.uid()), 'view_aggregate_analytics'))
    and c.metric_date >= coalesce((select d from latest) - greatest(p_days, 1) + 1, current_date)
  order by c.metric_date desc, c.reach desc nulls last, c.channel asc;
$function$;

CREATE OR REPLACE FUNCTION public.exec_chapter_comparison()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'access_denied'; END IF;
  -- ADR-0111 amendment: external aggregate auditor (view_aggregate_analytics) joins GP (manage_platform).
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  IF public.can_by_member(v_caller_id, 'view_aggregate_analytics')
     AND NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    -- EXTERNAL auditor path: k-anonymity small-cell bucketing (RoPA/LIA s2.3/s8). Chapters with
    -- < 5 active members collapse into one "Outros (<5 ativos)" bucket so a single-member chapter is
    -- never an individual record keyed by a real chapter code.
    WITH base AS (
      SELECT
        m.chapter,
        count(*)::bigint AS total_members,
        count(*) FILTER (WHERE m.current_cycle_active)::bigint AS active_members,
        count(*) FILTER (WHERE m.cpmai_certified)::bigint AS cpmai_certified,
        COALESCE((SELECT count(*) FROM public.board_item_assignments bia2
          JOIN public.board_items bi2 ON bi2.id = bia2.item_id
          WHERE bia2.member_id = ANY(array_agg(m.id))
          AND bi2.curation_status = 'approved'), 0)::bigint AS articles_approved,
        COALESCE((SELECT count(DISTINCT a2.event_id) FROM public.attendance a2
          WHERE a2.member_id = ANY(array_agg(m.id))
          AND a2.present = true), 0)::bigint AS attendance_events
      FROM public.members m
      WHERE m.chapter IS NOT NULL
      GROUP BY m.chapter
    ),
    shaped AS (
      SELECT chapter, total_members, active_members, cpmai_certified, articles_approved, attendance_events
      FROM base
      WHERE active_members >= 5
      UNION ALL
      SELECT 'Outros (<5 ativos)'::text, sum(total_members)::bigint, sum(active_members)::bigint,
             sum(cpmai_certified)::bigint, sum(articles_approved)::bigint, sum(attendance_events)::bigint
      FROM base
      WHERE active_members < 5
      HAVING count(*) > 0
    )
    SELECT jsonb_agg(row_to_json(s) ORDER BY s.active_members DESC) INTO v_result
    FROM shaped s;
  ELSE
    -- internal / GP path: ORIGINAL query verbatim (byte-neutral full named list).
    SELECT jsonb_agg(row_to_json(r)) INTO v_result
    FROM (
      SELECT
        m.chapter,
        count(*) AS total_members,
        count(*) FILTER (WHERE m.current_cycle_active) AS active_members,
        count(*) FILTER (WHERE m.cpmai_certified) AS cpmai_certified,
        COALESCE((SELECT count(*) FROM board_item_assignments bia2
          JOIN board_items bi2 ON bi2.id = bia2.item_id
          WHERE bia2.member_id = ANY(array_agg(m.id))
          AND bi2.curation_status = 'approved'), 0) AS articles_approved,
        COALESCE((SELECT count(DISTINCT a2.event_id) FROM attendance a2
          WHERE a2.member_id = ANY(array_agg(m.id))
          AND a2.present = true), 0) AS attendance_events
      FROM members m
      WHERE m.chapter IS NOT NULL
      GROUP BY m.chapter
      ORDER BY count(*) FILTER (WHERE m.current_cycle_active) DESC
    ) r;
  END IF;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$function$;
