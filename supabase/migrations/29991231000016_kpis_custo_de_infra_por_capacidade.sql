-- =====================================================================================
-- get_annual_kpis: o custo de infraestrutura do mes sai so para quem tem view_finance
--
-- A chave infra_cost_current (soma do mes da categoria de infraestrutura) passa a seguir a mesma
-- regra das RPCs de financas: so quem tem view_finance recebe o numero; os demais recebem NULL, como
-- ja recebia quem entra so pelo portao de comunicacao. O resto da funcao nao muda.
--
-- Corpo montado sobre o vivo (md5 normalizado == captura 20261009192905, conferido em 09/10).
-- Assinatura, SECURITY DEFINER, search_path e grants nao mudam (CREATE OR REPLACE).
-- ROLLBACK: reaplicar a captura 20261009192905 de get_annual_kpis.
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
  v_finance boolean;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  v_analytics := v_caller_id IS NOT NULL AND (public.can_by_member(v_caller_id, 'view_internal_analytics') OR public.can_by_member(v_caller_id, 'view_aggregate_analytics'));
  -- o custo de infraestrutura e dado financeiro: sai so para quem tem a capacidade de financas
  v_finance := v_caller_id IS NOT NULL AND public.can_by_member(v_caller_id, 'view_finance');
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
    -- #1877 + financas: o custo de infraestrutura e dado financeiro; sai so para quem tem view_finance
    -- (a mesma regra das RPCs de financas). Os demais, inclusive o portao de comunicacao, recebem NULL.
    'infra_cost_current', CASE WHEN NOT v_finance THEN NULL ELSE (SELECT COALESCE(SUM(ce.amount_brl), 0) FROM public.cost_entries ce JOIN public.cost_categories cc ON cc.id = ce.category_id WHERE cc.name = 'infrastructure' AND ce.date >= date_trunc('month', now())::date AND ce.date < (date_trunc('month', now()) + interval '1 month')::date) END
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
