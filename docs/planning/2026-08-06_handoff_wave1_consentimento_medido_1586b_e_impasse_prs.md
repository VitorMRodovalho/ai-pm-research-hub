# Handoff, Wave 1: consentimento medido, #1586(b) pronto, impasse dos PRs resolvido (06/08/2026, noite)

> Repo PÚBLICO. Nenhum candidato nomeado. Números são contagens.
> Supersede a Parte 3 do `2026-08-06_handoff_wave0_fechada_wave1_arranque.md`, cujos números do
> ciclo seletivo estavam certos na contagem e errados na interpretação.
> **Nada deste documento pode ser recitado. Re-medir.**

---

## Parte 1, o que a medição desmentiu

Três premissas do handoff anterior não sobreviveram à medição direta. Não são erros de aritmética,
são erros de leitura: os números batiam e significavam outra coisa.

### 1.1 Consentimento, a medição que faltava

Os dois conjuntos coincidem: 47 consentiram e têm análise, 34 não têm nem uma coisa nem outra, zero
revogações, zero casos cruzados. Mas a coincidência é **estrutural**, não informativa:
`analisou_sem_consentir = 0` nos quatro ciclos históricos, ou seja, a análise é gateada pelo
consentimento por construção. Medir uma e citar a outra continua sendo método errado, mesmo quando
dá o mesmo número.

O que a medição direta acrescenta, e é o insumo que muda a pergunta jurídica, é a decomposição dos
34 por evidência de token de onboarding:

| situação | n |
|---|---|
| nunca recebeu token, nunca foi perguntado | 1 |
| recebeu token e **nunca abriu** o portal | 27 (apenas 1 com token ainda válido) |
| abriu o portal e não consentiu, opt-out ativo | 6 |

Só **6 dos 34** exerceram escolha. Outros 28 nunca se manifestaram, e **26 desses não conseguem
consentir hoje nem querendo**, porque só têm tokens expirados. Tratar "sem consentimento" como
"recusou" é falso para 28 dos 34.

> **Armadilha de método registrada.** A primeira leitura deu "34 nunca foram perguntados", porque o
> filtro usou `source_type = 'selection_application'` e o valor real é `pmi_application`. Vocabulário
> errado de discriminador fabrica coorte. O que pegou foi rodar o **grupo de controle** (os 47 que
> consentiram): se eles também aparecessem sem token, o filtro estaria errado. Apareceram.

> ⚠️ **"Opt-out ativo" é INFERÊNCIA, não evento registrado.** Medido depois, a pedido do parecer
> jurídico: as únicas colunas de consentimento são `consent_ai_analysis_at` e
> `consent_ai_analysis_revoked_at`. **Não existe carimbo de recusa.** Logo os 6 são "abriu o portal
> ao menos uma vez e nenhum consentimento foi gravado", o que é compatível tanto com recusar quanto
> com abandonar o onboarding no meio. O modelo de dados não distingue as duas coisas. Isso não muda
> a proteção ao candidato (sem consentimento, não há análise), mas muda o que a instituição
> consegue **provar** se precisar demonstrar que respeitou uma recusa expressa.

### 1.2 As 206 recusas `GATE_NO_AI` não são produção

- recusas com `caller_id` não nulo: **0**
- recusas na janela do cron (15:30 a 15:35 UTC): **0**
- 203 das 206 concentradas em **2** candidaturas, uma delas com `app_status = 'rejected'`, martelada
  104 vezes por um token de entrevista

Origem: `tests/contracts/1594-1595-*` e `1598-1599-*` escolhem candidatura real de produção por
predicado e chamam `_issue_interview_booking_token_core` com `p_caller_id: null`. O propósito
declarado do teste é que a linha de recusa **sobreviva** ao rollback. Cada `npm test`, local ou em
CI, sedimenta recusas em prod, sempre nas mesmas candidaturas reais.

**O gate nunca recusou um despacho real.** Isso não o inocenta: ele nunca mordeu porque o cron que o
acionaria não enxerga os afetados. Issue **#1636** aberta.

### 1.3 Não são 35 candidaturas invisíveis, são 4

Dos 35 sem carimbo de convite: 19 `approved`, 6 `final_eval`, 1 `interview_done`, 4 `rejected`, 1
`submitted`, e **4** em `interview_pending`.

Os 26 que avançaram sem carimbo revelam o modelo real de operação: 24 deles têm linha de entrevista
com **zero** log de despacho e **zero** token de agendamento. As entrevistas foram marcadas fora da
maquinaria. Contraparte: dos 46 com carimbo, 43 têm log de despacho. Existem dois caminhos
paralelos, o automático e o manual, e os 4 presos caíram entre os dois.

**E não estão parados há 21 dias.** Os 21,4 dias são idade da candidatura. A segunda avaliação, que
os torna elegíveis ao gate, caiu em 04/08 e 06/08: estão elegíveis há 2,06 / 2,04 / 0,30 / 0,30
dias. Todos os quatro passam nos gates 2 e 3 (duas avaliações, nota calculada) e falham só no 1.

---

## Parte 2, #1586(b): duas cegueiras empilhadas

Branch `fix/1586b-detector-ciclo-e-anchor-elegivel`, commit `17bb7b5a`. **Sem push e sem DDL
aplicada** (ver Parte 3, é deliberado).

### Causa 1, o detector varre o ciclo errado

`detect_stuck_selection_funnel` resolvia `active_cycle` por `ORDER BY created_at DESC LIMIT 1`. O
ciclo `cycle2-2025` foi carregado no banco em **13/07/2026** com datas de 2025 e `created_at` de
2026: virou "o mais recente". Desde então o detector varre um ciclo FECHADO de 8 candidaturas
enquanto o aberto tem 81, e devolve `0/0/0` com `status: succeeded` no `cron.job_run_details`.

`created_at` é a data em que a LINHA foi escrita, não a data em que o ciclo aconteceu.

### Causa 2, o anchor exclui justamente a coorte-alvo

Os dois buckets ancoram em `cutoff_approved_email_sent_at`, NULL por definição para quem nunca
recebeu convite. Bucket A exige `IS NOT NULL`; bucket B compara `< now() - grace` contra NULL, o que
dá NULL e também exclui.

### Por que as duas tinham de cair juntas

Predicado do bucket C novo, rodado como SELECT puro contra os dados vivos antes de qualquer DDL:

| leitura de ciclo | bucket C |
|---|---|
| `status = 'open'` (nova) | **2** |
| `created_at DESC LIMIT 1` (antiga) | **0** |

Consertar só o anchor continuaria dando zero, porque o ciclo está errado. Consertar só o ciclo
continuaria dando zero, porque o anchor exclui a coorte. Quem consertasse uma, medisse "continua
zero" e concluísse "não era isso" reverteria um conserto correto.

### O que a migration faz

- `active_cycle` por `status = 'open'`, via JOIN e sem `LIMIT 1`, para dois ciclos abertos
  simultâneos não fazerem um sumir calado
- bucket C `selection_candidate_eligible_uninvited`, ancorado em `eligible_at` (instante da 2ª
  avaliação), exigindo nota calculada, sem linha de entrevista e sem log de despacho
- `eligible_uninvited_grace` = **2 dias**, da família "bola do lado da ORGANIZAÇÃO" que já existe em
  `sla_policies` (`stuck_scheduled_grace` 48h, `reapply_invite_grace` 2 dias). Os 10 dias de
  `interview_booking_grace` são a família "bola do lado do CANDIDATO" e não cabem aqui
- o type novo entra na janela de idempotência de 7 dias, senão renotifica o GP todo dia

**Efeito hoje: 2 notificações**, não 4. As outras duas entram em cerca de 2 dias. (O handoff anterior
e uma fala minha de meio de sessão diziam 4; está corrigido aqui.)

### O que a migration NÃO faz, e por quê

Não despacha convite. As 4 candidaturas desta coorte não têm análise de IA, logo o core as recusaria
com `GATE_NO_AI` em modo `full`. E na recusa o `selection_rescue_unbooked_invite` **não** incrementa
o contador e devolve o carimbo, então despacho automático aqui viraria laço diário de recusa com
zero e-mails: trocaria verde-e-vazio por vermelho-e-inútil.

**Isso inverte a premissa do handoff anterior.** O #1586(b) é tecnicamente independente da decisão
jurídica, mas o efeito dele nesta coorte é inteiramente determinado por ela. É o (b) que **liga** o
#1632. Escopo "só visibilidade" decidido pelo PM em 06/08.

### Teste

`tests/contracts/1586b-detector-cycle-and-uninvited-anchor.test.mjs`, ligado nas **duas** whitelists
do `package.json` (537 para 538). Afirma a REGRA, nunca o instantâneo: a coorte esperada é
recalculada contra os dados vivos a cada execução e comparada com o que o detector reporta. O guard
da causa 1 proíbe `created_at` de voltar àquela CTE. Todas as chamadas usam `p_dry_run := true`.
Parte offline verde (3 passam, 6 pulam sem credencial).

---

## Parte 3, o impasse dos PRs e por que a ordem do handoff era impossível

A Wave 0 aplicou DDL direto em prod antes do merge. Três gates comparam a árvore do branch contra o
banco vivo, então **todo branch que não carrega o `.sql` fica vermelho por causa que não é dele**:
`gen-types-drift`, órfãos Track Q-C e missing-file drift ADR-0097. O próprio teste nomeia:
`PROD-AHEAD / DDL-lag ... DDL on a shared DB serializes PRs (apply -> merge -> apply)`.

Daí o impasse circular:

- **#1635 não fica verde sozinho.** Muda UM arquivo de teste e falhava nos três gates, porque só o
  #1633 carrega a migration `20260806000100` e o `database.gen.ts` com as duas RPCs novas.
- **#1633 não ficava verde sozinho.** Falhava em `p246-229b` (que é o que o #1635 conserta) e numa
  asserção que **ele mesmo invalidou**: sobe `ef_version` 2.94.0 para 2.95.0 em
  `supabase/functions/nucleo-mcp/index.ts` e deixou o literal em
  `tests/contracts/mcp-lgpd-retroactive-operator-tools.test.mjs` para trás. Terceira quebra do mesmo
  teste pelo mesmo motivo, e o nome dele registra a série: 2.93.0 (#1619), 2.94.0 (#1620), 2.95.0
  (#1631).

**Resolução:** cherry-pick de `35b5153f` (o commit do #1635, autoria preservada) para o branch do
#1633, mais o conserto da asserção de `ef_version`. O #1633 passa a carregar o conteúdo dos dois.
Commits `6afb4260` e `39864911`.

> **Vermelho que não é defeito.** O primeiro `check-invariants` do #1633 falhou após esperar 900s
> pela faixa de banco e desistir, em vez de rodar concorrente contra prod (#1509). Foi contenção
> criada por reemitir os dois PRs de uma vez, não regressão. Distinguir isso importa: um vermelho de
> contenção lido como defeito é o caminho curto para um bypass injustificado.

---

## Parte 4, o parecer jurídico do #1632

`legal-counsel` acionado com a decomposição dos 34. O parecer achou uma coisa que a medição sozinha
não alcançava, e ela é textual:

**A comunicação nega ativamente a consequência que existe.** A tela primária de consentimento
(`src/i18n/pt-BR.ts` linha 6715) apresenta o consentimento como acelerador opcional, sem qualquer
menção a efeito sobre o convite. O e-mail de nudge
(`20260517100000_consent_nudge_template_and_dispatch_rpc.sql`, linhas 36-38) vai além e instrui:
*"se já completou ou prefere não dar consentimento de IA, ignore esta mensagem"*. Como a
consequência existe (não avançar), a informação prestada foi **falsa por conteúdo declarado**, não
apenas incompleta. O art. 18, VIII da LGPD é textualmente sobre isso: direito à informação sobre as
consequências de negar consentimento. O art. 8º, §2º põe o ônus da prova no controlador, e a própria
evidência documental prova o vício.

Pontos adicionais do parecer, resumidos: o gate usa a ausência do consentimento (base do art. 7º, I)
para negar efeito de uma base distinta e autônoma, o art. 7º, V do procedimento seletivo; a política
pública cita as duas bases para a mesma operação, o que é incoerente; e há risco concreto de art. 20
(decisão automatizada com efeito adverso e sem revisão humana no ponto da recusa), agravado por a
própria plataforma já ter reconhecido esse risco e desenhado uma via manual de contorno que o gate
contorna.

**Grounding, porque importa:** o parecer citou de handoff antigo "18 de 50 aprovadas sem
`ai_analysis`". Re-medido nesta sessão contra o banco vivo, e confere: **50** aprovadas, **18** sem
`ai_analysis`, **17** delas com entrevista registrada. Ou seja, a evidência de que a análise não é
necessária ao mérito é real. Os outros números do parecer que vieram de handoff não foram
re-medidos e **não devem ser recitados**.

O parecer também pediu uma medição, que foi feita e está na Parte 1.1: não existe carimbo de recusa
no modelo de dados.

Recomendação priorizada dele: (1) tirar `ai_analysis`/`consent_ai_analysis_at` da pré-condição do
convite, mantendo `GATE_NO_PEER_REVIEW` e `GATE_NO_SCORE`, que não têm problema de LGPD; (2)
reprocessar as bloqueadas; (3) corrigir o texto da tela e do nudge **depois** de (1) estar em
produção, nunca antes; (4) corrigir a política pública; (5) reemitir token aos 26 impedidos; (6)
registrar a remediação no formato do precedente de art. 11; (7) auditar se outros "consentimentos
opcionais" têm gate equivalente escondido.

**Tudo isso é decisão do PM.** Nada foi implementado.

---

## Parte 5, estado ao fechar

| item | estado |
|---|---|
| **#1633** | **MERGEADO** em `cdb77a51`, 12/12 gates verdes. Carrega Wave 0 + o teste do #1635 + a asserção de `ef_version`. |
| **#1635** | conteúdo já na main (md5 do arquivo idêntico). Comentado no PR. **Decisão pendente: fechar como superseded ou rebasear.** |
| **#1586(b)** | **MERGEADO** em `864d4cf6` via PR #1638, 12/12 gates verdes. DDL aplicada (`20260807000100`, ritual GC-097 completo, phantom apagada). Teste 9/9 com credencial, zero skips. **A metade (a) do #1586, superfície MCP para reenvio humano, continua ABERTA.** |
| **#1636** | aberta, poluição de `gate_attempts` por contract test. |
| **#1632** | parecer do `legal-counsel` na Parte 4. Decisão do PM. |
| **#588 [LL]** | 4 lições registradas para o harvest do PMO. |

**Verificação do efeito, antes e depois:**

| | `unbooked` | `noshow` | `eligible_uninvited` |
|---|---|---|---|
| antes | 0 | 0 | (chave não existia) |
| depois | 0 | 0 | **2** |

**Bypass:** janela de 7 dias segue em **1 de 2**. Nada nesta sessão usou bypass.

> ✅ **PROD-AHEAD fechado** no merge do #1638: a versão `20260807000100` está rastreada no banco
> **e** o `.sql` está na main. Os 8 outros PRs abertos (#1605, #1166, #1146, #1066, #863, #765,
> #289, #154) voltaram a poder ficar verdes sem rebase por essa causa.

**Cadeia de entrega verificada:** cron `detect-stuck-selection-funnel-daily` ativo, `0 16 * * *`,
`p_dry_run := false`, e existem **2** membros com `operational_role = 'manager'` para receber o
fan-out. Sem essa última conferência o bucket contaria 2 e inseriria 0, que é a mesma família de
falha silenciosa que esta issue trata.

### A ordem ao retomar

1. Decidir a disposição do #1635 (no-op comprovado por md5).
2. Decidir o #1632 à luz do parecer. Atenção à ordem do item (3) do parecer: **não publicar o texto
   novo antes de o gate estar corrigido em produção**, senão cria-se a mesma informação falsa na
   direção inversa.
3. #1586(a): expor `selection_rescue_unbooked_invite` no `interview_manage`, para o reenvio humano
   sair com `caller_id` em vez de "sistema".
4. Conferir no dia seguinte que o cron das 16:00 UTC realmente inseriu as notificações (ler o
   EFEITO, não o `status: succeeded` — foi exatamente isso que escondeu o defeito por 24 dias).
5. Follow-up anotado: a asserção de `ef_version` quebrou 3 vezes seguidas pelo mesmo motivo (mora
   longe do valor que espelha). Candidata a derivação.

### Regras da casa, inalteradas

- Números vêm de tool call na MESMA volta. Re-medir sempre.
- Teste novo não roda em CI se não estiver nas **duas** whitelists do `package.json`.
- `npm test` sem `.env` exportado pula cerca de 548 testes calado. Conferir o número de skips.
- Não rodar `npm test` local com CI em voo: as suítes DB-aware escrevem em prod.
- Merge à `main` é da sessão main. Lane leva o PR até verde e para.
- Commit: `Assisted-By: Claude (Anthropic) <noreply@anthropic.com>`, nunca `Co-Authored-By`.
