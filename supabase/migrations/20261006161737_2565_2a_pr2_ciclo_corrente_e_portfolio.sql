-- #2565 2A, PR 2: o card novo nasce no ciclo corrente, por qualquer caminho, e as leituras do
-- portfólio seguem a janela do ciclo (decisão (g) da #2565, ADR-0100 §2.1).
--
-- Visão de um ciclo: o ciclo corrente mostra todo card aberto, de qualquer ciclo, mais o que foi
-- concluído dentro da janela dele; um ciclo passado mostra o que foi concluído dentro da janela
-- dele. O ciclo gravado no card deixa de decidir o que a leitura mostra, e nenhuma leitura assume
-- mais o ciclo 3 como padrão: sem ciclo pedido, vale o ciclo corrente (cycles.is_current).

-- 1. Número do ciclo corrente, derivado de cycles.cycle_code (a chave de ciclo decidida na #2565).
CREATE OR REPLACE FUNCTION public.current_cycle_number()
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT substring(c.cycle_code from '^cycle_([0-9]{1,6})$')::int
  FROM public.cycles c
  WHERE c.is_current IS TRUE
  ORDER BY c.sort_order DESC
  LIMIT 1;
$function$;

COMMENT ON FUNCTION public.current_cycle_number() IS
  '#2565 2A: número do ciclo corrente (cycles.is_current), extraído de cycle_code (cycle_4 -> 4). NULL sem ciclo corrente ou com código fora do padrão.';
REVOKE ALL ON FUNCTION public.current_cycle_number() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_cycle_number() TO authenticated, service_role;

-- 2. Janela de um ciclo (NULL = o corrente) e a regra de pertencer à visão dele.
CREATE OR REPLACE FUNCTION public._cycle_window(p_cycle integer DEFAULT NULL::integer)
 RETURNS TABLE(cycle_number integer, is_current boolean, window_start date, window_end date)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT substring(c.cycle_code from '^cycle_([0-9]{1,6})$')::int,
         c.is_current IS TRUE,
         c.cycle_start,
         c.cycle_end
  FROM public.cycles c
  WHERE c.cycle_code = 'cycle_' || COALESCE(p_cycle, public.current_cycle_number())::text
  ORDER BY c.sort_order DESC
  LIMIT 1;
$function$;

COMMENT ON FUNCTION public._cycle_window(integer) IS
  '#2565 2A: janela de um ciclo pelo número (NULL = ciclo corrente). Sem linha quando o ciclo não existe: quem lê mostra vazio, nunca outro ciclo.';
REVOKE ALL ON FUNCTION public._cycle_window(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._cycle_window(integer) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public._in_cycle_view(p_completed date, p_is_current boolean, p_start date, p_end date)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN p_completed IS NULL THEN coalesce(p_is_current, false)
    ELSE p_completed >= p_start AND (p_end IS NULL OR p_completed <= p_end)
  END;
$function$;

COMMENT ON FUNCTION public._in_cycle_view(date, boolean, date, date) IS
  '#2565 2A, decisão (g): card aberto entra só na visão do ciclo corrente; card concluído entra na visão do ciclo em cuja janela foi concluído.';
REVOKE ALL ON FUNCTION public._in_cycle_view(date, boolean, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._in_cycle_view(date, boolean, date, date) TO authenticated, service_role;

-- 3. Carimbo: todo card novo sem ciclo recebe o ciclo corrente, venha de qual caminho vier.
--    SECURITY DEFINER para valer também na inserção direta por usuário autenticado.
CREATE OR REPLACE FUNCTION public._trg_board_items_stamp_cycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.cycle IS NULL THEN
    NEW.cycle := public.current_cycle_number();
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._trg_board_items_stamp_cycle() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_board_items_stamp_cycle ON public.board_items;
CREATE TRIGGER trg_board_items_stamp_cycle
  BEFORE INSERT ON public.board_items
  FOR EACH ROW EXECUTE FUNCTION public._trg_board_items_stamp_cycle();

-- 4. Os caminhos que gravavam ciclo errado deixam o carimbo para o gatilho; o espelho herda o da origem.
CREATE OR REPLACE FUNCTION public.create_board_item(p_board_id uuid, p_title text, p_description text DEFAULT NULL::text, p_assignee_id uuid DEFAULT NULL::uuid, p_tags text[] DEFAULT '{}'::text[], p_due_date date DEFAULT NULL::date, p_status text DEFAULT 'backlog'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
  v_max_pos int;
  v_caller record;
  v_board record;
  v_board_legacy_tribe_id int;
  v_is_gp boolean;
  v_is_leader boolean;
  v_is_tribe_member boolean;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_board FROM project_boards WHERE id = p_board_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Board not found'; END IF;

  -- ADR-0015 Phase 3d: project_boards.tribe_id dropado; derivar via initiative
  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  v_is_gp := coalesce(v_caller.is_superadmin, false)
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR coalesce('co_gp' = ANY(v_caller.designations), false);
  v_is_leader := v_caller.operational_role = 'tribe_leader' AND v_caller.tribe_id = v_board_legacy_tribe_id;
  v_is_tribe_member := v_caller.is_active AND v_caller.tribe_id = v_board_legacy_tribe_id;

  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
  IF NOT public._can_write_board(v_caller.id, p_board_id) AND NOT v_is_tribe_member AND NOT (
    (coalesce(v_board.domain_key, '') = 'communication' AND (
      v_caller.operational_role = 'communicator'
      OR coalesce('comms_team' = ANY(v_caller.designations), false)
      OR coalesce('comms_leader' = ANY(v_caller.designations), false)
      OR coalesce('comms_member' = ANY(v_caller.designations), false)
    ))
    OR (coalesce(v_board.domain_key, '') = 'publications_submissions' AND (
      v_caller.operational_role IN ('tribe_leader', 'communicator')
      OR public.can_by_member(v_caller.id, 'curate_content')
    ))
  ) THEN RAISE EXCEPTION 'Unauthorized to create cards on this board'; END IF;

  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos FROM board_items WHERE board_id = p_board_id AND status = p_status;

  -- #2565 2A: o ciclo sai do gatilho trg_board_items_stamp_cycle (ciclo corrente), nunca de literal.
  INSERT INTO board_items (board_id, title, description, assignee_id, tags, due_date, position, status, created_by)
  VALUES (p_board_id, p_title, p_description, COALESCE(p_assignee_id, v_caller.id), p_tags, p_due_date, v_max_pos, p_status, v_caller.id)
  RETURNING id INTO v_id;

  INSERT INTO board_item_assignments (item_id, member_id, role, assigned_by)
  VALUES (v_id, v_caller.id, 'author', v_caller.id)
  ON CONFLICT DO NOTHING;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, new_status, actor_member_id)
  VALUES (p_board_id, v_id, 'created', p_status, v_caller.id);

  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.duplicate_board_item(p_item_id uuid, p_target_board_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_new_id uuid;
  v_board_id uuid;
  v_max_pos int;
  v_actor uuid;
  v_authorized boolean;
BEGIN
  SELECT coalesce(p_target_board_id, board_id) INTO v_board_id
  FROM board_items WHERE id = p_item_id;
  IF v_board_id IS NULL THEN RAISE EXCEPTION 'Source card not found'; END IF;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Unauthorized: authentication required'; END IF;

  IF NOT public.rls_can_see_item(p_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access source card';
  END IF;
  IF NOT public.rls_can_see_board(v_board_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access target board';
  END IF;

  v_authorized := public._can_write_board(v_actor, v_board_id)
    OR EXISTS (SELECT 1 FROM board_members bm WHERE bm.board_id = v_board_id AND bm.member_id = v_actor AND bm.board_role IN ('admin', 'editor'));
  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission or board editor role on the target board';
  END IF;

  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos
  FROM board_items WHERE board_id = v_board_id AND status = 'backlog';

  -- #2565 2A: a cópia é trabalho novo; o ciclo sai do gatilho (ciclo corrente), não da origem.
  INSERT INTO board_items (
    board_id, title, description, tags, labels, checklist, attachments, position, status
  )
  SELECT v_board_id, title || ' (cópia)', description, tags, labels, checklist, attachments, v_max_pos, 'backlog'
  FROM board_items WHERE id = p_item_id
  RETURNING id INTO v_new_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_board_id, v_new_id, 'created', 'Duplicado de ' || p_item_id::text, v_actor);

  RETURN v_new_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_mirror_card(p_source_item_id uuid, p_target_board_id uuid, p_target_status text DEFAULT 'backlog'::text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_member_id uuid;
  v_source record;
  v_mirror_id uuid;
  v_max_pos integer;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id LIMIT 1;

  SELECT * INTO v_source FROM public.board_items WHERE id = p_source_item_id;
  IF v_source IS NULL THEN RAISE EXCEPTION 'Source card not found'; END IF;

  IF NOT public.rls_can_see_item(p_source_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access source card';
  END IF;
  IF NOT public.rls_can_see_board(p_target_board_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access target board';
  END IF;
  IF NOT (public._can_write_board(v_member_id, p_target_board_id)
          OR EXISTS (SELECT 1 FROM public.board_members bm WHERE bm.board_id = p_target_board_id AND bm.member_id = v_member_id AND bm.board_role IN ('admin', 'editor'))) THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission or board editor role on the target board';
  END IF;

  SELECT COALESCE(MAX(position), 0) + 1 INTO v_max_pos
  FROM public.board_items
  WHERE board_id = p_target_board_id AND status = p_target_status;

  -- #2565 2A: o espelho é o mesmo trabalho da origem e herda o ciclo dela; sem ciclo na origem, o gatilho carimba.
  INSERT INTO public.board_items (
    board_id, title, description, status, tags,
    mirror_source_id, is_mirror, position, cycle
  ) VALUES (
    p_target_board_id,
    v_source.title,
    COALESCE(p_notes, v_source.description),
    p_target_status,
    v_source.tags,
    p_source_item_id,
    true,
    v_max_pos,
    v_source.cycle
  )
  RETURNING id INTO v_mirror_id;

  UPDATE public.board_items
  SET mirror_target_id = v_mirror_id
  WHERE id = p_source_item_id;

  INSERT INTO public.board_lifecycle_events (item_id, board_id, action, new_status, reason, actor_member_id)
  VALUES
    (p_source_item_id, v_source.board_id, 'mirror_created', v_mirror_id::text,
     'Card espelho criado no board ' || p_target_board_id::text, v_member_id),
    (v_mirror_id, p_target_board_id, 'mirror_created', p_source_item_id::text,
     'Espelho do card: ' || v_source.title, v_member_id);

  RETURN v_mirror_id;
END;
$function$;

-- 5. Leituras do portfólio na visão do ciclo. As travas de acesso ficam como estavam.
CREATE OR REPLACE FUNCTION public.get_portfolio_dashboard(p_cycle integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
  v_artifacts jsonb;
  v_summary jsonb;
  v_by_tribe jsonb;
  v_by_type jsonb;
  v_by_month jsonb;
  v_cycle integer;
  v_is_current boolean;
  v_start date;
  v_end date;
BEGIN
  -- Leitura pela API segue a política de leitura de board_items.
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN
    RETURN NULL;
  END IF;

  -- #2565 2A: visão do ciclo pedido (NULL = corrente), pela regra (g).
  SELECT w.cycle_number, w.is_current, w.window_start, w.window_end
  INTO v_cycle, v_is_current, v_start, v_end
  FROM public._cycle_window(p_cycle) w;

  SELECT jsonb_agg(row_to_json(sub.*) ORDER BY sub.tribe_id, sub.baseline_date NULLS LAST)
  INTO v_artifacts
  FROM (
    SELECT
      bi.id, bi.title, bi.description, bi.status,
      bi.baseline_date, bi.forecast_date, bi.actual_completion_date,
      CASE
        WHEN bi.baseline_date IS NOT NULL AND bi.forecast_date IS NOT NULL
        THEN (bi.forecast_date - bi.baseline_date) ELSE NULL
      END AS variance_days,
      CASE
        WHEN bi.actual_completion_date IS NOT NULL THEN 'completed'
        WHEN bi.baseline_date IS NULL OR bi.forecast_date IS NULL THEN 'no_baseline'
        WHEN CURRENT_DATE > bi.forecast_date THEN 'delayed'
        WHEN bi.forecast_date <= bi.baseline_date THEN 'on_track'
        WHEN (bi.forecast_date - bi.baseline_date) <= 7 THEN 'at_risk'
        ELSE 'delayed'
      END AS health,
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      i.id AS initiative_id,
      i.kind AS initiative_kind,
      m.name AS leader_name,
      bi.tags AS legacy_tags,
      (SELECT jsonb_agg(jsonb_build_object('name', tg.name, 'label', tg.label_pt, 'color', tg.color))
       FROM board_item_tag_assignments bita JOIN tags tg ON tg.id = bita.tag_id
       WHERE bita.board_item_id = bi.id AND tg.name <> 'entregavel_lider' AND tg.name !~ '^ciclo_[0-9]+$') AS unified_tags,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id) AS checklist_total,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id AND bic.is_completed = true) AS checklist_done,
      CASE WHEN bi.baseline_date IS NOT NULL THEN 'Q' || EXTRACT(QUARTER FROM bi.baseline_date)::text ELSE 'TBD' END AS quarter,
      CASE WHEN bi.baseline_date IS NOT NULL THEN to_char(bi.baseline_date, 'YYYY-MM') ELSE 'TBD' END AS baseline_month
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN initiatives i ON i.id = pb.initiative_id
    LEFT JOIN members m ON m.id = bi.assignee_id
    WHERE bi.status <> 'archived' AND bi.is_portfolio_item = true
      AND public._in_cycle_view(bi.actual_completion_date, v_is_current, v_start, v_end)
  ) sub;

  SELECT jsonb_build_object(
    'total_artifacts', count(*),
    'completed', count(*) FILTER (WHERE sub.health = 'completed'),
    'on_track', count(*) FILTER (WHERE sub.health = 'on_track'),
    'at_risk', count(*) FILTER (WHERE sub.health = 'at_risk'),
    'delayed', count(*) FILTER (WHERE sub.health = 'delayed'),
    'no_baseline', count(*) FILTER (WHERE sub.health = 'no_baseline'),
    'avg_variance_days', ROUND(AVG(sub.variance_days) FILTER (WHERE sub.variance_days IS NOT NULL), 1),
    'checklist_total', SUM(sub.checklist_total),
    'checklist_done', SUM(sub.checklist_done),
    'pct_with_baseline', ROUND(count(*) FILTER (WHERE sub.baseline_date IS NOT NULL)::numeric / NULLIF(count(*), 0) * 100, 1)
  )
  INTO v_summary
  FROM (
    SELECT bi.baseline_date, bi.forecast_date, bi.actual_completion_date,
      CASE
        WHEN bi.actual_completion_date IS NOT NULL THEN 'completed'
        WHEN bi.baseline_date IS NULL OR bi.forecast_date IS NULL THEN 'no_baseline'
        WHEN CURRENT_DATE > bi.forecast_date THEN 'delayed'
        WHEN bi.forecast_date <= bi.baseline_date THEN 'on_track'
        WHEN (bi.forecast_date - bi.baseline_date) <= 7 THEN 'at_risk'
        ELSE 'delayed'
      END AS health,
      (bi.forecast_date - bi.baseline_date) AS variance_days,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id) AS checklist_total,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id AND bic.is_completed = true) AS checklist_done
    FROM board_items bi
    WHERE bi.status <> 'archived' AND bi.is_portfolio_item = true
      AND public._in_cycle_view(bi.actual_completion_date, v_is_current, v_start, v_end)
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'tribe_id', sub.tribe_id, 'tribe_name', sub.tribe_name,
    'initiative_id', sub.initiative_id, 'initiative_kind', sub.initiative_kind,
    'leader', sub.leader_name, 'total', sub.total,
    'completed', sub.completed, 'on_track', sub.on_track,
    'at_risk', sub.at_risk, 'delayed', sub.delayed,
    'no_baseline', sub.no_baseline, 'next_deadline', sub.next_deadline,
    'checklist_pct', sub.checklist_pct
  ) ORDER BY sub.tribe_id NULLS LAST, sub.tribe_name)
  INTO v_by_tribe
  FROM (
    SELECT
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      i.id AS initiative_id,
      i.kind AS initiative_kind,
      m.name AS leader_name,
      count(*) AS total,
      count(*) FILTER (WHERE bi.actual_completion_date IS NOT NULL) AS completed,
      count(*) FILTER (
        WHERE bi.actual_completion_date IS NULL
          AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
          AND bi.forecast_date <= bi.baseline_date
          AND CURRENT_DATE <= bi.forecast_date
      ) AS on_track,
      count(*) FILTER (
        WHERE bi.actual_completion_date IS NULL
          AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
          AND (bi.forecast_date - bi.baseline_date) BETWEEN 1 AND 7
          AND CURRENT_DATE <= bi.forecast_date
      ) AS at_risk,
      count(*) FILTER (
        WHERE bi.actual_completion_date IS NULL
          AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
          AND ((bi.forecast_date - bi.baseline_date) > 7 OR CURRENT_DATE > bi.forecast_date)
      ) AS delayed,
      count(*) FILTER (WHERE bi.baseline_date IS NULL) AS no_baseline,
      MIN(bi.forecast_date) FILTER (WHERE bi.actual_completion_date IS NULL AND bi.forecast_date >= CURRENT_DATE) AS next_deadline,
      CASE WHEN SUM(chk.total) > 0 THEN ROUND(SUM(chk.done)::numeric / SUM(chk.total) * 100, 1) ELSE 0 END AS checklist_pct
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN initiatives i ON i.id = pb.initiative_id
    LEFT JOIN members m ON m.id = bi.assignee_id
    LEFT JOIN LATERAL (
      SELECT count(*) AS total, count(*) FILTER (WHERE is_completed) AS done
      FROM board_item_checklists WHERE board_item_id = bi.id
    ) chk ON true
    WHERE bi.status <> 'archived' AND bi.is_portfolio_item = true
      AND public._in_cycle_view(bi.actual_completion_date, v_is_current, v_start, v_end)
    GROUP BY i.legacy_tribe_id, i.title, i.id, i.kind, m.name
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'type', sub.tag_name, 'label', sub.tag_label, 'color', sub.tag_color, 'count', sub.cnt
  ) ORDER BY sub.cnt DESC)
  INTO v_by_type
  FROM (
    SELECT tg.name AS tag_name, tg.label_pt AS tag_label, tg.color AS tag_color, count(DISTINCT bi.id) AS cnt
    FROM board_items bi
    JOIN board_item_tag_assignments bita ON bita.board_item_id = bi.id
    JOIN tags tg ON tg.id = bita.tag_id
    WHERE bi.status <> 'archived'
      AND public._in_cycle_view(bi.actual_completion_date, v_is_current, v_start, v_end)
      AND tg.name <> 'entregavel_lider' AND tg.name !~ '^ciclo_[0-9]+$'
      AND tg.tier = 'system' AND bi.is_portfolio_item = true
    GROUP BY tg.name, tg.label_pt, tg.color
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'month', sub.month, 'count', sub.cnt, 'tribes', sub.tribes
  ) ORDER BY sub.month)
  INTO v_by_month
  FROM (
    SELECT
      to_char(bi.baseline_date, 'YYYY-MM') AS month,
      count(*) AS cnt,
      jsonb_agg(DISTINCT i.legacy_tribe_id) AS tribes
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN initiatives i ON i.id = pb.initiative_id
    WHERE bi.status <> 'archived'
      AND public._in_cycle_view(bi.actual_completion_date, v_is_current, v_start, v_end)
      AND bi.baseline_date IS NOT NULL AND bi.is_portfolio_item = true
    GROUP BY to_char(bi.baseline_date, 'YYYY-MM')
  ) sub;

  v_result := jsonb_build_object(
    'cycle', COALESCE(v_cycle, p_cycle),
    'window_start', v_start,
    'window_end', v_end,
    'generated_at', now(),
    'summary', COALESCE(v_summary, '{}'::jsonb),
    'artifacts', COALESCE(v_artifacts, '[]'::jsonb),
    'by_tribe', COALESCE(v_by_tribe, '[]'::jsonb),
    'by_type', COALESCE(v_by_type, '[]'::jsonb),
    'by_month', COALESCE(v_by_month, '[]'::jsonb)
  );

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_portfolio_planned_vs_actual(p_cycle integer DEFAULT NULL::integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_result jsonb;
  v_is_current boolean;
  v_start date;
  v_end date;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  -- #2565 2A: visão do ciclo pedido (NULL = corrente), pela regra (g).
  SELECT w.is_current, w.window_start, w.window_end
  INTO v_is_current, v_start, v_end
  FROM public._cycle_window(p_cycle) w;

  SELECT coalesce(jsonb_agg(row_data ORDER BY row_data->>'tribe_name'), '[]'::jsonb) INTO v_result
  FROM (
    SELECT jsonb_build_object(
      'tribe_id', t.id,
      'tribe_name', t.name,
      'chapter', (SELECT chapter FROM members WHERE tribe_id = t.id AND operational_role = 'tribe_leader' LIMIT 1),
      'total_cards', count(bi.id),
      'portfolio_cards', count(bi.id) FILTER (WHERE bi.is_portfolio_item = true),
      'planned', count(bi.id) FILTER (WHERE bi.baseline_date IS NOT NULL AND bi.is_portfolio_item = true),
      'in_progress', count(bi.id) FILTER (WHERE bi.status IN ('in_progress', 'review') AND bi.is_portfolio_item = true),
      'done', count(bi.id) FILTER (WHERE bi.status = 'done' AND bi.is_portfolio_item = true),
      'backlog', count(bi.id) FILTER (WHERE bi.status = 'backlog' AND bi.is_portfolio_item = true),
      'on_time', count(bi.id) FILTER (
        WHERE bi.is_portfolio_item = true
          AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
          AND bi.forecast_date <= bi.baseline_date
          AND (bi.actual_completion_date IS NOT NULL OR CURRENT_DATE <= bi.forecast_date)
      ),
      'at_risk', count(bi.id) FILTER (
        WHERE bi.is_portfolio_item = true
          AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
          AND bi.forecast_date > bi.baseline_date AND bi.forecast_date <= bi.baseline_date + 14
          AND (bi.actual_completion_date IS NOT NULL OR CURRENT_DATE <= bi.forecast_date)
      ),
      'delayed', count(bi.id) FILTER (
        WHERE bi.is_portfolio_item = true
          AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
          AND (
            (bi.forecast_date - bi.baseline_date) > 14
            OR (bi.actual_completion_date IS NULL AND CURRENT_DATE > bi.forecast_date)
          )
      ),
      'avg_deviation_days', round(coalesce(avg(
        CASE WHEN bi.is_portfolio_item = true AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
        THEN bi.forecast_date - bi.baseline_date END
      ), 0)),
      'spi', CASE
        WHEN count(bi.id) FILTER (WHERE bi.baseline_date IS NOT NULL AND bi.is_portfolio_item = true) = 0 THEN null
        ELSE round(
          count(bi.id) FILTER (WHERE bi.status = 'done' AND bi.is_portfolio_item = true)::numeric /
          NULLIF(count(bi.id) FILTER (WHERE bi.baseline_date IS NOT NULL AND bi.is_portfolio_item = true), 0),
          2
        )
      END,
      'completion_pct', CASE
        WHEN count(bi.id) FILTER (WHERE bi.is_portfolio_item = true) = 0 THEN 0
        ELSE round(
          count(bi.id) FILTER (WHERE bi.status = 'done' AND bi.is_portfolio_item = true)::numeric * 100 /
          NULLIF(count(bi.id) FILTER (WHERE bi.is_portfolio_item = true), 0),
          1
        )
      END
    ) as row_data
    FROM tribes t
    JOIN initiatives i ON i.legacy_tribe_id = t.id
    JOIN project_boards pb ON pb.initiative_id = i.id AND pb.is_active = true
    JOIN board_items bi ON bi.board_id = pb.id AND bi.status != 'archived'
      AND public._in_cycle_view(bi.actual_completion_date, v_is_current, v_start, v_end)
    WHERE t.is_active = true
    GROUP BY t.id, t.name
  ) sub;

  IF v_caller.operational_role IN ('sponsor', 'chapter_liaison') AND NOT coalesce(v_caller.is_superadmin, false) THEN
    SELECT coalesce(jsonb_agg(elem), '[]'::jsonb) INTO v_result
    FROM jsonb_array_elements(v_result) elem
    WHERE elem->>'chapter' = v_caller.chapter OR elem->>'chapter' IS NULL;
  END IF;

  IF v_caller.operational_role = 'tribe_leader' AND NOT coalesce(v_caller.is_superadmin, false) THEN
    SELECT coalesce(jsonb_agg(elem), '[]'::jsonb) INTO v_result
    FROM jsonb_array_elements(v_result) elem
    WHERE (elem->>'tribe_id')::integer = v_caller.tribe_id;
  END IF;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_portfolio_items(p_tribe_id integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_cycle_code text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, title text, status text, tribe_id integer, initiative_id uuid, baseline_date date, baseline_locked_at timestamp with time zone, forecast_date date, due_date date, is_portfolio_item boolean, portfolio_kpi_refs text[], cycle_code text, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_cycle integer;
  v_is_current boolean;
  v_start date;
  v_end date;
BEGIN
  SELECT m.id INTO v_member_id FROM members m WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT (can_by_member(v_member_id, 'view_internal_analytics') OR can_by_member(v_member_id, 'view_chapter_dashboards') OR can_by_member(v_member_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'Access denied — requires view_internal_analytics or view_chapter_dashboards';
  END IF;

  -- #2565 2A: com ciclo pedido, a lista segue a visão do ciclo (regra (g)), não o ciclo gravado.
  -- Código fora do padrão cycle_N não resolve janela e a lista volta vazia, nunca de outro ciclo.
  IF p_cycle_code IS NOT NULL THEN
    v_cycle := substring(p_cycle_code from '^cycle_([0-9]{1,6})$')::int;
    IF v_cycle IS NOT NULL THEN
      SELECT w.is_current, w.window_start, w.window_end
      INTO v_is_current, v_start, v_end
      FROM public._cycle_window(v_cycle) w;
    END IF;
  END IF;

  RETURN QUERY
  SELECT bi.id, bi.title, bi.status,
         i.legacy_tribe_id AS tribe_id,
         pb.initiative_id,
         bi.baseline_date, bi.baseline_locked_at,
         bi.forecast_date, bi.due_date,
         bi.is_portfolio_item, bi.portfolio_kpi_refs,
         c.cycle_code,
         bi.updated_at
  FROM board_items bi
  JOIN project_boards pb ON pb.id = bi.board_id
  LEFT JOIN initiatives i ON i.id = pb.initiative_id
  LEFT JOIN public.cycles c ON c.cycle_code = 'cycle_' || bi.cycle::text
  WHERE bi.is_portfolio_item = true
    AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
    AND (p_status IS NULL OR bi.status = p_status)
    AND (p_cycle_code IS NULL OR public._in_cycle_view(bi.actual_completion_date, v_is_current, v_start, v_end))
    AND public.rls_can_see_initiative(pb.initiative_id)
  ORDER BY bi.due_date NULLS LAST, bi.updated_at DESC;
END $function$;

CREATE OR REPLACE FUNCTION public.audit_portfolio_flag_tag_gaps(
  p_include_non_tribe boolean DEFAULT false,
  p_dashboard_cycle integer DEFAULT NULL::integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_caller_id uuid;
  v_rows jsonb;
  v_by_initiative jsonb;
  v_summary jsonb;
  v_cycle integer;
  v_is_current boolean;
  v_start date;
  v_end date;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  -- #2565 2A: "fora do dashboard" passa a ser fora da visão do ciclo (regra (g)), NULL = corrente.
  SELECT w.cycle_number, w.is_current, w.window_start, w.window_end
  INTO v_cycle, v_is_current, v_start, v_end
  FROM public._cycle_window(p_dashboard_cycle) w;

  WITH scope AS (
    SELECT
      bi.id,
      bi.title,
      bi.status,
      bi.cycle,
      bi.baseline_date,
      bi.forecast_date,
      bi.actual_completion_date,
      coalesce(bi.is_portfolio_item, false) AS is_portfolio_item,
      pb.id   AS board_id,
      pb.board_name,
      i.id    AS initiative_id,
      i.title AS initiative_title,
      i.kind::text AS initiative_kind,
      i.legacy_tribe_id AS tribe_id,
      public.portfolio_suggest_item_type(bi.title, bi.tags) AS suggested_type,
      EXISTS (
        SELECT 1 FROM public.board_item_tag_assignments a
        JOIN public.tags g ON g.id = a.tag_id
        WHERE a.board_item_id = bi.id
          AND g.tier = 'system' AND g.domain = 'board_item'
          AND g.name <> 'entregavel_lider'
      ) AS has_type_tag,
      EXISTS (
        SELECT 1 FROM public.board_item_tag_assignments a
        JOIN public.tags g ON g.id = a.tag_id
        WHERE a.board_item_id = bi.id AND g.name = 'entregavel_lider'
      ) AS is_leader_deliverable
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    JOIN public.initiatives i ON i.id = pb.initiative_id
    WHERE bi.status <> 'archived'
      AND (p_include_non_tribe OR i.kind = 'research_tribe')
      -- Gate confidencial (ADR-0105 / #785). Hoje neutro: o gate de entrada e
      -- manage_platform e rls_can_see_initiative devolve true para o GP ("GP ve
      -- sempre"). Fica aqui para o dia em que o gate de entrada afrouxar -- e
      -- porque a regra 5 do CLAUDE.md nao abre excecao para reader SECDEF sobre
      -- tabela ligada a iniciativa.
      AND public.rls_can_see_initiative(i.id)
  ),
  gaps AS (
    SELECT jsonb_build_object(
      'gap_kind', 'missing_flag',
      'card_id', s.id, 'title', s.title, 'status', s.status, 'cycle', s.cycle,
      'board_id', s.board_id, 'board_name', s.board_name,
      'initiative_id', s.initiative_id, 'initiative_title', s.initiative_title,
      'initiative_kind', s.initiative_kind, 'tribe_id', s.tribe_id,
      'baseline_date', s.baseline_date, 'forecast_date', s.forecast_date,
      'actual_completion_date', s.actual_completion_date,
      'suggested_type', s.suggested_type,
      'is_leader_deliverable', s.is_leader_deliverable,
      'confidence', CASE
        WHEN s.baseline_date IS NOT NULL OR s.actual_completion_date IS NOT NULL THEN 'alta'
        WHEN s.forecast_date IS NOT NULL THEN 'media'
        ELSE 'baixa' END
    ) AS r
    FROM scope s
    WHERE NOT s.is_portfolio_item AND s.suggested_type IS NOT NULL

    UNION ALL

    SELECT jsonb_build_object(
      'gap_kind', 'missing_type_tag',
      'card_id', s.id, 'title', s.title, 'status', s.status, 'cycle', s.cycle,
      'board_id', s.board_id, 'board_name', s.board_name,
      'initiative_id', s.initiative_id, 'initiative_title', s.initiative_title,
      'initiative_kind', s.initiative_kind, 'tribe_id', s.tribe_id,
      'baseline_date', s.baseline_date, 'forecast_date', s.forecast_date,
      'actual_completion_date', s.actual_completion_date,
      'suggested_type', s.suggested_type,
      'is_leader_deliverable', s.is_leader_deliverable,
      'confidence', CASE WHEN s.suggested_type IS NOT NULL THEN 'alta' ELSE 'revisar' END
    ) AS r
    FROM scope s
    WHERE s.is_portfolio_item AND NOT s.has_type_tag
  ),
  rows_agg AS (
    SELECT jsonb_agg(g.r ORDER BY g.r->>'gap_kind', (g.r->>'tribe_id')::int NULLS LAST, g.r->>'title') AS v
    FROM gaps g
  ),
  init_agg AS (
    SELECT jsonb_agg(jsonb_build_object(
      'tribe_id', t.tribe_id, 'initiative_id', t.initiative_id,
      'initiative_title', t.initiative_title, 'initiative_kind', t.initiative_kind,
      'cards', t.cards, 'flagged', t.flagged,
      'missing_flag', t.missing_flag, 'missing_type_tag', t.missing_type_tag
    ) ORDER BY t.tribe_id NULLS LAST, t.initiative_title) AS v
    FROM (
      SELECT s.tribe_id, s.initiative_id, s.initiative_title, s.initiative_kind,
        count(*) AS cards,
        count(*) FILTER (WHERE s.is_portfolio_item) AS flagged,
        count(*) FILTER (WHERE NOT s.is_portfolio_item AND s.suggested_type IS NOT NULL) AS missing_flag,
        count(*) FILTER (WHERE s.is_portfolio_item AND NOT s.has_type_tag) AS missing_type_tag
      FROM scope s
      GROUP BY 1,2,3,4
    ) t
  ),
  sum_agg AS (
    SELECT jsonb_build_object(
      'cards_in_scope', count(*),
      'flagged', count(*) FILTER (WHERE s.is_portfolio_item),
      'missing_flag', count(*) FILTER (WHERE NOT s.is_portfolio_item AND s.suggested_type IS NOT NULL),
      'missing_flag_alta', count(*) FILTER (
        WHERE NOT s.is_portfolio_item AND s.suggested_type IS NOT NULL
          AND (s.baseline_date IS NOT NULL OR s.actual_completion_date IS NOT NULL)),
      'missing_type_tag', count(*) FILTER (WHERE s.is_portfolio_item AND NOT s.has_type_tag),
      'flagged_outside_dashboard_cycle', count(*) FILTER (
        WHERE s.is_portfolio_item
          AND public._in_cycle_view(s.actual_completion_date, v_is_current, v_start, v_end) IS NOT TRUE)
    ) AS v
    FROM scope s
  )
  SELECT rows_agg.v, init_agg.v, sum_agg.v
  INTO v_rows, v_by_initiative, v_summary
  FROM rows_agg, init_agg, sum_agg;

  RETURN jsonb_build_object(
    'generated_at', now(),
    'scope', CASE WHEN p_include_non_tribe THEN 'all_initiatives' ELSE 'research_tribe' END,
    'dashboard_cycle', COALESCE(v_cycle, p_dashboard_cycle),
    'summary', coalesce(v_summary, '{}'::jsonb),
    'by_initiative', coalesce(v_by_initiative, '[]'::jsonb),
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
END;
$fn$;
