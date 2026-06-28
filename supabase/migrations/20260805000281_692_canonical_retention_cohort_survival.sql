-- #692 — Canonical retention metric = COHORT-SURVIVAL (members of cycle N present in cycle N+1).
--
-- Problem: "retention" showed THREE divergent values across surfaces (issue #692):
--   * home get_public_platform_stats.retention_rate = 68.1 (snapshot: current_cycle_active / ever-active)
--   * get_annual_kpis members_retained (auto_query retention_pct) = 98.7 (degenerate: is_active∧current/is_active)
--   * exec_cycle_report.members.retention_rate = 53 (actually % of active members with >1 cycle = RECURRING)
-- None is cohort-survival. PM decision (locked): canonical retention = cohort-survival.
--
-- Live grounding (2026-06-28) from member_cycle_history (distinct member_id per cycle_code):
--   pilot(8)->c1: 7 survived = 87.5% | c1(22)->c2: 18 = 81.8% | c2(31)->c3: 30 = 96.8% (last closed).
--   cycle_4 not yet in member_cycle_history -> last closed transition = C2->C3 = 96.8% (the canonical headline).
--   The function is DATA-DRIVEN (no hardcoded cycle codes): when cycle_4 is backfilled, the headline auto-advances
--   to C3->C4.
--
-- This migration:
--   1. get_member_retention_canonical() — the SSOT (per-transition survival + last-closed headline).
--   2. Repoints the 4 surfaces to the SSOT: home + annual KPI (replace the wrong value with 96.8); exec_cycle_report
--      (RELABEL the 53 as recurring_members_pct + add cohort-survival retention); get_adoption_dashboard
--      (parametrize the already-correct retention_c2_c3 to the SSOT + add a dynamic basis label).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Canonical SSOT — cohort-survival retention (data-driven, no hardcoded cycles)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_member_retention_canonical()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH cyc AS (
    SELECT cycle_code, min(cycle_start) AS cstart, min(cycle_label) AS clabel
    FROM public.member_cycle_history
    GROUP BY cycle_code
  ),
  ordered AS (
    SELECT cycle_code, clabel, cstart, row_number() OVER (ORDER BY cstart) AS rn FROM cyc
  ),
  pairs AS (
    SELECT a.cycle_code AS from_code, a.clabel AS from_label,
           b.cycle_code AS to_code, b.clabel AS to_label, a.rn AS rn
    FROM ordered a JOIN ordered b ON b.rn = a.rn + 1
  ),
  computed AS (
    SELECT p.rn, p.from_code, p.from_label, p.to_code, p.to_label,
      (SELECT count(DISTINCT member_id) FROM public.member_cycle_history WHERE cycle_code = p.from_code) AS cohort_n,
      (SELECT count(DISTINCT mh1.member_id) FROM public.member_cycle_history mh1
         WHERE mh1.cycle_code = p.from_code
           AND EXISTS (SELECT 1 FROM public.member_cycle_history mh2
                       WHERE mh2.member_id = mh1.member_id AND mh2.cycle_code = p.to_code)) AS survived
    FROM pairs p
  ),
  withpct AS (
    SELECT *, ROUND(survived::numeric * 100 / NULLIF(cohort_n, 0), 1) AS survival_pct FROM computed
  )
  SELECT jsonb_build_object(
    'metric', 'cohort_survival',
    'definition', 'Share of cycle N members (distinct member_id in member_cycle_history) who return in cycle N+1. Headline = last closed transition.',
    'transitions', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'from_code', from_code, 'from_label', from_label, 'to_code', to_code, 'to_label', to_label,
        'cohort_n', cohort_n, 'survived', survived, 'survival_pct', survival_pct) ORDER BY rn) FROM withpct), '[]'::jsonb),
    'headline', (SELECT jsonb_build_object(
        'from_code', from_code, 'from_label', from_label, 'to_code', to_code, 'to_label', to_label,
        'cohort_n', cohort_n, 'survived', survived, 'survival_pct', survival_pct,
        'basis', replace(from_code, 'cycle_', 'C') || '->' || replace(to_code, 'cycle_', 'C')
      ) FROM withpct ORDER BY rn DESC LIMIT 1),
    'computed_at', now()
  );
$function$;

REVOKE ALL ON FUNCTION public.get_member_retention_canonical() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_member_retention_canonical() TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2a. HOME (public) — replace the snapshot retention_rate with the canonical cohort-survival headline
-- ─────────────────────────────────────────────────────────────────────────────
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
    -- #692: canonical retention = cohort-survival (members of cycle N present in N+1), last closed transition.
    -- Replaces the old snapshot ratio (current_cycle_active / ever-active) that read 68.1.
    'retention_rate', (public.get_member_retention_canonical() -> 'headline' ->> 'survival_pct')::numeric,
    -- R2 (Ciclo 4): canonical impact-hours, shared with the hero headline (single denominator).
    'impact_hours', round(public.get_impact_hours_canonical())
  );
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2b. ANNUAL KPI — members_retained (auto_query retention_pct) now = canonical cohort-survival
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_annual_kpis(p_cycle integer DEFAULT 4, p_year integer DEFAULT 2026)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_auto_values jsonb;
  v_kpis jsonb;
  v_cycle_start date := '2025-12-01';
  v_cycle_end date := '2026-06-30';
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  v_auto_values := jsonb_build_object(
    'pilots_active_or_completed', (SELECT count(*) FROM public.pilots WHERE status IN ('active', 'completed')),
    'publications_submitted_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name = 'publicacao' AND bi.status IN ('done', 'review')),
    'articles_academic_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name = 'artigo_academico' AND bi.status IN ('done', 'review')),
    'frameworks_delivered_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name IN ('framework', 'ferramenta') AND bi.status IN ('done', 'review')),
    'webinars_realized_count', public.get_webinars_count(v_cycle_start, LEAST(v_cycle_end, CURRENT_DATE), 'realized'),
    'attendance_general_avg_pct', public.calc_attendance_pct(),
    -- #692: members_retained now reads the canonical cohort-survival headline (was a degenerate
    -- is_active∧current/is_active ratio that read ~98.7).
    'retention_pct', (public.get_member_retention_canonical() -> 'headline' ->> 'survival_pct')::numeric,
    'events_total_count', (SELECT count(*) FROM public.events e WHERE e.date BETWEEN v_cycle_start AND LEAST(v_cycle_end, CURRENT_DATE) AND NOT EXISTS (SELECT 1 FROM public.event_tag_assignments eta JOIN public.tags t ON t.id = eta.tag_id WHERE eta.event_id = e.id AND t.name = 'interview')),
    'trail_completion_pct', public.calc_trail_completion_pct(),
    'cpmai_certified_count', public.get_cpmai_certified_goal_count(),
    'active_members_count', (SELECT count(*) FROM public.members WHERE is_active = true AND current_cycle_active = true),
    'infra_cost_current', (SELECT COALESCE(SUM(ce.amount_brl), 0) FROM public.cost_entries ce JOIN public.cost_categories cc ON cc.id = ce.category_id WHERE cc.name = 'infrastructure' AND ce.date >= date_trunc('month', now())::date AND ce.date < (date_trunc('month', now()) + interval '1 month')::date)
  );

  SELECT jsonb_agg(
    jsonb_build_object(
      'id', k.id, 'kpi_key', k.kpi_key, 'label_pt', k.kpi_label_pt, 'label_en', k.kpi_label_en,
      'category', k.category, 'target', k.target_value, 'baseline', k.baseline_value,
      'current', CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END,
      'unit', k.target_unit, 'icon', k.icon,
      'progress_pct', CASE
        WHEN k.target_value > 0 THEN ROUND(COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) / k.target_value * 100, 1)
        WHEN k.target_value = 0 THEN 100
        ELSE 0
      END,
      'health', CASE
        WHEN k.target_value = 0 AND COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) = 0 THEN 'achieved'
        WHEN k.target_value = 0 THEN 'at_risk'
        WHEN COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) >= k.target_value THEN 'achieved'
        WHEN COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) >= k.target_value * 0.7 THEN 'on_track'
        WHEN COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) >= k.target_value * 0.4 THEN 'at_risk'
        ELSE 'behind'
      END,
      'notes', k.notes,
      'auto_query', k.auto_query
    ) ORDER BY k.display_order
  ) INTO v_kpis
  FROM public.annual_kpi_targets k
  WHERE k.cycle = p_cycle AND k.year = p_year;

  v_result := jsonb_build_object(
    'cycle', p_cycle, 'year', p_year, 'generated_at', now(),
    'kpis', COALESCE(v_kpis, '[]'::jsonb),
    'summary', jsonb_build_object(
      'total', jsonb_array_length(COALESCE(v_kpis, '[]'::jsonb)),
      'achieved', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'achieved'),
      'on_track', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'on_track'),
      'at_risk', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'at_risk'),
      'behind', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'behind')
    )
  );
  RETURN v_result;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2c. CYCLE REPORT — relabel the 53 as recurring_members_pct (it is % of active members with >1
--     cycle, NOT retention) + add the canonical cohort-survival retention alongside.
-- ─────────────────────────────────────────────────────────────────────────────
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
    -- #692: this is RECURRING members (active members who have been in >1 cycle), NOT retention.
    -- Renamed from retention_rate; the canonical cohort-survival retention ships alongside.
    'recurring_members_pct', ROUND(COALESCE((SELECT COUNT(*) FILTER (WHERE COALESCE(array_length(cycles, 1), 0) > 1)::numeric * 100 / NULLIF(COUNT(*), 0) FROM public.members WHERE current_cycle_active = true AND cycles IS NOT NULL), 0)),
    'retention_cohort_survival_pct', (public.get_member_retention_canonical() -> 'headline' ->> 'survival_pct')::numeric,
    'retention_basis', (public.get_member_retention_canonical() -> 'headline' ->> 'basis'),
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
    'webinars_completed', public.get_webinars_count(NULL, NULL, 'realized'),
    'webinars_planned', public.get_webinars_count(NULL, NULL, 'planned')
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 2d. ADOPTION — parametrize the (already-correct) retention_c2_c3 to the canonical SSOT so it
--     auto-advances when cycle_4 is backfilled; add a dynamic basis label.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_adoption_dashboard()
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
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  -- ADR-0042: V4 catalog (manage_platform writes; view_chapter_dashboards reads)
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  WITH tier_stats AS (
    SELECT operational_role, count(*)::integer as total,
      count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::integer as seen_7d,
      count(*) FILTER (WHERE last_seen_at > now() - interval '30 days')::integer as seen_30d,
      count(*) FILTER (WHERE last_seen_at IS NULL)::integer as never,
      ROUND(AVG(total_sessions)::numeric, 1) as avg_sessions
    FROM members WHERE is_active = true GROUP BY operational_role
  ),
  tribe_stats AS (
    SELECT t.id as tribe_id, t.name as tribe_name,
      count(m.id)::integer as total,
      count(m.id) FILTER (WHERE m.last_seen_at > now() - interval '7 days')::integer as seen_7d,
      count(m.id) FILTER (WHERE m.last_seen_at > now() - interval '30 days')::integer as seen_30d,
      count(m.id) FILTER (WHERE m.last_seen_at IS NULL)::integer as never,
      ROUND(AVG(m.total_sessions)::numeric, 1) as avg_sessions
    FROM tribes t
    LEFT JOIN members m ON public.get_member_tribe(m.id) = t.id AND m.is_active = true
    WHERE t.is_active = true GROUP BY t.id, t.name
  ),
  daily AS (
    SELECT session_date, count(DISTINCT member_id)::integer as cnt, sum(pages_visited)::integer as pvs
    FROM member_activity_sessions WHERE session_date > CURRENT_DATE - 30 GROUP BY session_date
  )
  SELECT jsonb_build_object(
    'generated_at', now(),
    'summary', jsonb_build_object(
      'total_active', (SELECT count(*) FROM members WHERE is_active = true AND current_cycle_active = true),
      'total_registered', (SELECT count(*) FROM members),
      'ever_logged_in', (SELECT count(*) FROM members WHERE is_active = true AND auth_id IS NOT NULL),
      'seen_last_7d', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at > now() - interval '7 days'),
      'seen_last_30d', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at > now() - interval '30 days'),
      'never_seen', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at IS NULL),
      'adoption_pct_7d', (SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::numeric / NULLIF(count(*) FILTER (WHERE is_active = true), 0) * 100, 1) FROM members),
      'adoption_pct_30d', (SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '30 days')::numeric / NULLIF(count(*) FILTER (WHERE is_active = true), 0) * 100, 1) FROM members),
      'avg_sessions_per_member', (SELECT ROUND(AVG(total_sessions)::numeric, 1) FROM members WHERE is_active = true AND total_sessions > 0)
    ),
    'lifecycle', jsonb_build_object(
      'total_ever', (SELECT count(*) FROM members),
      'active_c3', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
      'alumni', (SELECT count(*) FROM members WHERE member_status = 'alumni' OR (NOT is_active AND operational_role IN ('alumni','observer','guest'))),
      'observers_active', (SELECT count(*) FROM members WHERE is_active AND operational_role = 'observer'),
      'founders_total', (SELECT count(*) FROM members WHERE 'founder' = ANY(designations)),
      'founders_active', (SELECT count(*) FROM members WHERE 'founder' = ANY(designations) AND is_active AND current_cycle_active),
      'founders_with_auth', (SELECT count(*) FROM members WHERE 'founder' = ANY(designations) AND auth_id IS NOT NULL),
      'sponsors_total', (SELECT count(*) FROM members WHERE operational_role = 'sponsor' AND is_active),
      'sponsors_with_auth', (SELECT count(*) FROM members WHERE operational_role = 'sponsor' AND is_active AND auth_id IS NOT NULL),
      'liaisons_total', (SELECT count(*) FROM members WHERE operational_role = 'chapter_liaison' AND is_active),
      'liaisons_with_auth', (SELECT count(*) FROM members WHERE operational_role = 'chapter_liaison' AND is_active AND auth_id IS NOT NULL),
      -- #692: canonical cohort-survival (last closed transition), SSOT-driven (was hardcoded cycle_2/cycle_3).
      'retention_c2_c3', (public.get_member_retention_canonical() -> 'headline' ->> 'survival_pct')::numeric,
      'retention_basis', (public.get_member_retention_canonical() -> 'headline' ->> 'basis')
    ),
    'by_tier', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'tier', ts.operational_role, 'total', ts.total, 'seen_7d', ts.seen_7d,
      'seen_30d', ts.seen_30d, 'never', ts.never, 'avg_sessions', ts.avg_sessions
    )), '[]'::jsonb) FROM tier_stats ts),
    'by_tribe', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'tribe_id', ts.tribe_id, 'tribe_name', ts.tribe_name, 'total', ts.total,
      'seen_7d', ts.seen_7d, 'seen_30d', ts.seen_30d, 'never', ts.never,
      'avg_sessions', ts.avg_sessions
    ) ORDER BY ts.tribe_id), '[]'::jsonb) FROM tribe_stats ts),
    'daily_activity', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'date', d.dt::text, 'unique_members', COALESCE(dy.cnt, 0),
      'total_pageviews', COALESCE(dy.pvs, 0)
    ) ORDER BY d.dt), '[]'::jsonb)
    FROM generate_series(CURRENT_DATE - 30, CURRENT_DATE, '1 day') d(dt)
    LEFT JOIN daily dy ON dy.session_date = d.dt),
    'members', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', m.id, 'name', m.name, 'tier', m.operational_role,
      'designations', m.designations,
      'tribe_id', public.get_member_tribe(m.id), 'tribe_name', t.name,
      'has_auth', m.auth_id IS NOT NULL, 'last_seen', m.last_seen_at,
      'total_sessions', m.total_sessions, 'last_pages', m.last_active_pages,
      'is_founder', 'founder' = ANY(m.designations),
      'status', CASE
        WHEN m.last_seen_at IS NULL THEN 'never'
        WHEN m.last_seen_at > now() - interval '7 days' THEN 'active'
        WHEN m.last_seen_at > now() - interval '30 days' THEN 'inactive'
        ELSE 'dormant' END
    ) ORDER BY m.last_seen_at DESC NULLS LAST), '[]'::jsonb)
    FROM members m LEFT JOIN tribes t ON t.id = public.get_member_tribe(m.id)
    WHERE m.is_active = true),
    'mcp_usage', (SELECT get_mcp_adoption_stats()),
    'auth_providers', (SELECT get_auth_provider_stats()),
    'designation_counts', (
      SELECT COALESCE(jsonb_object_agg(d, cnt), '{}'::jsonb) FROM (
        SELECT unnest(designations) as d, count(*) as cnt
        FROM members WHERE is_active = true AND designations != '{}'
        GROUP BY d
      ) x
    )
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
