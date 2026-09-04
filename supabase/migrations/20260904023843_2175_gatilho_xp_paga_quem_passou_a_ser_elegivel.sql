-- #2175 - a #1880 alargou a clausula UPDATE OF do gatilho de XP de entregavel para vigiar as
-- tres colunas do predicado que podem virar depois do status, e declarou no proprio cabecalho
-- que NAO mexeria no corpo ("as cinco condicoes seguem identicas"). O corpo, porem, exigia uma
-- TRANSICAO de status:
--
--     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'done')
--
-- Num card que JA esta `done`, `OLD.status` e 'done', a condicao e falsa e a guarda barra tudo.
-- O gatilho dispara e nao paga. Ou seja: a classe que a #1880 dizia fechar - virar a flag de
-- portfolio ou definir o assignee num card ja concluido - continuou aberta.
--
-- O bloco de reparo da propria #1880 e no-op pela mesma razao: ele faz um UPDATE de toque
-- (`SET is_portfolio_item = bi.is_portfolio_item`) sobre cards que ja estao `done`, o
-- `UPDATE OF` dispara, e o corpo barra na mesma linha de sempre. Passou despercebido porque no
-- instante em que rodou o conjunto de elegiveis-nao-pagos ja era 0: o contrato #1147 ficou verde
-- por ausencia de casos, nao por eficacia do reparo.
--
-- O CONSERTO: a guarda deixa de perguntar "o status mudou?" e passa a perguntar "o card NAO era
-- elegivel antes e passou a ser agora?". E o predicado inteiro, nao uma coluna dele.
--
-- CUIDADO DE NULL, que e onde este conserto erraria em silencio: `OLD.status = 'done'` devolve
-- NULL quando `OLD.status` e nulo, e `NOT (NULL AND ...)` e NULL, o que faz o IF nao disparar.
-- Por isso a comparacao de status usa `IS NOT DISTINCT FROM`. As outras tres ja sao NULL-safe
-- por construcao (`IS TRUE`, `IS NOT TRUE`, `IS NOT NULL`), e ficam como estao de proposito.
--
-- MEDIDO ANTES DE APLICAR (04/09/2026), com controle positivo na mesma consulta: 32 cards
-- elegiveis, 32 pagos, 0 nao pagos. O backfill manual de 03/09 zerou a fila. Portanto esta
-- migration NAO traz bloco de reparo: reparo sobre conjunto vazio nao prova nada, e foi
-- exatamente esse falso verde que escondeu o defeito da #1880 por quinze dias. O que ela conserta
-- e a PROXIMA ocorrencia, nao um passivo.
--
-- LIMITE CONHECIDO, mantido de proposito: reatribuir um card ja elegivel de uma pessoa para
-- outra continua nao pagando a nova, porque OLD e NEW sao ambos elegiveis. O comportamento e o
-- mesmo de antes desta migration; mudar isso e decisao de politica de merito, nao conserto de
-- defeito. `is_mirror` tambem segue fora do `UPDATE OF`, como a #1880 registrou.
--
-- A idempotencia de `_grant_auto_xp` (SELECT ... WHERE ref_id = p_ref_id AND category = p_slug
-- AND member_id = p_recipient_id) continua sendo a protecao contra pagamento duplo quando mais de
-- uma coluna vigiada muda na mesma transacao.

CREATE OR REPLACE FUNCTION public.trg_board_item_deliverable_xp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_is_tribe boolean;
  v_deadline date;
  v_on_time boolean;
BEGIN
  -- #2175: paga quando o card E elegivel agora e NAO era elegivel antes. A guarda antiga
  -- ("o status acabou de virar para done") cegava o gatilho para a virada das outras colunas.
  IF NEW.status = 'done'
     AND NEW.is_portfolio_item IS TRUE
     AND NEW.is_mirror IS NOT TRUE
     AND NEW.assignee_id IS NOT NULL
     AND (
       TG_OP = 'INSERT'
       OR NOT (
              OLD.status IS NOT DISTINCT FROM 'done'
          AND OLD.is_portfolio_item IS TRUE
          AND OLD.is_mirror IS NOT TRUE
          AND OLD.assignee_id IS NOT NULL
       )
     ) THEN

    SELECT (pb.board_scope = 'tribe') INTO v_is_tribe
    FROM public.project_boards pb
    WHERE pb.id = NEW.board_id;

    IF v_is_tribe IS TRUE THEN
      -- deadline = committed date: due_date wins, baseline_date is the fallback commitment.
      -- No deadline → NULL → base only (no bonus, no penalty) — same policy as _grant_auto_xp.
      v_deadline := COALESCE(NEW.due_date, NEW.baseline_date);
      -- move_board_item sets actual_completion_date = CURRENT_DATE in the same UPDATE as
      -- status='done', so NEW carries it; direct UPDATEs without it fall back to today.
      v_on_time := CASE
        WHEN v_deadline IS NULL THEN NULL
        ELSE (COALESCE(NEW.actual_completion_date, CURRENT_DATE) <= v_deadline)
      END;

      PERFORM public._grant_auto_xp(
        'deliverable_completed',
        NEW.assignee_id,
        NEW.id,
        'Entregável concluído: ' || coalesce(substring(NEW.title FROM 1 FOR 80), '(sem título)'),
        v_on_time
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.trg_board_item_deliverable_xp() IS
  '#2175: a guarda pergunta se o card PASSOU A SER elegivel (predicado inteiro em OLD vs NEW), '
  'nao se o status mudou. A #1880 alargou o UPDATE OF e manteve OLD.status IS DISTINCT FROM done, '
  'entao virar a flag de portfolio ou o assignee num card ja done disparava o gatilho e nao pagava. '
  'Comparacao de status por IS NOT DISTINCT FROM para nao virar NULL e cegar o IF em silencio.';
