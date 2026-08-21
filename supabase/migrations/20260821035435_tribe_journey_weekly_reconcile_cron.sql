-- Reconciliação semanal do card de Jornada da Tribo.
--
-- O card só funciona se o estado for CALCULADO. Sem reconciliação periódica ele
-- congela no retrato do dia em que foi criado e vira exatamente o que a decisão
-- do GP (2026-08-20) descartou: uma lista estática que envelhece e passa a
-- cobrar coisa já resolvida.
--
-- Problema a resolver: `tribe_journey_health` e `sync_tribe_journey_card` são
-- gated por `auth.uid()` + manage_platform. O pg_cron não tem sessão, então não
-- pode chamá-las. O padrão do repo (ver `_data_retention_sweep` +
-- `_data_retention_sweep_cron`) é separar um worker interno sem portão de um
-- wrapper público com portão. É o que esta migration faz, sem duplicar lógica.
--
-- Decisão de governança: o cron **só reconcilia card que já existe**. Criar o
-- card de uma tribo nova continua sendo ato deliberado do GP, porque o dono do
-- card é uma pessoa e escolher essa pessoa não é decisão de rotina. Tribo ativa
-- sem card entra no relatório como `sem_card`, para ficar visível em vez de ser
-- silenciosamente adotada por um dono arbitrário.

-- ─── 1. Worker interno de saúde (sem portão) ────────────────────────────────
CREATE OR REPLACE FUNCTION public._tribe_journey_health_data(
  p_initiative_id uuid DEFAULT NULL,
  p_window_days integer DEFAULT 90
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_rows jsonb;
BEGIN
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
      -- Gate confidencial (ADR-0105 / #785). Para tribo sempre resolve true; fica
      -- porque a regra 5 do CLAUDE.md não abre exceção para leitura sobre tabela
      -- ligada a iniciativa, e este worker é chamado por caminho sem sessão.
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

COMMENT ON FUNCTION public._tribe_journey_health_data(uuid, integer) IS
  'Worker interno da saúde da jornada, SEM portão de sessão — existe para o caminho do pg_cron, que não tem auth.uid(). O portão público vive em tribe_journey_health().';

REVOKE ALL ON FUNCTION public._tribe_journey_health_data(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._tribe_journey_health_data(uuid, integer) TO service_role;

-- ─── 2. O leitor público passa a delegar (portão intacto) ───────────────────
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
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  RETURN public._tribe_journey_health_data(p_initiative_id, p_window_days);
END;
$fn$;

-- ─── 3. Worker interno de reconciliação (ator explícito) ────────────────────
-- Sem portão de sessão, com o ator passado de fora. Quem chama é responsável por
-- provar autoridade: o wrapper público (portão manage_platform) ou o cron (que
-- só reusa o dono já registrado no card).
CREATE OR REPLACE FUNCTION public._sync_tribe_journey_card(
  p_initiative_id uuid,
  p_actor_id uuid,
  p_window_days integer DEFAULT 90
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
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
  IF p_actor_id IS NULL THEN RAISE EXCEPTION 'actor_required'; END IF;

  v_health := public._tribe_journey_health_data(p_initiative_id, p_window_days);
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

  SELECT id INTO v_card_id FROM public.board_items
  WHERE board_id = v_board_id AND status <> 'archived'
    AND 'jornada_tribo' = ANY(COALESCE(tags, ARRAY[]::text[]))
  LIMIT 1;

  IF v_card_id IS NULL THEN
    INSERT INTO public.board_items (board_id, title, description, status, tags,
                                    assignee_id, created_by, position)
    VALUES (v_board_id,
            '🧭 Jornada documentada da tribo — checklist do ciclo',
            v_desc, 'in_progress', ARRAY['jornada_tribo'], p_actor_id, p_actor_id,
            COALESCE((SELECT max(position) + 1 FROM public.board_items WHERE board_id = v_board_id), 0))
    RETURNING id INTO v_card_id;
    v_created := true;
  ELSE
    UPDATE public.board_items
    SET description = v_desc, assignee_id = COALESCE(assignee_id, p_actor_id), updated_at = now()
    WHERE id = v_card_id;
  END IF;

  -- O líder entra como contribuidor: o dono do card é o GP, e é o líder quem age.
  IF v_leader_id IS NOT NULL THEN
    INSERT INTO public.board_item_assignments (item_id, member_id, role, assigned_by)
    VALUES (v_card_id, v_leader_id, 'contributor', p_actor_id)
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
              CASE WHEN (v_item->>'done')::boolean THEN now() END, p_actor_id, now());
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
    'card_id', v_card_id, 'created', v_created,
    'initiative_id', p_initiative_id, 'tribe_name', v_t->>'tribe_name',
    'tribe_id', v_t->>'tribe_id',
    'leader_assigned', v_leader_id IS NOT NULL,
    'passos_completos', v_done, 'passos_total', v_total);
END;
$fn$;

COMMENT ON FUNCTION public._sync_tribe_journey_card(uuid, uuid, integer) IS
  'Worker interno da reconciliação do card de jornada. Ator explícito, sem portão de sessão — a autoridade é provada por quem chama (wrapper público ou cron).';

REVOKE ALL ON FUNCTION public._sync_tribe_journey_card(uuid, uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._sync_tribe_journey_card(uuid, uuid, integer) TO service_role;

-- ─── 4. O escritor público passa a delegar (portão intacto) ─────────────────
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
  v_t jsonb;
  v_done int := 0;
  v_total int := 0;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  IF p_dry_run THEN
    v_t := (public._tribe_journey_health_data(p_initiative_id, p_window_days))->'tribos'->0;
    IF v_t IS NULL THEN
      RAISE EXCEPTION 'initiative_not_found_or_not_an_active_tribe: %', p_initiative_id;
    END IF;
    SELECT count(*) FILTER (WHERE (i->>'done')::boolean), count(*)
    INTO v_done, v_total FROM jsonb_array_elements(v_t->'itens') i;
    RETURN jsonb_build_object(
      'dry_run', true, 'initiative_id', p_initiative_id,
      'tribe_name', v_t->>'tribe_name', 'board_id', v_t->>'board_id',
      'leader_id', v_t->>'leader_id',
      'passos_completos', v_done, 'passos_total', v_total,
      'evidencia', v_t->'evidencia', 'itens', v_t->'itens');
  END IF;

  RETURN jsonb_set(
    public._sync_tribe_journey_card(p_initiative_id, v_caller_id, p_window_days),
    '{dry_run}', 'false'::jsonb, true);
END;
$fn$;

-- ─── 5. Entrada do cron ─────────────────────────────────────────────────────
-- Só reconcilia card que JÁ existe, e reusa o dono registrado nele. Tribo ativa
-- sem card entra no relatório como `sem_card` em vez de ganhar um dono arbitrário
-- — escolher a pessoa dona do card não é decisão de rotina.
CREATE OR REPLACE FUNCTION public.sync_tribe_journey_cards_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  r record;
  v_res jsonb;
  v_ok int := 0;
  v_erros int := 0;
  v_sem_card int := 0;
  v_detalhe jsonb := '[]'::jsonb;
  v_sem_card_lista jsonb := '[]'::jsonb;
BEGIN
  FOR r IN
    SELECT i.id AS initiative_id, i.legacy_tribe_id, i.title,
           bi.id AS card_id, bi.assignee_id, bi.created_by
    FROM public.initiatives i
    JOIN public.project_boards pb ON pb.initiative_id = i.id AND pb.is_active = true
    LEFT JOIN public.board_items bi
      ON bi.board_id = pb.id AND bi.status <> 'archived'
     AND 'jornada_tribo' = ANY(COALESCE(bi.tags, ARRAY[]::text[]))
    WHERE i.kind = 'research_tribe' AND i.status = 'active'
    ORDER BY i.legacy_tribe_id NULLS LAST
  LOOP
    IF r.card_id IS NULL THEN
      v_sem_card := v_sem_card + 1;
      v_sem_card_lista := v_sem_card_lista || jsonb_build_object(
        'tribe_id', r.legacy_tribe_id, 'tribe_name', r.title,
        'initiative_id', r.initiative_id);
      CONTINUE;
    END IF;

    -- Dono do card é a autoridade herdada. Sem dono registrado, não inventa.
    IF COALESCE(r.assignee_id, r.created_by) IS NULL THEN
      v_erros := v_erros + 1;
      v_detalhe := v_detalhe || jsonb_build_object(
        'tribe_id', r.legacy_tribe_id, 'erro', 'card sem assignee e sem created_by');
      CONTINUE;
    END IF;

    BEGIN
      v_res := public._sync_tribe_journey_card(
        r.initiative_id, COALESCE(r.assignee_id, r.created_by), 90);
      v_ok := v_ok + 1;
      v_detalhe := v_detalhe || jsonb_build_object(
        'tribe_id', r.legacy_tribe_id,
        'passos_completos', v_res->'passos_completos',
        'passos_total', v_res->'passos_total');
    EXCEPTION WHEN OTHERS THEN
      -- Uma tribo com dado ruim não pode derrubar a reconciliação das outras.
      v_erros := v_erros + 1;
      v_detalhe := v_detalhe || jsonb_build_object(
        'tribe_id', r.legacy_tribe_id, 'erro', SQLERRM);
    END;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'tribe_journey.cards_reconciled', 'system', NULL,
    jsonb_build_object('reconciliados', v_ok, 'erros', v_erros, 'sem_card', v_sem_card),
    jsonb_build_object('detalhe', v_detalhe, 'sem_card', v_sem_card_lista)
  );

  RETURN jsonb_build_object(
    'success', true, 'reconciliados', v_ok, 'erros', v_erros,
    'sem_card', v_sem_card, 'detalhe', v_detalhe, 'sem_card_lista', v_sem_card_lista);
END;
$fn$;

COMMENT ON FUNCTION public.sync_tribe_journey_cards_cron() IS
  'Reconcilia semanalmente os cards de Jornada da Tribo já existentes, reusando o dono registrado em cada card. Não cria card novo — tribo sem card sai no relatório. Loga em admin_audit_log com actor_id NULL (sistema).';

REVOKE ALL ON FUNCTION public.sync_tribe_journey_cards_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sync_tribe_journey_cards_cron() TO service_role;

-- ─── 6. Agendamento ─────────────────────────────────────────────────────────
-- Segundas 06:20 UTC = 03:20 em São Paulo. Antes do expediente, para o líder abrir
-- a semana com o card já fresco. Minuto deslocado de propósito: 06:00 e 09:00 em
-- ponto já têm vizinhos (`audit-drive-offboarding-weekly` às 05:00,
-- `auto-promote-eligible-leads-daily` às 09:00), e o pool do banco é compartilhado
-- com o tráfego real (#1844).
-- cron.schedule(name, ...) faz upsert por nome, então é idempotente.
SELECT cron.schedule(
  'tribe-journey-cards-weekly',
  '20 6 * * 1',
  $cron$SELECT public.sync_tribe_journey_cards_cron();$cron$
);
