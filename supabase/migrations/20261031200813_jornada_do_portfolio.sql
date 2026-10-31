-- #2565 (i) e #2865: jornada do portfolio.
-- exec_portfolio_health: a meta articles_published conta curation_status = 'published'. O valor
-- 'approved' nao existe no CHECK de board_items.curation_status, e a meta ficava sempre em 0.
-- Corpo recriado a partir da captura vigente, igual ao corpo vivo; muda so essa linha. A ACL fica.
-- O rotulo da meta, em portfolio_kpi_targets, passa a dizer que ela conta o aprovado pela curadoria.
-- create_publication_submission: SECURITY DEFINER passa a fixar search_path, como as outras
-- funcoes da jornada do portfolio. O corpo nao muda.

-- exec_portfolio_health: captura vigente 20261025160648_pr3_decisoes_site.sql
CREATE OR REPLACE FUNCTION public.exec_portfolio_health(p_cycle_code text DEFAULT 'cycle3-2026'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb := '[]'::jsonb;
  v_cycle_code text;
  v_target record;
  v_current numeric;
  v_progress numeric;
  v_status text;
  v_year_start date;
  v_current_quarter int;
  v_q_target numeric;
  v_q_cumulative numeric;
  v_q_progress numeric;
  v_q_status text;
BEGIN
  v_year_start := make_date(EXTRACT(year FROM now())::int, 1, 1);
  v_current_quarter := EXTRACT(quarter FROM now())::int;

  -- GI-3 resilient cycle resolution: never silently return zero metrics. If the requested
  -- code has no targets (NULL/blank, or a namespace-mismatched code like cycles 'cycle_3'),
  -- fall back to the most-recently-created cycle_code that has targets.
  v_cycle_code := NULLIF(trim(p_cycle_code), '');
  IF v_cycle_code IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.portfolio_kpi_targets WHERE cycle_code = v_cycle_code) THEN
    SELECT cycle_code INTO v_cycle_code
    FROM public.portfolio_kpi_targets
    GROUP BY cycle_code
    ORDER BY MAX(created_at) DESC
    LIMIT 1;
  END IF;

  FOR v_target IN
    SELECT * FROM public.portfolio_kpi_targets
    WHERE cycle_code = v_cycle_code
    ORDER BY display_order
  LOOP
    CASE v_target.metric_key

      WHEN 'chapters_participating' THEN
        -- #2553: capítulos = engaged (assinados + em negociação), decisão do GP de 03/10/2026.
        v_current := (public.get_chapter_metrics()->>'engaged')::numeric;

      WHEN 'partner_entities' THEN
        -- PR3 A3 (GP 25/10/2026): governo, academia e empresa pelos tipos que o CRM grava ('academic' e o legado
        -- 'academia'), e só parceria com termo assinado. O termo assinado de uma entidade é o cooperation_agreement
        -- ativo com signed_at em governance_documents, ligado a ela por partner_entity_id (o registro que
        -- link_attachment_to_governance cria e que auto_generate_cr_for_partnership lê como acordo assinado).
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.partner_entities pe
        WHERE pe.entity_type IN ('academia', 'academic', 'governo', 'empresa')
          AND pe.status = 'active'
          AND pe.partnership_date >= v_year_start
          AND EXISTS (
            SELECT 1 FROM public.governance_documents gd
            WHERE gd.partner_entity_id = pe.id
              AND gd.doc_type = 'cooperation_agreement'
              AND gd.status = 'active'
              AND gd.signed_at IS NOT NULL
          );

      WHEN 'certification_trail' THEN
        SELECT calc_trail_completion_pct() INTO v_current;

      WHEN 'cpmai_certified' THEN
        v_current := public.get_cpmai_certified_goal_count(EXTRACT(year FROM v_year_start)::int);

      WHEN 'articles_published' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')
          AND bi.curation_status = 'published'  -- #2565 (i): o CHECK nao tem 'approved'
          AND bi.created_at >= v_year_start::timestamptz AND NOT public.is_confidential_board(bi.board_id);

      WHEN 'webinars_completed' THEN
        v_current := public.get_webinars_count(v_year_start, current_date, 'realized');

      WHEN 'ia_pilots' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.ia_pilots
        WHERE start_date >= v_year_start
          AND status IN ('active', 'completed');

      WHEN 'meeting_hours' THEN
        SELECT COALESCE(ROUND(SUM(COALESCE(e.duration_actual, e.duration_minutes)::numeric / 60.0)), 0)
        INTO v_current
        FROM public.events e
        WHERE e.date >= v_year_start AND e.date <= current_date AND NOT public.is_confidential_initiative(e.initiative_id);

      WHEN 'impact_hours' THEN
        v_current := public.get_impact_hours_canonical(v_year_start, current_date);

      ELSE
        v_current := 0;
    END CASE;

    v_progress := CASE
      WHEN v_target.target_value > 0 THEN ROUND((v_current / v_target.target_value) * 100)
      ELSE 0
    END;

    v_status := CASE
      WHEN v_current >= v_target.target_value THEN 'green'
      WHEN v_current >= v_target.warning_threshold THEN 'yellow'
      ELSE 'red'
    END;

    SELECT qt.quarter_target, qt.quarter_cumulative_target
    INTO v_q_target, v_q_cumulative
    FROM public.portfolio_kpi_quarterly_targets qt
    WHERE qt.kpi_target_id = v_target.id
      AND qt.quarter = v_current_quarter;

    v_q_progress := CASE
      WHEN COALESCE(v_q_cumulative, 0) > 0 THEN ROUND((v_current / v_q_cumulative) * 100)
      ELSE 0
    END;

    v_q_status := CASE
      WHEN v_current >= COALESCE(v_q_cumulative, 0) THEN 'green'
      WHEN COALESCE(v_q_cumulative, 0) > 0 AND v_current >= v_q_cumulative * 0.5 THEN 'yellow'
      ELSE 'red'
    END;

    v_result := v_result || jsonb_build_object(
      'metric_key', v_target.metric_key,
      'label', v_target.metric_label,
      'target', ROUND(v_target.target_value),
      'current', ROUND(v_current),
      'progress_pct', v_progress,
      'status', v_status,
      'unit', v_target.unit,
      'display_order', v_target.display_order,
      'quarter', v_current_quarter,
      'quarter_target', ROUND(COALESCE(v_q_target, 0)),
      'quarter_cumulative', ROUND(COALESCE(v_q_cumulative, 0)),
      'quarter_progress_pct', v_q_progress,
      'quarter_status', v_q_status
    );
  END LOOP;

  RETURN v_result;
END;
$function$;

-- #2565 (i), decisao do GP de 31/10/2026 (G6, opcao c): a meta articles_published conta o que a
-- curadoria aprovou (a aprovacao grava curation_status = 'published'), nao publicacao externa. O
-- rotulo passa a dizer isso. Mesmo desenho da troca de rotulo da #2553: portfolio_kpi_targets tem so
-- o ciclo cycle3-2026 e o unico leitor de metric_label e exec_portfolio_health. A troca exige o
-- rotulo de hoje: se alguem o mudou antes, a migration para em vez de sobrescrever.
DO $do$
DECLARE
  v_rows integer;
  v_old  jsonb;
  v_new  jsonb := jsonb_build_object(
    'pt', 'Artigos aprovados pela curadoria',
    'en', 'Articles approved by curation',
    'es', 'Artículos aprobados por la curaduría');
BEGIN
  SELECT metric_label INTO v_old FROM public.portfolio_kpi_targets
  WHERE cycle_code = 'cycle3-2026' AND metric_key = 'articles_published';
  UPDATE public.portfolio_kpi_targets SET metric_label = v_new
  WHERE cycle_code = 'cycle3-2026' AND metric_key = 'articles_published' AND metric_label->>'pt' = 'Artigos Publicados';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION '#2565 metas: esperava 1 linha de articles_published com o rótulo "Artigos Publicados", achei % (rótulo atual %)', v_rows, v_old;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, changes, metadata)
  VALUES (NULL, 'kpi.label_set', 'portfolio_kpi_targets',
          jsonb_build_object('articles_published', jsonb_build_object('before', v_old, 'after', v_new)),
          jsonb_build_object('issue', '#2565', 'source', 'migration', 'cycle_code', 'cycle3-2026',
                             'decision', 'GP 31/10/2026 (G6, opção c): o rótulo diz que a meta conta o aprovado pela curadoria'));
END;
$do$;

ALTER FUNCTION public.create_publication_submission(p_title text, p_target_type public.submission_target_type, p_target_name text, p_primary_author_id uuid, p_tribe_id integer, p_board_item_id uuid, p_abstract text, p_target_url text, p_estimated_cost_brl numeric)
  SET search_path = public, pg_temp;
