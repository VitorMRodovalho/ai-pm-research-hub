-- #1906 follow-up — a reconciliação da Jornada da Tribo passa a escrever só quando muda,
-- e a agenda vira diária.
--
-- Por que as duas coisas andam juntas. A #1906 mostrou que 53 dos 68 crons ativos não se
-- recuperam de uma falha de janela, e os 22 semanais são a fatia pior: perder a segunda
-- custa sete dias. O `tribe-journey-cards-weekly` nasceu ali dentro sem precisar —
-- medido: **0,26 s para as 12 tribos**. A agenda semanal não protegia trade-off nenhum.
--
-- Mas trocar para diária sem mexer na escrita criaria um defeito pior que o resolvido:
--
--   1. A `description` embutia `_Última reconciliação: DD/MM HH:MM_`, então TODA execução
--      reescrevia os 12 cards mesmo sem nada mudar. Diário faria o card piscar como
--      alterado todo dia, e treinaria o líder a ignorá-lo — o oposto do objetivo.
--   2. O `UPDATE` mencionava `assignee_id` no `SET`. `UPDATE OF` no Postgres dispara pelas
--      colunas MENCIONADAS, não pelas alteradas, então cada reconciliação acionava
--      `trg_board_item_deliverable_xp` 12 vezes à toa — num gatilho que é o epicentro do
--      #1881.
--
-- Correção: o carimbo de execução sai do card e fica no `admin_audit_log` (onde já estava),
-- a descrição passa a depender só da contagem de passos, e cada escrita é condicionada a
-- uma diferença real. Com isso a exposição a perda de janela cai de 7 dias para 1, e o
-- líder só vê o card mudar quando algo de fato mudou.

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
  v_changed boolean := false;
  v_item jsonb;
  v_existing uuid;
  v_txt_atual text;
  v_done_atual boolean;
  v_pos_atual smallint;
  v_desc_atual text;
  v_assignee_atual uuid;
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

  -- SEM carimbo de execução: ele vive no admin_audit_log. Assim a descrição só muda
  -- quando a contagem de passos muda, e a execução diária fica silenciosa.
  v_desc := format(
    E'Checklist da jornada documentada da tribo — **%s de %s passos completos**.\n\n'
    'Este card é **atualizado automaticamente** a partir dos dados da plataforma: '
    'cada passo é marcado quando o dado prova que ele foi cumprido. Não marque à mão — '
    'ao registrar a ata, o link da gravação ou a data no card, o passo fecha sozinho na '
    'próxima reconciliação.\n\nJanela de análise: últimos %s dias. Frequência individual '
    'não entra aqui por desenho — isso é assunto do painel do líder e da conversa 1:1.',
    v_done, v_total, p_window_days);

  SELECT id, description, assignee_id
  INTO v_card_id, v_desc_atual, v_assignee_atual
  FROM public.board_items
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
    v_changed := true;
  ELSE
    IF v_desc_atual IS DISTINCT FROM v_desc THEN
      UPDATE public.board_items
      SET description = v_desc, updated_at = now()
      WHERE id = v_card_id;
      v_changed := true;
    END IF;
    -- `assignee_id` só entra no SET quando está nulo: mencioná-lo dispara
    -- `trg_board_item_deliverable_xp` mesmo sem alterar valor.
    IF v_assignee_atual IS NULL THEN
      UPDATE public.board_items
      SET assignee_id = p_actor_id, updated_at = now()
      WHERE id = v_card_id;
      v_changed := true;
    END IF;
  END IF;

  IF v_leader_id IS NOT NULL THEN
    INSERT INTO public.board_item_assignments (item_id, member_id, role, assigned_by)
    VALUES (v_card_id, v_leader_id, 'contributor', p_actor_id)
    ON CONFLICT (item_id, member_id, role) DO NOTHING;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(v_t->'itens')
  LOOP
    v_pos := (v_item->>'pos')::smallint;
    SELECT id, text, is_completed, position
    INTO v_existing, v_txt_atual, v_done_atual, v_pos_atual
    FROM public.board_item_checklists
    WHERE board_item_id = v_card_id AND text LIKE '[' || (v_item->>'key') || ']%'
    LIMIT 1;

    IF v_existing IS NULL THEN
      INSERT INTO public.board_item_checklists
        (board_item_id, text, is_completed, position, assigned_to, completed_at, assigned_by, assigned_at)
      VALUES (v_card_id, v_item->>'text', (v_item->>'done')::boolean, v_pos, v_leader_id,
              CASE WHEN (v_item->>'done')::boolean THEN now() END, p_actor_id, now());
      v_changed := true;
    ELSIF v_txt_atual IS DISTINCT FROM (v_item->>'text')
       OR v_done_atual IS DISTINCT FROM (v_item->>'done')::boolean
       OR v_pos_atual IS DISTINCT FROM v_pos THEN
      UPDATE public.board_item_checklists
      SET text = v_item->>'text',
          is_completed = (v_item->>'done')::boolean,
          position = v_pos,
          assigned_to = COALESCE(assigned_to, v_leader_id),
          completed_at = CASE WHEN (v_item->>'done')::boolean THEN COALESCE(completed_at, now()) END
      WHERE id = v_existing;
      v_changed := true;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'card_id', v_card_id, 'created', v_created, 'changed', v_changed,
    'initiative_id', p_initiative_id, 'tribe_name', v_t->>'tribe_name',
    'tribe_id', v_t->>'tribe_id',
    'leader_assigned', v_leader_id IS NOT NULL,
    'passos_completos', v_done, 'passos_total', v_total);
END;
$fn$;

COMMENT ON FUNCTION public._sync_tribe_journey_card(uuid, uuid, integer) IS
  'Worker interno da reconciliação do card de jornada. Ator explícito, sem portão de sessão. Escreve SÓ quando há diferença real (#1906) — a descrição não carrega carimbo de execução e assignee_id não entra no SET quando já preenchido.';

-- O relatório do cron passa a distinguir "reconciliado" de "alterado". Sem isso a
-- execução diária vira ruído no `admin_audit_log` e some a informação que interessa:
-- em quantas tribos algo de fato mudou.
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
  v_alterados int := 0;
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
      IF (v_res->>'changed')::boolean THEN
        v_alterados := v_alterados + 1;
        v_detalhe := v_detalhe || jsonb_build_object(
          'tribe_id', r.legacy_tribe_id,
          'passos_completos', v_res->'passos_completos',
          'passos_total', v_res->'passos_total');
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_erros := v_erros + 1;
      v_detalhe := v_detalhe || jsonb_build_object(
        'tribe_id', r.legacy_tribe_id, 'erro', SQLERRM);
    END;
  END LOOP;

  -- Só registra no audit log quando houve mudança ou erro. Execução diária sem
  -- novidade não deve deixar rastro — senão o log vira ruído e a leitura se perde.
  IF v_alterados > 0 OR v_erros > 0 OR v_sem_card > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'tribe_journey.cards_reconciled', 'system', NULL,
      jsonb_build_object('reconciliados', v_ok, 'alterados', v_alterados,
                         'erros', v_erros, 'sem_card', v_sem_card),
      jsonb_build_object('detalhe', v_detalhe, 'sem_card', v_sem_card_lista)
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'reconciliados', v_ok, 'alterados', v_alterados,
    'erros', v_erros, 'sem_card', v_sem_card,
    'detalhe', v_detalhe, 'sem_card_lista', v_sem_card_lista);
END;
$fn$;

COMMENT ON FUNCTION public.sync_tribe_journey_cards_cron() IS
  'Reconcilia diariamente os cards de Jornada da Tribo já existentes, reusando o dono registrado em cada card. Escreve só quando há diferença (#1906) e só loga em admin_audit_log quando houve mudança, erro ou tribo sem card.';

-- Agenda diária, e o job MUDA DE NOME. `cron.schedule` faz upsert por NOME: manter
-- `...-weekly` rodando todo dia seria uma mentira no catálogo, e criar o nome novo sem
-- remover o antigo deixaria DOIS jobs disparando a mesma reconciliação.
-- `cron.unschedule` levanta erro se o job não existir, daí o guard.
DO $unsched$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'tribe-journey-cards-weekly') THEN
    PERFORM cron.unschedule('tribe-journey-cards-weekly');
  END IF;
END
$unsched$;

-- 06:20 UTC = 03:20 em São Paulo, antes do expediente. Minuto deslocado de propósito:
-- 06:00 e 09:00 em ponto já têm vizinhos, e o pool é compartilhado com tráfego real (#1844).
SELECT cron.schedule(
  'tribe-journey-cards-daily',
  '20 6 * * *',
  $cron$SELECT public.sync_tribe_journey_cards_cron();$cron$
);
