-- #1880 - o trigger de XP de entregavel vigia apenas `status`, mas a elegibilidade
-- depende de CINCO colunas. Virar qualquer uma das outras quatro num card que JA esta
-- `done` cria um card elegivel que nunca sera pago, porque o unico gatilho e a mudanca
-- de status e ela ja aconteceu no passado.
--
-- Foi o que derrubou o `validate` (required) em 19/08: um card virou `done` em 16/08 sem
-- ser item de portfolio (o trigger corretamente NAO pagou) e recebeu `portfolio_flag_changed`
-- em 19/08 22:19, entrando no conjunto elegivel do contrato #1147 sem nada disparar.
--
-- Esta migration NAO muda o corpo da funcao (as cinco condicoes seguem identicas). Ela so
-- amplia a clausula UPDATE OF para as colunas do predicado que podem virar depois do status.
-- A idempotencia de `_grant_auto_xp` (SELECT ... WHERE ref_id = p_ref_id AND category = p_slug
-- AND member_id = p_recipient_id) protege contra pagamento duplo quando mais de uma coluna
-- vigiada mudar na mesma transacao.
--
-- `is_mirror` NAO entra: um card que deixa de ser espelho e caso de correcao manual, e
-- inclui-lo faria o trigger reavaliar cards importados em lote. Fica registrado como limite
-- conhecido, nao como esquecimento.

DROP TRIGGER IF EXISTS trg_board_item_deliverable_xp ON public.board_items;

CREATE TRIGGER trg_board_item_deliverable_xp
AFTER INSERT OR UPDATE OF status, is_portfolio_item, assignee_id ON public.board_items
FOR EACH ROW EXECUTE FUNCTION public.trg_board_item_deliverable_xp();

COMMENT ON TRIGGER trg_board_item_deliverable_xp ON public.board_items IS
  '#1880: vigia TODAS as colunas do predicado de elegibilidade que podem virar depois do status '
  '(status, is_portfolio_item, assignee_id). Vigiar so `status` deixava cards elegiveis sem pagar '
  'quando a flag de portfolio ou o assignee eram definidos num card ja done, e derrubava o '
  'contrato #1147 (validate, required). Idempotencia fica em _grant_auto_xp.';

-- ---------------------------------------------------------------------------
-- Reparo das linhas ja elegiveis e nao pagas.
--
-- Com o trigger ja ampliado acima, o reparo e um TOQUE, nao um INSERT: listar
-- `is_portfolio_item` no SET faz o `UPDATE OF` disparar mesmo com valor identico, e o
-- proprio trigger recalcula `on_time` a partir da linha (due_date/baseline_date vs
-- actual_completion_date). Nao ha reimplementacao da regra de pontuacao aqui, e
-- `_grant_auto_xp` e idempotente, entao rodar de novo nao paga em dobro.
--
-- Efeito colateral aceito e declarado: `updated_at` das linhas tocadas avanca (via
-- trg_board_items_updated). O `granted_by` fica NULL, que em `_grant_auto_xp` significa
-- sistema, o que e a leitura correta para um reparo.
--
-- O predicado abaixo e o MESMO do contrato #1147, de proposito: o que o teste considera
-- elegivel e o que este bloco repara.

UPDATE public.board_items bi
   SET is_portfolio_item = bi.is_portfolio_item
  FROM public.project_boards pb
 WHERE pb.id = bi.board_id
   AND pb.board_scope = 'tribe'
   AND bi.status = 'done'
   AND bi.is_portfolio_item IS TRUE
   AND bi.assignee_id IS NOT NULL
   AND bi.is_mirror IS DISTINCT FROM TRUE
   AND NOT EXISTS (
     SELECT 1 FROM public.gamification_points gp
      WHERE gp.category = 'deliverable_completed'
        AND gp.ref_id = bi.id
        AND gp.member_id = bi.assignee_id
   );

-- Verificacao fail-loud: se sobrar qualquer elegivel sem pagamento, a migration aborta em
-- vez de deixar o `validate` vermelho depois do deploy.
DO $$
DECLARE v_restantes integer;
BEGIN
  SELECT count(*) INTO v_restantes
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id AND pb.board_scope = 'tribe'
  WHERE bi.status = 'done' AND bi.is_portfolio_item IS TRUE
    AND bi.assignee_id IS NOT NULL AND bi.is_mirror IS DISTINCT FROM TRUE
    AND NOT EXISTS (
      SELECT 1 FROM public.gamification_points gp
       WHERE gp.category = 'deliverable_completed'
         AND gp.ref_id = bi.id AND gp.member_id = bi.assignee_id
    );
  IF v_restantes > 0 THEN
    RAISE EXCEPTION '#1880: % card(s) elegivel(is) seguem sem deliverable_completed apos o reparo', v_restantes;
  END IF;
END $$;
