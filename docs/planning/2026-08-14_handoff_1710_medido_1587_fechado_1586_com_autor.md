# Handoff — #1710 medido antes do prazo, #1587 fechado, #1586 com autor

> Sessão de 14/08/2026 (tarde). Anterior: `2026-08-14_handoff_1587_o_estado_da_entrevista_ganhou_fonte.md`
> Arranque desta sessão: `2026-08-14_PROMPT_ARRANQUE_1710_SELO_E_1587_BACKFILL.md`

---

## Regra zero

Todo número aqui foi medido em **14/08/2026** por consulta viva. Vários se movem sozinhos — dois já
se moveram entre o arranque e esta sessão. Re-meça na mesma volta em que o número entrar numa
decisão, num commit ou numa pergunta ao PM.

---

## Estado

`main` em **`2e315694`**. **PR #1774 mergeada** (#1586) com **12/12 gates verdes**. **Zero bypass**
nesta sessão.

**Aplicado em produção durante a sessão** (fora de PR, por serem atos e não código):

- **DML:** backfill do cache do #1587 — 97 linhas.
- **DDL:** migration `20260814154021_1586_resgate_manual_com_contador_proprio` (coluna nova +
  `selection_rescue_unbooked_invite`). Aplicada com **zero PRs abertas**, e o arquivo local renomeado
  para o timestamp da linha de tracking.
- **EF:** `nucleo-mcp` deployada, `/health` responde **`ef_version: 2.98.0`**.

---

## ⏰ #1710 — o que a primeira execução vai gravar, medido 10 dias antes

O cron `attendance-seal-window-daily` está **ativo** (`40 11 * * *`), piso **24/08**, carência **14
dias**. Ensaiado dentro de transação abortada; para projetar 24/08 sem esperar, a carência foi
deslocada para 4 dias (mesmo corte: `2026-08-10 11:40 UTC`).

| | ensaio de HOJE | projeção de **24/08** |
|---|---:|---:|
| `events_due` | 34 | **47** |
| coorte vazia (pulados) | 3 | **4** |
| eventos selados | 31 | **43** |
| **faltas materializadas** | 65 | **82** |

As 82 saíram por **dois caminhos independentes** (o retorno da função e uma consulta externa que
reproduz coorte + carência), e batem.

**Distribuição:** 41 pessoas, média 2,00, **pior caso 7**, 9 pessoas com 3 ou mais.

⚠️ **É teto, não previsão.** Toda presença registrada por um líder até 24/08 tira uma linha da conta.
**Re-medir na véspera.**

### O cuidado de coorte da issue: medido e fechado

- **0 células invisíveis nas duas grades.** Nenhuma falta seria gravada sem superfície.
- 75 aparecem na grade de tribo (`get_tribe_attendance_grid`, o caminho de correção pelo líder).
- 65 aparecem na grade geral (`get_attendance_grid`).
- **17** só na de tribo: são do evento `geral` "Aftershow Núcleo IA & GP", que tem `initiative_id`
  preenchido e cai no filtro `(e.initiative_id IS NULL OR e.type = 'tribo')` da grade geral.
- **7** só na geral: pertencem a membros **sem tribo**, que não têm grade de tribo nenhuma.

⚠️ **Pendência para o PM:** a decisão registrada é "correção pelo líder da tribo", e essas **7
células não têm líder de tribo que as alcance** — só GP, pela grade geral.

### Duas coisas que o arranque dizia e que a medição desmentiu

1. **`unseal_event_attendance` EXISTE** (o arranque dizia que não). Gateada em `_can_manage_event`,
   apaga só as linhas nascidas do selo e ainda **intocadas**, preserva e conta as que alguém marcou
   presente ou justificou.
2. **O selo NÃO "anda nos dois sentidos".** Ele grava **só `present=false`** para elegível sem linha,
   com `ON CONFLICT DO NOTHING`: nunca marca presença, nunca sobrescreve linha existente.

Os 4 primeiros itens de escopo do #1710 estão entregues (SealPanel em `/attendance`, selo na grade,
tool MCP `attendance_seal`, gatilho automático). O 5º só é respondível depois de 24/08.

---

## ✅ #1587 — FECHADA

**O `UPDATE` do arranque abortaria.** A coluna tem CHECK com cinco valores (`none`, `scheduled`,
`needs_reschedule`, `completed`, `rescheduled`) e a view emite três que não estão nele (`cancelled`,
`noshow`, `stuck`). Sendo atômico, o `UPDATE` sem filtro não teria gravado nenhuma das 106.

| | antes | depois |
|---|---:|---:|
| `cache_is_stale` | **106** | **9** |
| cache `completed` | **0** | 97 |
| cache `none` | 131 | 66 |
| cache `scheduled` | 37 | 5 |
| cache `needs_reschedule` | 1 | **1** |

`cache_completed = 0` no "antes" é a confirmação mais direta do diagnóstico da issue.

**Raio de ação: nenhuma mudança de comportamento.** Varrido `pg_proc`: 9 funções mencionam a coluna,
**só duas** a usam como predicado, e ambas sobre `needs_reschedule`, que o backfill não toca. No
frontend, a fila de convite lê a chave **já derivada da view**; o cache viaja como
`interview_status_cache`. O backfill fez a coluna alcançar o que a tela já mostrava.

📌 **Piso do alarme: `cache_is_stale = 9`.** Significa "a view tem domínio maior que a coluna".
Deriva real é **acima de 9**.

⚖️ **Decisão do PM (14/08):** deixar os 9 — ampliar o CHECK estenderia o domínio de uma coluna
demovida a cache, e `stuck` é derivado (pode deixar de valer sem escrita nenhuma).

---

## 🔁 #1586 — entregue (PR #1774), issue ABERTA de propósito

**Expor a RPC, sozinho, não resolveria:** medido em 14/08, **10** candidaturas em `interview_pending`
no ciclo aberto, das quais **7** já têm `interview_auto_rescue_count >= 1`. A superfície recusaria 7
dos 10 casos que ela mostra. (O arranque dizia 9 e 6 — os dois se moveram.)

⚖️ **Decisões do PM (14/08):** contador **separado**, **cap 3** no manual; auditoria antiga
**anotada como exceção**, não reescrita.

Entra: `interview_manual_rescue_count NOT NULL DEFAULT 0`; a RPC lê o cap do contador **do caminho**
(cron 1 / manual 3) e incrementa a coluna correspondente em **dois ramos separados**; MCP
`interview_manage action='rescue_unbooked'`.

### O detalhe que parece redundante e não é

Os dois ramos do incremento existem de propósito. O contrato do #1598 casa **por regex** o literal
`interview_auto_rescue_count = interview_auto_rescue_count + 1` e exige que ele apareça **depois** do
notify — é assim que prova que uma recusa de gate não queima o cap. Um `CASE WHEN ... THEN 1 ELSE 0
END` unificado apagaria o literal e desligaria esse guard em silêncio. O teste novo (A5) fixa isso
para a próxima pessoa não "simplificar" os dois ramos em um.

### A auditoria antiga é maior do que a issue dizia

`selection.unbooked_invite_rescued` tem **18 linhas**, todas com `actor_id` nulo e
`dispatch_source: 'cron'`. Cruzando com os carimbos de execução (±10 min contra qualquer
`selection.%cron_run%`): **17 das 18 não têm par** — 19/06 (1, com par) · 30/06 (6) · 03/08 (3) ·
06/08 (6) · 07/08 (1) · 13/08 (1).

A ausência de par é conclusiva porque `selection.unbooked_rescue_cron_run` tem 57 execuções cobrindo
**19/06 → 14/08 sem lacuna**. Sem essa conferência, "sem par" significaria apenas "não instrumentado".

O caminho sem autor foi usado em pelo menos **5 ocasiões distintas ao longo de dois meses**. É a
medida do custo de a superfície ter faltado.

### Por que a issue segue ABERTA

**O caminho com autor nunca foi exercido.** Está correto por construção e coberto por contrato
(11/11, camada B contra o banco), mas nenhuma chamada real passou por ele — e exercitar significa
despachar e-mail a um candidato de verdade, que é decisão do PM.

Mesma classe de "mecanismo armado e inerte" que o funil da onda D e os blackouts da onda C.
**Na primeira chamada real, conferir na linha nova do `admin_audit_log`:** `actor_id` **não nulo** e
`metadata->>'dispatch_source' = 'manual'`. Conferido isso, fecha.

---

## O erro de sequenciamento da sessão anterior NÃO se repetiu

A DDL do #1586 foi aplicada com **zero PRs abertas**, e migration + `database.gen.ts` + o guard de
`ef_version` foram para a **mesma PR**, que mergeou com `gen-types-drift` e `check-invariants` verdes.
O banco e a `main` voltaram a coincidir no mesmo merge — nenhuma branch ficou vermelha.

---

## Próxima sessão

1. **#1710 (prazo 24/08):** re-medir na véspera — o número **encolhe** com registro de presença. E
   decidir com o PM as **7 células sem líder de tribo**.
2. **#1586:** fecha na primeira chamada real de `rescue_unbooked`, conferindo `actor_id` não nulo +
   `dispatch_source = 'manual'`. **Despachar é decisão do PM** (é e-mail a candidato real).
3. **#1664 fase 2** — fila de VÍNCULO (7 linhas / 6 pessoas com outro e-mail); encosta na #1614.
4. **#1762** — o rodízio concentra despachos quando o lote sai na mesma transação. **Corrigir muda
   quem recebe candidato → precisa do PM.**
5. **Onda E:** #1572 (P0), #1575, #1574, #1573, #1576, #1634, #1581, #1579.

## 🔔 Pendência de observação, prazo 28/08

O funil da onda D saiu do vácuo **só até o despacho**: 95 linhas, 1 instrumentada, **0 aberturas, 0
reservas**. **Nenhum número de conversão pode ser publicado** até uma linha carimbar `first_opened_at`
e `booked_at`. O token vence **28/08**. Ao conferir, exija `instrumented = true` **e**
`booking_token_md5` preenchido.
