-- =====================================================================================
-- #2565 decisao (a) / ADR-0100: as metricas resolvem o ciclo corrente
--
-- MEDIDO em 2026-10-09: o ciclo corrente e cycle_4 (inicio 2026-07-09, sem fim); annual_kpi_targets
-- tem 9 metas em 4/2026 e 13 em 3/2026. /admin/portfolio pedia get_annual_kpis com ciclo 3 fixo, e a
-- funcao contava eventos e webinars numa janela cravada (2025-12-01 a 2026-06-30) que nem e a do
-- ciclo 3 vivo (2026-03-01 a 2026-07-08). O relatorio pedia get_cycle_report com ciclo 3 fixo, com
-- eventos desde 2026-01-01 e todas as metas de 2026 misturadas.
--
-- O QUE MUDA
--   - sem ciclo informado (o novo padrao das duas funcoes), vale o ciclo corrente de
--     cycles.is_current; a janela vem da linha do ciclo em cycles (fim aberto = hoje); o ano das
--     metas e o do inicio do ciclo. Quem passa o ciclo continua recebendo aquele ciclo, agora com a
--     janela certa dele. As duas devolvem cycle_start e cycle_end.
--   - get_cycle_report filtra as metas pelo ciclo e pelo ano, nao so pelo ano, e conta eventos
--     ate hoje dentro da janela; o total de CPMAI usa o ano das metas, nao o ano do relogio.
--   Portoes de acesso, colunas e o resto dos corpos nao mudam.
--
-- Corpos montados sobre o vivo (md5 normalizado == capturas 20261009042313 e 20260805000320,
-- conferido em 09/10). So os padroes dos parametros mudam na assinatura (CREATE OR REPLACE
-- preserva grants).
-- ROLLBACK: reaplicar as capturas 20261009042313 (get_annual_kpis) e 20260805000320
--   (get_cycle_report).
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.get_annual_kpis(p_cycle integer DEFAULT NULL::integer, p_year integer DEFAULT NULL::integer)
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
  v_cycle integer;
  v_year integer;
  v_cycle_start date;
  v_cycle_end date;
  v_analytics boolean;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  v_analytics := v_caller_id IS NOT NULL AND (public.can_by_member(v_caller_id, 'view_internal_analytics') OR public.can_by_member(v_caller_id, 'view_aggregate_analytics'));
  -- #1877: the communication team reads the annual KPIs to plan (decision of the GP, 2026-10-08), through the
  -- comms analytics gate (designations comms_leader/comms_member, or manage_comms). Narrow on purpose: granting
  -- view_aggregate_analytics instead would have opened 12 RPCs, among them selection and diversity dashboards.
  IF v_caller_id IS NULL OR NOT (v_analytics OR public.can_view_comms_analytics()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- #2565 (a) / ADR-0100: sem ciclo informado, vale o ciclo corrente (cycles.is_current); a janela
  -- e a do proprio ciclo, e o ano das metas e o do inicio do ciclo.
  v_cycle := coalesce(p_cycle,
    (SELECT substring(c.cycle_code FROM '^cycle_([0-9]+)$')::integer FROM public.cycles c
      WHERE c.is_current ORDER BY c.cycle_start DESC LIMIT 1));
  IF v_cycle IS NULL THEN
    RAISE EXCEPTION 'Nenhum ciclo corrente em cycles';
  END IF;
  SELECT c.cycle_start, coalesce(c.cycle_end, CURRENT_DATE)
    INTO v_cycle_start, v_cycle_end
    FROM public.cycles c WHERE c.cycle_code = 'cycle_' || v_cycle;
  IF v_cycle_start IS NULL THEN
    RAISE EXCEPTION 'Ciclo % nao encontrado', v_cycle;
  END IF;
  v_year := coalesce(p_year, extract(year FROM v_cycle_start)::integer);

  v_auto_values := jsonb_build_object(
    'pilots_active_or_completed', (SELECT count(*) FROM public.pilots WHERE status IN ('active', 'completed')),
    'publications_submitted_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name = 'publicacao' AND bi.status IN ('done', 'review') AND NOT public.is_confidential_board(bi.board_id)),
    'articles_academic_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name = 'artigo_academico' AND bi.status IN ('done', 'review') AND NOT public.is_confidential_board(bi.board_id)),
    'frameworks_delivered_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name IN ('framework', 'ferramenta') AND bi.status IN ('done', 'review') AND NOT public.is_confidential_board(bi.board_id)),
    'webinars_realized_count', public.get_webinars_count(v_cycle_start, LEAST(v_cycle_end, CURRENT_DATE), 'realized'),
    'attendance_general_avg_pct', public.calc_attendance_pct(),
    -- #692: members_retained now reads the canonical cohort-survival headline (was a degenerate
    -- is_active∧current/is_active ratio that read ~98.7).
    'retention_pct', (public.get_member_retention_canonical() -> 'headline' ->> 'survival_pct')::numeric,
    'events_total_count', (SELECT count(*) FROM public.events e WHERE e.date BETWEEN v_cycle_start AND LEAST(v_cycle_end, CURRENT_DATE) AND NOT EXISTS (SELECT 1 FROM public.event_tag_assignments eta JOIN public.tags t ON t.id = eta.tag_id WHERE eta.event_id = e.id AND t.name = 'interview') AND NOT public.is_confidential_initiative(e.initiative_id)),
    'trail_completion_pct', public.calc_trail_completion_pct(),
    'cpmai_certified_count', public.get_cpmai_certified_goal_count(v_year),
    'active_members_count', (SELECT count(*) FROM public.members WHERE is_active = true AND current_cycle_active = true),
    -- #1877: the infrastructure cost is financial data; it stays with whoever already read it (internal or aggregate
    -- analytics), and a caller who passes only through the comms gate gets null.
    'infra_cost_current', CASE WHEN NOT v_analytics THEN NULL ELSE (SELECT COALESCE(SUM(ce.amount_brl), 0) FROM public.cost_entries ce JOIN public.cost_categories cc ON cc.id = ce.category_id WHERE cc.name = 'infrastructure' AND ce.date >= date_trunc('month', now())::date AND ce.date < (date_trunc('month', now()) + interval '1 month')::date) END
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
  WHERE k.cycle = v_cycle AND k.year = v_year;

  v_result := jsonb_build_object(
    'cycle', v_cycle, 'year', v_year, 'cycle_start', v_cycle_start, 'cycle_end', v_cycle_end, 'generated_at', now(),
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

CREATE OR REPLACE FUNCTION public.get_cycle_report(p_cycle integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_cycle integer;
  v_year integer;
  v_cycle_start date;
  v_cycle_end date;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT (public.can_by_member(v_caller_id, 'view_internal_analytics') OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- #2565 (a) / ADR-0100: sem ciclo informado, vale o ciclo corrente (cycles.is_current); a janela
  -- e a do proprio ciclo, e o ano das metas e o do inicio do ciclo.
  v_cycle := coalesce(p_cycle,
    (SELECT substring(c.cycle_code FROM '^cycle_([0-9]+)$')::integer FROM public.cycles c
      WHERE c.is_current ORDER BY c.cycle_start DESC LIMIT 1));
  IF v_cycle IS NULL THEN
    RAISE EXCEPTION 'Nenhum ciclo corrente em cycles';
  END IF;
  SELECT c.cycle_start, coalesce(c.cycle_end, CURRENT_DATE)
    INTO v_cycle_start, v_cycle_end
    FROM public.cycles c WHERE c.cycle_code = 'cycle_' || v_cycle;
  IF v_cycle_start IS NULL THEN
    RAISE EXCEPTION 'Ciclo % nao encontrado', v_cycle;
  END IF;
  v_year := extract(year FROM v_cycle_start)::integer;

  v_result := jsonb_build_object(
    'cycle', v_cycle,
    'cycle_start', v_cycle_start,
    'cycle_end', v_cycle_end,
    'generated_at', now(),
    'members', (SELECT jsonb_build_object(
      'total', count(*),
      'active', (SELECT count(*) FROM public.v_active_members),
      'observers', count(*) FILTER (WHERE member_status = 'observer'),
      'alumni', count(*) FILTER (WHERE member_status = 'alumni'),
      'by_role', (SELECT coalesce(jsonb_object_agg(operational_role, cnt), '{}') FROM (SELECT operational_role, count(*) as cnt FROM public.v_active_members GROUP BY operational_role) r)
    ) FROM public.members),
    'tribes', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'name', t.name,
      'member_count', (SELECT count(*) FROM public.members WHERE tribe_id = t.id AND is_active),
      'board_progress', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE bi.status = 'done') / count(*)) END FROM public.project_boards pb JOIN public.initiatives i ON i.id = pb.initiative_id JOIN public.board_items bi ON bi.board_id = pb.id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived')
    ) ORDER BY t.id), '[]') FROM public.tribes t WHERE t.is_active),
    'events', (SELECT jsonb_build_object(
      'total', count(*),
      'total_impact_hours', (SELECT * FROM public.get_homepage_stats())->'impact_hours'
    ) FROM public.events e WHERE e.date BETWEEN v_cycle_start AND LEAST(v_cycle_end, CURRENT_DATE) AND NOT public.is_confidential_initiative(e.initiative_id)),
    'boards', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', pb.id, 'title', pb.board_name,
      'total_items', (SELECT count(*) FROM public.board_items WHERE board_id = pb.id AND status != 'archived'),
      'done_items', (SELECT count(*) FROM public.board_items WHERE board_id = pb.id AND status = 'done'),
      'progress', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE status = 'done') / count(*)) END FROM public.board_items WHERE board_id = pb.id AND status != 'archived')
    )), '[]') FROM public.project_boards pb WHERE pb.is_active AND NOT public.is_confidential_board(pb.id)),
    'kpis', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'name', k.kpi_label_pt, 'name_en', k.kpi_label_en,
      'target', k.target_value, 'current', k.current_value,
      'pct', CASE WHEN k.target_value > 0 THEN round(100.0 * k.current_value / k.target_value) ELSE 0 END
    )), '[]') FROM public.annual_kpi_targets k WHERE k.cycle = v_cycle AND k.year = v_year),
    'platform', jsonb_build_object(
      'releases_count', (SELECT count(*) FROM public.releases),
      'governance_entries', 125,
      'zero_cost', true,
      'stack', 'Astro 5 + React 19 + Tailwind 4 + Supabase + Cloudflare Pages'
    )
  );
  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
