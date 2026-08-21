-- Card de Jornada da Tribo — saúde calculada + reconciliador idempotente.
--
-- Contexto (medido em 2026-08-20, 110 reuniões de tribo nos últimos 90 dias):
-- link de reunião está em 93% dos casos, mas ATA em 24% e GRAVAÇÃO em 4,5%.
-- O problema não são 14 histórias diferentes — são 2 itens sistêmicos. Por isso o
-- card é um CHECKLIST DE BOA PRÁTICA, não uma lista de faltas: o líder vê a
-- jornada e o que falta para completá-la, não uma cobrança.
--
-- Duas decisões de desenho, ambas do GP (2026-08-20):
--
-- 1. ESTADO CALCULADO, NÃO ESCRITO. Um card escrito à mão vira mentira em dias —
--    na auditoria do #1900 duas coletas com 10 min de diferença já divergiram em
--    3 cards. Aqui `sync_tribe_journey_card()` é idempotente e reconcilia o card
--    contra o dado: o líder marca ✅ arrumando o dado, não clicando na atividade.
--    Consequência aceita: um check manual é sobrescrito no próximo sync.
--
-- 2. NENHUM DADO DE FREQUÊNCIA INDIVIDUAL. Frequência por pessoa num card que a
--    tribo inteira lê expõe dado pessoal a terceiros e é o item com maior chance
--    de ofender — vai para o painel do líder e para a conversa 1:1, não para cá.
--    Esta RPC não lê `attendance` de propósito.

-- ─── 0a. A heurística de tipo ignora os cards da própria automação ──────────
-- O card de jornada tem "checklist" no título, então `portfolio_suggest_item_type`
-- o classificaria como `ferramenta` — e, por não ser item de portfólio, ele
-- apareceria como falso "entregável sem flag" na auditoria do #1900 (e nos
-- contadores do Data sanity). O corte é feito aqui, no ponto único, em vez de
-- repetido em cada consumidor.
CREATE OR REPLACE FUNCTION public.portfolio_suggest_item_type(
  p_title text,
  p_tags text[] DEFAULT NULL
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $fn$
  SELECT CASE
    WHEN 'jornada_tribo' = ANY(COALESCE(p_tags, ARRAY[]::text[])) THEN NULL
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
$fn$;

-- ─── 0. Os 8 passos da jornada ──────────────────────────────────────────────
-- Cada item carrega a evidência no próprio texto, para o líder ver o gap sem
-- abrir relatório nenhum. `done` é DERIVADO — 80% de cobertura, exceto onde o
-- item é binário. Sem reunião registrada na janela, os itens de reunião ficam
-- 'sem_dados' em vez de falharem: ausência de dado não é o mesmo que descuido.
CREATE OR REPLACE FUNCTION public.tribe_journey_items(p_ev jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $fn$
  WITH n AS (
    SELECT
      (p_ev->>'reunioes_realizadas')::int        AS realizadas,
      (p_ev->>'reunioes_agendadas_30d')::int     AS agendadas_30d,
      (p_ev->>'com_link')::int                   AS com_link,
      (p_ev->>'com_gravacao')::int               AS com_gravacao,
      (p_ev->>'com_ata')::int                    AS com_ata,
      (p_ev->>'ata_com_acao')::int               AS ata_com_acao,
      (p_ev->>'cards')::int                      AS cards,
      (p_ev->>'cards_com_data')::int             AS com_data,
      (p_ev->>'cards_com_atividade_completa')::int AS com_ativ,
      (p_ev->>'entregavel_sem_flag')::int        AS sem_flag,
      (p_ev->>'portfolio_sem_tipo')::int         AS sem_tipo
    FROM (SELECT 1) _
  ),
  it AS (
    SELECT 1 AS pos, 'J1' AS key,
      'Próxima reunião da tribo já agendada' AS label,
      format('%s agendada(s) para os próximos 30 dias', n.agendadas_30d) AS evidencia,
      (n.agendadas_30d >= 1) AS done, false AS sem_dados FROM n
    UNION ALL SELECT 2, 'J2', 'Reunião realizada com link registrado',
      format('%s de %s reuniões', n.com_link, n.realizadas),
      (n.realizadas > 0 AND n.com_link::numeric / n.realizadas >= 0.8), (n.realizadas = 0) FROM n
    UNION ALL SELECT 3, 'J3', 'Reunião gravada com link da gravação',
      format('%s de %s reuniões', n.com_gravacao, n.realizadas),
      (n.realizadas > 0 AND n.com_gravacao::numeric / n.realizadas >= 0.8), (n.realizadas = 0) FROM n
    UNION ALL SELECT 4, 'J4', 'Ata publicada depois da reunião',
      format('%s de %s reuniões', n.com_ata, n.realizadas),
      (n.realizadas > 0 AND n.com_ata::numeric / n.realizadas >= 0.8), (n.realizadas = 0) FROM n
    UNION ALL SELECT 5, 'J5', 'Ata rende ação registrada (ata → card/atividade)',
      format('%s de %s atas', n.ata_com_acao, n.com_ata),
      (n.com_ata > 0 AND n.ata_com_acao::numeric / n.com_ata >= 0.8), (n.com_ata = 0) FROM n
    UNION ALL SELECT 6, 'J6', 'Card do ciclo tem data (base, previsão ou prazo)',
      format('%s de %s cards', n.com_data, n.cards),
      (n.cards > 0 AND n.com_data::numeric / n.cards >= 0.8), (n.cards = 0) FROM n
    UNION ALL SELECT 7, 'J7', 'Card tem atividade com responsável e data',
      format('%s de %s cards', n.com_ativ, n.cards),
      (n.cards > 0 AND n.com_ativ::numeric / n.cards >= 0.8), (n.cards = 0) FROM n
    UNION ALL SELECT 8, 'J8', 'Entregável marcado no portfólio e com tipo',
      format('%s entregável(is) sem marcar · %s no portfólio sem tipo', n.sem_flag, n.sem_tipo),
      (n.sem_flag = 0 AND n.sem_tipo = 0), (n.cards = 0) FROM n
  )
  SELECT jsonb_agg(jsonb_build_object(
    'key', it.key, 'pos', it.pos, 'label', it.label, 'evidencia', it.evidencia,
    'done', CASE WHEN it.sem_dados THEN false ELSE it.done END,
    'sem_dados', it.sem_dados,
    'text', format('[%s] %s — %s', it.key, it.label,
      CASE WHEN it.sem_dados THEN 'sem dados na janela' ELSE it.evidencia END)
  ) ORDER BY it.pos)
  FROM it;
$fn$;

COMMENT ON FUNCTION public.tribe_journey_items(jsonb) IS
  'Traduz a evidência de uma tribo nos 8 passos da jornada documentada. Determinística; o texto de cada passo já carrega a evidência.';

-- ─── 1. Saúde da jornada (read-only) ────────────────────────────────────────
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
  ),
  -- Reuniões da janela. `date <= hoje` = realizada; `> hoje` = agendada.
  reuniao AS (
    SELECT t.id AS initiative_id,
      count(*) FILTER (WHERE e.date <= CURRENT_DATE) AS realizadas,
      count(*) FILTER (WHERE e.date <= CURRENT_DATE AND e.meeting_link IS NOT NULL) AS com_link,
      count(*) FILTER (WHERE e.date <= CURRENT_DATE
        AND (e.recording_url IS NOT NULL OR e.youtube_url IS NOT NULL)) AS com_gravacao,
      count(*) FILTER (WHERE e.date <= CURRENT_DATE
        AND (e.minutes_text IS NOT NULL OR e.minutes_url IS NOT NULL)) AS com_ata,
      -- Ata publicada que rendeu ação registrada: é o sinal de que a reunião
      -- virou trabalho rastreável, e não só um registro morto.
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
  -- Cards do quadro da tribo. `journey_card` é excluído para o card não se auditar.
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
      -- Reaproveita a heurística do #1900: entregável reconhecido sem o flag.
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

COMMENT ON FUNCTION public.tribe_journey_health(uuid, integer) IS
  'Saúde da jornada documentada por tribo (reuniões/link/gravação/ata/ação, cards com data e atividade, entregáveis no portfólio). Read-only, manage_platform. NÃO lê frequência individual — por desenho.';

-- ─── 2. Reconciliador do card (idempotente) ─────────────────────────────────
-- Identidade do card = (board_id, marcador 'jornada_tribo' em board_items.tags).
-- NÃO usar `source_type`: é um domínio fechado (internal/external_partner/
-- external_event) que descreve a ORIGEM do trabalho — alargá-lo para carregar um
-- marcador de automação daria dois significados à mesma coluna. `tags` é texto
-- livre e é onde marcadores de máquina já convivem com os humanos.
-- Sem esse marcador o sync criaria um card novo a cada execução. As atividades
-- são casadas pelo prefixo
-- `[Jn]` no texto — `board_item_checklists` não tem chave estável, e o prefixo é
-- a chave mais barata que sobrevive à reescrita do rótulo e da evidência.
--
-- p_dry_run = true por padrão: quem chama precisa pedir a escrita de propósito.
CREATE OR REPLACE FUNCTION public.sync_tribe_journey_card(
  p_initiative_id uuid,
  p_dry_run boolean DEFAULT true,
  p_window_days integer DEFAULT 90
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_caller_id uuid;
  v_health jsonb;
  v_t jsonb;
  v_board_id uuid;
  v_leader_id uuid;
  v_card_id uuid;
  v_created boolean := false;
  v_item jsonb;
  v_existing uuid;
  v_pos smallint;
  v_desc text;
  v_done int := 0;
  v_total int := 0;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  v_health := public.tribe_journey_health(p_initiative_id, p_window_days);
  v_t := v_health->'tribos'->0;
  IF v_t IS NULL THEN
    RAISE EXCEPTION 'initiative_not_found_or_not_an_active_tribe: %', p_initiative_id;
  END IF;

  v_board_id := (v_t->>'board_id')::uuid;
  v_leader_id := (v_t->>'leader_id')::uuid;
  IF v_board_id IS NULL THEN
    RAISE EXCEPTION 'tribe_has_no_active_board: %', p_initiative_id;
  END IF;

  SELECT count(*) FILTER (WHERE (i->>'done')::boolean), count(*)
  INTO v_done, v_total
  FROM jsonb_array_elements(v_t->'itens') i;

  v_desc := format(
    E'Checklist da jornada documentada da tribo — **%s de %s passos completos**.\n\n'
    'Este card é **atualizado automaticamente** a partir dos dados da plataforma: '
    'cada passo é marcado quando o dado prova que ele foi cumprido. Não marque à mão — '
    'ao registrar a ata, o link da gravação ou a data no card, o passo fecha sozinho no '
    'próximo sync.\n\nJanela de análise: últimos %s dias. Frequência individual não entra '
    'aqui por desenho — isso é assunto do painel do líder e da conversa 1:1.\n\n'
    '_Última reconciliação: %s._',
    v_done, v_total, p_window_days, to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'));

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'dry_run', true, 'initiative_id', p_initiative_id,
      'tribe_name', v_t->>'tribe_name', 'board_id', v_board_id, 'leader_id', v_leader_id,
      'passos_completos', v_done, 'passos_total', v_total,
      'evidencia', v_t->'evidencia', 'itens', v_t->'itens', 'description_preview', v_desc);
  END IF;

  SELECT id INTO v_card_id FROM public.board_items
  WHERE board_id = v_board_id AND status <> 'archived'
    AND 'jornada_tribo' = ANY(COALESCE(tags, ARRAY[]::text[]))
  LIMIT 1;

  IF v_card_id IS NULL THEN
    INSERT INTO public.board_items (board_id, title, description, status, tags,
                                    assignee_id, created_by, position)
    VALUES (v_board_id,
            '🧭 Jornada documentada da tribo — checklist do ciclo',
            v_desc, 'in_progress', ARRAY['jornada_tribo'], v_caller_id, v_caller_id,
            COALESCE((SELECT max(position) + 1 FROM public.board_items WHERE board_id = v_board_id), 0))
    RETURNING id INTO v_card_id;
    v_created := true;
  ELSE
    UPDATE public.board_items
    SET description = v_desc, assignee_id = COALESCE(assignee_id, v_caller_id), updated_at = now()
    WHERE id = v_card_id;
  END IF;

  -- O líder entra como contribuidor: o dono do card é o GP (quem chama), e é o
  -- líder quem age. Idempotente pela UNIQUE (item_id, member_id, role).
  IF v_leader_id IS NOT NULL THEN
    INSERT INTO public.board_item_assignments (item_id, member_id, role, assigned_by)
    VALUES (v_card_id, v_leader_id, 'contributor', v_caller_id)
    ON CONFLICT (item_id, member_id, role) DO NOTHING;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(v_t->'itens')
  LOOP
    v_pos := (v_item->>'pos')::smallint;
    SELECT id INTO v_existing FROM public.board_item_checklists
    WHERE board_item_id = v_card_id AND text LIKE '[' || (v_item->>'key') || ']%'
    LIMIT 1;

    IF v_existing IS NULL THEN
      INSERT INTO public.board_item_checklists
        (board_item_id, text, is_completed, position, assigned_to, completed_at, assigned_by, assigned_at)
      VALUES (v_card_id, v_item->>'text', (v_item->>'done')::boolean, v_pos, v_leader_id,
              CASE WHEN (v_item->>'done')::boolean THEN now() END, v_caller_id, now());
    ELSE
      UPDATE public.board_item_checklists
      SET text = v_item->>'text',
          is_completed = (v_item->>'done')::boolean,
          position = v_pos,
          assigned_to = COALESCE(assigned_to, v_leader_id),
          completed_at = CASE WHEN (v_item->>'done')::boolean THEN COALESCE(completed_at, now()) END
      WHERE id = v_existing;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', false, 'card_id', v_card_id, 'created', v_created,
    'initiative_id', p_initiative_id, 'tribe_name', v_t->>'tribe_name',
    'leader_assigned', v_leader_id IS NOT NULL,
    'passos_completos', v_done, 'passos_total', v_total,
    'evidencia', v_t->'evidencia');
END;
$fn$;

COMMENT ON FUNCTION public.sync_tribe_journey_card(uuid, boolean, integer) IS
  'Cria/reconcilia o card de Jornada da Tribo e suas 8 atividades a partir de tribe_journey_health(). Idempotente por (board_id, marcador jornada_tribo em tags) e pelo prefixo [Jn] das atividades. p_dry_run=true por padrão.';

REVOKE ALL ON FUNCTION public.tribe_journey_items(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.tribe_journey_health(uuid, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_tribe_journey_card(uuid, boolean, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tribe_journey_items(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.tribe_journey_health(uuid, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.sync_tribe_journey_card(uuid, boolean, integer) TO authenticated, service_role;
