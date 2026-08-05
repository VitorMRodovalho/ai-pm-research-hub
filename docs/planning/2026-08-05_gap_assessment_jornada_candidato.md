# Gap assessment - jornada do candidato (05/08/2026)

> 🔒 **Candidatos aparecem como rotulos (`candidato A`, `candidata B`, ...), nunca por nome ou
> e-mail: este repositorio e PUBLICO.** A identidade de cada rotulo e recuperavel por consulta
> ao `selection_applications` com os ids/contagens citados. Mesmo criterio da
> `SPEC_INTERVIEW_BOOKING_INTEGRITY`, que nao nomeia nenhum candidato.

Item 2 da ordem de execucao da `SPEC_INTERVIEW_BOOKING_INTEGRITY` (§7). Escrito depois de fechar
o arco #1584 / #1594 / #1595 / #1598 / #1599, que e o que muda o veredito: **o arco fechou a porta
de SAIDA (quem e convidado) e nao tocou a porta de ENTRADA (quem acaba agendado).**

## 0. Metodo e ressalvas

- **Todo numero aqui foi medido nesta sessao**, em 05/08 entre 00:40 e 01:45 UTC, contra o banco de
  producao. Nenhum numero veio do handoff nem da spec sem ser reconferido - e varios divergem.
- **A coorte se moveu durante a sessao.** candidato J foi entrevistado de verdade as
  00:30 UTC (`selection_interviews.conducted_at` gravado, `completed`) e passou a `final_eval`.
  `interview_scheduled` caiu de 2 para 1 no meio da medicao. Re-medir antes de agir.
- Ha um `CI Validate` do PR #1606 rodando contra o mesmo banco. Contagens de linhas de log podem
  ter alguns registros de teste; as contagens de coorte e os corpos de funcao nao sao afetados.

## 1. A coorte hoje (ciclo aberto, 81 candidaturas)

| status | n | sem nota objetiva | sem analise de IA (P0001) | < 2 avaliacoes |
|---|---|---|---|---|
| approved | 50 | 5 | **18** | 3 |
| rejected | 10 | 1 | 7 | 1 |
| interview_pending | 8 | 1 | **5** | 1 |
| final_eval | 7 | 2 | 2 | 0 |
| submitted | 4 | 4 | 2 | 4 |
| interview_done | 1 | 0 | 1 | 0 |
| interview_scheduled | 1 | 0 | 0 | 0 |

**O numero que dimensiona tudo: 18 de 50 `approved` nao tem analise de IA.** Se a porta governada
fosse aplicada a eles hoje, em modo `full`, ela recusaria 18 - e a auditoria de recusa (#1594) agora
registraria cada uma. Isso e o tamanho da cauda do A6 (reemissao de token), e a razao pela qual
reemitir em lote sem antes decidir o que fazer com quem falha P0001 produziria 18 recusas e nenhum
e-mail.

## 2. A jornada, etapa por etapa

| # | etapa | mecanismo | estado |
|---|---|---|---|
| 1 | Inscricao | formulario -> `selection_applications` | sem gap medido |
| 2 | Triagem / IA | `retry-pending-ai-triages`, `retry-pending-ai-analyses`, `extract-cv-text-15min` | crons rodando; **a lacuna nao esta no cron, esta no estoque**: 18 approved sem analise |
| 3 | Fase objetiva | avaliacoes + `objective_score_avg` | 5 approved sem nota; 4 submitted sem nota (esperado) |
| 4 | Corte / convite | `notify_selection_cutoff_approved` -> token governado | ✅ **FECHADO** pelo arco. Fonte unica `_dispatch_interview_booking_link`, 3 gates, recusa auditada |
| 5 | **Agendamento (entrada)** | `calendar-webhook.ts` -> `match_booking_application` | 🔴 **ABERTO. E o gargalo real.** §3 |
| 6 | Entrevista | `selection_interviews` + reminders | funcionando (candidato J hoje) |
| 7 | Resgate de preso | 2 crons de rescue | ✅ fechado hoje (#1598/#1599), com deploy do MCP pendente |
| 8 | Pos-entrevista | `recompute_application_status`, `final_eval` | 0 `final_eval` sem entrevista conduzida - sem gap vivo |
| 9 | Decisao / VEP | `approve_selection_application`, nudges | fora do escopo desta medicao |

## 3. O gargalo: a porta de ENTRADA (Classe A + B + C juntas)

### 3.1 O estrago, medido — **#1609**

`admin_audit_log`, acao `calendar_booking_unmatched`, ultimos 30 dias:

| metrica | valor |
|---|---|
| linhas | **12.237** |
| eventos de calendario distintos | **11** |
| e-mails de convidado distintos | **9** |

Onze reservas produziram doze mil linhas de auditoria. A spec media 5.693 para um evento e "70 e
contando" para outro; esse segundo (`bsb4n49e06al6cj95mdivgqkp8`) esta hoje em **381** e a ultima
tentativa foi as **01:31 UTC de hoje**. Nao parou.

### 3.2 A decomposicao por classe - e ela muda a prioridade

| convidado | e candidatura? | e-mail da candidatura | status | linhas | classe |
|---|---|---|---|---|---|
| `candidato A` (gmail pessoal) | **sim** (candidato A) | (dominio corporativo, divergente) | interview_pending | **5.693** | B |
| `o e-mail do PM` | nao (e o PM) | - | - | **3.975** | C |
| `candidata B` (institucional 1) | **sim** (candidata B) | (gmail, divergente) | interview_pending | 830 | B |
| `candidata B` (institucional 2) | **sim** (a mesma) | idem | interview_pending | 666 | B |
| `candidata C` (gmail pessoal) | **sim** (candidata C) | (divergente) | final_eval | 552 | B |
| `candidato D` (gmail pessoal) | **sim** (candidato D) | (uol, divergente) | final_eval | 308 | B |
| `candidato E` (e-mail QUE BATE) | **sim, e o e-mail BATE** | (bate) | final_eval | 89 | **D / allow-list** |
| `candidato F` (gmail pessoal) | **sim** (candidato F) | (yahoo, divergente) | approved | 75 | B |
| `membro G` (ciclo fechado) | sim, **ciclo fechado** | (bate) | approved | 49 | ciclo |

**Leitura:**

- **Classe B (e-mail divergente) e a maior fatia: 8.124 linhas** (A 5.693 + B 830+666 +
  D 308 + C 552 + F 75). Sao **6 candidatos reais** que tentaram agendar com um
  e-mail diferente do da candidatura.
  A ponte de e-mail alternativo passa por `member_emails`, e o proprio corpo vivo de
  `match_booking_application` diz em comentario que "a candidate is usually not a member, so this
  is NULL in the common case". **A ponte e inerte por construcao** - confirmado no corpo, nao
  inferido.
- **candidato A e o caso mais grave da plataforma hoje.** Ele esta em `interview_pending`,
  tentou agendar **5.693 vezes desde 17/07**, e a plataforma nunca viu. candidata B idem, 1.496
  vezes em dois enderecos institucionais.
- **Classe C e o unico trafego ainda queimando agora, e e 100% o e-mail do PM.** Os tres eventos
  ativos nos ultimos 3 dias tem `guest_email = `o e-mail do PM``. Ninguem esta bloqueado por
  isso neste momento - mas o log leva ~12 linhas/hora por evento ativo.
- **candidato E e um caso proprio, e nao e a Classe B**: o e-mail dele BATE com a candidatura. Ele nao
  casou porque `final_eval` nao esta na allow-list de `match_booking_application`. Ou seja, a
  allow-list rejeita quem ja avancou - o que e correto por desenho, mas produz linha de "nao casado"
  em vez de "ja decidido", e polui a mesma superficie.

### 3.3 O gate de objetiva na entrada: quem tem, quem nao tem

Conferido no corpo VIVO (`pg_proc`), nao em migration:

| escritor | gate de objetiva | roda de verdade? |
|---|---|---|
| `schedule_interview` | ✅ sim (P0003) | sim - **e a porta que o arco fechou** |
| `sync_calendar_booking_to_interview` | ✅ sim | **nao** - e a implementacao morta da Classe A |
| `src/pages/api/calendar-webhook.ts` | ❌ nao (linha 194 escreve `interview_scheduled` direto) | **sim** |
| `_trg_sync_interview_to_app_status` | ❌ nao | sim |
| `mark_interview_status` | ❌ nao | sim |
| `recompute_application_status` | menciona a coluna, mas nao barra a entrada | sim (cron 49) |
| **`admin_update_application(uuid, jsonb)`** | ❌ nao | sim - **5º escritor, ausente da tabela da spec** |

**Achado novo:** a spec lista 4 escritores. `admin_update_application` e um quinto: escreve
`selection_applications`, controla `v_old_status`/`v_new_status`, e nao tem gate de objetiva. Ele e
gateado por `manage_platform`, entao pode ser lido como o caminho de excecao do GP que o R1.4 pede -
mas hoje ele nao e declarado como tal, nao exige motivo e nao registra a excecao como excecao.
Se a Opcao 1 da §4.1 (trigger BEFORE UPDATE) for escolhida, ela cobre este quinto por construcao,
que e exatamente o argumento a favor dela.

## 4. Correcoes as premissas da spec e do handoff

| premissa | estado medido |
|---|---|
| "resolver a fila de e-mail ANTES de qualquer aborto de cron" (spec §7.3) | **A fila NAO esta congestionada.** Hoje: 1 entregue, cota 100, **0 pendentes, 0 throttled**. Falhados: 11, todos historicos, o mais recente de 04/07. Isso desbloqueia a ordem de execucao |
| "5 candidaturas em estagio de entrevista sem nota objetiva" (spec, 03/08) | Hoje sao **3** em estagio de entrevista (1 `interview_pending` + 2 `final_eval`); a coorte andou |
| "Classe D - no-show e beco sem saida" | **Populacao viva hoje: ZERO.** 0 candidaturas em `interview_noshow` no ciclo aberto; 5 linhas de entrevista `noshow`; 0 pedidos de reagendamento pendentes. O defeito e latente, nao ativo - rebaixa a prioridade de D |
| "o cron de resgate erra ha 4+ dias" (#1599) | **Sao 6 dias** (30/07 a 04/08) |
| "candidato E terminal em `recompute_application_status`" (handoff antigo) | Ja estava errado; ele esta em `final_eval` |

## 5. Achados novos, fora da spec

### 5.1 🔴 Dois e-mails encalhados ha 32 dias, e o retry nunca vai pega-los — **#1608**

`process_pending_email_queue` (job 30) reprocessa `status='failed'` **somente** quando
`error_log ILIKE '%rate_limit_exceeded%'`. Os dois envios falhados de 04/07 dizem:

```
{"statusCode":429,"message":"You have reached your daily email sending quota.","name":"daily_quota_exceeded"}
```

`daily_quota_exceeded` **nao casa** o predicado `%rate_limit_exceeded%` - conferido por consulta, os
dois dao `false`. Cada um tem 1 destinatario nao entregue. Sao **32 dias encalhados**, e ficarao
encalhados para sempre.

Sao duas pessoas reais que nunca receberam o e-mail: `(destinatario 1)` e
`(destinatario 2)`. E a mesma classe de [[reference-resend-email-quota-lanes]] (#1424):
a cota tem **dois** nomes de erro e o retry so conhece um.

### 5.2 🟡 O job verde que esconde o trabalho falhado

`cron.job_run_details` reporta **7 execucoes, 0 falhas** para `selection-stuck-scheduled-rescue-daily`
nos ultimos 7 dias. O `admin_audit_log` do mesmo cron reporta `error_count: 1` em **6** delas. As
duas superficies discordam porque a funcao retorna normalmente depois de engolir a excecao. O #1599
corrige a gravacao da mensagem; **nao corrige a discordancia entre as duas superficies** - um
operador que olhe o painel de cron continua vendo verde. Vale um alerta derivado de
`data_anomaly_log` (que o #1599 passa a alimentar), nao do `job_run_details`.

### 5.3 🟡 A allow-list produz "nao casado" onde o correto seria "ja decidido" — **#1611**

O caso do candidato E (89 linhas, e-mail correto, status `final_eval`). Misturar "nao achei o candidato"
com "achei e ele ja avancou" no mesmo balde e a classe de
[[reference-probe-failure-must-not-share-bucket-with-violation]]. Barato de separar, e tira ruido do
balde que o R4 quer medir.

## 6. Fila recomendada

| # | frente | por que nesta ordem | tamanho |
|---|---|---|---|
| 1 | **#1609 - R4.1, cortar a hemorragia do log** (contador por `calendar_event_id` + corte apos N) | 12.237 linhas de 11 eventos, ainda crescendo. Nao depende de decisao do PM e torna todo o resto mensuravel | P |
| 2 | **#1608 - o retry de e-mail cobrir `daily_quota_exceeded`** | 2 pessoas reais, 32 dias, correcao de uma linha no predicado | PP |
| 3 | **R2 - resolucao de candidato por e-mail proprio** | e a maior fatia do estrago (8.124 linhas, 66% do total) e tem **6 candidatos reais** bloqueados, sendo candidato A ha 19 dias. Exige campo novo - **decisao do PM** entre `alternate_emails text[]` e tabela propria | M |
| 4 | **R3 - webhook aceitar todos os convidados** | mata a Classe C na origem (3.975 linhas do e-mail do PM). Exige mudanca no Apps Script, fora do repo | M |
| 5 | **R1 - gate unico de entrada** | ✅ decisao pendente do PM: Opcao 1 (trigger) vs 2 (helper). Recomendo a **1**, e o 5º escritor achado aqui (§3.3) e o argumento novo a favor | M |
| 6 | R5 - saida do no-show | **populacao viva zero hoje**; rebaixado de prioridade, mas segue latente | P |

**Duas decisoes de PM travam a fila:** (a) Opcao 1 vs 2 do gate unico (§4.1 da spec); (b) forma do
e-mail alternativo de candidatura (§4.2). Os itens 1 e 2 acima nao dependem de nenhuma das duas e
podem comecar ja.

## 7. O que NAO foi medido aqui

- #1277 (35 ghosts, 2 leads sem follow-up) - fora desta passada.
- Os 11 crons "um a um" pedidos pela spec: medi os **16 da trilha de selecao** por saude de execucao
  (§5.2), nao por leitura de corpo um a um.
- Etapa 9 (decisao / VEP / assinatura) - so a etapa ate a entrevista foi coberta.
- Para cada um dos 6 candidatos da Classe B, NAO foi verificado se a reserva de calendario ainda
  esta de pe (o reparo manual precisa disso antes de casar a mao).

## 8. Issues abertas por este assessment

| # | titulo | prioridade na fila |
|---|---|---|
| #1609 | 12.237 linhas de `calendar_booking_unmatched`, sem corte | 1 |
| #1608 | retry da fila nao cobre `daily_quota_exceeded` (2 pessoas, 32 dias) | 2 |
| #1611 | balde de `unmatched` mistura "nao achei" com "ja decidido" | junto com a 1 |
| #1610 | manifesto MCP classifica 3 escritas como `read` (fora da trilha de selecao) | avulsa |

As frentes R2, R3 e R1 seguem sem issue **de proposito**: as tres dependem de decisao do PM que a
spec ja enquadrou (§4.1 Opcao 1 vs 2; §4.2 forma do e-mail alternativo; §4.3 mudanca no Apps
Script, fora deste repo).

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
