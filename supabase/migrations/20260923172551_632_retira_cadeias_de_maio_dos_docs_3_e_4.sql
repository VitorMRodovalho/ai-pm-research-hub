-- WHAT: correcao de acervo, so dado: as approval_chains de 05/05 do Acordo de Cooperacao Bilateral
--       (template) e do Anexo Tecnico passam a `withdrawn`. Nenhuma estrutura muda.
--
--       86408434-6582-49b9-be1c-ba8b372fd805  Acordo de Cooperacao Bilateral (cd170c37-...)  sobre v5 `v1.4-p90c-material-fixes`
--       7537f6d2-1c28-48aa-9097-d420720b2d18  Anexo Tecnico (980a71fd-...)                  sobre v1 `v1.0-p90c-anexo-tecnico-creation`
--
-- WHY: `get_pending_ratifications` lista toda cadeia em `review`/`approved` em que o membro tem portao
--       elegivel, sem perguntar se o texto da cadeia ainda vale. Estas duas foram abertas em 05/05 sobre
--       textos anteriores as duas revisoes juridicas (06/07 e 21/09) e seguem roteando assinatura.
--       Medido em 23/09/2026: no Acordo, 2 lideres ainda veem "ciencia" e o proponente ve o aceite;
--       no Anexo, o proponente ve o aceite. Um aceite do proponente no Acordo abriria 12 testemunhas de
--       capitulo, a presidencia e 4 presidentes sobre a v1.4. Decisao do GP em 23/09 (#632): retirar ja.
--       As versoes novas abrirao cadeia propria; sem cadeia aberta, o `lock_document_version` da versao
--       nova nao e recusado pela guarda da #2151.
--
-- POR QUE O ADENDO RETIFICATIVO (1c593d54-...) NAO SAI JUNTO: e a UNICA cadeia em `review` com o portao
--       `volunteers_in_role_active`, e `tests/contracts/654-sequential-gate-write-path-guard.test.mjs`
--       ("out-of-order signature is REJECTED") a usa como fixture viva: sem ela o teste reprova em toda PR.
--       Ele sai por `recirculate_governance_doc` quando a versao nova existir, e a cadeia nova carrega o
--       mesmo portao. Ate la, so o proponente pode avancar essa cadeia.
--
-- POR QUE POR ID: predicado por status/data varreria outras cadeias em `review` (Politica v0, Adendo de
--       PI v0, TAP) que NAO sao alvo. Mesmo criterio da #2151.
--
-- `closed_by` FICA NULL: mesmo precedente das 4 retiradas de abril e da #2151 (a migration nao e um ato
--       de assinatura de pessoa; quem decidiu e por que esta na nota e no historico do repositorio).
--
-- NADA DE ASSINATURA E APAGADO: as 21 linhas de `approval_signoffs` (18 + 3) ficam como historico.
--       Os documentos seguem `under_review`, com a versao corrente travada; o leitor continua servindo-a.
--
-- ENSAIADO em 23/09/2026 12:5x BRT num bloco DO abortado de proposito (nada persistiu, conferido por
--       consulta nova): review 6 -> 4, 2 atualizadas, Retificativo e as duas v0 intactos, 21 assinaturas
--       preservadas, 0 elegiveis restantes, 0 documentos com duas cadeias abertas.
--
-- ROLLBACK: `status='review', closed_at=NULL` e `notes` sem a linha anexada, nas duas.
-- CROSS-REF: #632 (guarda-chuva) · #2151 (guarda de cadeia aberta e precedente de correcao) · #654

DO $mig$
DECLARE
  c_alvo CONSTANT uuid[] := ARRAY['86408434-6582-49b9-be1c-ba8b372fd805',
                                  '7537f6d2-1c28-48aa-9097-d420720b2d18']::uuid[];
  v_review_antes int; v_review_depois int; v_sig_antes int; v_sig_depois int;
  v_alvo_em_review int; v_upd int; v_elig int; v_ret int; v_v0 int; v_dup int;
BEGIN
  -- PRE: as duas existem e seguem em review. Se alguem ja mexeu, aborta em vez de sobrescrever.
  SELECT count(*) INTO v_alvo_em_review FROM public.approval_chains
   WHERE id = ANY(c_alvo) AND status = 'review' AND closed_at IS NULL;
  IF v_alvo_em_review <> 2 THEN
    RAISE EXCEPTION 'PRE: esperava as 2 cadeias alvo em review e abertas, achei %', v_alvo_em_review;
  END IF;

  SELECT count(*) INTO v_review_antes FROM public.approval_chains WHERE status = 'review';
  SELECT count(*) INTO v_sig_antes FROM public.approval_signoffs WHERE approval_chain_id = ANY(c_alvo);

  UPDATE public.approval_chains
     SET status     = 'withdrawn',
         closed_at  = COALESCE(closed_at, now()),
         notes      = COALESCE(notes, '') ||
                      E'\n[withdrawn em 2026-09-23 por decisao do GP (#632): cadeia aberta em 05/05 sobre texto '
                      'anterior as revisoes juridicas de 06/07 e 21/09; a versao nova abrira cadeia propria. '
                      'As assinaturas registradas permanecem como historico.]',
         updated_at = now()
   WHERE id = ANY(c_alvo) AND status = 'review';
  GET DIAGNOSTICS v_upd = ROW_COUNT;

  -- POS 1: exatamente as duas.
  IF v_upd <> 2 THEN
    RAISE EXCEPTION 'POS: esperava 2 cadeias atualizadas, atualizei %', v_upd;
  END IF;

  -- POS 2 (ESCOPO): o total em review caiu exatamente 2, medido contra o momento da aplicacao.
  SELECT count(*) INTO v_review_depois FROM public.approval_chains WHERE status = 'review';
  IF v_review_depois <> v_review_antes - 2 THEN
    RAISE EXCEPTION 'ESCOPO: review foi de % para %, esperava queda de exatamente 2', v_review_antes, v_review_depois;
  END IF;

  -- POS 3 (CONTROLE): o Retificativo segue em review (fixture viva do teste 654).
  SELECT count(*) INTO v_ret FROM public.approval_chains
   WHERE id = '1c593d54-481f-41cd-a8f2-e3b92876dcbc' AND status = 'review';
  IF v_ret <> 1 THEN
    RAISE EXCEPTION 'CONTROLE: a cadeia do Adendo Retificativo saiu de review; o teste 654 reprovaria';
  END IF;

  -- POS 4 (CONTROLE): as cadeias v0 da Politica e do Adendo de PI seguem em review (contrato do #571).
  SELECT count(*) INTO v_v0 FROM public.approval_chains
   WHERE id IN ('b885fac5-989f-44fb-859d-8eaf8c5446c2','ee6bb9ca-de4a-47d1-9e35-38db021fe57f') AND status = 'review';
  IF v_v0 <> 2 THEN
    RAISE EXCEPTION 'CONTROLE: esperava as 2 cadeias v0 em review, achei %', v_v0;
  END IF;

  -- POS 5: nenhuma assinatura apagada.
  SELECT count(*) INTO v_sig_depois FROM public.approval_signoffs WHERE approval_chain_id = ANY(c_alvo);
  IF v_sig_depois <> v_sig_antes THEN
    RAISE EXCEPTION 'POS: assinaturas das cadeias alvo foram de % para %', v_sig_antes, v_sig_depois;
  END IF;

  -- POS 6 (EFEITO): ninguem mais e elegivel nelas, logo `get_pending_ratifications` deixa de lista-las.
  SELECT count(*) INTO v_elig
    FROM public.approval_chains ac CROSS JOIN LATERAL jsonb_array_elements(ac.gates) g
    JOIN public.members m ON m.is_active
   WHERE ac.id = ANY(c_alvo) AND public._can_sign_gate(m.id, ac.id, g->>'kind');
  IF v_elig <> 0 THEN
    RAISE EXCEPTION 'EFEITO: ainda ha % pares membro-portao elegiveis nas cadeias retiradas', v_elig;
  END IF;

  -- POS 7: nenhum documento com duas cadeias abertas (guarda da #2151).
  SELECT count(*) INTO v_dup FROM (
    SELECT document_id FROM public.approval_chains
     WHERE status IN ('draft','review','approved') GROUP BY document_id HAVING count(*) > 1) x;
  IF v_dup <> 0 THEN
    RAISE EXCEPTION 'POS: % documento(s) com mais de uma cadeia aberta', v_dup;
  END IF;
END $mig$;
