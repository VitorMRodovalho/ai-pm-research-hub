-- Portfolio flag/tag gap audit.
--
-- Motivação: os quadros das tribos acumulam cards que são entregáveis reais mas
-- (a) não têm `board_items.is_portfolio_item = true`, logo não entram em
-- `get_portfolio_dashboard()`, e/ou (b) estão marcados como item de portfólio mas
-- sem nenhuma tag de tipo (tier='system', domain='board_item'), o que deixa o
-- filtro "Todos os Tipos" do /admin/portfolio cego para eles.
--
-- Esta migration entrega:
--   1. public.portfolio_suggest_item_type(text, text[]) — heurística determinística
--      que sugere uma das 7 tags de tipo a partir do título + tags legadas.
--   2. public.audit_portfolio_flag_tag_gaps(boolean, integer) — RPC SECDEF
--      (manage_platform) com o drill-down dos dois gaps + contadores.
--   3. admin_run_portfolio_data_sanity() ganha os contadores dos dois gaps,
--      reaproveitando a mesma heurística (uma única fonte de verdade).
--
-- Nada aqui escreve em board_items: o output é sugestão para decisão do GP/líder,
-- nunca auto-aplicação (a tipificação do entregável é conteúdo do líder da tribo).

-- ─── 1. Heurística de tipo ──────────────────────────────────────────────────
-- Calibrada contra as tags de tipo já aplicadas por humanos nos quadros das
-- tribos (2026-08-20): 30 de 31 cards tipados concordam com a sugestão. A ordem
-- dos ramos é significativa — `ferramenta` vem antes de `workshop_artifact`
-- para que "Toolkit ... — Gate B" não seja capturado por "workshop".
-- Sem dependência de unaccent: o fold de acentos é feito com translate().
CREATE OR REPLACE FUNCTION public.portfolio_suggest_item_type(
  p_title text,
  p_tags text[] DEFAULT NULL
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN hay ~ '\y(webinar|webnair|webnar|webinario|palestra|live)\y' THEN 'webinar'
    WHEN hay ~ '\y(toolkit|checklist|guia|guias|template|ferramenta|ferramentas|planilha|questionario)\y'
      OR hay ~ 'landing page' THEN 'ferramenta'
    WHEN hay ~ '\y(workshop|treinamento|curso|bootcamp)\y'
      OR hay ~ 'mesa redonda' THEN 'workshop_artifact'
    WHEN hay ~ '\y(artigo|artigos|ebook|cartilha|newsletter|paper|whitepaper|relatorio|report|podcast|infografico|pilula|pilulas)\y'
      OR hay ~ '(e-book|publicac|submiss)' THEN 'publicacao'
    WHEN hay ~ '\y(framework|matriz|taxonomia|playbook|protocolo|manual|rubrica|rubricas|metodologia|arquitetura|arquiteturas)\y'
      OR hay ~ 'modelo de' THEN 'framework'
    WHEN hay ~ '\y(poc|prototipo|mvp|plataforma)\y'
      OR hay ~ '(prova de conceito|simulac|vibe coding)' THEN 'poc'
    WHEN hay ~ '\y(pesquisa|survey|levantamento|estudo|analise|benchmark|curadoria|diagnostico|sintese|formulario)\y'
      OR hay ~ 'revisao de literatura' THEN 'pesquisa'
    ELSE NULL
  END
  FROM (
    SELECT translate(
      lower(coalesce(p_title, '') || ' ' || coalesce(array_to_string(p_tags, ' '), '')),
      'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'
    ) AS hay
  ) s;
$$;

COMMENT ON FUNCTION public.portfolio_suggest_item_type(text, text[]) IS
  'Sugere uma tag de tipo (tier=system, domain=board_item) para um card a partir do título + tags legadas. Determinística e apenas consultiva — não escreve nada.';

-- ─── 2. Drill-down dos gaps ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.audit_portfolio_flag_tag_gaps(
  p_include_non_tribe boolean DEFAULT false,
  p_dashboard_cycle integer DEFAULT 3
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  ),
  -- gap A: entregavel sem flag de portfolio.
  -- Confianca pela evidencia de que o card ja e tratado como entregavel:
  --   alta  = data-base pactuada ou entrega registrada
  --   media = so previsao (forecast)
  --   baixa = nenhuma data, apenas o titulo sugere artefato
  -- gap B: marcado como portfolio, porem sem tag de tipo.
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
      -- Flagged porem fora do ciclo que o /admin/portfolio consulta: invisivel
      -- no dashboard mesmo com o flag correto.
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
$$;

COMMENT ON FUNCTION public.audit_portfolio_flag_tag_gaps(boolean, integer) IS
  'Audita cards de quadros de iniciativa que deveriam entrar no portfólio (sem is_portfolio_item) ou que estão no portfólio sem tag de tipo. Read-only, gated por manage_platform.';

REVOKE ALL ON FUNCTION public.audit_portfolio_flag_tag_gaps(boolean, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.audit_portfolio_flag_tag_gaps(boolean, integer) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.portfolio_suggest_item_type(text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.portfolio_suggest_item_type(text, text[]) TO authenticated, service_role;

-- ─── 3. Sanity check do /admin/portfolio ganha os dois contadores ───────────
CREATE OR REPLACE FUNCTION public.admin_run_portfolio_data_sanity()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_summary jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  v_summary := jsonb_build_object(
    'orphan_items', (SELECT count(*) FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      WHERE pb.id IS NULL),
    'items_in_inactive_board', (SELECT count(*) FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      WHERE pb.is_active = false AND bi.status <> 'archived'),
    'global_with_tribe_id', (SELECT count(*) FROM public.project_boards
      WHERE board_scope = 'global' AND initiative_id IS NOT NULL),
    'tribe_without_tribe_id', (SELECT count(*) FROM public.project_boards
      WHERE board_scope = 'tribe' AND initiative_id IS NULL),
    -- Cards de tribo que a heurística reconhece como entregável mas que não
    -- estão marcados como item de portfólio (invisíveis no /admin/portfolio).
    'tribe_cards_missing_portfolio_flag', (
      SELECT count(*) FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE i.kind = 'research_tribe' AND bi.status <> 'archived'
        AND coalesce(bi.is_portfolio_item, false) = false
        AND public.portfolio_suggest_item_type(bi.title, bi.tags) IS NOT NULL),
    -- Itens de portfólio sem tag de tipo: entram na contagem, mas o filtro
    -- "Todos os Tipos" do dashboard não os enxerga.
    'tribe_portfolio_items_missing_type_tag', (
      SELECT count(*) FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE i.kind = 'research_tribe' AND bi.status <> 'archived'
        AND bi.is_portfolio_item = true
        AND NOT EXISTS (
          SELECT 1 FROM public.board_item_tag_assignments a
          JOIN public.tags g ON g.id = a.tag_id
          WHERE a.board_item_id = bi.id
            AND g.tier = 'system' AND g.domain = 'board_item'
            AND g.name <> 'entregavel_lider'))
  );

  INSERT INTO public.portfolio_data_sanity_runs(run_by, summary)
  VALUES (v_caller_id, v_summary);

  RETURN jsonb_build_object('success', true, 'summary', v_summary);
END;
$$;
