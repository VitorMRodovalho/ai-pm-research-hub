# Handoff — a escrita das filhas do card ganhou gate, e o log ganhou nome próprio

> Sessão de 15/08/2026 (tarde). Continuação de `docs/planning/2026-08-16_PROMPT_ARRANQUE_1710_VESPERA_E_1779.md`.
> Handoff anterior: `docs/planning/2026-08-15_handoff_1780_fase1_medida_tres_cortes_entregues.md`

---

## Regra zero

Todo número aqui foi medido em **15/08/2026** com tool call na mesma volta. Vários se movem sozinhos
(o teto do #1710 encolhe todo dia; o funil anda sozinho pelo cron). **Re-meça antes de usar qualquer
um deles numa decisão, num commit, numa issue ou numa pergunta ao PM.**

---

## O que o PM decidiu nesta sessão

Três decisões, tomadas com a medição já no transcript:

1. **#1791 (a classe do #1778 nas vizinhas):** espelhar a forma do #1784 nas **cinco** filhas do card,
   não só nas três do domínio do card.
2. **#1779:** expor as tarefas no semântico **e** renomear a assinatura do log, aceitando mexer em
   consumidor vivo.
3. **#1710:** as células que nenhum líder de tribo alcança ficam com o **GP, pela grade geral**. Nada
   muda no código; a lista nominal vai ao GP na véspera (23/08), fora de issue e de PR.

---

## Estado

`main` em **`8e9b83c4`**. **Zero PRs abertas.** **2 merges, zero bypass** (#1792 e #1793).

Em produção, fora de PR (atos, não código, todos com antes/depois medidos):

- **4 migrations** por `apply_migration`, cada uma com arquivo local renomeado para o timestamp da
  linha de tracking, e as duas que criam função com **md5 normalizado conferido** contra o corpo vivo
- EF `nucleo-mcp` deployada: `/health` responde **`ef_version: 2.101.0`**, `/semantic` **0.16.0**, 54 tools
- `check_schema_invariants()` **sem nenhuma violação**

---

## 🔒 #1791 — FECHADA: a escrita nas filhas do card agora enxerga o recurso

O #1784 fechou a **leitura** e registrou, no cabeçalho da própria migration, que a escrita ficava de
fora. Ficava.

**Medido por impersonação em transação abortada**, com sujeito que tem a capacidade e não enxerga o
board confidencial (excluído de **todos** os ramos do gate: engajamento, superadmin, `manage_platform`):

| porta, no card/board confidencial | antes | depois |
|---|---|---|
| INSERT de papel | PASSOU | barrado (42501) |
| INSERT de atividade | PASSOU | barrado (42501) |
| INSERT de tag | PASSOU | barrado (42501) |
| INSERT no log de ciclo de vida | PASSOU | barrado (42501) |

**Controle inverso**, mesmo sujeito e mesma transação, num card não-confidencial: as quatro seguem
`PASSOU`. População que escrevia sem enxergar: **66** por `write_board`, **12** por `write`. Os **3**
engajamentos autoritativos na confidencial são todos de superadmin, então nenhum escritor legítimo
perdeu acesso.

### A descoberta que mudou o diagnóstico

**UPDATE e DELETE já estavam barrados, mas por efeito indireto.** O Postgres aplica as policies de
SELECT ao UPDATE/DELETE que referencia colunas, e o gate de leitura do #1784 esconde a linha alvo. O
`DELETE` no card confidencial apagou **0** e pareceria "já fechado" — mas o mesmo sujeito, na mesma
transação, apagou **1** num card não-confidencial. Sem o controle inverso, o zero passaria por falta
de autoridade. **O INSERT escapava porque não lê linha nenhuma.**

Isso é contenção por acidente. A barreira explícita é a mesma policy promovida de `FOR SELECT` para
`FOR ALL` com `WITH CHECK`: uma por tabela, cobrindo as duas direções.

### Por que o guard do #1784 não pegou

Ele era exemplar no eixo certo (derivava as filhas por **chave estrangeira**), e mesmo assim ficou
verde o patch inteiro: só classificava a **leitura**. O irmão
`_audit_confidential_write_gate_coverage()` usa o mesmo conjunto derivado por FK e classifica a
escrita em `explicito` / `sem_escrita` / `no_predicado` / `ausente`, olhando **as duas bordas** do
predicado (INSERT decide por `WITH CHECK`, DELETE por `USING`).

**Linha de base declarada:** **7** filhas seguem decidindo só por capacidade
(`board_sla_config`, `curation_review_log`, `event_showcases`, `meeting_action_items`, `pilots`,
`public_publications`, `webinars`), **todas com zero linhas ligadas ao board confidencial hoje**. A
lista só encolhe.

⚠️ **Nota de contrato:** o teste do #1784 mudou numa linha — `board_item_checklists` saiu de
`transitivo` para `explicito` na leitura. É o guard fazendo o que deve, e para mais forte.

---

## 🔀 #1779 — FECHADA: uma palavra, um sentido

`get_board_activities` significava duas coisas opostas. Depois desta sessão,
`SELECT count(*) FROM pg_proc WHERE proname='get_board_activities'` devolve **1**: a das tarefas.

- **`get_board_lifecycle_log(uuid, integer)`**, envelope `{events, count}`, ACL espelhada da origem
  (`authenticated` + `service_role`, **nunca `anon`**: o log carrega nome de ator).
- **`board_overview scope='tasks'`** — a porta agregada que faltava, com filtros de responsável,
  status e prazo, e o mesmo fail-fast de confidencial do `scope='board'`. **Ação em tool existente de
  propósito:** o conector cacheia `tools/list`.
- **Vocabulário:** a chave `recent_activities` do envelope de `scope='board'` virou
  `recent_lifecycle_events`. No produto, "atividade" é linha de checklist do card.

**Qual dos dois nomes estava errado:** o do log. `board_item_checklists` é o que o produto chama de
atividade (o verbo que o #1778 destravou).

### Implantação sem janela quebrada

Nesta ordem, cada passo conferido antes do seguinte: migration que **cria** o nome novo deixando a
velha viva → deploy da EF → `/health` em 2.101.0 → migration que **apaga** a velha. A EF em produção
nunca apontou para função inexistente.

**Exercido, não inferido:** impersonando um membro real com `write_board`, no mesmo board, o log
devolveu `{count, events}` com **5 eventos** e as tarefas `{activities, completed, pending, total}`
com **22 atividades, 17 pendentes**.

⚠️ **13 outras `proname` duplicadas seguem em `public`** — a Fase 1 já havia varrido e confirmado que
só esta significava duas coisas. As demais são sobrecargas do mesmo sentido.

---

## ⏰ #1710 — o prazo é 24/08, e o número foi re-medido hoje

Projeção para 24/08, pelos **dois caminhos independentes** (a consulta externa que reproduz coorte +
carência, e o ensaio da própria função em transação abortada). **Batem exatamente:**

| | |
|---|---:|
| eventos due | **47** |
| coorte vazia (pulados) | **4** |
| eventos que selam | **43** |
| **faltas materializadas** | **80** |
| pessoas atingidas | **40** |

⚠️ **É TETO.** Encolhe a cada presença registrada por um líder até lá. **RE-MEDIR EM 23/08.**

### A pendência do PM, resolvida

**5 faltas, em 2 pessoas sem tribo** — nenhum líder de tribo as alcança, só o GP pela grade geral.
Eram 7 em 14/08. **Decisão do PM: aceitar; o GP corrige pela grade geral.** Nada muda no código.

📌 **Para a véspera (23/08):** re-medir pelos dois caminhos, e levar ao GP a lista nominal das
células sem tribo — **na conversa, não em issue nem em PR** (repo público).

**Como ensaiar sem esperar:** bloco `DO` que faz `UPDATE` em `platform_settings` deslocando
`grace_days` (5 dias em 15/08 dá o mesmo corte de 10/08 11:40Z que 14 darão em 24/08) e recuando
`floor_date`, e termina em `RAISE EXCEPTION` com o resultado. A exceção aborta o bloco inteiro, então
o `UPDATE` volta sozinho — conferido depois: `floor_date` segue `2026-08-24`, `grace_days` segue 14.

---

## 🔔 Funil — prazo 28/08, re-medido hoje

**97 linhas · 3 instrumentadas · 3 com token · 1 abertura · 0 reservas.**

Andou desde o último handoff (era 95 / 1 / 0 / 0): a **primeira abertura foi carimbada**. Falta
`booked_at`. **Nenhum número de conversão pode ser publicado** até uma linha carimbar reserva, e o
token vence 28/08.

**Não provocar despacho, e agora com evidência de que não é preciso:** o cron despachou **hoje**
(último `dispatched_at` em 15/08 00:13Z). Dos 97 despachos sem reserva, o mais antigo tem **80 dias**,
a média é **50,6 dias**, e **0** estão superados. As linhas instrumentadas vão aparecer sozinhas.

⚠️ Exigir `instrumented = true` **e** `booking_token_md5` na linha nova antes de tratar qualquer
número como medição.

---

## O que fica para a próxima

- **#1710:** re-medir em 23/08 pelos dois caminhos; levar a lista nominal ao GP.
- **#1586:** fecha na primeira chamada real de `interview_manage action='rescue_unbooked'`,
  conferindo `actor_id` não nulo + `dispatch_source='manual'`. ⚠️ **Não despachar para testar.**
- **#1783:** 8 alertas Dependabot (5 high) em 3 lotes; `astro` é major 6→7. ⚠️ **PR local de higiene,
  nunca mergear Dependabot** (#611). São 2 lockfiles.
- **#1780 (EPIC, aberto):** agregada de comentário e de anexo **não existe nem em SQL** · 4
  definições de autoridade para a mesma ação · 8 verbos de curadoria sem porta MCP nenhuma (escopo é
  do PM).
- **#1777** (o fluxo que gravou o papel divergente; o dado já está normalizado), **#1776**, **#1664
  fase 2**, **#1762**, **#1729**, **#1742**, **#1744**.
- **Onda E:** #1572 (P0), #1575, #1574, #1573, #1576, #1634, #1581, #1579.

---

## Armadilhas confirmadas nesta sessão

1. **`gh pr checks` cresceu de 10 para 12 linhas** durante a espera do CI. Uma listagem curta não
   sustenta "está verde".
2. **A versão da superfície semântica tem QUATRO pins em arquivos que não se conhecem.** A lista que
   o #1755 deixou no teste do #1710 nomeia três; o quarto (o pin cruzado dentro do próprio teste do
   #1710) só apareceu quando a suíte inteira rodou offline. O comentário lá agora registra isso.
3. **RPC que resolve o chamador por `auth.uid()` devolve "Not authenticated" para `service_role`.**
   Um teste que afirmasse a forma do envelope chamando a função mediria a falta de sessão. Derivar do
   catálogo (`_audit_function_source`) ou impersonar.
4. **`pg_get_function_identity_arguments` devolve nome E tipo** (`p_board_id uuid, ...`), não só os
   tipos. Regex sobre ele precisa casar o formato real.
5. **`apply_migration` cria a linha de tracking com timestamp próprio** — as 4 migrations foram
   renomeadas para casar. Nenhuma precisou de `migration repair`.
6. **`npm run db:types` saiu limpo nas duas vezes** (exit 0, sentinela intacta, símbolo novo
   presente, últimas linhas limpas) — mas o cuidado do #1733 continua valendo, e o diff do #1779
   mostrou o colapso da união de duas sobrecargas para uma assinatura só, que é a mesma colisão
   aparecendo no nível de tipo.
