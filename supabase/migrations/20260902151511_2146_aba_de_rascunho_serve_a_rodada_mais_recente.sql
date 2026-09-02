-- WHAT: `get_next_draft_version` passa a devolver o rascunho MAIS RECENTE acima da versao
--       corrente, e nao o mais antigo. Uma palavra: ASC vira DESC.
-- WHY:  com UM rascunho aberto, "proximo" e "mais recente" sao a mesma linha e ninguem percebe a
--       diferenca. Com DOIS, divergem para sempre: o mais recente nunca e alcancado enquanto o
--       anterior existir e estiver destrancado.
--       Medido em 02/09/2026 no TAP do Grupo de Estudos CPMAI:
--         current_version_id ....... M02 (lacrada)
--         rascunhos abertos ........ 1=M01 | 3=M03 | 4=M04
--         por ASC (o que servia) ... M03
--         por DESC (o correto) ..... M04
-- O QUE ISSO CAUSAVA, E POR QUE E PIOR QUE UM DEFEITO DE TELA: `ReviewChainIsland` usa esta RPC
--       para a aba "Draft". Quem abrisse o link canonico do documento lia a RODADA ANTERIOR
--       achando que lia a atual, e comentava contra o texto errado. O TAP vai a aprovacao em
--       11/09 e depende de o GP do Grupo de Estudos ler e comentar a minuta.
-- POR QUE DESC E NAO UMA RPC NOVA: o trade-off era mudar o contrato de uma funcao chamada "next"
--       contra criar uma rota paralela para "latest". Medido: ha UM chamador em codigo
--       (src/components/governance/ReviewChainIsland.tsx:281) mais um teste que so verifica que a
--       chamada existe. Sem outros chamadores, o argumento de contrato nao se sustenta, e nome
--       infeliz custa menos que tela servindo rodada errada.
-- O CONSERTO DE RAIZ CONTINUA ABERTO, e e outro: `current_version_id` do TAP aponta para M02 e
--       nao avancou quando a M03 e a M04 foram publicadas, porque `upsert_document_version` nao
--       toca esse campo. Enquanto ele nao avancar, "proximo" segue ambiguo por construcao. Isso
--       pede decisao de dominio (o que "corrente" significa para rascunho com varias minutas) e
--       nao entra aqui.
-- SCOPE LOCK: so a ordenacao muda. Assinatura, STABLE, SECURITY DEFINER, search_path e o retorno
--       ficam identicos. `CREATE OR REPLACE` preserva a ACL.
-- ROLLBACK: trocar DESC de volta por ASC.
-- CROSS-REF: #2146 · #2136 (o rename das minutas) · p88 (a migration de origem, 20260516460000)

CREATE OR REPLACE FUNCTION public.get_next_draft_version(p_version_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_current record;
  v_draft record;
BEGIN
  SELECT dv.id, dv.document_id, dv.version_number
  INTO v_current
  FROM public.document_versions dv WHERE dv.id = p_version_id;
  IF v_current.id IS NULL THEN
    RETURN jsonb_build_object('error','version_not_found');
  END IF;

  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html,
         dv.content_markdown, dv.authored_at, dv.notes
  INTO v_draft
  FROM public.document_versions dv
  WHERE dv.document_id = v_current.document_id
    AND dv.version_number > v_current.version_number
    AND dv.locked_at IS NULL
  ORDER BY dv.version_number DESC
  LIMIT 1;

  IF v_draft.id IS NULL THEN
    RETURN jsonb_build_object('exists', false);
  END IF;

  RETURN jsonb_build_object(
    'exists', true,
    'version_id', v_draft.id,
    'version_number', v_draft.version_number,
    'version_label', v_draft.version_label,
    'content_html', v_draft.content_html,
    'content_markdown', v_draft.content_markdown,
    'authored_at', v_draft.authored_at,
    'notes', v_draft.notes
  );
END;
$fn$;

DO $mig$
DECLARE v_doc uuid; v_cur uuid; v_rot text; v_esperado text;
BEGIN
  SELECT document_id INTO v_doc FROM public.document_versions
   WHERE id = '43f3bb5c-7e39-45a1-b548-800b6ad22ff5';
  IF v_doc IS NULL THEN
    RAISE NOTICE 'documento de referencia ausente: pos-condicao pulada';
    RETURN;
  END IF;

  SELECT current_version_id INTO v_cur FROM public.governance_documents WHERE id = v_doc;
  IF v_cur IS NULL THEN
    RAISE NOTICE 'documento sem versao corrente: pos-condicao pulada';
    RETURN;
  END IF;

  -- O que a funcao passa a servir.
  v_rot := public.get_next_draft_version(v_cur) ->> 'version_label';

  -- O que DEVERIA ser: o rotulo do maior version_number destrancado acima do corrente.
  SELECT dv.version_label INTO v_esperado
    FROM public.document_versions dv
    JOIN public.document_versions cur ON cur.id = v_cur
   WHERE dv.document_id = v_doc
     AND dv.version_number > cur.version_number
     AND dv.locked_at IS NULL
   ORDER BY dv.version_number DESC LIMIT 1;

  IF v_rot IS DISTINCT FROM v_esperado THEN
    RAISE EXCEPTION 'a RPC devolveu % e o rascunho mais recente e %', v_rot, v_esperado;
  END IF;
  RAISE NOTICE 'pos-condicao: a aba de rascunho passa a servir %', v_rot;
END $mig$;

NOTIFY pgrst, 'reload schema';
