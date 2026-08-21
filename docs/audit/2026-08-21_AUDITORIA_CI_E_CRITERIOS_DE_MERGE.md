# Auditoria da CI e dos criterios de merge

> **Produto desta lane: diagnostico, nao conserto.** Nenhum workflow, teste, portao ou protecao de
> branch foi alterado. Toda mudanca listada na secao 9 depende de decisao do PM.
>
> **Tudo medido ao vivo em 21/08/2026**, contra a API do GitHub, o log da propria CI, o banco de
> producao (somente leitura) e execucao local da suite. Onde um numero diverge do que estava no
> prompt de arranque, a divergencia esta marcada e o numero novo e o medido hoje.
>
> Repositorio publico: nenhum nome de pessoa e nenhum identificador de candidatura aparece aqui.

---

## 0. As tres perguntas do PM, respondidas primeiro

**"Os CI e criterios de validacao de merge estao seguindo as boas praticas?"**

Em grande parte sim, e alguns padroes daqui sao melhores que a media do mercado: o
`wait-for-db-lane` resolve um bug real do proprio GitHub (fila que cancela pendente), o
`invariant-exceptions.mjs` e um allowlist com data de validade e modo estrito, e existem 8 testes
que auditam a propria CI. O problema nao e falta de rigor. E que **o portao required foi acoplado a
um recurso mutavel compartilhado**, e isso quebra duas boas praticas simultaneamente: um gate de
merge deve ser (a) hermetico e (b) uma funcao do diff. Hoje ele nao e nenhum dos dois.

**"Nao estao ficando pesados?"**

Sim, e da para dizer exatamente onde. Na amostra de 30 dias, `CI Validate` + `Schema Invariants`
somam **5.786 dos 6.938 minutos de runner (83,4%)**, e as duas disputam a mesma faixa de banco. O
p50 do `validate` e **14m05s** e o p90 e **26m41s**. A diferenca entre os dois nao e trabalho: e
espera. O passo `wait-for-db-lane` tem p50 de 53s e **p90 de 14m21s**.

Mas o peso mais caro nao e o relogio, e a **taxa de acerto**. Em 198 runs amostrados, `validate`
ficou verde 138 vezes (70%), com 53 vermelhos e 7 cancelados. Num subconjunto de 45 desses runs,
para o qual coletei o detalhe passo a passo, **22 dos 23 vermelhos morreram no mesmo passo**
(`Run Unit Tests`) e o 23o na propria espera da faixa. Nenhum veio de lint, build ou smoke.

**"Precisamos de um plano de agrupamento de licoes aprendidas e organizacao das rotinas?"**

De agrupamento, sim, e a secao 6 mostra o formato: o repo ja **inventou** o padrao certo de
tolerancia com prazo (o do #1850) e o aplicou a **1 de 30 superficies**. As outras 8 listas de
tolerancia somam **823 entradas sem nenhuma data de validade**. De organizacao de rotinas, o
diagnostico e mais especifico que "organizar": 4 dos 16 workflows nao tem funcao de portao
nenhuma, 1 job existe so para ecoar, e 20 arquivos de teste Playwright nunca rodam.

---

## 1. O achado central, medido de ponta a ponta

**A fila de merge esta travada agora, por UMA linha de dado de producao.**

A cadeia inteira, cada elo medido nesta sessao:

| elo | medicao |
|---|---|
| linhas em `gate_attempts` depois do cutoff de 09/08 | 29 |
| destas, com `caller_id IS NULL` (a populacao que o guard #1636 vigia) | 9 |
| fora do allowlist de 5 operacoes ja declaradas | 4 |
| sem carimbo de cron que as explique (janela de 60s) | **1** |
| candidaturas REAIS ofensoras | **1** |
| carimbo da linha | **2026-08-21 14:18:47 UTC** |
| a RPC | `_issue_interview_booking_token_core` |
| desfecho no portao | `gate_passed=false`, codigo `P0002` |
| e a mesma candidatura das 4 entradas de 20/08? | **sim** |

Do lado da CI, o mesmo instante:

| run | branch | SHA | inicio | desfecho |
|---|---|---|---|---|
| 32481010980 | `claude/1900-cron-jornada-tribo` | `b41217d9` | 21/08 12:15 | **success** |
| 32492721370 | `claude/1900-cron-jornada-tribo` | `005ee51c` | 21/08 14:32 | **failure** |

E o log do run vermelho nomeia uma unica asserção:

```
not ok 1 - depois do cutoff, tentativa de gate sem ator so existe se o CRON a explicar
not ok 1091 - #1636 B - nenhuma escrita nova de teste cai em candidatura real
    candidatura REAL recebeu tentativa de gate sem ator e sem cron que a explique
```

Leia-se: **uma pessoa tentou pela quinta vez emitir o mesmo convite, o portao recusou exatamente
como projetado, e a recusa correta congelou o merge de todo mundo.** Nao ha defeito de codigo em
lugar nenhum dessa cadeia. Ha um teste comportamental sobre dado de producao dentro de um check
required.

> Observacao de metodo: a mensagem de falha do guard afirma "algum teste voltou a escolher alvo por
> predicado sobre producao". Isso e **hipotese, nao diagnostico**. A linha tem a mesma digital das
> 4 operacoes manuais ja declaradas (mesma candidatura, mesma RPC, mesma recusa), o que aponta para
> operacao humana e nao para regressao da suite. Confirmar a origem e escopo do #1636, nao desta lane.

---

## 2. Inventario dos 16 workflows

Duracoes: mediana e p90 sobre os 200 runs mais recentes de cada workflow dentro dos ultimos 30
dias. "runs/30d" e a contagem exata da API (`total_count`), nao a amostra.

| # | workflow | gatilhos | required | p50 | p90 | runs/30d | min de runner | o que protege |
|---|---|---|---|---|---|---|---|---|
| 1 | `ci.yml` **CI Validate** | push(main,dev), PR(main,dev) | **`validate`, `browser_guards`** | 14m05s | 26m41s | 590 | **3.676** | o portao. 4 jobs, ver 2.1 |
| 2 | `deno-ef-check.yml` | PR (sem filtro de path) | **`deno`** | 0m26s | 0m31s | 388 | 86 | tipos e lint das Edge Functions |
| 3 | `invariants-check.yml` | push+PR(main), cron 07:00 | nao | 11m36s | 24m27s | 622 | **2.110** | 43 invariantes em modo estrito |
| 4 | `codeql-analysis.yml` | push+PR(main) | nao | 2m15s | 3m42s | 591 | 481 | SAST JavaScript |
| 5 | `deploy.yml` | push(main) | nao | 1m22s | 1m32s | 205 | 251 | publica em producao |
| 6 | `gen-types-drift.yml` | push+PR(main), cron 07:15 | nao | 0m24s | 0m30s | 623 | 98 | `database.gen.ts` x schema vivo |
| 7 | `issue-reference-gate.yml` | push+PR(main,dev) | nao | 0m12s | 0m15s | 590 | 41 | issue linkada em path critico |
| 8 | `advisors-check.yml` | PR(paths), cron seg 08:00 | nao | 0m18s | 0m23s | 131 | 40 | drift dos advisors do Supabase |
| 9 | `ci-heartbeat-monitor.yml` | cron a cada 30min | nao | 0m09s | 0m10s | **722** | 30 | abre issue se main ficar vermelha |
| 10 | `backup-database.yml` | cron 23:00 | nao | 6m28s | 7m36s | 17 | 88 | dump diario + restauracao de prova |
| 11 | `project-governance-sync.yml` | push(paths), cron 09:15 | nao | 0m13s | 0m18s | 31 | 7 | snapshot de governanca (best effort) |
| 12 | `comms-metrics-sync.yml` | cron 07:30 | nao | 0m08s | 0m12s | 31 | 5 | dispara EF de metricas |
| 13 | `knowledge-insights-auto-sync.yml` | cron seg+qui 10:30 | nao | - | - | 9 | - | dispara EF de insights |
| 14 | `credly-auto-sync.yml` | cron seg 08:00 | nao | - | - | 4 | - | dispara EF do Credly |
| 15 | `bypass-audit-weekly.yml` | cron seg 10:00 | nao | - | - | 4 | - | tripwire do protocolo de bypass |
| 16 | `release-tag.yml` | manual | nao | - | - | 0 | - | tag semantica + proveniencia |
|  | *(dinamico)* Dependabot Updates | alerts-only | nao | - | - | - | - | limite de PR = 0 por politica #611 |

**Total medido na janela: 4.558 runs, 6.938 minutos de runner.** Os itens 1 e 3 sozinhos sao 83,4%.

### 2.1 Os 4 jobs dentro do `CI Validate`

| job | required | p50 do job | verde/vermelho em 198 runs |
|---|---|---|---|
| `validate` | **sim** | 13m57s | 138 / 53 (+7 cancelados) |
| `browser_guards` | **sim** | 1m35s | **198 / 0** |
| `visual_dark_mode` | nao | 0m50s | **198 / 0** |
| `quality_gate` | nao | ~5s | 138 success, 56 skipped, 4 cancelados |

`quality_gate` declara `needs: [validate, browser_guards, visual_dark_mode]` e o corpo dele e um
`echo`. Como ele **nao e required**, ele nao agrega nada: e o padrao "um unico check required
agregador" implementado pela metade, sem o passo que lhe daria sentido.

### 2.2 Sobreposicoes e trabalho repetido

1. **`Schema Invariants` re-executa o que o `validate` ja executou.** Os 3 arquivos do
   `test:contracts:db` (`schema-invariants`, `schema-cache-columns`, `log-retention`) estao **todos**
   dentro dos 608 do `npm test`. A unica diferenca e `INVARIANT_STRICT=1`. Custo dessa duplicacao:
   **2.110 minutos de runner em 30 dias**, mais a ocupacao da mesma faixa de banco que o `validate`
   precisa. O desenho e proposital e esta bem documentado no #1850; o preco e que ele foi pago com
   uma re-execucao inteira em vez de uma segunda asserção sobre o mesmo resultado.

2. **`validate` roda de novo em `push` para main.** 72 dos 200 runs amostrados sao push. Como a
   protecao de branch esta com `strict: true` (branch tem de estar atualizada antes do merge), a
   arvore pos-merge e a arvore que ja passou. A re-execucao so acrescenta deteccao de **deriva de
   dado de producao**, que e exatamente a classe que nao deveria estar no portao. E ela segura a
   faixa do banco por ~14 min, atrasando a proxima PR.

3. **`deploy.yml` nao depende de nada.** Dispara no mesmo `push` para main, sem `needs:` e sem
   `concurrency:`. Com p50 de 1m22s contra 14m do `validate`, **a producao vai ao ar cerca de 12
   minutos antes do portao pos-merge terminar.** O check pos-merge, portanto, nao pode impedir um
   deploy ruim; ele so avisa depois.

4. **`CodeQL` roda em push e em PR** sobre commits equivalentes: 481 minutos em 30 dias.

5. **20 specs Playwright nunca rodam.** `test:e2e` (18 arquivos em `tests/e2e/`) mais
   `tests/mobile-viewport.spec.ts` e `tests/persona-journeys.spec.ts` nao sao invocados por workflow
   nenhum. Nao e falha: e superficie que parece cobertura e nao e.

---

## 3. Onde vai o tempo

Decomposicao do job `validate`, sobre os passos que **de fato executaram** (45 runs amostrados):

| passo | p50 | p90 | max |
|---|---|---|---|
| **`Run Unit Tests`** | **11m17s** | 12m44s | 12m53s |
| **`wait-for-db-lane`** | 0m53s | **14m21s** | **27m43s** |
| `Smoke Test Routes` | 0m32s | 0m40s | 0m57s |
| `Install dependencies` | 0m13s | 0m14s | 0m15s |
| `Build Project` | 0m09s | 0m10s | 0m10s |
| `lint:client-scripts` | 0m06s | 0m06s | 0m06s |
| `lint:i18n` | 0m02s | 0m02s | 0m03s |

Tres leituras diretas:

- **O p90 e espera, nao trabalho.** O trabalho varia pouco (11m17s a 12m53s). O que explode e a
  fila do banco: p50 de 53s, p90 de 14m21s, pior caso medido de 27m43s.
- **Os portoes baratos ja rodam primeiro, mas os hermeticos rodam por ultimo.** `Build` (9s) e
  `Smoke` (32s) so acontecem depois dos 11 minutos de teste. Uma quebra de build so aparece no
  minuto 12 de um job que poderia te-la mostrado no minuto 1. Nos 45 runs para os quais coletei
  detalhe de passo, nenhum vermelho veio de `Build` ou de `Smoke`.
- **Quase todo vermelho e um passo so.** Dos 23 vermelhos na amostra de 45 runs com detalhe de
  passo, 22 morreram em `Run Unit Tests` e 1 na propria espera da faixa.

### 3.1 Dentro dos 11 minutos, medido no log TAP da propria CI

Do run verde de 21/08 12:15 (PR #1905), extraido do log completo do job:

```
# tests 7013     # pass 7012     # fail 0     # skipped 1
# duration_ms 725701          (12m06s)
```

Distribuicao dos 4.810 testes de nivel de topo, somando 676,4s:

| faixa de duracao | testes | tempo | % do tempo |
|---|---|---|---|
| < 0,1s | **4.087** | 11,6s | **1,7%** |
| 0,1s a 1s | 573 | 217,8s | 32,2% |
| 1s a 5s | 134 | 254,6s | 37,6% |
| > 5s | **16** | 192,4s | **28,4%** |

**85% dos testes custam 1,7% do tempo.** Os 25 mais lentos sozinhos sao 33,8%.

### 3.2 A consulta nao e o custo. A porta e.

Medido hoje, em SQL puro, contra o banco de producao:

| medicao | valor |
|---|---|
| `check_schema_invariants()`, 1a chamada (plano frio) | **72,4 ms** |
| chamadas 2 a 5 | 13,2 / 13,4 / 14,4 / 13,6 ms |
| `EXPLAIN ANALYZE`, tempo de execucao | 69,7 ms |
| invariantes retornados | 43 |
| violacoes agora | 0 |

> ⚠️ **Divergencia com o arranque.** O prompt cita "2,53 s em SQL puro" (do #1844, medido em
> 17-18/08). **Nao reproduzi esse valor hoje**: medi 72 ms na primeira chamada e ~14 ms nas
> seguintes. Isso nao contradiz o #1844, reforca a conclusao dele: se a funcao custa 14 ms e a
> chamada pela porta do PostgREST custava 33 a 49 s, entao **praticamente 100% daquele tempo era
> fila de pool**, nao trabalho. Antes de reusar o 2,53 s em qualquer lugar, re-medir.

O amplificador esta na quantidade de portas abertas: os 321 arquivos comportamentais tem
**1.112 sitios estaticos de chamada de rede** (`fetch`/`rest`/`rpc`/`getRows`/`sb.from`), e chamadas
dentro de laco contam 1 aqui, entao o numero em execucao e maior. 676,4s / 1.112 = **0,61 s por
sitio**.

Fator estrutural que nenhum conserto de codigo remove: os runners caem em regioes dos EUA
(medido no log de um unico run: `eastus`, `westcentralus`, `westus`, `westus3`) e o banco esta em
`sa-east-1`. Cada uma dessas 1.112+ idas e voltas atravessa o continente, em serie, porque
`--test-concurrency=1` esta travado pelo #1261 por causa do banco compartilhado.

---

## 4. Classificacao dos testes: estrutural x comportamental

Criterio: um arquivo e **comportamental** se referencia `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
`SUPABASE_ANON_KEY` ou o helper `db-fetch`. Caso contrario e **estrutural** (le arquivo, catalogo ou
codigo do repo).

| | arquivos | testes | tempo |
|---|---|---|---|
| **estrutural** | **287** (47%) | 3.588 | **30,4s** serial / **12,7s** com concorrencia 4 |
| **comportamental** | **321** (53%) | ~3.425 | ~11m35s |

Os numeros da linha estrutural nao sao estimativa. Rodei o subconjunto localmente, sem `.env`,
node v24.19.0:

```
287 arquivos, --test-concurrency=1  ->  30,42s   (3588 testes, 0 falhas, 0 skipped)
287 arquivos, concorrencia padrao   ->   9,92s
287 arquivos, --test-concurrency=4  ->  12,69s   (aproxima o runner publico)
```

`0 skipped` prova que sao mesmo hermeticos: nenhum deles esta gated por credencial.

**A leitura que importa: metade dos arquivos do check required custa 4% do tempo, nao toca banco
nenhum, e mesmo assim espera na faixa do banco (p90 14m21s) e roda em serie por uma restricao que
nao se aplica a eles.**

### 4.1 Cruzamento de risco: comportamental x relogio real

Dos 321 comportamentais, **39 tambem usam relogio real** (`new Date()`, `Date.now()`,
`CURRENT_DATE`, `now()`):

| combinacao | arquivos |
|---|---|
| so relogio de JS | 5 |
| so relogio de SQL | 20 |
| os dois | 14 |
| **total** | **39** |

Esses 39 sao a interseção mais fragil da suite: afirmam sobre dado que muda sozinho, numa janela
que anda sozinha. E a classe do #1727 (`CURRENT_DATE` e UTC e engole a noite local).

Em contrapartida, os **91 literais de data em linha de codigo, em 34 arquivos**, sao em quase toda
parte o padrao **correto**: relogio congelado passado como parametro explicito
(`{ p_as_of: '2026-07-09' }`, `new Date(2026, 6, 28, 12, 0)`). Isso e determinismo, nao divida.

---

## 5. Varredura de alvos instaveis

### 5.1 `limit` sem `ORDER BY`

Varri todo literal de string em `tests/**/*.test.mjs` que contenha `select=`, `limit=` ou `order=`,
excluindo comentarios.

| medida | valor |
|---|---|
| strings de consulta PostgREST encontradas | 73 |
| com `order=` | **4** |
| sem `order=`, mas fixadas por um `=eq.` de chave | 4 |
| **sem `order=` e sem chave que fixe a linha** | **65** |
| destas, carregando `limit=` | **17** |

Para comparacao de escala: existem **203 sitios de indexacao `[0]`** em 183 arquivos, contra
**4 usos de `order=`** na suite inteira. A suite escolhe alvo por ordem fisica quase sempre.

Classifiquei os 17 a mao, lendo a asserção que vem depois:

| classe | sitios | por que |
|---|---|---|
| **presenca / forma** (seguro) | 12 | a asserção e sobre HTTP status, existencia de coluna ou formato. A identidade da linha nao entra. |
| **dependente de identidade** (instavel) | **5** | a asserção afirma algo sobre a linha sorteada. |

Os 5 instaveis, todos dentro do check **required** `validate`:

| arquivo:linha | o que sorteia | o que afirma sobre o sorteado |
|---|---|---|
| `1710-elegibilidade-fala-a-lingua-do-selo.test.mjs:182` | 5 linhas de `v_member_operational_tiers` | que **toda** linha tem `operational_tier` preenchido |
| `666-leader-gate-initiative-scoped.test.mjs:80` | 1 `tribe_leader` ativo que nao seja o lider da iniciativa | que o portao **recusa** (`false`) |
| `666-leader-gate-initiative-scoped.test.mjs:95` | 1 `tribe_leader` ativo qualquer | que recusa em `project_charter` **e** aceita em `policy` |
| `cert-director-go-gate.test.mjs:72` | 1 membro PMI-GO **com** `certificacao_director` | que aceita em charter **e recusa** em policy |
| `cert-director-go-gate.test.mjs:90` | 1 membro PMI-GO **sem** a designacao | que o portao **recusa** |

**Estao vivos hoje?** Fui medir a homogeneidade de cada populacao sorteavel no banco de producao,
porque um alvo instavel so vira vermelho quando a populacao tem veredito misto:

| sitio | populacao | vereditos | e coin flip hoje? |
|---|---|---|---|
| `1710:182` | 71 linhas na view | 0 com tier nulo ou vazio | **nao** |
| `cert-director:90` | 25 membros PMI-GO sem a designacao | 25 recusam, 0 aceitam | **nao** |
| `666:95` | 13 `tribe_leader` ativos | 13 de 13 com o mesmo par de vereditos | **nao** |
| `666:80` | 13 lideres x 1 chain com portao `leader` | 1 aceita, 12 recusam | **nao**, ver abaixo |

O caso `666:80` merece o detalhe porque quase virou um falso achado. O produto 13x1 tem exatamente
**1 veredito `true`**, o que parecia um sorteio 1 em 13 para vermelho. Fui checar quem e esse 1: e o
proprio lider do roster da iniciativa, que o teste **exclui de proposito** (`id=neq.${leaderId}`). E
o roster daquela iniciativa devolve **2 linhas para 1 membro distinto** (a view duplica), entao nem
a escolha do passo anterior tem alternativa. O teste esta correto por construcao hoje.

**Conclusao honesta da varredura: a classe e real e estrutural em 5 asserções, mas nenhuma esta
disparando hoje. O #1113 foi o que ja tinha virado.** As 5 estao a um evento de dado de distancia:
basta um membro PMI-GO ganhar autoridade ampla, ou uma linha de tier ficar nula, para um check
required reprovar sem que autoridade nenhuma tenha mudado.

### 5.2 O padrao de conserto ja existe no repo

O #1113 (consertado hoje, `1113-initiative-roadmap.test.mjs:113-130`) escolhe o alvo **pela
propriedade que a asserção precisa**, nao pela ordem fisica, e quando nao acha um alvo valido ele
**diz isso** em vez de reprovar. Esse e o gabarito para os 5. Ele nao precisa de `ORDER BY`: precisa
de predicado.

### 5.3 O que a varredura NAO cobre

`limit` sem `ORDER BY` e a forma mais visivel, mas a mesma doenca aparece em `chains.find(...)`,
`rows[0]` e `Object.keys()[0]` sobre resultado nao ordenado. Os 203 sitios `[0]` sao um teto
superior, nao uma lista de defeitos: a maioria indexa resultado ja fixado por chave. Separar os
dois exige leitura caso a caso e nao coube nesta lane.

---

## 6. A superficie de tolerancia (allowlists e baselines)

O arranque falava em 2 listas (26 e 15 linhas). Medindo o repo inteiro, sao mais:

| arquivo | linhas | **entradas** | tem prazo? |
|---|---|---|---|
| `MIGRATION_FILE_DRIFT_BASELINE_P224.txt` | 709 | **693** | nao |
| `TABLE_ORPHAN_ALLOWLIST_P174.txt` | 65 | 35 | nao |
| `TABLE_DRIFT_ALLOWLIST_P64.txt` | 57 | 22 | nao |
| `MIGRATION_EMPTY_STATEMENTS_BASELINE_P224.txt` | 74 | 41 | nao |
| `CSS_UNDEFINED_TOKEN_BASELINE_1545.txt` | 29 | 19 | nao |
| `MIGRATION_ORPHAN_LOCAL_BASELINE_P224.txt` | 36 | 8 | nao |
| `scripts/advisor_baseline.json` | 75 | 5 | nao |
| `RPC_BODY_DRIFT_ALLOWLIST_P175.txt` | 26 | **0** | nao |
| **total em arquivo** | | **823** | **0 com prazo** |
| allowlists embutidos em codigo de teste | 22 arquivos | nao contado | ver abaixo |

**Duas coisas boas, que precisam ser ditas antes das ruins.**

1. **O ratchet funciona quando alguem o empurra.** O `RPC_BODY_DRIFT_ALLOWLIST_P175.txt` tinha
   **225 entradas** no p175 (numero registrado no CLAUDE.md). Hoje tem **0**. A recuperacao de
   drift via `apply_migration` zerou a lista. Isso e prova de que a disciplina converge.

2. **O repo ja inventou o allowlist certo.** `tests/helpers/invariant-exceptions.mjs` (#1850) tem
   as quatro propriedades que faltam em todos os outros:
   - **prazo** (`expires: '2026-09-30'`), e passado o prazo volta a reprovar;
   - **issue** por entrada, com o motivo escrito;
   - **contrato de ratchet** declarado ("a contagem so cai");
   - **modo estrito** (`INVARIANT_STRICT=1`) que desliga toda declaracao no job **nao-required**,
     para que destravar o portao nunca apague o sinal.

   Hoje ele tem **1 entrada**. E a unica superficie de tolerancia do repo com data de validade.

**A ruim:** 823 entradas em arquivo mais 22 allowlists em codigo, e uma unica delas tem prazo. Uma
lista sem prazo nao e portao nem divida: e um numero que ninguem tem obrigacao de olhar de novo.

### 6.1 O allowlist do #1636 e um instrumento de medicao, nao uma divida de teste

O caso citado no arranque (1 para 5 entradas em um dia, 4 delas a mesma operacao) esta corretamente
auto-diagnosticado no proprio arquivo: *"enquanto `selection_rescue_unbooked_invite` nao tiver
superficie (#1586), a unica porta para despachar e o service_role, e toda operacao manual vai cair
aqui"*.

Medido hoje: a lista teria de ir para **6 entradas**, e a sexta e a **quinta tentativa na mesma
candidatura**. O crescimento dessa lista e uma medicao limpa da ausencia do #1586. Ele nao deve ser
resolvido mexendo no teste.

---

## 7. As 5 perguntas estruturais do arranque, respondidas

### 7.1 Teste de contrato deve rodar contra PRODUCAO?

**Depende de qual metade, e a resposta e diferente para cada uma.**

Primeiro, uma correcao de classificacao que decide o resto. Rodei `check_schema_invariants()` e li
os 43 invariantes: **nenhum deles e um invariante de schema.** Todos contam LINHAS que violam
(`violation_count`, `sample_ids`): consistencia de papel, `is_active`, `designations`, integridade
de bridge, paridade de capitulo, ancestralidade de milestone. **O workflow chamado "Schema
Invariants" e um monitor de invariante de DADO.**

Isso decide a viabilidade de banco efemero. Segundo a documentacao do Supabase, preview branches
**nascem sem dado** ("do not start with any data from your main project"). Portanto:

| classe | pode ir para branch efemera? | por que |
|---|---|---|
| 287 arquivos **estruturais** | nao precisa, nem toca banco | ja sao hermeticos |
| invariante de **schema** (catalogo, RLS, grants, assinatura de RPC) | **sim** | migrations reproduzem o catalogo |
| 43 invariantes de **dado** + 321 arquivos comportamentais | **nao** | populacao zero deixa tudo verde por vacuo |

Mover os testes de dado para uma branch sem dado seria trocar vermelho por **verde por vacuo**, que
e o anti-padrao que o proprio repo ja nomeia em `1655-grade-sem-tribo...` ("este teste passaria por
POPULACAO ZERO").

**A saida nao e mudar o banco. E mudar o momento.** Um invariante de dado responde a pergunta "a
producao esta sa agora?", e essa pergunta nao tem relacao com "este diff pode entrar?". Ela pertence
a um monitor agendado que abre issue, nao a um portao de merge. O repo ja tem o monitor
(`invariants-check.yml`, com modo estrito) e ja tem o alarme (`ci-heartbeat-monitor.yml`).

### 7.2 Quantos dos 3 required deveriam ser required?

Medido em 198 runs (30 dias):

| check required | vermelhos | observacao |
|---|---|---|
| `validate` | **53** | toda a capacidade de discriminar esta aqui |
| `browser_guards` | **0** | e ainda tem retentativa cega 2x |
| `deno` | **3 em 388 runs** | os 3 sao 20/08, o incidente #1896 que ele mesmo motivou |

Sobre a retentativa do `browser_guards`: `run_browser_guards_with_retry.sh` roda ate 2 vezes com 5s
entre elas. Um flake na primeira tentativa vira verde sem deixar registro. Da para descartar que
isso esteja acontecendo na amostra: uma tentativa custa p50 64s, entao um run com retentativa
custaria pelo menos 64+5+64 = 133s, e o **maximo observado em 45 runs foi 103s**. Nenhum run pediu
segunda tentativa. Ainda assim, o mecanismo existe e apaga sinal quando disparar.

`visual_dark_mode` tambem fez 198 de 198 verde e **nao e required**, o que e coerente.

**Nao concluo que `browser_guards` deva sair.** Zero falhas em 198 runs e evidencia fraca para um
guard que protege contra classe rara, e ele custa 1m35s (nao esta no caminho critico, que e
`validate`). O que a medicao diz e outra coisa: **o conjunto required nao esta pesado por ter 3
membros. Esta pesado porque 1 deles carrega 100% da carga e 53% desse 1 nao e funcao do diff.**

O inverso da pergunta (ha check nao-required que deveria ser?): `gen-types-drift` e o candidato mais
forte, porque a deriva do `database.gen.ts` foi um dos 6 travamentos e ele custa p50 de 24s. Mas
ele **le o schema vivo**, ou seja, tornar required repetiria o mesmo erro de acoplamento. Decisao
do PM, com esse trade-off na mao.

### 7.3 Allowlist que so cresce e portao ou divida?

Nenhum dos dois enquanto nao tiver prazo: e **um numero**. A resposta operacional esta na secao 6:
o repo ja tem o formato certo (#1850) e o aplicou a 1 de ~30 superficies. Um allowlist com prazo,
issue e ratchet declarado e portao. Sem prazo, e sedimento.

O caso especifico do #1636 nao e problema de allowlist: ele esta medindo a ausencia do #1586, e esta
medindo bem.

### 7.4 Alvo instavel em teste comportamental

Secao 5. **5 asserções dependentes de identidade, em 3 arquivos, todas dentro do required, nenhuma
disparando hoje.** O padrao de conserto ja existe no repo (#1113): escolher pela propriedade que a
asserção precisa e degradar dizendo por que, em vez de reprovar.

> 📌 A regra do repo vale aqui: **ao consertar, injete o defeito e prove que ainda REPROVA.** Para
> estes 5, o teste decisivo e forcar a populacao a ficar heterogenea (um alvo com o veredito oposto)
> e confirmar que o teste vermelha. Sem isso, o conserto pode virar verde por vacuo.

### 7.5 Ordem de execucao e orcamento

Tres achados, em ordem de retorno:

1. **A metade hermetica esta refem.** 287 arquivos, 12,7s com concorrencia 4, zero banco, hoje
   esperando p90 de 14m21s numa faixa que nao lhes diz respeito e rodando em serie por uma trava
   (`--test-concurrency=1`) que existe por causa do banco.
2. **Build e smoke rodam depois dos 11 minutos.** Sao hermeticos, custam 41s somados, e nunca
   reprovaram nos 45 runs com detalhe de passo. Estao no fim de uma fila cujo comeco e a parte que
   sempre quebra.
3. **A serializacao gasta a cota da API de que depende.** O `wait-for-db-lane` consulta a API a cada
   15s, e cada ciclo faz 1 chamada de runs mais 1 por run em voo. Num p90 de 14m21s sao ~57 ciclos
   por job em espera, com 2 jobs por vez na faixa. Ja mordeu antes (#1509/#1844: o guard falhou em
   **ler** a faixa, nao em esperar). Nao instrumentei o consumo real; e o que eu mediria a seguir.

---

## 8. Comparacao com o que os 4 fornecedores publicaram

> Convencao: **"na janela"** = publicado entre 22/06/2026 e 21/08/2026 (60 dias).
> **"fora da janela"** = mais antigo, e dito com a data, porque continua sendo a orientacao vigente.

### GitHub

| item | data | na janela? | aplicavel aqui |
|---|---|---|---|
| [Migrar branch protection para rulesets automaticamente](https://github.blog/changelog/2026-08-11-automatically-migrate-branch-protection-rules-to-repository-rulesets/) | **11/08/2026** | **sim** (10 dias) | **muito.** Este repo esta em branch protection **legada** (`/rulesets` volta vazio). O GitHub **nao** declara a legada depreciada, mas descreve rulesets como "the foundation for repository governance" |
| [Rule insights para organizacoes (public preview)](https://github.blog/changelog/2026-08-12-rule-insights-for-organizations-in-public-preview/) | **12/08/2026** | **sim** | painel de como as regras sao avaliadas. Casa com o protocolo de bypass, que hoje reconstroi isso por script semanal |
| [Code coverage merge protection](https://github.blog/changelog/2026-06-30-github-code-coverage-merge-protection-for-pull-requests/) | **30/06/2026** | **sim** | **nao** hoje: exige GitHub Code Quality em Team/Enterprise Cloud. Vale como sinal de direcao: **portao novo do GitHub nasce em ruleset, nao em branch protection** |
| [Restringir quem descarta review em rulesets](https://github.blog/changelog/2026-07-07-restrict-who-can-dismiss-reviews-in-rulesets/) | **07/07/2026** | sim | baixa (dono unico) |
| [Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue) | doc viva, **sem data na pagina** | - | ver analise abaixo |

**Sobre merge queue, e a recomendacao contraria.** O GitHub e explicito em dois pontos: *"You **must**
use the `merge_group` event to trigger your GitHub Actions workflow"*, e a fila *"provides the same
benefits as the Require branches to be up to date before merging"* sem obrigar o autor a rebasar e
reesperar. Verifiquei: **nenhum dos 16 workflows declara `merge_group`**, entao adotar a fila exige
editar os 3 workflows required antes de qualquer coisa.

E ainda assim **eu nao recomendo merge queue aqui, agora.** Ela resolve contencao entre PRs
concorrentes de varios autores. Este repo tem dono unico e 3 PRs abertas, e as duas causas medidas
(banco compartilhado e teste sobre dado de producao) **sobrevivem intactas** dentro de uma fila: o
`merge_group` roda o mesmo `validate` de 14 minutos contra o mesmo banco. Trocar `strict: true` por
fila troca "rebasar e reesperar" por "esperar na fila", com o mesmo custo de banco e um workflow a
mais para manter.

### Supabase

| item | data | na janela? | aplicavel aqui |
|---|---|---|---|
| [Branching (doc viva)](https://supabase.com/docs/guides/deployment/branching) | sem data na pagina | - | **decisivo, e no sentido negativo.** Preview branches sao efemeras e **nascem sem dado**: *"do not start with any data from your main project"*. Isso **inviabiliza** mover os 43 invariantes de dado e os 321 arquivos comportamentais para la |
| [Branching 2.0](https://supabase.com/blog/branching-2-0) | **julho de 2025** | **nao, ~13 meses** | continua sendo a orientacao vigente de branching. Dito com a data, como pede o metodo |
| CLI: `supabase link` aceita nome/UUID de branch; `pg-delta` como motor de diff (public alpha) | changelog de jul/ago 2026 | sim | util **se** houver branch efemera para linkar. Depende da decisao acima |
| `log_connections` desligado por padrao em projetos novos | **09/07/2026** | sim | baixa, mas relevante se for instrumentar o pool do #1844 |

**A leitura:** o Supabase resolve o problema 2 do arranque (DDL antes do merge serializa as PRs),
porque cada PR ganharia seu proprio banco com suas proprias migrations. Ele **nao** resolve o
problema 6 (teste comportamental sobre dado de producao), e piora: transforma vermelho legitimo em
verde por vacuo. Qualquer adocao aqui precisa vir **depois** da separacao da secao 4, nao antes.

### Cloudflare

| item | data | na janela? | aplicavel aqui |
|---|---|---|---|
| [`wrangler deploy` envia metadados de dependencia npm](https://developers.cloudflare.com/changelog/post/2026-07-07-wrangler-deploy-upload-dependencies-metadata/) | **07/07/2026** | **sim** | **direto no #1896.** A causa la foi uma publicacao npm quebrada de terceiro derrubando um check required. Visibilidade de cadeia de suprimentos no deploy e o complemento defensivo |
| [Perfil de startup do Worker (`wrangler check startup`)](https://developers.cloudflare.com/changelog/post/2026-07-31-wrangler-startup-profile-summary/) | **31/07/2026** | sim | baixa hoje |
| [`@cloudflare/workers-types` v5](https://developers.cloudflare.com/changelog/post/2026-07-03-workers-types-v5/) | **03/07/2026** | sim | baixa hoje |
| [Workers Builds / preview deployments](https://developers.cloudflare.com/workers/ci-cd/builds/) | doc viva, sem data | - | daria URL de preview por PR (`wrangler versions upload`). **Acrescenta superficie**, e o diagnostico aqui e de excesso de acoplamento, nao de falta de ambiente |
| Remote bindings sem flag experimental (Wrangler/Vite/Vitest) | agosto de 2026 | sim | interessante a medio prazo para exercitar codigo local contra recurso remoto |

### Anthropic

| item | data | na janela? | aplicavel aqui |
|---|---|---|---|
| [Code Review for Claude Code](https://claude.com/blog/code-review) | **09/03/2026** | **NAO, 165 dias** | continua sendo a orientacao vigente. Dito com a data |
| [Engineering blog](https://www.anthropic.com/engineering) | mais recente: **23/04/2026** | **NAO** | **nada publicado na janela de 60 dias** sobre agentes em CI, revisao ou testes |

Do post de 09/03, o que se aplica direto a este diagnostico e a **postura**, e ela e a oposta do
instinto de adicionar mais um portao: a revisao por agentes e **consultiva**, nao bloqueante
("*It won't approve PRs - that's still a human call*"), com **menos de 1% dos achados marcados como
incorretos** e cobertura de review substantivo subindo de 16% para 54% das PRs. E o mesmo principio
que o `INVARIANT_STRICT` do #1850 ja aplica aqui: **profundidade fora do portao, portao estreito.**

---

## 9. Recomendacao priorizada

Ordenada por (retorno medido) / (risco de mexer). **Nada disto foi executado.**

### A. Decisao do PM (muda o contrato do portao)

| # | decisao | retorno medido | risco |
|---|---|---|---|
| **A1** | **Partir `npm test` em dois jobs: `structural` (287 arquivos, hermetico, paralelo, sem faixa de banco) e `behavioural` (321 arquivos, faixa de banco, serial). Manter os DOIS required.** | tira 287 arquivos de tras de uma espera de p90 14m21s. Feedback estrutural em ~13s em vez de ~14min. Nao reduz o caminho critico do `behavioural`, mas separa 47% da suite de uma contencao que nao lhe pertence | medio. Exige atualizar `1505-ci-db-suite-serialization` e `1509-db-lane-runtime-serialization`, que travam a fiacao atual. Exige adicionar o novo nome de check as protecoes de branch |
| **A2** | **Tirar os testes de invariante de DADO do check required, deixando-os no `invariants-check` (que ja roda em modo estrito, ja tem cron e ja nao e required), com o heartbeat abrindo issue.** | e a unica mudanca que resolve a causa dos travamentos 6 e do card de XP: um evento de producao legitimo deixa de reprovar PR de docs. Hoje isso esta congelando a fila | **alto, e e o ponto que exige decisao.** Perde-se o canario largo dentro do portao. A contrapartida honesta e que esse canario **ja** e um sinal nao-acionavel pelo autor da PR |
| **A3** | **Parar de rodar `validate` em `push` para main, OU fazer `deploy.yml` depender dele.** | 72 de 200 runs amostrados. Libera a faixa do banco logo apos o merge, que e exatamente quando a proxima PR precisa dela. Hoje o deploy (p50 1m22s) publica ~12 min antes do check pos-merge terminar, entao o check pos-merge nao protege deploy nenhum | baixo tecnicamente, mas e escolha de governanca: e aceitavel publicar sem portao pos-merge, desde que dito |
| **A4** | **Migrar branch protection legada para ruleset** (o GitHub tem migracao automatica desde 11/08/2026) | portao novo do GitHub nasce em ruleset. Ganha bypass por ator explicito e auditavel, que e melhor que `enforce_admins: false` para o protocolo de bypass que ja existe | baixo. Reversivel |
| **A5** | **NAO adotar merge queue agora**, e **NAO mover teste de dado para branch efemera do Supabase** | ver secao 8: a fila nao ataca nenhuma das duas causas medidas, e a branch efemera nasce sem dado, trocando vermelho legitimo por verde por vacuo | decisao de nao-fazer |

### B. Conserto mecanico (nao muda o contrato do portao)

| # | conserto | retorno medido | risco |
|---|---|---|---|
| **B1** | **Fixar `deno-version` numa versao exata** em `deno-ef-check.yml`. Hoje ainda esta `v2.x`, flutuante. O comentario do #1896 nomeia a flutuacao como amplificador ("o runner instalou 2.9.5, que falha; 2.5.6 passa"), mas o conserto entregue foi so o `DENO_NO_PACKAGE_JSON` | 1 linha. Elimina a metade nao consertada de um dos 6 travamentos | minimo |
| **B2** | **Mover `Build Project` e `Smoke Test Routes` para antes de `Run Unit Tests`**, ou para um job hermetico proprio | 41s somados, hermeticos, 0 vermelhos nos 45 runs com detalhe de passo. Hoje uma quebra de build so aparece no minuto 12 | minimo |
| **B3** | **Consertar os 5 alvos instaveis** (secao 5) com o padrao do #1113: escolher pela propriedade, degradar dizendo por que. **Com injecao de defeito provando que ainda reprova** | previne a repeticao de um travamento que ja custou uma investigacao inteira. Nenhum dispara hoje, entao e prevencao, nao urgencia | baixo, mas exige o experimento de injecao para nao virar verde por vacuo |
| **B4** | **Dar prazo (`expires`) e issue as 823 entradas de tolerancia**, comecando pelas 693 do `MIGRATION_FILE_DRIFT_BASELINE_P224`. O formato ja existe em `invariant-exceptions.mjs` | converte 823 numeros em divida datada. O ratchet do `RPC_BODY_DRIFT` (225 para 0) prova que funciona | baixo, mas e trabalho de volume |
| **B5** | **Decidir sobre os 20 specs Playwright que nunca rodam** (`tests/e2e/` + 2): ligar num job nao-required, ou apagar | 20 arquivos que parecem cobertura e nao sao | minimo |
| **B6** | **Tornar `quality_gate` o unico check required agregador, ou apaga-lo.** Hoje ele declara `needs` dos 3 jobs e ecoa um `echo`, sem ser required | limpa um job por run verde e, se virar o agregador, simplifica a lista de required para 1 nome estavel | baixo. Se virar agregador, atencao a regra do GitHub de que job `skipped` conta como passado |
| **B7** | **Uniformizar `actions/checkout@v4` para `@v6`** em `deno-ef-check.yml` (unico fora do padrao) | higiene | minimo |
| **B8** | **Instrumentar o consumo de API do `wait-for-db-lane`** antes que ele volte a falhar por cota | ~57 ciclos de polling por job em espera no p90, 2 jobs na faixa. Ja mordeu no #1509/#1844 | minimo (so medicao) |

### C. Fora do escopo de CI, mas e a causa raiz de um dos travamentos

| # | item |
|---|---|
| **C1** | **#1586 (superficie autenticada para `selection_rescue_unbooked_invite`).** Enquanto a unica porta for `service_role`, toda decisao manual do PM vira linha sem ator, e o allowlist do #1636 cresce a cada tentativa. Hoje ele iria para 6 entradas, e a sexta e a **quinta tentativa na mesma candidatura**. Nenhum conserto de CI resolve isso |

---

## 10. O que esta lane NAO fez, de proposito

- **Nao alterou** workflow, teste, allowlist, protecao de branch ou required check.
- **Nao rodou** a metade comportamental da suite localmente. Ela escreve em producao (`tx=rollback`
  nao desfaz INSERT de SECURITY DEFINER) e disputa o mesmo pool do trafego real. Medi-la teria sido
  a lane injetando na producao a carga que veio estudar. Os numeros da metade comportamental vem do
  log TAP da propria CI e da subtracao da metade estrutural, que essa sim rodei.
- **Nao diagnosticou** a origem da linha de `gate_attempts` de 21/08 14:18:47. Caracterizei a
  digital dela (mesma candidatura, mesma RPC, mesma recusa das 4 de 20/08); atribuir origem e escopo
  do #1636.
- **Nao classificou** os 203 sitios `[0]` um a um. E teto superior, nao lista de defeitos.

---

## Apendice: numeros do arranque que a medicao de hoje corrigiu

| medida | no arranque | medido em 21/08/2026 |
|---|---|---|
| duracao do `CI Validate` | ~13 min | **p50 14m05s, p90 26m41s, max 117m50s** |
| duracao do `Schema Invariants` | ~6 min | **p50 11m36s, p90 24m27s, max 53m12s** |
| custo de `check_schema_invariants()` em SQL puro | 2,53 s (#1844, 17-18/08) | **72 ms a frio, 13 a 14 ms a quente. Nao reproduzi os 2,53 s** |
| arquivos de teste | 611 | **631** (610 `.test.mjs` + 21 `.spec.ts`) |
| testes de contrato | 594 | **593** em `tests/contracts/` |
| allowlists | 2 arquivos (26 e 15 linhas) | **8 arquivos, 823 entradas**, mais 22 allowlists em codigo |
| allowlist de body-drift (P175) | 26 linhas | 26 linhas, **0 entradas** (eram 225 no p175: o ratchet zerou) |

Metodo dos numeros novos: API de Actions (200 runs mais recentes por workflow dentro de 30 dias,
contagem total via `total_count`), log completo do run 32481010980, `EXPLAIN ANALYZE` e
`clock_timestamp()` contra `ldrfrvwhxsmgaabwmaik`, e execucao local do subconjunto estrutural em
node v24.19.0.
