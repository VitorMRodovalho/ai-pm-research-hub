-- =====================================================================================
-- #625 (Camada 1 / sweep de coorte) — KPI active_members + adoption_7d do get_admin_dashboard
-- deixam de contar a coorte pré-onboarding.
--
-- Bug (aterrado 2026-06-12): active_members = count(*) FROM members WHERE is_active AND
--   current_cycle_active — CRU. Inclui os 25 membros pré-onboarding (active mas com TODOS os
--   engagements ativos pendentes do termo). Mesma classe de denominador do #419/ADR-0100 (G6) e a
--   irmã admin/MCP das correções já feitas na homepage (#629, mig 143) e na trilha (#637, mig 145).
--   adoption_7d herda o mesmo denominador → também contaminado. O KPI alimenta o tool MCP
--   get_admin_dashboard (supabase/functions/nucleo-mcp/index.ts).
--
-- Fix: AND NOT public.member_is_pre_onboarding(person_id, member_status) — helper canônico C0
--   (mig 20260805000143) — nas DUAS linhas (numerador active_members + denominador adoption_7d),
--   p/ numerador e % ficarem consistentes. ⚠️ o helper recebe person_id (members é bridge p/
--   persons), não id.
--
-- Antes→depois (live 2026-06-12, pré-apply): active_members 72 → 47 (Δ25) · adoption_7d 55.6% → 51.1%.
--
-- Signature inalterada (no args, RETURNS jsonb) → reload PostgREST não é estritamente necessário
--   (incluído por consistência). Body-only CREATE OR REPLACE (preserva ACL). Reproduz a função
--   INTEIRA verbatim da captura anterior (mig 20260805000123) com 2 deltas marcados `-- #625`; o
--   único comentário inline pré-existente (-- ADR-0042) é reproduzido byte-fiel p/ não driftar o body-hash.
-- ROLLBACK: restaurar a captura de get_admin_dashboard da mig 20260805000123 / git.
-- =====================================================================================
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
  -- ADR-0042: V4 catalog (manage_platform writes; view_chapter_dashboards reads)
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
      -- #625: exclui a coorte pré-onboarding (helper C0) do numerador.
      'active_members', (SELECT count(*) FROM public.members WHERE is_active AND current_cycle_active AND NOT public.member_is_pre_onboarding(person_id, member_status)),
      -- #625: mesmo predicado no denominador da % para numerador e base ficarem consistentes.
      'adoption_7d', (SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::numeric / NULLIF(count(*), 0) * 100, 1) FROM public.members WHERE is_active AND current_cycle_active AND NOT public.member_is_pre_onboarding(person_id, member_status)),
      'deliverables_completed', (SELECT count(*) FROM public.board_items WHERE status = 'done'),
      'deliverables_total', (SELECT count(*) FROM public.board_items WHERE status != 'archived'),
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
