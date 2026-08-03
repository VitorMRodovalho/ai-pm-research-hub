# Auditoria da jornada do candidato

**Data da medição:** 2026-08-03, entre 16:04 e 16:40 UTC.
**Ciclo sob análise:** `cycle4-2026` (`08c1e301-9f7b-4d01-a13c-43ac7775c0f7`), status `open`, fase `evaluating`,
`min_evaluators = 2`.
**Método:** consulta ao vivo (Supabase MCP `execute_sql`) + leitura do corpo VIVO das funções (`pg_get_functiondef`)
+ leitura do código da aplicação. Nenhum número aqui foi herdado de handoff.

> ⚠️ Toda contagem abaixo é um retrato de 03/08. Re-consulte antes de usar em decisão, PR ou spec.

> 🔒 **PII pseudonimizada.** Este repositório é **público**. Candidatos aparecem como `Candidato A..J` e
> e-mails como descritores do que importa para a análise (o domínio diverge entre candidatura e
> agendamento), nunca o endereço. Membros do comitê aparecem nominalmente porque a análise é sobre a
> **autoridade institucional** deles, não sobre dados pessoais de titular em processo seletivo.
> A versão identificada, com o de-para, fica **fora do repositório**, em
> `~/.claude/uploads/auditoria-jornada-candidato-2026-08-03/`.
> A primeira versão deste arquivo trazia e-mails reais e foi barrada pelo hook de pre-commit; o hook
> estava certo.

---

## 1. Reparo executado durante a auditoria (autorizado pelo PM)

Uma entrevista de hoje estava agendada no Google Calendar e **invisível para a plataforma**.

- Candidato: Candidato A, candidatura `3b714c5d-6c13-41d6-815d-8a13237c270b` (trilha `researcher`).
- Agendou em 31/07 para **03/08 22:00 UTC (19:00 BRT)** usando `<agendamento A: gmail pessoal>`.
- O e-mail da candidatura é `<candidatura A: dominio corporativo>`, então o webhook devolveu `application_not_found` em
  **todas** as tentativas, a última às 16:00 UTC de hoje.
- Consequência: sem linha em `selection_interviews`, fora do dashboard, e o lembrete de 1h **não dispararia**.
- Ele é o **único dos quatro** entrevistados do ciclo que passou pela objetiva de verdade
  (`objective_score_avg = 233.50`, `cutoff_approved_email_sent_at = 2026-07-31 14:00 UTC`).

Ação: linha `selection_interviews` `622206ad-ce1b-43bf-a956-7337a21b5eff` criada com o `calendar_event_id`
original, candidatura promovida a `interview_scheduled`, e linha de auditoria
`selection.interview_manually_materialized` registrada com a justificativa completa.

Verificado depois do reparo: a janela do lembrete (`process_interview_reminders_1h`) é
`scheduled_at BETWEEN now()+30min AND now()+90min`, e o cron 46 roda aos minutos 5, 20, 35 e 50 de cada hora,
então a entrevista das 22:00 UTC será capturada por volta das 21:05 UTC.

**Ressalva operacional:** o lembrete vai para `<candidatura A: dominio corporativo>` (e-mail da candidatura), não para o gmail
com que ele agendou.

Agenda real de hoje, depois do reparo: **18:30, 19:00 e 19:30 BRT, em sequência**.

---

## 2. Achado A: o gate do #1450 foi aplicado numa função que não roda

O #1450 (fechado em 21/07) instalou o gate `objective_score_avg IS NULL` em duas superfícies, via
`supabase/migrations/20260805000469_1450_objective_gate_invite_and_calendar_sync.sql`:

1. `notify_selection_cutoff_approved` - gate **vivo e efetivo**. Esta metade funciona.
2. `sync_calendar_booking_to_interview` - gate vivo no corpo, mas a função é **código morto**.

Evidência de que a segunda é morta: `admin_audit_log` tem **1 única linha** com prefixo `arm116.` desde
sempre, datada de **2026-05-06 19:19 UTC**. A função não roda desde maio.

Quem realmente sincroniza é **`src/pages/api/calendar-webhook.ts`**, uma rota Astro que:

- usa `service_role`, portanto passa por cima de RLS;
- escreve `selection_interviews` e promove `selection_applications.status` para `interview_scheduled`;
- **não tem nenhum gate de objetiva**;
- grava a ação `calendar_booking_synced` (sem prefixo `arm116.`) com `metadata.source = 'calendar_webhook'`.

O comentário do próprio arquivo (linhas 30-33) declara a premissa que sustenta a ausência do gate:

> "service_role, bypasses RPC auth gate because: only invoked by trusted Calendar webhook AFTER
> mark_interview_status('pending') legítimo flow; gate validation already happened server-side"

É exatamente essa premissa que o #1450 derrubou. Existem duas implementações do mesmo webhook e o fix
entrou na que não é chamada.

### Lição de método

Um `grep` pelo nome do gate encontra as duas e diz "coberto". Só a **trilha de auditoria** distingue a
implementação viva da morta. O sinal foi o prefixo da ação: `arm116.calendar_booking_synced` (SQL, morta)
contra `calendar_booking_synced` (TypeScript, viva).

---

## 3. Achado B: quatro escritores podem levar o candidato ao "agende sua entrevista"

| # | escritor | tipo | gate de objetiva | audita |
|---|---|---|---|---|
| 1 | `src/pages/api/calendar-webhook.ts` | rota Astro, service_role | **não** | sim (`calendar_booking_synced`) |
| 2 | `trg_sync_interview_to_app_status` | trigger AFTER INSERT em `selection_interviews` | **não** | **não** |
| 3 | `mark_interview_status` | RPC | **não** | **não** |
| 4 | `recompute_application_status` | RPC (cron 49, 13:00 UTC) | **não**, no ramo `interview_scheduled` | sim |

Sobre o item 4, o detalhe importa: a função é **correta** no ramo de `interview_pending`, onde exige
`obj_n >= min_evaluators AND objective_score_avg IS NOT NULL`. Mas o ramo acima dele,
`WHEN sched_active THEN 'interview_scheduled'`, deriva o status apenas da existência de uma linha de
entrevista viva. Ou seja, o cron **ratifica diariamente** o que o webhook sem gate criou. Corrigir só o
webhook não basta: o cron reintroduziria o status.

Os itens 2 e 3 não gravam auditoria, o que explica por que a consulta a `admin_audit_log` pelas três
candidaturas afetadas voltou **vazia**. `mark_interview_status` é a origem mais provável do
`interview_pending` prematuro (ação em lote no `/admin/selection`), e não deixa rastro.

---

## 4. Achado C: as 4 entrevistas do ciclo aberto não passaram pela objetiva

| candidato | entrevista (BRT) | avaliações objetivas submetidas | `objective_score_avg` | e-mail de cutoff |
|---|---|---|---|---|
| Candidato B | 03/08 18:30 | **0** | null | nunca enviado |
| Candidato C | 03/08 19:30 | **0** | null | nunca enviado |
| Candidato D | 04/08 21:00 | **0** | null | nunca enviado |
| Candidato E | 23/07 18:00 (passada, ainda `scheduled`) | 1 (mínimo do ciclo = 2) | null | nunca enviado |

Candidato A, reparado na seção 1, é a exceção legítima: objetiva concluída.

Em `interview_pending` (6 candidaturas), duas também estão sem o gate satisfeito: **Candidato F** e
**Candidato G**, ambas com 1 avaliação objetiva e sem e-mail de cutoff.

O #1450 documentou 2 casos (Candidato H e Candidato F) com 1 avaliação cada. O quadro de hoje é **pior**: três
candidaturas com **zero** avaliações chegaram a entrevista agendada. Não é regressão do fix; é que o fix
nunca alcançou o caminho vivo.

**Decisão do PM (03/08):** manter as 3 e corrigir o processo, mesmo tratamento dado a Candidato H e Candidato F no #1450.

---

## 5. Achado D: agendamento invisível por e-mail divergente

O candidato agenda no Google Calendar com o e-mail pessoal dele, que frequentemente não é o e-mail da
candidatura importada do VEP.

| candidato | e-mail da candidatura | e-mail usado ao agendar |
|---|---|---|
| Candidato A | `<candidatura A: dominio corporativo>` | `<agendamento A: gmail pessoal>` |
| Candidato F | `<candidatura F: dominio corporativo>` | `<agendamento F: gmail pessoal>` |
| Candidato G | `<candidatura G: gmail>` | `<agendamento G: outro gmail>` |
| Candidato H | `<candidatura H: gmail>` | `<agendamento H: dominio institucional 1>` e `<agendamento H: dominio institucional 2>` |

Existe uma ponte de e-mail alternativo, tanto no `match_booking_application` quanto na rota Astro. Ela
resolve o e-mail via **`member_emails`**, que só cobre **membros da plataforma**. Candidato em seleção não
é membro. **A ponte é inerte por construção para exatamente o público que deveria atender.**

Escala medida: **9 `calendar_event_id` distintos** desde 01/07 registraram `calendar_booking_unmatched` e
**nunca** viraram entrevista. Descontando os que são o e-mail do organizador (você e o Fabricio, que o Apps
Script também envia como convidado), sobram estes agendamentos de candidato perdidos:

| e-mail do agendamento | agendado para (UTC) |
|---|---|
| `<agendamento I: gmail pessoal>` | 01/07 00:30 e 01/07 21:00 |
| `<agendamento J: gmail pessoal>` | 06/07 21:30 |
| `<agendamento H: dominio institucional 2>` | 21/07 22:30 |
| `<agendamento H: dominio institucional 1>` | 28/07 22:00 |
| `<agendamento G: outro gmail>` | 29/07 22:00 |
| `<agendamento F: gmail pessoal>` | 01/08 18:00 |

Todos já no passado. Candidato A era o único ainda no futuro, e foi reparado.

Este é o sintoma que o Vitor descreveu como "gaps na jornada": o candidato faz a parte dele, bloqueia a
agenda, e do lado do Núcleo não existe entrevista nenhuma.

---

## 6. Achado E: tempestade de retry do Apps Script

O webhook não tem backoff nem dead-letter. Ele re-tenta o mesmo evento indefinidamente, e cada tentativa
grava uma linha em `admin_audit_log`.

Contagem de linhas de `calendar_booking_unmatched` por agendamento não casado:

- `<agendamento F: gmail pessoal>`, evento de 01/08: **5.693 tentativas**
- `<e-mail pessoal do PM>`, evento de 21/07: **2.004 tentativas**
- `<agendamento H: dominio institucional 1>`, evento de 28/07: **830 tentativas**

Duas consequências: poluição do log de auditoria (que é a superfície forense usada nesta própria
auditoria) e chamadas inúteis contra a plataforma. Um agendamento que não casa **nunca** vai casar sem
intervenção, então re-tentar milhares de vezes não é resiliência, é ruído.

---

## 7. Achado F: roteamento da URL de agendamento ("às vezes a agenda deles, às vezes a do Núcleo")

O sintoma tem causa identificada e é **parcialmente por design**. `notify_selection_cutoff_approved`
resolve a URL por três caminhos, registrados em `selection_dispatch_url_log`:

| `resolution_path` | quando | URL usada |
|---|---|---|
| `cycle_fallback` | trilha `leader`, sempre | `selection_cycles.interview_booking_url` (a "agenda do Núcleo") |
| `committee_override` | trilha `researcher`, round-robin LRD | `selection_committee.interview_booking_url` do avaliador sorteado |
| `member_global` | trilha `researcher`, quando o comitê não tem URL própria | `members.interview_booking_url` |

A parte por design: **candidato a líder sempre cai na agenda do Núcleo**, porque a entrevista de líder é em
grupo (você e o Fabricio juntos). Isso está explícito no #1450 e na migration de roteamento.

### Correção de um achado preliminar (verificado 03/08 por resolução de redirect)

Uma versão anterior desta seção afirmava que a URL do PM **divergia** entre `committee_override`
(`calendar.app.google/MHAmfkgZCwT9KsoKA`) e `member_global` (`calendar.app.google/q9urWE15HYZRNymd7`), e
usava isso como metade da explicação do sintoma. **Isso está errado.**

`calendar.app.google/...` é o encurtador do Google para `calendar.google.com/appointments/schedules/...`.
Resolvendo os quatro links cadastrados pelo `Location` do redirect:

| link curto | schedule de destino | dono |
|---|---|---|
| `1jDNjPpoGCkV2V9A6` | `AcZssZ1HnqjUn0m8zof...` | Fabricio (confirmado pelo PM contra a URL longa dele) |
| `MHAmfkgZCwT9KsoKA` | `AcZssZ23xtPliqd0Kjf...` | PM |
| `q9urWE15HYZRNymd7` | `AcZssZ23xtPliqd0Kjf...` | PM, **mesmo schedule do anterior** |
| `XPiGWLh9JaLVFKJc6` | `AcZssZ2X11x_q2gAe8C...` | terceiro schedule, distinto dos dois pessoais |

Ou seja: os dois links do PM são **dois encurtadores do mesmo agendamento**. Nunca houve divergência
funcional; o candidato chega na mesma página por qualquer caminho. A duplicação é cosmética (duas
representações do mesmo recurso) e vale convergir por higiene, não por correção de bug.

**Lição de método:** duas strings diferentes não são dois destinos diferentes quando a string é um
encurtador. A comparação tem de ser feita no **recurso resolvido**, não no literal guardado no banco.
Comparar os literais produziu um falso achado que já estava escrito como causa do sintoma relatado.

Com a correção, o sintoma "às vezes uma agenda, às vezes outra" fica **inteiramente explicado pela
trilha** (pesquisador vai para PM ou Fabricio em rodízio; líder vai para o terceiro schedule), que é o
comportamento desenhado. Não há bug de configuração de URL.

A parte que **não** é por design:

1. **O round-robin alcança só duas pessoas.** Dos 7 membros do comitê do ciclo aberto, apenas você e o
   Fabricio têm `interview_booking_url`. O filtro do LRD exige
   `role IN ('evaluator','lead') AND can_interview AND URL IS NOT NULL`, então o Fernando Maquiaveli, que é
   `evaluator` com `can_interview = true`, **nunca é sorteado** por não ter URL.
2. **Todos os 4 `observer` estão com `can_interview = true`.** Hoje isso é inócuo, porque o filtro do LRD
   exclui `observer` por papel. Mas é um dado incoerente, e qualquer código futuro que confie em
   `can_interview` sem checar o papel vai escalar observador a entrevistador.

Composição medida do comitê do ciclo aberto:

| membro | papel | `can_interview` | `interview_booking_url` |
|---|---|---|---|
| Vitor Maia Rodovalho | evaluator | true | `calendar.app.google/MHAmfkgZCwT9KsoKA` |
| Fabricio Costa | evaluator | true | `calendar.app.google/1jDNjPpoGCkV2V9A6` |
| Fernando Maquiaveli | evaluator | true | **null** |
| Ivan Lourenço | observer | true | null |
| Lorena Souza | observer | true | null |
| Welma Alves de Melo | observer | true | null |
| VP Desenvolvimento Profissional (PMI-GO) | observer | true | null |

**O campo já existe.** O pedido de front-end não é "criar o campo", é decidir a superfície onde o próprio
membro do comitê edita o dele, e qual a regra de precedência entre comitê, membro e ciclo.

---

## 7-bis. Achado G: o comitê não alcança a superfície onde trabalha

**Origem:** o Fernando tentou abrir `/admin/selection` em 03/08 e recebeu "acesso negado". Não é erro de
cadastro dele.

### O que bloqueia

A tela tem **dois gates independentes**, de naturezas diferentes:

| gate | onde | exigência | Fernando passa? |
|---|---|---|---|
| cliente | `canAccessAdminRoute(m,'admin_selection')`, `src/lib/admin/constants.ts:181` | tier mínimo **`admin`** | **não** (tier `leader`) |
| servidor | `get_selection_dashboard` | `can_by_member(caller,'view_internal_analytics')` | **não** |

O gate do cliente é **tier-based** (`operational_role` + `designations`) e o do servidor é **action V4**.
Eles não são a mesma pergunta, e discordam entre si: Ivan Lourenço e Welma Alves de Melo têm
`view_internal_analytics = true` (passariam no servidor) e mesmo assim são barrados no cliente por tier.

### Extensão medida no comitê do ciclo aberto

| membro | papel | `operational_role` | `view_internal_analytics` | abre a tela? |
|---|---|---|---|---|
| Vitor Maia Rodovalho | evaluator | manager | true | **sim** |
| Fabricio Costa | evaluator | manager | true | **sim** |
| Fernando Maquiaveli | evaluator | tribe_leader | false | não |
| Ivan Lourenço | observer | sponsor | true | não |
| Welma Alves de Melo | observer | chapter_liaison | true | não |
| Lorena Souza | observer | chapter_liaison | false | não |
| VP Desenvolvimento Profissional | observer | chapter_liaison | false | não |

**5 dos 7 membros do comitê não conseguem abrir a superfície de seleção.** Só os dois admins conseguem.
Isso passou despercebido porque, até agora, o comitê operante *era* os dois admins.

### Procedimento de audit V4 (4 etapas, `docs/reference/V4_AUTHORITY_MODEL.md`) — executado

- **Etapa 1 (combos seedados para `view_internal_analytics`):** 6 combos -
  `chapter_board×liaison`, `sponsor×sponsor`, `volunteer×co_gp`, `volunteer×curator`,
  `volunteer×deputy_manager`, `volunteer×manager`. Nenhum representa "avaliador de comitê".
- **Etapa 2 (RPCs que usam a action):** 55 RPCs. O gate de `get_selection_dashboard` é **puro**
  (`IF NOT can_by_member(...) THEN Unauthorized`), sem `OR` alternativo. Não há path 1 alternativo embutido.
- **Etapa 3 e 4 (designation gates e RPCs scope-filtered):** **path 3 existe e é rico.** 32 funções
  referenciam `selection_committee`, e ao menos 26 gateiam **pela participação no comitê**, cobrindo
  exatamente o trabalho do avaliador: `get_my_committee_assignments`, `get_my_pending_evaluations`,
  `get_evaluation_form`, `submit_evaluation`, `get_evaluation_results`.

Verificado no corpo de `get_my_pending_evaluations`: o gate é
`EXISTS (SELECT 1 FROM selection_committee WHERE member_id = caller AND cycle_id = <ciclo evaluating>)
OR can_by_member(caller,'manage_member')`. Fernando satisfaz o primeiro ramo: `is_active = true`, e está
no comitê do `cycle4-2026`, que está em `phase = 'evaluating'`.

### Conclusão: é gap, mas NÃO onde parece

**A autoridade do Fernando como avaliador já está correta e completa no backend.** O path 3 cobre o caso
de uso inteiro. O que falta é **superfície**: `grep` por consumidores das RPCs de avaliador retorna
**um único arquivo**, `src/pages/admin/selection.astro`, e ele está atrás do gate de tier `admin`.

Portanto:

- ❌ **Não** seedar `view_internal_analytics` para o kind/role do Fernando. Seria o anti-pattern documentado
  na própria referência: a action é **leitura global de analytics de toda a plataforma**, e concedê-la para
  poder avaliar candidato é escalar privilégio muito além do caso de uso.
- ❌ **Não** baixar `ROUTE_MIN_TIER.admin_selection` de `admin` para `leader`. A tela tem abas de import,
  decisão e diversidade que não são do avaliador.
- ✅ O consertável é a **superfície**: ou uma rota dedicada de avaliador que consome só as RPCs
  committee-scoped, ou um modo reduzido da tela atual liberado por participação no comitê, com o
  `get_selection_dashboard` continuando fora do alcance dele.

Isto é o mesmo eixo do ADR-0105 (visibilidade ≠ autoridade de ação): o backend já separa os dois; o
frontend colapsou tudo num único tier.

---

## 8. Inventário residual do ciclo aberto

| medida | valor |
|---|---|
| candidaturas duplicadas (mesmo e-mail, ciclo aberto) | **3** |
| entrevistas passadas ainda com status `scheduled` | **1** (Candidato E, 23/07) |
| entrevistas `scheduled` sem nenhum entrevistador em `interviewer_ids` | **4** |
| candidaturas `submitted` sem nenhuma avaliação | **3** |
| agendamentos não casados desde 01/07 que nunca viraram entrevista | **9** |

Sobre as duplicadas: Candidato A tem duas candidaturas no mesmo ciclo, uma como `researcher`
(`interview_pending`, com score) e outra como `leader` (`submitted`, sem score). Precisa checar se é
dual-track intencional ou duplicação de import.

Sobre `interviewer_ids` vazio: as 4 entrevistas agendadas não têm entrevistador atribuído. Isso afeta o
`recompute_application_status`, cujo ramo `fully_scored` exige
`array_length(interviewer_ids, 1) >= 1`. Sem entrevistador, a candidatura **nunca** avança sozinha para
`final_eval` depois da entrevista.

---

## 9. Estado do funil (ciclo aberto)

| status | n | sem `objective_score_avg` | sem e-mail de cutoff |
|---|---|---|---|
| approved | 50 | 5 | 19 |
| rejected | 10 | 1 | 4 |
| submitted | 9 | 9 | 9 |
| interview_pending | 6 | 2 | 2 |
| interview_scheduled | 4 | 4 | 4 |
| final_eval | 1 | 0 | 1 |

`selection_evaluations` no total da plataforma: 273 `objective`, 95 `interview`, 52 `leader_extra`, todas
com `submitted_at` preenchido.

---

## 10. O que ainda NÃO foi auditado

Escopo declarado em aberto, para não parecer cobertura que não existe:

- **#1277** (35 ghosts, 2 leads sem follow-up, 1 `submitted` preso): a etapa Hub/OAuth/entrada não foi
  medida nesta sessão. Os "3 `submitted` sem avaliação" acima são do ciclo aberto e não foram cruzados
  com o `submitted` preso do #1277.
- **Fila de e-mail**: `notifications` tem 14 `selection_apto_to_sign_digest` e 1
  `selection_interview_overdue` com `email_sent_at` nulo nos últimos 7 dias, mas não distingui "aguardando
  envio" de "modo digest". Isso precisa ser resolvido **antes** do passo de abortar.
- **Os 11 crons geradores**: inventariados, não auditados um a um. O PM decidiu não pausar antes da
  auditoria terminar.
- **Etapa pós-entrevista**: `final_eval`, oferta VEP, assinatura de termo.

---

## 11. Ambiguidade aberta

O Vitor disse que "está entrando mais uma pessoa no Comitê (Fernando)". Em `members` só existe **Fernando
Maquiaveli**, que **já está** no comitê do ciclo aberto como `evaluator` com `can_interview = true` e
**sem** `interview_booking_url`. O Fernando Carvalho que circulou nesta semana é palestrante do webinar de
04/08 e não é membro.

Se for o Maquiaveli, a tarefa não é adicionar: é configurar a URL de agendamento dele, o que também
conserta o round-robin de duas pessoas descrito no Achado F.

---

## 12. Próximos passos, na ordem que o PM pediu

1. **Spec e requisitos** do gate único de objetiva, cobrindo os 4 escritores do Achado B, e da resolução de
   candidato por e-mail alternativo do Achado D.
2. **Gap assessment** por etapa da jornada, incluindo o que ficou de fora na seção 10.
3. **Decisão de front-end** para `interview_booking_url` por membro do comitê (superfície + precedência).
4. **Abortar com bisturi**, com a fila de e-mail resolvida antes.
5. **Só então** as issues cirúrgicas.

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
