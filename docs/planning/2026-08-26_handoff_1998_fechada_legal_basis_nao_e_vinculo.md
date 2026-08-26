# Handoff 26/08 — #1998 fechada, e a coluna que ninguém governa

**Estado final:** main `e63267db`, **fila VAZIA**, zero bypass, árvore limpa.
Merge do dia: **#2002** (#1998). Issue nova: **#2001**.

O arranque apontava a #1998 como primeira: *"uma mudança de predicado conserta 5 falsos positivos e
o denominador do painel"*. Estava certo no diagnóstico e **errado no tamanho** — e o erro de tamanho
estava no corpo da própria issue.

---

## 1. #1998 — `legal_basis` não é prova de vínculo

`get_vep_role_cohort_reconciliation` filtrava `e.legal_basis = 'contract'` nas **três** CTEs do lado
plataforma. `legal_basis` é a base legal LGPD Art. 7 do engajamento, não um estado de fluxo. Como a
coluna tem `DEFAULT 'consent'`, ela virou na prática um carimbo de **qual caminho criou a linha**:

| origem | `legal_basis` | linhas |
|---|---|---:|
| `approve_selection_application` | `contract` | 51 |
| `backfill_v4_phase3` | `contract` | 21 |
| `tribe_request_approved` | **`consent`** (o DEFAULT) | 31 |
| `audit_1247_regularize_phantom` | `consent` | 7 |
| outros | `consent` | 6 |

É a **única** função viva que filtra por esse valor — o raio de alcance era exatamente uma tela.

### Não são 44 pessoas, são 5

O corpo da issue afirmava *"44 de 115 pessoas (38%) são invisíveis"*. Medido sobre **78 pessoas
distintas** com `volunteer` ativo:

| tem `contract` | tem `consent` | pessoas |
|---|---|---:|
| sim | não | 34 |
| sim | sim | **39** |
| não | sim | **5** |

O `44` conta **linhas**; a tela conta **pessoas**, e 39 daquelas pessoas já apareciam pela outra
linha. Lição apensada em `reference-contar-da-tabela-de-linhas-em-vez-do-catalogo`.

A 6ª linha da lista (Vinicyus) **saiu sozinha**: o `pmi-vep-sync` reimportou 26/08 01:45 UTC e o
espelho virou `Complete`. Na hora da medição a lista tinha **5 linhas e 5 falsos positivos**.

### Duas armadilhas que o conserto ingênuo criaria

**(a) Largar o filtro troca quem o `DISTINCT ON` elege.** O filtro também era desempate implícito:
39 pessoas têm **duas** linhas `volunteer` ativas, e com só uma visível o `ORDER BY start_date DESC`
nunca decidia nada. Removido o filtro, ele passa a decidir — e a linha `consent` é a mais nova e
**não tem FK de candidatura**. Medido: **39 trocariam de linha, 38 de coorte**, e as pessoas sem
coorte no lado plataforma iriam de **2 para 45**. Com o desempate
`(e.selection_application_id IS NOT NULL) DESC`: 1 troca (o GP, mesmo balde `other`), **0 mudanças
de coorte**. Virou memory: `reference-largar-um-filtro-troca-quem-o-distinct-on-elege`.

**(b) Sem fallback de coorte, a correção só muda de lugar.** As 5 pessoas não têm
`selection_application_id`, mas as 5 têm candidatura achável por `pmi_id`/e-mail (4 `cycle3-2026`,
1 `cycle4-2026`). Sem o fallback elas entrariam em `no_cycle` — trocaria falso positivo numa lista
por linha fora de lugar na matriz. O fallback reusa a lateral `va` que a função **já** monta para o
`vep_status`, então não é máquina nova.

### Efeito medido, exercitando a função VIVA

| saída | antes | depois |
|---|---:|---:|
| `vep_only_count` | **5** | **0** |
| `platform_active` | 73 | 78 |
| `platform_only_count` | 5 | 5 (as MESMAS pessoas) |
| `delta` total | 5 | 5 |
| `researcher`/`cycle3-2026` | plat 7, VEP 11, **delta −4** | plat 12, VEP 12, **delta 0** |
| `researcher`/`cycle4-2026` | plat 48, VEP 46, +2 | plat 49, VEP 46, +3 |
| `researcher`/`no_cycle` | plat 1, VEP 1 | a célula **some** |

⚠️ **O "antes" tem de sair da MESMA cadeia de CTEs.** Simulei os dois lados em separado e errei o
"depois": o `FULL OUTER JOIN` reclassifica o lado VEP pela coorte do lado plataforma quando o par
casa. Só percebi porque exercitei a função real (impersonando o GP com `set_config`) em vez de
confiar na simulação. **Corrigi os números no cabeçalho da migration antes do commit.**

### A lista que sobrou é real, pequena e acionável

`platform_only`, 5 linhas: **Farhad Abdollahyan** (`OfferNotExtended` — o mesmo da #1997, que não
tem conta), Maria Sabino (`OfferExtended`), Rafael dos Santos e Thiago Sousa (`Submitted`), e o GP
(sem candidatura VEP, esperado). **4 das 5 são gap real do lado VEP.**

### Guard

`tests/contracts/1998-reconciliacao-vep-sem-legal-basis.test.mjs`, 4 testes, derivado da **captura
vigente** (não de nome de arquivo fixo — a lição do #1932). Inclui:
- **controle negativo** sobre o lado VEP (`c.cycle_code` ×2 intocado), que pega varredura que pegou
  demais;
- **reinjeção do filtro**, que prova que a asserção morde — verde ali seria lido como "não pega";
- teste de DB com **duas mensagens deliberadamente diferentes** para DDL-lag e para regressão.
  Verifiquei injetando de fato: reprova com a mensagem de DDL-lag.

### Texto da tela mudou junto com o predicado

`suggested_action` do ramo `ELSE` + **4 chaves de i18n nos 3 dicionários** (`vepOnlyTitle`,
`vepOnlyHint`, `platformOnlyHint`, `tabMatrixHint`). Deixar "contrato" no rótulo faria a tela
afirmar uma regra que ela não calcula mais.

---

## 2. #2001 — `engagements.legal_basis` não é governado por nada

Achado medindo a causa acima. **104 linhas ativas em 10 combinações** `kind` × base legal divergem
de `engagement_kinds.legal_basis`. As duas pontas de escrita erram em direções **opostas**:

- o **DEFAULT da coluna é `'consent'`**: quem não nomeia a coluna grava uma afirmação jurídica por
  omissão;
- **`seed_member_engagement_by_role` grava `'contract'` literal para qualquer `kind`**, sem ler o
  catálogo. Já produziu 1 `chapter_board` ativo com base legal errada.

`validate_privacy_policy_consistency()` valida o **catálogo** e nunca olha as **linhas**.

⚠️ **O backfill é decisão jurídica, não de schema.** Trocar as 44 de `volunteer` para `contract`
afirma que existe termo assinado, e o catálogo marca `requires_agreement = true` para esse kind.
A pergunta *"essas 44 assinaram?"* precisa de resposta antes de qualquer `UPDATE`. Sugerido passar
pelo `legal-counsel` do council — **não convoquei**, é gasto que pede decisão do PM.

Ordem recomendada: **guard primeiro** (invariante com baseline 104 e catraca só para baixo, padrão
#1932), depois as duas pontas de escrita, e o backfill por último.

---

## 3. Armadilhas medidas hoje

- **A palavra em português não fecha issue.** A PR #2002 levou `Fecha #1998`; mergeou verde e a
  issue ficou **aberta**. O memory já registrava isso, mas **o gancho no índice só citava a direção
  que dispara** (`close #N` dentro de aspas), e o espelho ficava invisível para quem lê só o índice.
  Corrigi o gancho. A convenção do repo é `Closes #N`.
- **Simulação parcial mente no "depois".** Ver seção 1: só a função viva fecha a conta.
- **A Management API do Supabase por `curl` é barrada pelo classificador.** O caminho é o MCP
  `apply_migration`, e o preço dele é transcrever o corpo na chamada. **O antídoto é medir:**
  conferi o md5 normalizado vivo contra o do arquivo local depois de aplicar
  (`08947ba0909249ad269900dea137e8a5`, 8593 bytes) — bateu, logo zero erro de transcrição. Isso
  transforma "espero ter copiado certo" em fato.
- **A captura da migration anterior era byte-fiel à produção** (`23855d64…`, 8403 bytes), então
  derivei o corpo novo dela com substituições **contadas** e controle negativo, em vez de reescrever.
- **Teste novo tem DOIS registros obrigatórios**, `test:behavioural` e `test:contracts`, e os dois
  guards (#1109 e #1908) pegam a falta. `node scripts/classify-test-suite.mjs --check` decide o
  balde — meu teste cita `SUPABASE_URL`, logo é comportamental.

---

## 4. O que tem relógio

- ⏰ **27/08 08h40 BRT: o selo de presença grava** (#1948). Decisão mantida: gravar as 77 e corrigir
  depois, em **3 passos, ou os três ou nenhum**. Efeito 77 → 66. O cron dispara sozinho.
- ⏳ Radar Tecnológico 13/07 segue o único item de presença aberto.
- ⏰ **28/08** funil · **09/09** retenção · **30/09** anonimização.
- 🆕 `operational-role-reconcile-daily` (`jobid 90`, `4 0 * * *`): ausência de linha em
  `admin_audit_log` é o esperado, ele só grava quando houve mudança ou erro.

## 5. Fila para a próxima sessão

Nenhuma PR aberta. Abertas e sem dono, na ordem que o arranque sugeriu:

| # | gancho |
|---|---|
| **#1997** | 9 de 20 sem `auth_id`. O Farhad é **líder**, 16 passos atribuídos, 0 feitos, **nenhuma conta** — e ele reaparece hoje no `platform_only` com `OfferNotExtended` |
| **#1995** | admin sem visão de alocação × termo × onboarding; denominador varia por template (3, 6, 7, 12, 16) |
| **#1996** | `No Memberships` do PMI virando `NULL`: negativa definitiva indistinguível de "não medi". 40 candidaturas |
| **#1999** | editar membro tem 2 RPCs com garantias diferentes; a tela de lista grava `is_superadmin` direto na tabela |
| **#2001** | a coluna `legal_basis` (acima). Guard primeiro; backfill é jurídico |
