-- WHAT: normaliza o rotulo da terceira minuta do TAP de `M3` para `M03`, e fecha a forma dos
--       rotulos de minuta deste documento em ^M[0-9]{2}$ por pos-condicao.
-- WHY:  a migration 20260902021856 renomeou v1 R00->M01 e v2 R01->M02 e nao tocou na v3, que ficou
--       `M3`. O acervo sai com M01, M02, M3, e a rodada seguinte nao tem forma obvia: M4 ou M04.
--       Duas familias de numeracao na mesma pagina de assinaturas.
-- POR QUE MIGRATION NOVA, E NAO EDICAO DA ANTERIOR: a 20260902021856 ja foi aplicada em producao
--       (tracking row presente). Migration aplicada nao volta a rodar, entao o passo acrescentado
--       ao arquivo dela NUNCA seria executado. O arquivo daquela versao descreve um passo que
--       producao nao executou, e este arquivo e o que torna o estado verdadeiro.
-- JANELA: `governance_document_is_unsigned_draft` do documento e a pre-condicao. Quando a cadeia de
--       aprovacao andar, o trigger de imutabilidade recusa o rename por regra, e a correcao fica
--       impossivel pela via normal. A lane do TAP segurou a publicacao da M04 justamente para esta
--       migration entrar antes.
-- ROLLBACK: UPDATE public.document_versions SET version_label='M3'
--             WHERE document_id=<doc> AND version_number=3 AND version_label='M03';
-- CREDITO: o bloco de UPDATE e a pos-condicao de forma sao da lane `lane-cpmai-ea`, propostos no
--       commit b9be7a31. O que muda aqui e so a rota: migration propria em vez de edicao de
--       migration aplicada.
-- ESTADO ANTES (medido 02/09/2026, imediatamente antes de aplicar): 1=M01, 2=M02 (lacrada), 3=M3.
--       R00 e R01 LIVRES. `UNIQUE (document_id, version_label)` existe; NAO existe CHECK de formato
--       em `version_label`.
-- ESTADO DEPOIS (o que este arquivo torna verdadeiro): 1=M01, 2=M02, 3=M03. Nenhum rotulo fora de
--       M99 ou R99. O espaco R segue livre para a versao aprovada nascer nele.
-- LEITOR FUTURO: as duas linhas acima sao DATADAS de proposito. Um cabecalho de migration descreve
--       o mundo de ANTES dela, e quem le meses depois le como se fosse o de agora. A migration
--       20260902021856 ilustra o custo: o "O CUSTO DE NAO FAZER" dela era verdadeiro quando o
--       arquivo foi escrito e ficou FALSO quando ele rodou, porque o proprio rename liberou R00.
--       Convencao proposta pela lane `lane-cpmai-ea` depois de ser enganada por aquele cabecalho.
-- NAO PROMOVA A POS-CONDICAO A INVARIANTE GLOBAL. Ela e escopada por `document_id` de proposito, e
--       o escopo e a linha que a sustenta, nao um detalhe. Medido em 02/09/2026 sobre toda a base:
--
--         familia            rotulos  documentos  exemplos
--         v1.0 e variantes        34          11  v0, v1.0, v1.0-assinado-2025-12-08
--         outro                   17          10  draft-rev-juridica-2026-06-07, M3, R2
--         M99                      2           1  M01, M02   <- so o TAP
--         R99                      0           0
--
--       A convencao M99/R99 existe em UM documento. Em `check_schema_invariants()` esta checagem
--       reprovaria 51 dos 53 rotulos da base hoje, e quebraria de novo no dia da aprovacao do TAP
--       quando `R00` nascer. Duas razoes independentes, nenhuma obvia de dentro do bloco.
--       Achado por `lane-video-shorts-21` (o denominador) e `lane-cpmai-ea` (o dia da aprovacao).
-- FORA DE ESCOPO, REGISTRADO: existe um `R2` noutro documento, mesma classe do `M3` (um digito onde
--       a convencao pede dois). Nao entra aqui porque esta migration e escopada ao TAP.
-- CROSS-REF: #2136 · #2137 · commit b9be7a31

DO $$
DECLARE v_doc_id uuid; v_n int; v_antes text; v_depois text;
BEGIN
  SELECT document_id INTO v_doc_id FROM public.document_versions
   WHERE id = '43f3bb5c-7e39-45a1-b548-800b6ad22ff5';
  IF v_doc_id IS NULL THEN
    RAISE EXCEPTION 'versao de referencia nao encontrada: o documento alvo mudou';
  END IF;

  -- A MESMA pre-condicao da migration anterior, e ela e o portao inteiro: se a cadeia andou, o
  -- rename deixa de ser correcao de rascunho e vira alteracao de documento aprovado.
  IF NOT COALESCE(public.governance_document_is_unsigned_draft(v_doc_id), false) THEN
    RAISE EXCEPTION 'documento nao e mais rascunho nao assinado: rename abortado';
  END IF;

  SELECT string_agg(version_number||'='||version_label, ' | ' ORDER BY version_number)
    INTO v_antes FROM public.document_versions WHERE document_id = v_doc_id;

  -- IDEMPOTENCIA: se M03 ja existe, esta migration ja rodou (ou alguem corrigiu a mao). Sai limpo
  -- em vez de reprovar, porque o estado desejado e o que importa, nao o caminho.
  SELECT count(*) INTO v_n FROM public.document_versions
   WHERE document_id = v_doc_id AND version_number = 3 AND version_label = 'M03';
  IF v_n = 1 THEN
    RAISE NOTICE 'v3 ja esta em M03, nada a fazer (estado: %)', v_antes;
    RETURN;
  END IF;

  UPDATE public.document_versions SET version_label='M03'
   WHERE document_id=v_doc_id AND version_number=3 AND version_label='M3';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'v3 M3->M03: renomeei % linhas (rotulo de origem nao era M3?)', v_n;
  END IF;

  -- POS-CONDICAO DE FORMA, afirmada sobre o DADO VIVO e nao sobre o texto desta migration.
  --
  -- ADMITE OS DOIS PREFIXOS DE PROPOSITO. A versao estreita (`!~ '^M[0-9]{2}$'`) e verdadeira hoje
  -- e deixa de ser verdadeira POR DESENHO no dia em que a versao aprovada nascer como `R00`. Como
  -- bloco anonimo de uma vez ela seria inofensiva, mas afirmacao de forma e o tipo de linha que
  -- alguem copia para uma constraint ou para `check_schema_invariants()` mais tarde, e ai ela
  -- quebra no dia da aprovacao, que e o pior dia possivel. Nasce sobrevivente.
  -- Achado pela lane `lane-cpmai-ea`, que leu o bloco que ela mesma tinha proposto.
  SELECT count(*) INTO v_n FROM public.document_versions
   WHERE document_id = v_doc_id
     AND version_label !~ '^M[0-9]{2}$'
     AND version_label !~ '^R[0-9]{2}$';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '% rotulo(s) fora de M99/R99 (estado: %)', v_n, v_antes;
  END IF;

  SELECT string_agg(version_number||'='||version_label, ' | ' ORDER BY version_number)
    INTO v_depois FROM public.document_versions WHERE document_id = v_doc_id;
  RAISE NOTICE 'antes: % | depois: %', v_antes, v_depois;
END $$;
