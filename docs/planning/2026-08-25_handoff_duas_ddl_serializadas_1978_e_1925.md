# Handoff 25/08 (tarde) - as duas entregas de DDL da fila, serializadas de proposito

**Estado final:** `#1978` e `#1925` FECHADAS. Main `97e35eef`, fila VAZIA, zero bypass. `#1986` e `#1988` mergeadas, 13/13 verdes cada. Uma issue nova: **#1987** (decisao de documentacao, sem DDL).

O arranque pedia as duas entregas de DDL que a fila liberou. As duas sairam, **uma de cada vez**, e
essa ordem foi a decisao mais importante do dia: aplicar a segunda DDL antes de a main fechar o
`check-invariants` da primeira teria recriado o impasse cruzado de 24/08.

---

## 1. #1978 - as 4 notificacoes de comite ganharam destinatario

`PERFORM create_notification(...) FROM selection_committee WHERE role='lead'` com **zero linhas nao
chama nada**: nao falha, nao avisa, nao grava.

`_selection_cycle_recipients(cycle_id)` e a irma **por-ciclo** da `_selection_consistency_recipients()`
do #1813 (que e global). Escada de 3 degraus, cada um so quando o anterior e vazio:
**lead do ciclo -> comite do ciclo -> `manage_platform`**.

| ciclo | antes | depois | degrau |
|---|---:|---:|---|
| cycle4-2026 (aberto) | 1 | 1 | lead |
| cycle3-2026 | 2 | 2 | lead |
| cycle3-2026-b2 | 1 | 1 | lead |
| **cycle2-2025** | **0** | **2** | manage_platform |

**Onde ha lead, nada muda.** O unico zero fecha. Ciclo NULL ou inexistente tambem resolve para os 2
GPs, nunca para o vazio - o invariante e TOTAL, nao so sobre os ciclos que existem hoje.

### A medicao que decidiu o degrau do meio

Alargar destinatario parecia decisao de privacidade. Nao era: o gate de `get_selection_dashboard` e
`is_selection_committee_member(caller, cycle_id)`, que **nao filtra papel**. Observer do ciclo ja lia
nome e capitulo do candidato. O degrau "comite do ciclo" e a **mesma audiencia da tela**, nao
ampliacao. → memoria `reference-audiencia-de-notificacao-se-mede-no-gate-da-tela-que-ela-aponta`.

### O que eu NAO fiz, e por que

Nao acrescentei guarda `recipient = actor`. Medido: das 3 sobrecargas de `create_notification`, so as
de 6 e 7 args **com** `p_actor_id` a tem; a de 7 args usada nas 3 superficies **nunca teve**. O lead
que marca no-show ja se auto-notifica hoje. Excluir o ator poderia **reesvaziar** a lista, que e o
defeito que a PR existe para fechar.

---

## 2. #1925 saida 2 - a escada virou SSOT, e ganhou reconciliacao agendada

`auth_engagements` usa `CURRENT_DATE`: a virada de data muda a **derivacao** sem que ninguem escreva,
e o cache so e reescrito pelo trigger, que so dispara em **escrita**.

A escada estava inline em **duas copias byte-identicas** (md5 `f7d75a5c...`, 1197 chars): o trigger e
a CTE `computed` da A3. Um cron copiado seria a **terceira**. Por isso ela virou
`_derive_operational_role(person_id)` **antes** do cron, com o `CASE` movido **verbatim**.

**A janela que o cron fecha:** `CURRENT_DATE` vira 00:00 UTC; o primeiro job que mexe em engajamento e
`v4_engagement_expiration`, **03:05 UTC**. Havia ~3h em que a derivacao ja mudara e nenhuma escrita
corrigia o cache. O cron novo roda **00:04 UTC**.

### O numero que mudou o escopo

| populacao | divergem | entra? |
|---|---:|---|
| **ativos** | **0** de 94 | sim (93 examinados; 1 e o pseudo-membro que a A3 exclui) |
| **nao-ativos** | **32** | **nao** |

As 32 sao papel **congelado** no offboarding. Um `WHERE true` teria reescrito 32 linhas que ninguem
pediu, e teria passado como "reconciliacao" no relatorio. → memoria
`reference-antes-do-reconciliador-conte-as-divergencias-fora-do-escopo`.

**Entre os ativos, zero divergem: e prevencao, nao reparo.** O "antes" honesto e 0 linhas corrigidas.

---

## 3. ⚠️ O que a suite INTEIRA pegou, e os testes-alvo nao pegariam

Depois da DDL do #1925, `npm test` reprovou **4 testes** em `role-ladder-parity.test.mjs`. Nao era
regressao: o guard de paridade do **ADR-0023** lia a escada **DENTRO do trigger**, e eu a movi.

**Ele ficou VERMELHO, nao vazio** - e essa e a diferenca que vale reter. O guard usa
`assert.ok(caseInner)`; se usasse `doesNotMatch` sobre o corpo, teria passado em silencio descrevendo
uma escada que nao existe mais.

O guard foi apontado para `_derive_operational_role` e ganhou uma assercao nova: o trigger **DELEGA**
e nao pode carregar a escada de volta. Provado nos dois sentidos por injecao de defeito.

**Efeito colateral na #1987:** eu havia proposto la "criar um guard de paridade" como saida. **Ele ja
existia.** O que sobra ali e decisao de **documentacao** no ADR-0023 - registrar que a duplicacao e
deliberada, para a proxima pessoa nao "consertar" apagando o guard junto.

---

## 4. Ritual de DDL, executado duas vezes sem drift

Nas duas entregas: **uma** chamada de `apply_migration`, renomear o arquivo local para o timestamp da
linha registrada (atalho que dispensa `repair` e nao deixa fantasma), md5 do `prosrc` vivo contra a
captura local.

**Zero drift de transcricao nas 8 funcoes**, apesar de colar ~26 KB e ~10 KB de SQL nas chamadas.

Tambem consertei **dois guards fixados em `.sql` vencido** (classe do #1932) que minha propria
migration venceu: `1972-designacao...` (ficou vermelho de verdade) e o md5 do `1978-paridade...`. Os
dois passaram a usar o helper compartilhado `latestFunctionCapture(ROOT, fn)`.

---

## 5. Armadilhas de sonda que eu mesmo caí hoje (e o antidoto que funcionou)

- **`assert` com contagem errada aborta antes de escrever, e isso e bom.** Errei 3 vezes a contagem
  esperada (2 blocos que eram 3, 1 ocorrencia que era 2, 2 leituras que eram 4). Como a escrita vinha
  DEPOIS das asserçoes, nenhuma escreveu arquivo pela metade. **Contar e melhor que checar presenca**,
  e a contagem errada e barata quando o script e atomico.
- **Postgres limita repeticao a 255:** `.{0,300}` em regex levanta `invalid repetition count(s)`.
- **`ELSE 'guest' END` nao casa em `prosrc` cru** (ha quebra de linha entre eles). Normalize com
  `regexp_replace(prosrc,'\s+',' ','g')` **antes** de sondar, e leve controle positivo junto: resultado
  vazio nao e evidencia.
- **`| tail -N` engole o codigo de saida da suite.** Rodei sem pipe, redirecionando para arquivo, e
  carimbei `TEST_EXIT=$?` na propria linha seguinte.

---

## 6. O que tem relogio

- ⏰ **Selo grava 27/08 08h40 BRT** (#1948). Decisao mantida: gravar as 77 e corrigir depois, em
  **3 passos, ou os tres ou nenhum**. Efeito 77 → 66.
- ⏳ Radar Tecnologico 13/07 segue o unico item de presenca aberto.
- ⏰ **28/08** funil · **09/09** retencao · **30/09** anonimizacao.
- 🧹 `MEMORY.md` em **24.041** de 24.985 (folga **944**, era 535 no inicio). Comprimi 5 linhas do
  READ-FIRST e movi a licao do impasse de DDL para o arquivo-topico, que e onde licao duravel mora.

## 7. Proximo passo sugerido

**#1987** e a unica coisa aberta que veio desta sessao, e e barata: decidir se o ADR-0023 registra a
duplicacao da escada como deliberada. Nao ha DDL envolvida, entao nao entra na fila de serializacao.
