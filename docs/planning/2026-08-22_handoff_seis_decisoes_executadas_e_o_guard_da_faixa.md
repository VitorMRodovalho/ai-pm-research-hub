# Handoff 22/08 — as seis decisões executadas, e o congelamento que nenhuma delas previa

**Sessão:** madrugada de 22/08 (02:45–05:30 UTC). `main` saiu de `8309ab94`.
**Fila:** entrou com 4 PRs, saiu vazia. **Zero bypass em todos os merges.**

---

## 1. O que landou

| PR | o que é | merge |
|---|---|---|
| **#1914** | **A2** — invariante de DADO sai do portão required | `4fab4c4d` |
| **#1924** | **#1923** — o guard da faixa para de queimar a cota de API | `82e8c9cf` |
| **#1920** | **C1** — a premissa do #1586, corrigida em 9 pontos | `ce8cc6fb` |
| **#1919** | **A3** — o deploy passa a depender do `CI Validate` | `4503171d` |
| **#1918** | registro das seis decisões, com rastreamento real | `05806b65` |
| **#1927** | **A1** — a metade hermética sai da faixa | `e6e0df16` |

**A4** e **A1** vieram no fim, nessa ordem e por um motivo, e o motivo se cumpriu: a A4 migrou a
proteção para o ruleset `21186263`, e só então a A1 landou e o check `structural` **nasceu dentro do
ruleset**, em vez de ser criado no formato legado e migrado logo em seguida.

**Portão final em `refs/heads/main`:** `required_status_checks` (strict, contextos `validate`,
`browser_guards`, `deno`, **`structural`**), `deletion`, `non_fast_forward`, e bypass por ator
**explícito** (RepositoryRole admin) no lugar de `enforce_admins: false`. Proteção legada: apagada.

**O ganho da A1, medido no MESMO run da #1927:** `structural` **61s**, `validate` **617s**.

---

## 2. O achado da rodada: a fila congelou pelo próprio guard da fila

Às **03:12–03:16**, **sete jobs de faixa morreram em quatro refs diferentes** — #1914, #1918,
#1919, #1920 e o push da própria `main` — todos em `falhei em ler a faixa apos 3 tentativas`.
Nenhum executou uma asserção. A `main` ficou com `validate` vermelho.

**Não era o `stuck-seconds`** (a linha `a faixa do banco esta TRAVADA` não aparece em nenhum dos
sete) e **não era incidente do GitHub** (`All Systems Operational`, 03:17Z). Falha **simultânea em
runs independentes** é recurso compartilhado esgotado: a cota de API do `GITHUB_TOKEN`, que é por
repositório.

**O mecanismo, contado nos logs:** 278 ciclos de espera entre 02:48 e 03:13, a
`1 + (TODOS os runs ativos)` chamadas cada, **por job em espera**. Um PR abre seis workflows e só
dois têm job de faixa — a maior parte das chamadas era para perguntar a CodeQL, Deploy e Cloudflare
Pages se tinham job de faixa. Nunca tiveram.

📌 **A nota de memória de 20/08 estimava ~240 chamadas/hora por run em espera. A conta estava errada
para baixo: é `1 + N`, não 1.**

**Conserto (#1923 / PR #1924):** filtro por workflow (lista **derivada** de `.github/workflows`,
nunca escrita à mão), cota como **terceira classe** de falha (espera o reset em vez de morrer em
20s, mas **continua falhando fechado** no teto), e o erro da API impresso — antes ia para
`/dev/null`, e por isso a causa teve de ser inferida correlacionando sete jobs.

**Validado em contenção real** na #1919: derivação achou `ci.yml` e `invariants-check.yml`, 20
ciclos a 15s e 18 a 30s (o backoff virou no ciclo 21, como dimensionado), zero erro de cota.

---

## 3. A A2 pagou o próprio custo em menos de uma hora

Uma hora depois de a A2 landar, **outra lane aplicou DDL na produção** sem o `.sql` na main:
`20260822032921_activate_deputy_manager_tier_for_co_gp` e
`20260822033913_wave1_restore_adr0023_ladder_parity`.

Antes da A2, `Phase C` e `ADR-0097` estavam no check required, e isso teria deixado **as quatro PRs
abertas vermelhas** — o 8º congelamento. Com a A2, reportou no `invariants-check` e não travou
ninguém.

E o par de alertas mostra a diferença entre sinal e ruído:

- **#1921** (`CI Validate failing on main`) **fechou sozinha** quando a causa sumiu.
- **#1922** (`Schema Invariants failing on main`) — o monitor que a **própria A2 criou**, e que
  disparou 3 minutos depois de ela landar — **segue aberta**, porque a causa dela persiste.

> ⚠️ **AÇÃO PENDENTE E URGENTE, não é minha:** o commit `9e15d73c` (worktree `lane-video-shorts`,
> "Wave 1 - ativa o degrau Vice-GP") **não está em nenhum remoto**, e é o mais novo de **cinco**
> commits não empurrados nessa lane. A DDL está viva em produção e a captura dela existe em **um
> único disco**. **Empurrar é urgente e independente do merge** — tira o risco de perda sem
> antecipar decisão nenhuma. Registrado em #1910.

---

## 4. Três correções em cima do meu próprio trabalho

**(a) A #1920 corrigia 2 pontos, e eram 9.** Contando as ocorrências em vez de checar presença, a
premissa falsa do #1586 seguia viva em 7 lugares além dos 2 já corrigidos — 4 no doc de auditoria
(seções 1.1, 6.1 duas vezes, 7.3) e 3 no arquivo de teste. A pior era a 7.3: *"está medindo a
ausência do #1586, e está medindo bem"* — a afirmação errada, elogiada como boa medição.
A 10ª ocorrência **não era falsa** (a entrada de 14/08 é anterior à entrega), e ali só mudou o
tempo verbal. **Varredura de premissa não é busca-e-substitui: cada ocorrência tem uma data.**

**(b) Abri a #1926 com a premissa errada e a fechei.** Afirmei que
`ip-gate-templates.test.mjs` era órfão silencioso e que o repo não tinha denominador comparando o
que roda com o que existe. **As duas coisas são falsas:**
`tests/contracts/1109-contract-whitelist-completeness.test.mjs` é exatamente esse denominador, e o
arquivo está no SKIP_LIST dele, com motivo e issue viva (**#1340**, aberta desde 12/07). Procurei em
`package.json` e `.github/` e concluí ausência — o guard vive num **teste**, que é onde este repo põe
guards. É a mesma lição que eu tinha acabado de ampliar na #1920, repetida no mesmo turno.

📌 E a A1 **teria desligado esse guard em silêncio**: com `test` deixando de listar arquivo, a
checagem do #1109 ficaria **vazia** — verde para sempre, o pior desfecho para o guard que É o
denominador. A A1 agora o atualiza para ler a união dos dois baldes.

**(c) A A1 quebrou DOIS guards, e os dois estavam certos.** `#1109` e `#1513` liam
`pkg.scripts.test` para conferir que um arquivo está mesmo no CI. Com `test` deixando de listar
caminhos, os dois ficariam **vazios** (`[] == []`), verdes para sempre, justamente nos guards cujo
trabalho é notar teste que parou de rodar. Peguei o #1109 rodando a suíte inteira local; o #1513 foi
o CI que pegou. Só então varri a classe: `pkg.scripts.test` é lido estruturalmente em três lugares,
e o resto das ocorrências de `npm test` é prosa. **Consertar o primeiro que aparece não é a
varredura.**

---

## 5. O que fica em aberto

| item | estado |
|---|---|
| **A4** — proteção legada → ruleset | **entregue**: ruleset `21186263` ativo, legada apagada. Criei o ruleset e verifiquei que valia para `refs/heads/main` ANTES de apagar, então a main nunca ficou sem portão. Restauração: `PUT` com `~/.claude/jobs/b2628e67/tmp/protection-main-pre-a4-0505Z.json` + `DELETE` no ruleset |
| **A1** — partir a suíte | **entregue** (`e6e0df16`). 289 estruturais / 322 comportamentais. No CI: `structural` 61s contra `validate` 617s |
| **`structural` como required** | **feito**, dentro do ruleset |
| **#1925** | **decisão do PM.** `check_schema_invariants` segue no required e depende de `CURRENT_DATE`; 150 de 211 engajamentos ativos têm `end_date`. Três saídas na issue |
| **#1910** | as 2 migrations não landadas, e o commit sem remoto |
| **DDL da mensagem do gate** | o registro de decisão diz que o substituto do C1 **não foi decidido**. Não assumido |

---

## 6. Lições gravadas na memória

- `reference-invariante-que-oscila-pergunte-se-o-codigo-dele-mudou` (nova) — vermelho no CI e verde
  ao medir pode ser **DDL concorrente trocando a função que MEDE**. `schema_migrations` responde em
  uma consulta. **E extraia o log ANTES de re-rodar:** re-rodei o job e o `gh run --log` passou a
  servir o log do re-run, destruindo os timestamps que fechariam o caso.
- `reference-guard-de-fila-gasta-a-cota-da-api-de-que-depende` (atualizada) — a aritmética de 20/08
  estava errada para baixo, e **otimizar um guard é mexer na garantia dele: escolha a degradação
  ANTES de escrever o filtro.**
- `reference-premissa-verificada-uma-vez-e-recitada-depois` (atualizada) — ao **corrigir** uma
  premissa propagada, `grep` e **conte**; a lista de lugares que outro documento enumerou foi feita
  com o mesmo descuido que criou o problema.
