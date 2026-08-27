# Handoff 26/08 (madrugada) — #2013 fechada, e o guard que a própria mudança derrubou

**Estado:** main `ca6f73f4`, fila **vazia**, zero bypass. **#2012 e #2013 fechadas** na mesma
sessão (migrations `20260826212137` e `20260826231144`). EF `nucleo-mcp` deployada; deploy do
Worker sai pelo portão da A3.

---

## 1. O que entrou na #2013

Quatro consertos, um por defeito medido:

| # | defeito | conserto |
|---|---|---|
| 1 | ultimato de 48h que renovava a cada 3 dias, e um estado de pausa que **não existe** | o **texto** para de prometer (decisão do PM: não criar o estado de pausa) |
| 2 | laço sem teto nem escada | teto de **3 despachos por episódio**, lido de `platform_settings`, + escalação única ao comitê |
| 3 | `open_count` gravado e nunca lido | diagnóstico na escalação, **sempre** filtrado por `instrumented` |
| 4 | `interview_status` que nunca se limpava | o trigger canônico da p240 vira o **dono** da coluna |

**Antes → depois, medido:** `needs_reschedule` **9 → 6**; linhas com entrevista conduzida e status
errado **6 → 0**; template prometendo 48h/pausa **1 → 0**; teto **inexistente → 3**.

### Três decisões que valem registro

- **A escrita de `interview_status` vem ANTES do portão terminal do trigger.** O portão existe para
  não sobrescrever `status` de quem é `approved`/`final_eval` — e é **exatamente ali** que estavam
  as linhas sujas. Escrever depois seria escrever para todos menos para quem precisa. Nada no
  trecho novo encosta na coluna `status`.
- **O saneamento tocou 6 linhas, não as 3 que a issue nomeia.** Escrevi o `UPDATE` pela regra
  ("tem entrevista conduzida") em vez de por lista de ids, e a regra achou 2 em `none` e 1 em
  `scheduled` na mesma condição. Todas legitimamente `completed`.
- **A regra `needs_reschedule → rescheduled` foi ESPELHADA, não inventada.** O webhook de calendário
  já a aplicava; duas regras divergentes sobre a mesma coluna seria o defeito seguinte.

### O que NÃO fechou, e está escrito na migration

**Item 5 do aceite:** quem RESPONDE ao e-mail automático continua invisível para o automatismo que
o gerou. Não existe caminho de volta da caixa de entrada para a candidatura. O teto reduz o dano —
depois de 3 despachos o caso vira notificação a gente de verdade — mas não é o conserto. Issue
própria, ainda não aberta.

## 2. O guard que a própria mudança derrubou (e por que isso foi bom)

A #2013 redefiniu `_trg_sync_interview_to_app_status`, e o `structural` reprovou: o scanner do
#1932 acusou `p240-251-interview-status-transition-trigger`, que fixava a migration de 05/08 para
afirmar sobre aquela função. **Sem o conserto ele seguiria verde descrevendo um corpo que produção
não executa mais** — e teria ficado verde do mesmo jeito se a redefinição tivesse afrouxado o
portão terminal.

Duas armadilhas na conversão, ambas pagas:

1. **O arquivo tinha DUAS naturezas.** História da migration (arquivo existir, `DROP`+`CREATE
   TRIGGER`, `REVOKE`, escopo do backfill) continua lendo o arquivo fixo — ali a pergunta é "aquela
   migration entregou X". Só o invariante corrente do corpo migrou para `latestFunctionCapture()`.
2. **`latestFunctionCapture().body` devolve o CORPO, não o cabeçalho.** É o mesmo texto do
   `prosrc`, então nome, `SECURITY DEFINER` e `search_path` **não estão nele** — a primeira
   tentativa reprovou exatamente aí. A saída foi recortar o cabeçalho da **própria** função dentro
   do arquivo da captura; afirmar sobre o arquivo inteiro passaria por causa das duas funções
   vizinhas que a mesma migration define.

## 3. Contenção outra vez, agora com diagnóstico limpo

O `validate` reprovou uma vez em `#1972 db: a migration É a captura`, com
`canceling statement due to statement timeout` — **não** asserção de conteúdo. Medido depois:
`_audit_list_public_function_bodies()` devolve **1226 funções em 347ms**, longe do teto. E no mesmo
SHA, `Schema Invariants` e `CI Validate` estavam vivos ao mesmo tempo, os dois no banco. A função
que o teste afirma (`submit_interview_scores`) **não foi tocada** pela #2013.

Re-run sem tocar em código: verde. Era contenção. O critério que separou os dois casos:
**a assinatura do erro** (timeout vs. mismatch) e **a medição do custo real**, não a intuição.

## 4. Fila daqui

`#1995` (denominador varia; 2 perguntas ao PM) · `#1996` · `#1999` · `#2001` (backfill jurídico) ·
`#2004` (rótulo ou portão) · `#2009` · `#2010` · `#2011` (37 links no domínio pessoal) · `#1997`
(e-mail de recuperação, ação sobre pessoa real).

**Relógios:** 27/08 08h40 BRT o selo de presença grava (cron dispara sozinho) · **29/08 14h UTC** o
cron de reagendamento roda — e agora escala em vez de mandar o 4º e-mail · 28/08 funil · 09/09 1ª
mordida da retenção · 30/09 portão da anonimização.

## 5. Pendência que é decisão do PM

As mensagens dos dois primeiros commits da branch `fix/2012-quem-conduz-registra` ainda carregam
nome e sobrenome de uma candidata e de um entrevistador. O squash manteve isso fora da main, mas os
objetos seguem alcançáveis pelas refs da PR #2015. Limpar exige `git push --force`. E o padrão é
maior que essa branch: a decisão de scrub de nomes de 08/08 segue **tomada e não executada** no
repositório.
