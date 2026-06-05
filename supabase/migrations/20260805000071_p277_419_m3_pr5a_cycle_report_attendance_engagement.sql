-- p277 / #419 (ADR-0100) metric 3 — PR5a: exec_cycle_report attendance DECOUPLED to engagement+reliability.
--
-- SPEC: docs/specs/SPEC_419_M3_ATTENDANCE_TWO_METRIC.md §5 surface 7 + §7 PR5 (reports).
-- WHAT: the cycle report's per-tribe attendance array consumed get_attendance_summary(...).combined_pct,
--       where combined_pct = 0.4*geral_pct + 0.6*tribe_pct — the hidden product weighting D9 ratified to
--       DROP. This decouples exec_cycle_report from get_attendance_summary entirely (PR7 still converges
--       get_attendance_summary on its own). attendance now reports BOTH canonical indicators:
--         - ENGAGEMENT / Participacao (headline)   = get_attendance_engagement_summary (present/eligible)
--         - RELIABILITY / Confiabilidade (diagnostic, WITH raw present/absent/excused counts; admin
--           surface gated manage_platform|view_chapter_dashboards => D10-compliant)
--       Shape change: r.attendance was a flat array; now an object {engagement, reliability, by_tribe[]}.
--       Frontend (src/pages/admin/cycle-report.astro) updated in the same PR.
-- WHY:  D9 (drop weighting) + the antes 0.4/0.6 combined_pct was a hidden product call; engagement is the
--       honest endpoint. The hardcoded v_start/v_end literals on the NON-attendance sections (kpis/hours)
--       are a SEPARATE pre-existing bug (window 2026-01-01..2026-06-30 vs cycle_3 2026-03-01..open) left
--       for a #420 follow-up — engagement/reliability summaries use cycles.is_current internally, so the
--       attendance numbers are now cycle-correct regardless.
-- ROLLBACK: re-apply the prior bodies (engagement summary sans at_risk_count; exec_cycle_report with the
--           get_attendance_summary combined_pct array). No data writes.

-- ── 1. ENGAGEMENT aggregate gains at_risk_count (ADDITIVE; same 3-arg signature) ──────────────────────
-- at_risk_count = cohort members with a non-null engagement rate strictly below 0.50 (genuine no-show
-- pattern). rate IS NULL (zero eligible events) is "no data", excluded. Consumed by exec_cycle_report
-- per-tribe + reusable by any surface (PR10 gate forbids inline rate re-impl). PR2-PR4 consumers read
-- avg_rate and are unaffected by the new key.
CREATE OR REPLACE FUNCTION public.get_attendance_engagement_summary(p_scope text DEFAULT 'global', p_scope_id integer DEFAULT NULL, p_cycle_start date DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH cohort AS (
    SELECT m.id
    FROM public.members m
    WHERE m.is_active = true AND m.current_cycle_active = true
      AND m.operational_role IN ('researcher', 'tribe_leader', 'manager')
      AND (
        p_scope = 'global'
        OR (p_scope = 'tribe' AND public.get_member_tribe(m.id) = p_scope_id)
      )
  ),
  rates AS (
    SELECT c.id, public.get_attendance_engagement_rate(c.id, p_cycle_start) AS rate
    FROM cohort c
  ),
  totals AS (
    SELECT
      count(*) FILTER (WHERE att.present = true)        AS present_total,
      count(*) FILTER (WHERE att.excused IS NOT TRUE)   AS expected_total,
      count(*) FILTER (WHERE att.excused = true)        AS excused_total
    FROM cohort c
    CROSS JOIN LATERAL public._attendance_eligible_events(c.id, p_cycle_start) el
    LEFT JOIN public.attendance att ON att.member_id = c.id AND att.event_id = el.event_id
  )
  SELECT jsonb_build_object(
    'scope', p_scope,
    'scope_id', p_scope_id,
    'cohort_n', (SELECT count(*) FROM rates WHERE rate IS NOT NULL),
    'avg_rate', (SELECT ROUND(AVG(rate), 4) FROM rates WHERE rate IS NOT NULL),
    'at_risk_count', (SELECT count(*) FROM rates WHERE rate IS NOT NULL AND rate < 0.50),
    'present_total', (SELECT present_total FROM totals),
    'expected_total', (SELECT expected_total FROM totals),
    'excused_total', (SELECT excused_total FROM totals),
    'coverage_flag', CASE WHEN (SELECT count(*) FROM rates WHERE rate IS NOT NULL) = 0 THEN 'no_data' ELSE 'ok' END
  );
$function$;

REVOKE ALL ON FUNCTION public.get_attendance_engagement_summary(text, integer, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_attendance_engagement_summary(text, integer, date) TO service_role;

-- ── 2. exec_cycle_report — attendance section decoupled to engagement+reliability ─────────────────────
CREATE OR REPLACE FUNCTION public.exec_cycle_report(p_cycle_code text DEFAULT 'cycle3-2026'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb; v_kpis jsonb; v_members jsonb; v_tribes jsonb;
  v_production jsonb; v_engagement jsonb; v_curation jsonb; v_cycle jsonb; v_attendance jsonb; v_att_by_tribe jsonb;
  v_total_members int; v_active_members int;
  v_start date := '2026-01-01';
  v_end date := '2026-06-30';
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  -- ADR-0042: V4 catalog (manage_platform writes; view_chapter_dashboards reads)
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  SELECT jsonb_build_object(
    'code', COALESCE(c.cycle_code, p_cycle_code),
    'name', COALESCE(c.cycle_label, 'Ciclo 3 — 2026/1'),
    'start_date', c.cycle_start, 'end_date', c.cycle_end
  ) INTO v_cycle FROM public.cycles c WHERE c.cycle_code = p_cycle_code OR c.is_current = true LIMIT 1;
  IF v_cycle IS NULL THEN v_cycle := jsonb_build_object('code', p_cycle_code, 'name', 'Ciclo 3', 'start_date', v_start, 'end_date', v_end); END IF;

  v_kpis := public.get_kpi_dashboard(v_start, v_end);

  SELECT COUNT(*) INTO v_total_members FROM public.members;
  SELECT COUNT(*) INTO v_active_members FROM public.members WHERE current_cycle_active = true;

  SELECT jsonb_build_object(
    'total', v_total_members, 'active', v_active_members,
    'by_chapter', COALESCE((SELECT jsonb_agg(jsonb_build_object('chapter', chapter, 'count', cnt) ORDER BY cnt DESC) FROM (SELECT chapter, count(*) AS cnt FROM public.members WHERE current_cycle_active = true AND chapter IS NOT NULL GROUP BY chapter) sub), '[]'::jsonb),
    'by_role', COALESCE((SELECT jsonb_agg(jsonb_build_object('role', operational_role, 'count', cnt) ORDER BY cnt DESC) FROM (SELECT COALESCE(operational_role, 'none') AS operational_role, count(*) AS cnt FROM public.members WHERE current_cycle_active = true GROUP BY operational_role) sub), '[]'::jsonb),
    'retention_rate', ROUND(COALESCE((SELECT COUNT(*) FILTER (WHERE COALESCE(array_length(cycles, 1), 0) > 1)::numeric * 100 / NULLIF(COUNT(*), 0) FROM public.members WHERE current_cycle_active = true AND cycles IS NOT NULL), 0)),
    'new_this_cycle', (SELECT COUNT(*) FROM public.members WHERE current_cycle_active = true AND (cycles IS NULL OR COALESCE(array_length(cycles, 1), 0) <= 1))
  ) INTO v_members;

  SELECT COALESCE(jsonb_agg(tribe_data ORDER BY tribe_data->>'name'), '[]'::jsonb) INTO v_tribes
  FROM (SELECT jsonb_build_object('id', t.id, 'name', t.name,
    'leader', COALESCE((SELECT m.name FROM public.members m WHERE m.tribe_id = t.id AND m.operational_role = 'tribe_leader' LIMIT 1), '—'),
    'member_count', (SELECT COUNT(*) FROM public.members m WHERE m.tribe_id = t.id AND m.current_cycle_active = true),
    'board_items_total', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived'), 0),
    'board_items_completed', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status = 'done'), 0),
    'completion_pct', COALESCE((SELECT ROUND(COUNT(*) FILTER (WHERE bi.status = 'done')::numeric * 100 / NULLIF(COUNT(*), 0)) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived'), 0),
    'articles_produced', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status IN ('done', 'published') AND (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')), 0)
  ) AS tribe_data FROM public.tribes t WHERE t.is_active = true) sub;

  SELECT jsonb_build_object(
    'articles_submitted', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')), 0),
    'articles_published', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%') AND bi.status IN ('done', 'published')), 0),
    'articles_in_review', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%') AND bi.status IN ('review', 'in_progress')), 0),
    'webinars_completed', (SELECT COUNT(*) FROM public.events WHERE type = 'webinar' AND date <= now()),
    'webinars_planned', (SELECT COUNT(*) FROM public.events WHERE type = 'webinar' AND date > now())
  ) INTO v_production;

  SELECT jsonb_build_object(
    'total_events', (SELECT COUNT(*) FROM public.events WHERE date BETWEEN v_start AND v_end),
    'total_attendance_hours', COALESCE((SELECT round(sum(COALESCE(e.duration_actual, e.duration_minutes, 60)::numeric * (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present)) / 60) FROM events e WHERE e.date BETWEEN v_start AND v_end), 0),
    'avg_attendance_per_event', COALESCE((SELECT ROUND(AVG(ac)) FROM (SELECT COUNT(*) AS ac FROM public.attendance a JOIN events e ON e.id = a.event_id WHERE a.present = true AND e.date BETWEEN v_start AND v_end GROUP BY a.event_id) sub), 0),
    'total_attendance_records', (SELECT COUNT(*) FROM public.attendance WHERE present = true),
    'certification_completion_rate', ROUND(COALESCE((SELECT COUNT(*) FILTER (WHERE cpmai_certified = true)::numeric * 100 / NULLIF(COUNT(*), 0) FROM public.members WHERE current_cycle_active = true), 0))
  ) INTO v_engagement;

  SELECT jsonb_build_object(
    'items_submitted', COALESCE((SELECT COUNT(*) FROM public.curation_review_log), 0),
    'items_approved', COALESCE((SELECT COUNT(*) FROM public.curation_review_log WHERE decision = 'approved'), 0),
    'items_in_review', COALESCE((SELECT COUNT(*) FROM public.board_items WHERE status = 'review'), 0),
    'avg_review_days', COALESCE((SELECT ROUND(AVG(EXTRACT(EPOCH FROM (completed_at - created_at)) / 86400)::numeric, 1) FROM public.curation_review_log), 0),
    'sla_compliance_rate', COALESCE((SELECT ROUND(COUNT(*) FILTER (WHERE completed_at <= due_date)::numeric * 100 / NULLIF(COUNT(*) FILTER (WHERE due_date IS NOT NULL), 0)) FROM public.curation_review_log), 0)
  ) INTO v_curation;

  -- p277 #419 m3 PR5a: attendance DECOUPLED from get_attendance_summary (D9 — drop the hidden 0.4/0.6
  -- combined_pct weighting). Per-tribe headline = ENGAGEMENT (present/eligible, cycles.is_current window);
  -- the RELIABILITY diagnostic ships alongside WITH raw present/absent/excused counts. at_risk_count now
  -- counts engagement < 0.50 (genuine no-show), not the old combined_pct band.
  SELECT COALESCE(jsonb_agg(att_row ORDER BY att_row->>'tribe_name'), '[]'::jsonb) INTO v_att_by_tribe
  FROM (SELECT jsonb_build_object('tribe_id', t.id, 'tribe_name', t.name,
    'members_count', (SELECT count(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active AND m.operational_role NOT IN ('sponsor','chapter_liaison','guest','none')),
    'engagement_pct', ROUND(COALESCE((eng.j ->> 'avg_rate')::numeric, 0) * 100, 1),
    'reliability_pct', ROUND(COALESCE((rel.j ->> 'avg_rate')::numeric, 0) * 100, 1),
    'present_total', COALESCE((rel.j ->> 'present_total')::int, 0),
    'absent_total', COALESCE((rel.j ->> 'absent_total')::int, 0),
    'excused_total', COALESCE((rel.j ->> 'excused_total')::int, 0),
    'at_risk_count', COALESCE((eng.j ->> 'at_risk_count')::int, 0)
  ) AS att_row
  FROM tribes t
  CROSS JOIN LATERAL (SELECT public.get_attendance_engagement_summary('tribe', t.id) AS j) eng
  CROSS JOIN LATERAL (SELECT public.get_attendance_reliability_summary('tribe', t.id) AS j) rel
  WHERE t.is_active = true) sub;

  v_attendance := jsonb_build_object(
    'engagement', public.get_attendance_engagement_summary('global'),
    'reliability', public.get_attendance_reliability_summary('global'),
    'by_tribe', v_att_by_tribe
  );

  v_result := jsonb_build_object('cycle', v_cycle, 'kpis', v_kpis, 'members', v_members, 'tribes', v_tribes, 'production', v_production, 'engagement', v_engagement, 'curation', v_curation, 'attendance', v_attendance);
  RETURN v_result;
END; $function$;

NOTIFY pgrst, 'reload schema';
