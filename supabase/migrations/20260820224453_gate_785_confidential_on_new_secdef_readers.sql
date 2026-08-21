-- #785 / ADR-0105 - os dois readers SECDEF novos passam a aplicar o gate confidencial.
--
-- `audit_portfolio_flag_tag_gaps` (#1900) e `tribe_journey_health` leem board_items /
-- events atraves de `initiatives`, e o guard
-- `tests/contracts/785-secdef-reader-confidential-gate.test.mjs` os acusou como
-- readers sem gate. O gate de entrada `manage_platform` NAO basta: a regra 5 do
-- CLAUDE.md exige `rls_can_see_initiative()` em qualquer reader SECDEF sobre tabela
-- ligada a iniciativa, e o allowlist do guard e para excecoes justificadas -- nao e
-- o caminho quando o gate simplesmente cabe.
--
-- Neutro em comportamento hoje: `rls_can_see_initiative` termina em
-- `rls_can('manage_platform')` ("decisao PM #1: GP ve sempre"), entao o GP continua
-- vendo tudo. O que muda e o dia em que o gate de entrada afrouxar -- ai a iniciativa
-- confidencial continua fora, em vez de vazar por uma RPC de auditoria.
--
-- `sync_tribe_journey_card` nao entra aqui: e writer (o guard filtra `!is_writer`) e
-- le o mundo atraves de `tribe_journey_health`, que agora esta gated.

CREATE OR REPLACE FUNCTION public.audit_portfolio_flag_tag_gaps(
  p_include_non_tribe boolean DEFAULT false,
  p_dashboard_cycle integer DEFAULT 3
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
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

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
        WHERE s.is_portfolio_item AND s.cycle IS DISTINCT FROM p_dashboard_cycle)
    ) AS v
    FROM scope s
  )
  SELECT rows_agg.v, init_agg.v, sum_agg.v
  INTO v_rows, v_by_initiative, v_summary
  FROM rows_agg, init_agg, sum_agg;

  RETURN jsonb_build_object(
    'generated_at', now(),
    'scope', CASE WHEN p_include_non_tribe THEN 'all_initiatives' ELSE 'research_tribe' END,
    'dashboard_cycle', p_dashboard_cycle,
    'summary', coalesce(v_summary, '{}'::jsonb),
    'by_initiative', coalesce(v_by_initiative, '[]'::jsonb),
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.tribe_journey_health(
  p_initiative_id uuid DEFAULT NULL,
  p_window_days integer DEFAULT 90
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_caller_id uuid;
  v_rows jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  WITH tribo AS (
    SELECT i.id, i.title, i.legacy_tribe_id,
      (SELECT m.id FROM public.engagements e
       JOIN public.members m ON m.person_id = e.person_id
       WHERE e.initiative_id = i.id AND e.status = 'active' AND e.role = 'leader'
       ORDER BY e.start_date DESC NULLS LAST LIMIT 1) AS leader_id,
      (SELECT pb.id FROM public.project_boards pb
       WHERE pb.initiative_id = i.id AND pb.is_active = true
       ORDER BY pb.created_at LIMIT 1) AS board_id
    FROM public.initiatives i
    WHERE i.kind = 'research_tribe' AND i.status = 'active'
      AND (p_initiative_id IS NULL OR i.id = p_initiative_id)
      -- Gate confidencial (ADR-0105 / #785) -- ver nota em audit_portfolio_flag_tag_gaps.
      AND public.rls_can_see_initiative(i.id)
  ),
  reuniao AS (
    SELECT t.id AS initiative_id,
      count(*) FILTER (WHERE e.date <= CURRENT_DATE) AS realizadas,
      count(*) FILTER (WHERE e.date <= CURRENT_DATE AND e.meeting_link IS NOT NULL) AS com_link,
      count(*) FILTER (WHERE e.date <= CURRENT_DATE
        AND (e.recording_url IS NOT NULL OR e.youtube_url IS NOT NULL)) AS com_gravacao,
      count(*) FILTER (WHERE e.date <= CURRENT_DATE
        AND (e.minutes_text IS NOT NULL OR e.minutes_url IS NOT NULL)) AS com_ata,
      count(*) FILTER (WHERE e.date <= CURRENT_DATE
        AND (e.minutes_text IS NOT NULL OR e.minutes_url IS NOT NULL)
        AND EXISTS (SELECT 1 FROM public.meeting_action_items a WHERE a.event_id = e.id)) AS ata_com_acao,
      count(*) FILTER (WHERE e.date > CURRENT_DATE) AS agendadas,
      count(*) FILTER (WHERE e.date > CURRENT_DATE AND e.date <= CURRENT_DATE + 30) AS agendadas_30d
    FROM tribo t
    JOIN public.events e ON e.initiative_id = t.id
    WHERE e.date >= CURRENT_DATE - p_window_days
      AND COALESCE(e.status, '') <> 'cancelled'
    GROUP BY t.id
  ),
  card AS (
    SELECT t.id AS initiative_id,
      count(*) AS total,
      count(*) FILTER (WHERE bi.baseline_date IS NOT NULL OR bi.forecast_date IS NOT NULL
        OR bi.due_date IS NOT NULL) AS com_data,
      count(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM public.board_item_checklists k WHERE k.board_item_id = bi.id)) AS com_atividade,
      count(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM public.board_item_checklists k
        WHERE k.board_item_id = bi.id AND k.assigned_to IS NOT NULL AND k.target_date IS NOT NULL)
      ) AS com_atividade_completa,
      count(*) FILTER (WHERE COALESCE(bi.is_portfolio_item, false) = false
        AND public.portfolio_suggest_item_type(bi.title, bi.tags) IS NOT NULL) AS entregavel_sem_flag,
      count(*) FILTER (WHERE bi.is_portfolio_item = true) AS no_portfolio,
      count(*) FILTER (WHERE bi.is_portfolio_item = true AND NOT EXISTS (
        SELECT 1 FROM public.board_item_tag_assignments a
        JOIN public.tags g ON g.id = a.tag_id
        WHERE a.board_item_id = bi.id AND g.tier = 'system' AND g.domain = 'board_item'
          AND g.name <> 'entregavel_lider')) AS portfolio_sem_tipo
    FROM tribo t
    JOIN public.board_items bi ON bi.board_id = t.board_id
    WHERE bi.status <> 'archived'
      AND NOT ('jornada_tribo' = ANY(COALESCE(bi.tags, ARRAY[]::text[])))
    GROUP BY t.id
  )
  SELECT jsonb_agg(jsonb_build_object(
    'initiative_id', t.id,
    'tribe_id', t.legacy_tribe_id,
    'tribe_name', t.title,
    'leader_id', t.leader_id,
    'board_id', t.board_id,
    'window_days', p_window_days,
    'evidencia', jsonb_build_object(
      'reunioes_realizadas', COALESCE(r.realizadas, 0),
      'reunioes_agendadas_30d', COALESCE(r.agendadas_30d, 0),
      'com_link', COALESCE(r.com_link, 0),
      'com_gravacao', COALESCE(r.com_gravacao, 0),
      'com_ata', COALESCE(r.com_ata, 0),
      'ata_com_acao', COALESCE(r.ata_com_acao, 0),
      'cards', COALESCE(c.total, 0),
      'cards_com_data', COALESCE(c.com_data, 0),
      'cards_com_atividade', COALESCE(c.com_atividade, 0),
      'cards_com_atividade_completa', COALESCE(c.com_atividade_completa, 0),
      'entregavel_sem_flag', COALESCE(c.entregavel_sem_flag, 0),
      'no_portfolio', COALESCE(c.no_portfolio, 0),
      'portfolio_sem_tipo', COALESCE(c.portfolio_sem_tipo, 0)
    ),
    'itens', public.tribe_journey_items(jsonb_build_object(
      'reunioes_realizadas', COALESCE(r.realizadas, 0),
      'reunioes_agendadas_30d', COALESCE(r.agendadas_30d, 0),
      'com_link', COALESCE(r.com_link, 0),
      'com_gravacao', COALESCE(r.com_gravacao, 0),
      'com_ata', COALESCE(r.com_ata, 0),
      'ata_com_acao', COALESCE(r.ata_com_acao, 0),
      'cards', COALESCE(c.total, 0),
      'cards_com_data', COALESCE(c.com_data, 0),
      'cards_com_atividade_completa', COALESCE(c.com_atividade_completa, 0),
      'entregavel_sem_flag', COALESCE(c.entregavel_sem_flag, 0),
      'portfolio_sem_tipo', COALESCE(c.portfolio_sem_tipo, 0)))
  ) ORDER BY t.legacy_tribe_id NULLS LAST)
  INTO v_rows
  FROM tribo t
  LEFT JOIN reuniao r ON r.initiative_id = t.id
  LEFT JOIN card c ON c.initiative_id = t.id;

  RETURN jsonb_build_object(
    'generated_at', now(),
    'window_days', p_window_days,
    'tribos', COALESCE(v_rows, '[]'::jsonb)
  );
END;
$fn$;
