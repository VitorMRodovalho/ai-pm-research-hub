-- WHAT: correcao de acervo em dois documentos de Propriedade Intelectual, nomeados por id:
--       (a) as duas approval_chains de MAIO passam a `superseded`; (b) `governance_documents.version`
--       passa a `v0`, o rotulo da versao corrente. Nenhuma estrutura muda: e dado.
--
-- OS DOIS DOCUMENTOS, por id, porque titulo nao e chave:
--       41de16e2-4f2e-4eac-b63e-8f0b45b22629  Adendo de Propriedade Intelectual aos Acordos de Cooperacao
--       cfb15185-2800-4441-9ff1-f36096e83aa8  Politica de Governanca de Propriedade Intelectual do Nucleo de IA & GP
--
-- WHY (a): medido em 02/09/2026, cada um tem DUAS cadeias em `review` abertas ao mesmo tempo:
--
--         969ef148-...  Adendo    aberta 08/05  sobre v6 `v2.6-p122-roberto-comment-redaction`  <- FECHA
--         ee6bb9ca-...  Adendo    aberta 30/08  sobre v7 `v0`                                   <- PRESERVA
--         796015f4-...  Politica  aberta 09/05  sobre v7 `v2.7-p128-roberto-comment-redaction`  <- FECHA
--         b885fac5-...  Politica  aberta 30/08  sobre v8 `v0`                                   <- PRESERVA
--
--       Escopo: 8 cadeias em `review` em 6 documentos no acervo; SO estes dois tem mais de uma.
--
-- A CAUSA, para quem for consertar a raiz (#2151): ha dois caminhos para lacrar uma versao e eles
--       nao fazem a mesma coisa. `recirculate_governance_doc` supersede a cadeia corrente ANTES de
--       chamar `lock_document_version`. `lock_document_version` sozinho nao supersede nada: a unica
--       guarda dele e `WHERE ac.version_id = p_version_id`, isto e, ele pergunta se existe cadeia
--       para AQUELA VERSAO, nunca se o DOCUMENTO ja tem outra aberta. Versao nova e sempre
--       version_id novo, entao a guarda nunca dispara. O audit log confirma o caminho: ha
--       `governance.recirculated` em 08/05 e 09/05 (as cadeias que supersederam certo) e NENHUM em
--       30/08, embora as v0 tenham sido lacradas nesse dia.
--       Esta migration corrige o ACERVO. A decisao sobre a RPC segue aberta na #2151.
--
-- WHY (b): a coluna `version` carrega `v2.6-p122-...` e `v2.7-p128-...`, que e exatamente a
--       numeracao de trabalho que a decisao ratificada no #632 diz que NAO migra ("documento
--       aprovado entra como v0 real"). A versao corrente dos dois ja e `v0`, e a nota gravada nela
--       registra a decisao. Ha precedente direto e do mesmo formato: a migration 20260805000370
--       (#1187) estampa `version = COALESCE(v_version_label, version)` na ativacao, pela mesma
--       razao — coluna de texto que envelhece separada do rotulo ratificado.
--
-- POR QUE AS CADEIAS DE 30/08 NAO PODEM SER FECHADAS JUNTO, e isto e um portao, nao uma preferencia:
--       `tests/contracts/571-pr2-camada5-version-pin.test.mjs` le
--       `approval_chains?version_id=eq.<current_version_id>` e exige que exista uma em `review`
--       (`headChainOpen`) para tolerar binding com `re_anchor_required = true`. Fechar a cadeia da
--       versao corrente derrubaria esse contrato. So as de MAIO saem.
--
-- POR QUE POR ID E NAO POR PREDICADO: um `UPDATE ... WHERE status='review' AND opened_at < ...`
--       varreria 8 cadeias em 6 documentos para corrigir 2. Predicado que casa mais do que o
--       medido e como correcao de acervo vira incidente.
--
-- `closed_by` FICA NULL de proposito: nao houve pessoa fechando estas cadeias agora. Preencher com
--       o membro que rodou a migration atribuiria a alguem um ato que ele nao praticou, e o
--       registro de quem fez esta no historico do repositorio, nao numa coluna de autoria de ato.
--
-- ROLLBACK: `status='review', closed_at=NULL, notes` sem a linha anexada nas duas cadeias; e
--       `version` de volta para os dois literais antigos.
--
-- CROSS-REF: #2151 (a causa, ainda aberta) · #632 e #2067 (a decisao do v0) · #1187 e a migration
--       20260805000370 (o precedente do stamp e do supersede de cadeia irma) · #2094

-- 1. As duas cadeias de MAIO, nomeadas.
UPDATE public.approval_chains
   SET status     = 'superseded',
       closed_at  = COALESCE(closed_at, now()),
       notes      = COALESCE(notes, '') ||
                    E'\n[superseded em 2026-09-02 por correcao de acervo #2151: a versao seguinte '
                    'foi lacrada por lock_document_version direto, que nao supersede a cadeia '
                    'anterior; esta cadeia ficou aberta em review desde entao]',
       updated_at = now()
 WHERE id IN ('969ef148-bee3-4b72-85bb-7c866a577aa3',
              '796015f4-3fc0-4589-8fcb-bd32ab112b8a');

-- 2. A coluna de texto dos dois documentos, alinhada ao rotulo da versao corrente. O valor NAO e
--    o literal 'v0' escrito a mao: vem de document_versions, para nao introduzir um terceiro lugar
--    onde o rotulo e digitado.
UPDATE public.governance_documents gd
   SET version    = dv.version_label,
       updated_at = now()
  FROM public.document_versions dv
 WHERE dv.id = gd.current_version_id
   AND gd.id IN ('41de16e2-4f2e-4eac-b63e-8f0b45b22629',
                 'cfb15185-2800-4441-9ff1-f36096e83aa8');

-- 3. POS-CONDICOES.
DO $$
DECLARE
  v_maio_abertas   int;
  v_ago_abertas    int;
  v_version_ok     int;
  v_outros_docs    int;
  v_review_total   int;
BEGIN
  -- 3a. As duas de maio fecharam.
  SELECT count(*) INTO v_maio_abertas FROM public.approval_chains
   WHERE id IN ('969ef148-bee3-4b72-85bb-7c866a577aa3','796015f4-3fc0-4589-8fcb-bd32ab112b8a')
     AND status <> 'superseded';
  IF v_maio_abertas <> 0 THEN
    RAISE EXCEPTION 'POS-CONDICAO: % cadeia(s) de maio nao fecharam', v_maio_abertas;
  END IF;

  -- 3b. CONTROLE: as de 30/08 continuam em review. Fechar demais quebraria o contrato do #571, e o
  --     sintoma seria um teste de binding vermelho longe daqui.
  SELECT count(*) INTO v_ago_abertas FROM public.approval_chains
   WHERE id IN ('ee6bb9ca-de4a-47d1-9e35-38db021fe57f','b885fac5-989f-44fb-859d-8eaf8c5446c2')
     AND status = 'review';
  IF v_ago_abertas <> 2 THEN
    RAISE EXCEPTION 'CONTROLE: esperava as 2 cadeias de 30/08 em review, achei %', v_ago_abertas;
  END IF;

  -- 3c. A coluna version bate com o rotulo da versao corrente nos dois.
  SELECT count(*) INTO v_version_ok
    FROM public.governance_documents gd
    JOIN public.document_versions dv ON dv.id = gd.current_version_id
   WHERE gd.id IN ('41de16e2-4f2e-4eac-b63e-8f0b45b22629','cfb15185-2800-4441-9ff1-f36096e83aa8')
     AND gd.version = dv.version_label AND gd.version = 'v0';
  IF v_version_ok <> 2 THEN
    RAISE EXCEPTION 'POS-CONDICAO: % de 2 documentos com version = v0', v_version_ok;
  END IF;

  -- 3d. CONTROLE DE ESCOPO: nenhum OUTRO documento teve a coluna version mexida. Medido antes:
  --     4 documentos tinham version divergente do rotulo corrente; dois eram estes, e os outros
  --     dois (TAP `R00` x `M02`, e o template legado `superseded`) NAO sao alvo e tem de continuar
  --     divergindo. Se este numero cair para 0, o UPDATE vazou de escopo.
  SELECT count(*) INTO v_outros_docs
    FROM public.governance_documents gd
    JOIN public.document_versions dv ON dv.id = gd.current_version_id
   WHERE gd.version IS DISTINCT FROM dv.version_label
     AND NOT (gd.version IS NOT NULL AND dv.version_label LIKE gd.version || '%');
  IF v_outros_docs <> 2 THEN
    RAISE EXCEPTION 'CONTROLE DE ESCOPO: esperava 2 divergencias remanescentes (TAP e template legado), achei %', v_outros_docs;
  END IF;

  -- 3e. CONTROLE DE ESCOPO nas cadeias: o acervo tinha 8 em review; saem 2, sobram 6.
  SELECT count(*) INTO v_review_total FROM public.approval_chains WHERE status = 'review';
  IF v_review_total <> 6 THEN
    RAISE EXCEPTION 'CONTROLE DE ESCOPO: esperava 6 cadeias em review apos fechar 2 de 8, achei %', v_review_total;
  END IF;
END $$;
