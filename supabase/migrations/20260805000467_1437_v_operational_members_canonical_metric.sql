-- #1437 / #1354 / ADR-0126 — "Pesquisadores ativos" headline = the active RESEARCH TEAM (68), not the
-- polluted 87. The label is correct and unchanged; only the COUNT is narrowed to the operational tier.
--
-- Problem: get_public_platform_stats.active_members / get_homepage_stats.members / get_admin_dashboard
-- KPI counted `is_active AND current_cycle_active AND NOT pre_onboarding` = 87, folding in chapter board /
-- sponsors / external reviewers / observers who are NOT part of the research operation.
--
-- Canonical rule (ADR-0126, ratified 2026-07-20, grounded live 87→68): the research team = the operational
-- tier of the operational_role priority ladder (sync_operational_role_cache SSOT):
--   manager (GP + Co-GP collapse here) | deputy_manager | tribe_leader (leaders + comms leaders) |
--   researcher (researchers + curators + facilitators + committee/workgroup/study members collapse here).
-- Allocation to a tribe is irrelevant (role-derived). The tier already excludes pre-onboarding (0 overlap
-- live) and correctly INCLUDES interim-grant leaders (ADR-0121), so no member_is_pre_onboarding filter.
--
-- Does NOT touch v_active_members (the general Tema A active-member view = 89, correctly consumed by
-- cycle report / pilot / platform usage / sustainability). Does NOT change the operational_role ladder
-- (governança vence is deliberate: chapter directors / sponsors stay stakeholders). Does NOT change i18n.
-- The 9 synthetic #205 rows are already soft-retired; their FK purge is a separate follow-up.
--
-- security_invoker=true mirrors v_active_members: SECURITY DEFINER callers (the stats RPCs) query it in
-- definer context (full count); a direct authenticated reader gets RLS-scoped rows.
--
-- The three consumer functions below are captured VERBATIM from the live definition (pg_get_functiondef)
-- so the migration file is byte-equal to prod (GC-097 / Phase-C body-drift discipline). The 'active_members'
-- / 'members' KPI (and the get_admin_dashboard adoption_7d denominator) read v_operational_members.

-- ── canonical view: active research team (operational tier) ──────────────────
CREATE OR REPLACE VIEW public.v_operational_members
  WITH (security_invoker = true) AS
  SELECT m.id, m.organization_id, m.chapter, m.tribe_id, m.person_id, m.operational_role
  FROM public.members m
  WHERE m.is_active = true
    AND m.current_cycle_active = true
    AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader', 'researcher');

REVOKE ALL ON public.v_operational_members FROM PUBLIC, anon;
GRANT SELECT ON public.v_operational_members TO authenticated, service_role;

COMMENT ON VIEW public.v_operational_members IS
  '#1437/#1354/ADR-0126 canonical active RESEARCH TEAM = operational tier of the operational_role ladder (manager/deputy_manager/tribe_leader/researcher; GP/Co-GP/curators/comms-leaders collapse in). This IS "Pesquisadores ativos". Distinct from v_active_members (general active system user, Tema A). Reused by home/public/admin headline + campaign audience selector.';

-- ── consumer 1: public homepage stats (anon) ────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_public_platform_stats()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT json_build_object(
    'active_members', (SELECT COUNT(*) FROM public.v_operational_members),
    'total_tribes', (SELECT COUNT(*) FROM public.tribes WHERE is_active),
    'total_initiatives', (
      SELECT count(*) FROM public.initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
        AND visibility <> 'confidential'
    ),
    'total_verticals', (
      SELECT count(*) FROM public.initiatives
      WHERE kind = 'community_vertical' AND status = 'active'
        AND visibility <> 'confidential'
    ),
    'total_chapters', (public.get_chapter_metrics()->>'signed')::int,
    'total_events', (SELECT COUNT(*) FROM public.events e WHERE e.date >= '2026-01-01' AND NOT EXISTS (SELECT 1 FROM public.initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential')),
    'total_resources', (SELECT COUNT(*) FROM public.hub_resources WHERE is_active),
    'retention_rate', (public.get_member_retention_canonical() -> 'headline' ->> 'survival_pct')::numeric,
    'impact_hours', round(public.get_impact_hours_canonical())
  );
$function$;

-- ── consumer 2: homepage stats (hero strip) ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_homepage_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN jsonb_build_object(
    'members', (SELECT count(*) FROM public.v_operational_members),
    'observers', (SELECT count(*) FROM members WHERE member_status = 'observer'),
    'alumni', (SELECT count(*) FROM members WHERE member_status = 'alumni'),
    'tribes', (SELECT count(*) FROM tribes WHERE is_active),
    'initiatives', (
      SELECT count(*) FROM initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
        AND visibility <> 'confidential'
    ),
    'total_initiatives', (
      SELECT count(*) FROM initiatives WHERE status = 'active'
        AND visibility <> 'confidential'
    ),
    'active_leaders', (
      SELECT count(DISTINCT person_id) FROM auth_engagements
      WHERE status = 'active' AND role IN ('leader', 'co_leader', 'co_gp')
    ),
    'chapters', (public.get_chapter_metrics()->>'signed')::int,
    'impact_hours', round(public.get_impact_hours_canonical()),
    'max_researchers_per_tribe', public.tribe_capacity_limit()
  );
END;
$function$;

-- ── consumer 3: admin dashboard KPI (manage_platform) ────────────────────────
CREATE OR REPLACE FUNCTION public.get_admin_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb; v_cycle_start date; v_current_cycle int;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  SELECT cycle_start,
    CASE WHEN cycle_code ~ '^\w+_\d+$' THEN substring(cycle_code from '\d+')::int ELSE sort_order END
  INTO v_cycle_start, v_current_cycle
  FROM public.cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-01-01'; END IF;
  IF v_current_cycle IS NULL THEN v_current_cycle := 3; END IF;

  SELECT jsonb_build_object(
    'generated_at', now(),
    'kpis', jsonb_build_object(
      'active_members', (SELECT count(*) FROM public.v_operational_members),
      'adoption_7d', (SELECT ROUND(count(*) FILTER (WHERE m.last_seen_at > now() - interval '7 days')::numeric / NULLIF(count(*), 0) * 100, 1) FROM public.members m WHERE m.id IN (SELECT id FROM public.v_operational_members)),
      'deliverables_completed', (SELECT count(*) FROM public.board_items WHERE status = 'done' AND NOT public.is_confidential_board(board_id)),
      'deliverables_total', (SELECT count(*) FROM public.board_items WHERE status != 'archived' AND NOT public.is_confidential_board(board_id)),
      'impact_hours', (SELECT COALESCE(public.get_impact_hours_excluding_excused(), 0)),
      'cpmai_current', (SELECT count(DISTINCT member_id) FROM public.gamification_points WHERE category = 'cert_cpmai' AND created_at >= v_cycle_start),
      'cpmai_target', (SELECT target_value FROM public.annual_kpi_targets WHERE kpi_key = 'cpmai_certified' AND cycle = v_current_cycle LIMIT 1),
      'chapters_current', (public.get_chapter_metrics()->>'signed')::int,
      'chapters_in_negotiation', (public.get_chapter_metrics()->>'in_negotiation')::int,
      'chapters_engaged', (public.get_chapter_metrics()->>'engaged')::int,
      'chapters_target', (SELECT target_value FROM public.annual_kpi_targets WHERE kpi_key = 'chapters_participating' AND cycle = v_current_cycle LIMIT 1)
    ),
    'alerts', (SELECT COALESCE(jsonb_agg(alert), '[]'::jsonb) FROM (
      SELECT jsonb_build_object(
        'severity', 'high',
        'message', count(*) || ' pesquisadores sem tribo',
        'action_label', 'Ir para Tribos',
        'action_href', '/admin/tribes'
      ) AS alert
      FROM public.members m
      WHERE m.is_active = true
        AND public.get_member_tribe(m.id) IS NULL
        AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'manager', 'deputy_manager', 'observer')
      HAVING count(*) > 0

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'medium',
        'message', count(*) || ' stakeholders sem conta',
        'action_label', 'Ver Membros',
        'action_href', '/admin/members'
      )
      FROM public.members
      WHERE is_active = true AND auth_id IS NULL AND operational_role IN ('sponsor', 'chapter_liaison')
      HAVING count(*) > 0

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'medium',
        'message', count(*) || ' membros em risco de dropout',
        'action_label', 'Ver lista',
        'action_href', '/admin/members'
      )
      FROM public.members m
      WHERE m.is_active = true AND m.current_cycle_active
        AND public.get_member_tribe(m.id) IS NOT NULL
        AND m.id NOT IN (
          SELECT a.member_id FROM public.attendance a
          JOIN public.events e ON e.id = a.event_id
          WHERE e.date > now() - interval '60 days'
            AND a.present IS TRUE
        )
      HAVING count(*) > 0

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'high',
        'message', t.name || ' sem reuniao ha ' || (current_date - max(e.date)) || ' dias',
        'action_label', 'Ver Tribo',
        'action_href', '/tribe/' || t.id
      )
      FROM public.tribes t
      LEFT JOIN public.initiatives i ON i.legacy_tribe_id = t.id
      LEFT JOIN public.events e ON e.initiative_id = i.id AND e.type = 'tribo' AND e.date <= current_date
      WHERE t.is_active = true
      GROUP BY t.id, t.name
      HAVING max(e.date) IS NOT NULL AND current_date - max(e.date) > 14

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'medium',
        'message', count(*) || ' membros detractors (3+ faltas consecutivas)',
        'action_label', 'Quadro de Presenca',
        'action_href', '/attendance?tab=grid'
      )
      FROM public.members m
      WHERE m.is_active AND m.current_cycle_active
        AND public.get_member_tribe(m.id) IS NOT NULL
        AND m.id IN (
          SELECT cand.id
          FROM public.members cand
          WHERE cand.is_active AND cand.current_cycle_active
            AND (
              SELECT count(*) FILTER (WHERE NOT ranked.was_present)
              FROM (
                SELECT (att.present IS TRUE) AS was_present,
                       ROW_NUMBER() OVER (ORDER BY el.event_date DESC, el.event_id DESC) AS rn
                FROM public._attendance_eligible_events(cand.id, NULL) el
                LEFT JOIN public.attendance att ON att.event_id = el.event_id AND att.member_id = cand.id
                WHERE att.excused IS NOT TRUE
              ) ranked
              WHERE ranked.rn <= 3
            ) >= 3
        )
      HAVING count(*) > 0
    ) sub),
    'recent_activity', (SELECT COALESCE(jsonb_agg(r.activity ORDER BY r.ts DESC), '[]'::jsonb) FROM (
      SELECT * FROM (SELECT jsonb_build_object('type', 'audit', 'message', actor.name || ' ' || al.action || ' em ' || COALESCE(target.name, '?'), 'details', al.changes, 'timestamp', al.created_at) as activity, al.created_at as ts FROM public.admin_audit_log al LEFT JOIN public.members actor ON actor.id = al.actor_id LEFT JOIN public.members target ON target.id = al.target_id WHERE al.created_at > now() - interval '7 days' ORDER BY al.created_at DESC LIMIT 10) a1
      UNION ALL SELECT * FROM (SELECT jsonb_build_object('type', 'campaign', 'message', 'Campanha "' || ct.name || '" enviada', 'timestamp', cs.created_at), cs.created_at FROM public.campaign_sends cs JOIN public.campaign_templates ct ON ct.id = cs.template_id WHERE cs.created_at > now() - interval '7 days' ORDER BY cs.created_at DESC LIMIT 5) a2
      UNION ALL SELECT * FROM (SELECT jsonb_build_object('type', 'publication', 'message', m.name || ' submeteu "' || ps.title || '"', 'timestamp', ps.submission_date), ps.submission_date FROM public.publication_submissions ps JOIN public.publication_submission_authors psa ON psa.submission_id = ps.id JOIN public.members m ON m.id = psa.member_id WHERE ps.submission_date > now() - interval '30 days' ORDER BY ps.submission_date DESC LIMIT 5) a3
    ) r LIMIT 15)
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
