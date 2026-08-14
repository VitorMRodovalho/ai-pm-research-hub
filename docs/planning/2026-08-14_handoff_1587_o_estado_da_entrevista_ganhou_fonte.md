# Handoff — #1587: o estado da entrevista ganhou uma fonte (e o cache que nunca chegava ao fim)

> Sessão de 14/08/2026, madrugada. Continuação do arranque
> `docs/planning/2026-08-14_PROMPT_ARRANQUE_1590_ONDA_E.md` (PR #1769).
> **Todos os números abaixo foram medidos nesta sessão. Nenhum é recitável: re-meça antes de usar.**

---

## O que fechou

| PR | o que é | estado |
|---|---|---|
| **#1752** | handoff da lane Biblioteca | **mergeada**, 11/11 verde, `CLEAN`, zero bypass |
| **#1770** | #1587 — a view canônica + o dashboard derivando dela | aberta nesta sessão |
| **#1769** | prompt de arranque da onda E | rebasada; ver "o vermelho que eu causei" |

`main` foi de `0aa661f4` para `e21d6669` com o merge do #1752.

---

## O item da vez: #1587

### O que a issue supunha, e o que a medição achou

A issue descrevia o viés da **última linha por data**: o trigger
`trg_supersede_prior_open_interviews` cancela as anteriores ao criar uma nova, então a linha com
maior `scheduled_at` pode ser uma cancelada por supersede enquanto a realizada está em outra linha.

Isso é real e foi confirmado: **14** candidaturas com mais de uma linha (34 linhas), das quais
**5** dão resposta errada (4 cuja última por data é `cancelled`, 1 `scheduled`, todas já
realizadas).

**Mas o grosso do dano estava em outro lugar, e é o 3º checkbox da issue.** A coluna
`selection_applications.interview_status` **nunca assume `completed`**:

| domínio vivo do cache | linhas |
|---|---|
| `none` | 131 |
| `scheduled` | 37 |
| `needs_reschedule` | 1 |
| `rescheduled` | 1 |

Varri as **29** funções vivas que tocam `selection_interviews` e **nenhuma** escreve `'completed'`
nessa coluna. Só `request_interview_reschedule` e `process_pending_reschedule_nudges` escrevem
literal, e ambas escrevem `needs_reschedule`. Resultado: **106 de 170** candidaturas exibiam no
dashboard um estado divergente do que as próprias linhas provam (dessas, **97 das 107** com
entrevista realizada).

### A ressalva que muda a urgência, e que eu só soube ao medir

Um cache errado **não é** automaticamente um bug de comportamento. Medi as duas superfícies que
poderiam AGIR sobre o valor:

- RPC `selection_rescue_stuck_interview`: **0** candidaturas exploráveis hoje.
- fila de convite do admin (`selection.astro:1819`): **0** vazamentos.

Nas duas, o `app.status` neutraliza o cache errado. Isso é
**contenção por DADO, não por estrutura** — vale hoje, por acidente do dado. O dano real era de
**LEITURA**: o que o operador vê na tela.

Dizer "bug crítico de despacho" teria sido falso. Dizer "só cosmético" também.

### Varredura das 29 funções (o que NÃO estava enviesado)

Só **uma** escolhe uma linha por ordenação de data pura: `selection_rescue_stuck_interview`
(`ORDER BY scheduled_at DESC LIMIT 1`). Mas ela já filtra `status='scheduled' AND conducted_at IS
NULL`, portanto **não cai no viés**. `mirror_sibling_interview` ordena por `conducted_at DESC`
primeiro, e por isso já acerta.

O arranque dizia que as duas liam "a mais recente por data". Uma lê; a outra não.

### Classificação das 14 multi-linha

| classe | candidaturas |
|---|---|
| supersede (1 realizada + canceladas) | 8 |
| nenhuma realizada | 3 |
| 1 realizada + 1 aberta | 2 |
| **duplicate_suspect** | 1 |

A `duplicate_suspect` tem 4 linhas, **2 `completed` a 8 minutos de distância**, e **1** nota de
entrevista. Nenhuma candidatura casa hoje com a assinatura de `dual_track` por instante idêntico —
a que a issue citava de 03/08 não aparece mais com esse formato.

### O que entrou (PR #1770)

- **`v_application_interview_state`**, `security_invoker = true`, sem `anon`:
  - `ja_realizada = bool_or(status='completed' OR conducted_at IS NOT NULL)` sobre **todas** as
    linhas;
  - linha canônica por **significado** (realizada > aberta futura mais próxima > aberta passada),
    não por acidente de `scheduled_at`;
  - `multiplicity_class` separando supersede / dual_track / duplicate_suspect;
  - `cache_is_stale`, para o ratchet medir a divergência encolher.
- **`get_selection_dashboard`** deriva `interview_status` da view; o cache continua no payload sob
  `interview_status_cache`.
- **Teste de contrato** `1587-estado-canonico-da-entrevista.test.mjs`, camadas A (estática) + B
  (viva). Rodado com credenciais: **10/10, 0 skipped**.

### ⚠️ A decisão de forma que é fácil desfazer sem perceber

**`needs_reschedule` vem do CACHE, de propósito.** É estado de INTENÇÃO (quem PEDE remarcação),
não derivável das linhas de entrevista, e o filtro da fila de convite depende dele. "Simplificar"
a view para derivar tudo das linhas **apaga a fila**. O teste A5 proíbe.

---

## O vermelho que eu causei, e como se corrige

Apliquei as duas migrations ao banco **antes** de a PR mergear. O banco é **um só e compartilhado**,
então a partir daquele instante toda branch aberta que não tivesse os arquivos passou a acusar:

- `Phase C: no NEW body-hash drift vs p175 allowlist`
- `ADR-0097: no NEW missing-file drift vs p224 baseline (tracked − local)`

A **#1769**, que é só documentação e não tocou em SQL nenhum, ficou vermelha por isso.

**Não é flake e não justifica bypass — é ordenação.** Prova: na branch do #1770, que carrega os
arquivos, o mesmo arquivo de teste roda **22/22, 0 falhas**.

**Ordem correta:** mergear #1770 → `gh pr update-branch 1769` → #1769 fica verde.

**Lição para a próxima sessão que aplicar DDL:** aplicar cedo abre uma janela em que TODA PR aberta
do repositório está vermelha, e a janela dura até o merge. Se houver PRs esperando merge, aplique
depois delas.

### E o custo maior: o trabalho ficou INSEPARÁVEL em PRs

O despacho manual (adiante) disparou o guard do #1636, e abri a **#1771** só para o allowlist,
por decisão do PM de isolar a correção. Ela **não podia ficar verde** — e a #1770 também não:

| PR | carregava | falhava em |
|---|---|---|
| **#1771** | allowlist do #1636 | `gen-types-drift`, `Phase C`, `ADR-0097` |
| **#1770** | migrations + `database.gen.ts` | guard `#1636` |

**Dependência circular:** cada uma descrevia metade do banco vivo, e o CI compara contra o banco
inteiro. Saída: `cherry-pick` do commit do guard para a #1770 e **#1771 fechada** como registro do
raciocínio.

**A regra:** depois que a DDL está no banco, **tudo que toca o schema vira uma única unidade
mergeável** — migrations + tipos gerados + qualquer guard que o novo estado afete. Planeje UMA PR,
ou aplique a DDL só depois de decidir o recorte.

---

## O funil da onda D saiu do vácuo

Por decisão do PM, disparei um **despacho real** (e-mail de verdade a um candidato real), com o
alvo confirmado antes: a candidatura mais antiga da fila (convite de 04/08, 10 dias esperando, 2
despachos anteriores, nenhuma linha de entrevista, resgate único intacto).

| | antes | depois |
|---|---|---|
| linhas em `selection_dispatch_url_log` | 94 | **95** |
| instrumentadas | **0** | **1** |
| com `booking_token_md5` | **0** | **1** |

A linha nova nasceu com `instrumented = true` e o hash md5 de 32 caracteres, como a onda D
desenhou. `resolution_path = committee_override`, token expira em **28/08**.

**As 2 linhas antigas da mesma candidatura NÃO foram supersedidas, e isso está certo:** o `UPDATE`
de supersede tem `AND instrumented` na cláusula. Supersedê-las afirmaria que foram medidas.

⚠️ **Os carimbos de ABERTURA e RESERVA seguem sem exercício** — dependem do candidato abrir o link.
**Nenhum número de conversão do funil pode ser publicado até uma linha real carimbar os dois.**

### ⚠️ O despacho manual disparou o guard do #1636, e o guard estava CERTO

Chamar `selection_rescue_unbooked_invite` via REST/service_role deixa `caller_id` **nulo** — a
MESMA digital de uma escrita de teste em candidatura real, que é o que o guard B do #1636 caça.
Uma linha: `gate_attempts` `4b99b6dc`, RPC `_issue_interview_booking_token_core`, 14/08 02:26:19Z,
candidatura real, sem carimbo de execução de cron.

Três saídas foram **rejeitadas**, e vale que fiquem rejeitadas:

- **apagar a linha** destruiria auditoria de um e-mail que realmente chegou a uma pessoa;
- **carimbar um `cron_run` retroativo** inventaria uma execução que não houve;
- **aceitar `dispatch_source='cron'` do metadata como prova** afrouxaria o guard para tolerar
  QUALQUER chamada via service_role. O cron de verdade se distingue por carimbar também a
  **execução** (`selection.%cron_run%`, **197** linhas medidas); a chamada manual não carimba.

Entrou um **allowlist por ID** com o motivo na própria constante, mais a asserção de sincronia
(entrada sem linha viva tem de ser removida — a lista só encolhe).

**Isto é dívida, não isenção:** enquanto o #1586 não der superfície à RPC, a única porta é o
service_role e **toda** operação manual cai nesse allowlist, sem registrar autor. A saída é a tela
com autor autenticado.

### Efeito colateral, e ele muda o #1586

O despacho **consumiu o resgate único** daquela candidatura:

| `interview_pending` no ciclo aberto | 13/08 | 14/08 |
|---|---|---|
| total | 9 | **9** |
| já gastaram o resgate | 5 | **6** |
| ainda elegíveis | 4 | **3** |

Ou seja: uma tela para `selection_rescue_unbooked_invite` hoje **recusaria 6 dos 9 casos que
mostra** (a RPC levanta exceção em `interview_auto_rescue_count >= 1`). O ponto do arranque ficou
mais agudo, não menos.

Confirmei também que a RPC segue **sem superfície**: para disparar eu tive que chamá-la direto pela
porta REST com service_role, que é o caminho do cron — e é exatamente a evidência de que falta
superfície para uma pessoa fazer isso.

---

## Estado das issues

- **#1587** — os 3 critérios estão atendidos, mas **deixei ABERTA**. A PR usa `Refs`, não `Closes`:
  o cache continua divergente **no banco** (só a leitura foi corrigida), e o destino dele
  (backfill? trigger? deixar derivado para sempre?) é decisão do PM. Comentário com a medição
  completa está na issue.
- **#1586** — ABERTA, com a re-medição do cap comentada.
- **#1664**, **#1762** — não tocadas nesta sessão.

---

## Próximos passos sugeridos (não decididos)

1. **Mergear #1770, depois rebasar #1769.** Nessa ordem.
2. **Decidir o destino do cache `interview_status`** (#1587): a view já expõe `cache_is_stale` para
   medir. Enquanto o cache existir como coluna escrita por fora, ele volta a divergir.
3. **#1586** — desenhar a superfície JUNTO com o cap, não depois: 6 dos 9 já não passam.
4. **Conferir os carimbos de abertura/reserva** assim que o candidato abrir o link (token vence
   28/08). É a única prova que falta do funil.
5. ⏰ **Antes de 24/08**, re-medir o que a 1ª execução do cron `attendance-seal-window-daily`
   (#1710) vai gravar. Continua pendente, e a data se aproxima.
