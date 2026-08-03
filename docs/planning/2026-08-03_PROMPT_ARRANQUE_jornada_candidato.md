# Arranque da próxima sessão: auditoria da jornada do candidato

> ⚠️ **Nenhum número deste documento vale como medição.** Todos foram levantados em 03/08 por volta
> das 15h30 UTC e derivam a partir daí. Re-consulte a fonte antes de usar qualquer um em decisão,
> commit, PR, SPEC ou memória.

## 1. O que o Vitor pediu (palavras dele, condensadas)

1. **Abortar** o workflow de seleção de candidatos, o comitê de seleção, os disparos de e-mail de
   agendamento e **qualquer outro e-mail da jornada do candidato**.
2. Ele acredita que **ainda há bugs na jornada**.
3. Está entrando **mais uma pessoa no comitê (Fernando)**, e é preciso organizar para funcionar.
4. Possivelmente algo de **front-end**, se for a melhor saída, para o **calendário de agendamento** e
   a **configuração pelo próprio membro do comitê**. Hoje ele e o Fabricio configuram por fora e
   mandam o link.
5. Três sintomas que ele relatou textualmente:
   - às vezes o agendamento **sai pela agenda deles**, às vezes **pela agenda do Núcleo**;
   - às vezes o convite sai **sem o candidato ter sido avaliado em peer review da objetiva**;
   - seguem existindo **problemas ou gaps na jornada**.
6. **Método exigido, nesta ordem:** levantar issues abertas e fechadas sobre o tema, fazer uma
   **auditoria**, produzir **spec, requisitos e gap assessment**, e **só depois** atuar de forma
   cirúrgica em issues e oportunidades de melhoria identificadas.

**Não comece pela cirurgia.** O pedido é explícito: auditar e especificar antes.

## 2. ⚠️ O que corre contra o relógio

Medido em 03/08 15:30 UTC:

| entrevista agendada (UTC) | falta | status |
|---|---|---|
| **03/08 21:30** | ~5h45 | scheduled |
| **03/08 22:30** | ~6h45 | scheduled |
| 05/08 00:00 | ~1 dia 8h | scheduled |

Ou seja: **há duas entrevistas hoje**. Abortar os fluxos sem olhar para elas cancela o lembrete de
1 hora que essas pessoas esperam receber. Decida o que fazer com as 3 antes de pausar qualquer job.

## 3. Inventário: o que dispara sozinho hoje

**11 cron jobs ativos tocam a jornada do candidato.** Todos confirmados `active = true` em
`cron.job`:

| jobid | job | schedule (UTC) | o que faz |
|---|---|---|---|
| 46 | `interview-reminder-1h-q15min` | `5,20,35,50 * * * *` | lembrete 1h antes da entrevista |
| 33 | `nudge-reschedule-pending-daily` | `0 14 * * *` | cobra reagendamento pendente |
| 48 | `selection-interview-overdue-daily` | `0 14 * * *` | entrevista vencida |
| 49 | `selection-status-recompute-daily` | `0 13 * * *` | recomputa status |
| 50 | `selection-consistency-check-daily` | `30 13 * * *` | consistência |
| 51 | `selection-cutoff-pending-daily` | `0 14 * * *` | corte pendente |
| 52 | `selection-stuck-scheduled-rescue-daily` | `0 15 * * *` | resgata travado em scheduled |
| 59 | `selection-apto-to-sign-digest-daily` | `45 13 * * *` | digest apto-para-assinar |
| 60 | `detect-stuck-selection-funnel-daily` | `0 16 * * *` | funil travado |
| 62 | `selection-unbooked-rescue-daily` | `30 15 * * *` | resgata não agendado |
| 61 | `nudge-vep-offer-accept-daily` | `0 17 * * *` | cobra aceite de oferta VEP |

**Os dois que efetivamente ENTREGAM e-mail são outros, e são compartilhados com o resto da
plataforma:**

| jobid | job | schedule | atenção |
|---|---|---|---|
| 9 | `send-notification-emails` | `*/5 * * * *` | chama a EF `send-notification-email` |
| 30 | `dispatch-pending-emails` | `*/30 * * * *` | `process_pending_email_queue()` |

⚠️ **Consequência de projeto:** pausar os 11 geradores **não impede** o envio do que já está na
fila, porque quem entrega são os jobs 9 e 30. E pausar os jobs 9 e 30 **derruba o e-mail da
plataforma inteira**, não só o da jornada. Qualquer "abortar" precisa escolher conscientemente entre
os dois níveis, e o handoff recomenda pausar os geradores e **drenar/limpar a fila** em vez de matar
a entrega global.

Pipeline de triagem que também alimenta a jornada: `extract-cv-text-15min` (43),
`retry-pending-ai-triages` (45), `retry-pending-ai-analyses` (31).

## 4. Estado do funil

| medida | valor |
|---|---|
| `selection_applications` | 169 |
| aprovados / rejeitados | 91 / 55 |
| **submitted** | **9** |
| **interview_pending** | **6** |
| **interview_scheduled** | **4** |
| final_eval / converted / withdrawn | 1 / 2 / 1 |
| `selection_evaluations` | 420 |
| notificações criadas nos últimos 7 dias | 231 |

Tabelas do domínio: `selection_applications`, `selection_cycles`, `selection_committee`,
`selection_interviews`, `selection_evaluations`, `selection_evaluation_ai_suggestions`,
`selection_evaluation_anomalies`, `selection_ranking_snapshots`, `selection_dispatch_url_log`,
`selection_application_service_history`, `selection_diversity_snapshots`,
`selection_membership_snapshots`, `selection_topic_views`, `tribe_selections`,
`volunteer_applications`.

⚠️ `selection_dispatch_url_log` tem cara de ser exatamente a trilha de qual URL foi despachada em
cada convite. Comece a investigação do sintoma "sai por agenda diferente" por ela.

## 5. Achado preliminar que reposiciona o pedido de front-end

**O campo já existe.** `selection_committee` tem a coluna **`interview_booking_url`**, por membro e
por ciclo. O que falta não é o modelo de dados.

Composição do comitê no ciclo **aberto** (7 linhas):

| membro | papel | `can_interview` | tem URL própria | host |
|---|---|---|---|---|
| Vitor Maia Rodovalho | evaluator | sim | **sim** | `calendar.app.google` |
| Fabricio Costa | evaluator | sim | **sim** | `calendar.app.google` |
| Fernando Maquiaveli | evaluator | sim | não | - |
| Ivan Lourenço | observer | sim | não | - |
| Lorena Souza | observer | sim | não | - |
| Welma Alves de Melo | observer | sim | não | - |
| VP Desenvolvimento Profissional (PMI-GO) | observer | sim | não | - |

Três hipóteses que essa tabela sugere e que a auditoria precisa **confirmar ou derrubar**, não
assumir:

1. **"Às vezes sai pela nossa agenda, às vezes pela do Núcleo"** tem candidato a causa: só 2 dos 7
   têm `interview_booking_url`; os outros 5 provavelmente caem num fallback. Procure o fallback e
   confirme qual URL é usada quando a do membro é nula.
2. **Ambos os links preenchidos são `calendar.app.google`**, ou seja, agenda pessoal, o que bate com
   o relato de "configurar externamente".
3. **Todos os 7 têm `can_interview = true`, inclusive os 4 `observer`**. Verifique se observador
   deveria poder entrevistar, ou se isso é um gap de permissão.

## 6. Ambiguidade a resolver com o Vitor logo no começo

Ele disse "estamos adicionando mais uma pessoa no Comitê (**Fernando**)".

**Só existe um Fernando em `members`: Fernando Maquiaveli** (tribe_leader, ativo) e ele **já está**
no comitê do ciclo aberto, como `evaluator` com `can_interview = true`, sem `interview_booking_url`.

O outro Fernando que circulou nesta semana, **Fernando Carvalho**, é palestrante do webinar de 04/08
e **não é membro da plataforma**. Há memória registrada de que os dois não devem ser confundidos.

**Pergunte antes de mexer no comitê.** Se for o Maquiaveli, a tarefa não é adicionar: é configurar
o `interview_booking_url` dele e conferir o papel. Se for outra pessoa, ela precisa existir como
membro primeiro.

## 7. Issues sobre o tema

**Abertas:**

| # | título |
|---|---|
| **1277** | audit(hub): gaps na jornada de entrada/candidatura - 35 ghosts, 2 leads sem follow-up, 1 submitted preso |
| 1102 | research(selection): revisitar modelos de IA + robustez de vídeo + lane de comms |
| 1134 | UX/mobile: colapsar quick-filters do /admin/selection |
| 1310 | [vep] formalizar posição de Curador numa VEP opportunity ativa |
| 1095 | feat(filiacao): automação da verificação |

A **#1277** é a mais próxima do pedido e provavelmente deve ser o guarda-chuva ou ser explicitamente
superada pela nova spec.

**Fechadas, e diretamente relevantes ao sintoma relatado:**

| # | por que importa |
|---|---|
| **1450** | candidatos VEP importados eram convidados a agendar **antes da avaliação**. É literalmente o sintoma "sai sem peer review da objetiva". Leia primeiro: pode ser regressão ou caso não coberto. |
| 1446 | `/admin/selection` abria no ciclo errado (default do `get_selection_dashboard`) |
| 1462 | ranks de seleção stale |
| 1316 | atribuição vaga VEP para ciclo interno é heurística por data (36 apps fora) |
| 1276 | `get_selection_health` quebrado |
| 1326 | `get_my_meetings` vazava entrevistas |
| 1474 / 1465 | visão do candidato pós-decisão e transparência de pontuação |
| 1247 | jornada de entrada em tribo: "Erro ao selecionar" |
| 1224 | captura de capítulo inconsistente na candidatura |
| 1175 | filiação x VEP: bulk verify usa status de candidatura como filiação |

## 8. Roteiro sugerido, na ordem que o Vitor pediu

1. **Decidir o destino das 3 entrevistas agendadas** (2 são hoje) antes de pausar qualquer coisa.
2. **Levantamento**: ler #1450 e #1277 na íntegra; mapear o caminho completo do convite de
   agendamento (RPC de origem, `selection_dispatch_url_log`, template de e-mail, fallback de URL).
3. **Abortar com bisturi**: pausar os 11 geradores, decidir o que fazer com a fila pendente, e
   **não** derrubar os jobs 9 e 30, que servem a plataforma inteira. Registre em issue o que foi
   pausado, quando, e o critério para religar.
4. **Auditoria e gap assessment**: estado real de cada etapa da jornada contra o que deveria ser,
   com evidência medida por etapa. O sintoma "convite antes do peer review" precisa de uma consulta
   que **conte** os casos, não de uma leitura de código.
5. **Spec e requisitos**: incluindo a decisão sobre front-end de configuração de agenda por membro
   do comitê (o campo já existe; a pergunta é a superfície e a regra de fallback).
6. **Só então**, atuar em issues cirúrgicas.

## 9. O que NÃO fazer

- Não pausar `send-notification-emails` (9) nem `dispatch-pending-emails` (30) sem entender que eles
  entregam e-mail de **toda** a plataforma.
- Não assumir que "Fernando" precisa ser adicionado (ver seção 6).
- Não tratar `interview_booking_url` como campo a criar: ele existe.
- Não recitar nenhum número deste documento sem re-medir.

## 10. Contexto herdado das sessões anteriores

- **Webinar da T6 em 04/08 19h (BRT)**: campanha entregue a 88 membros, posts D-1 e D0 agendados,
  link na bio já colocado pelo Vitor. Não deve exigir trabalho, mas é o pano de fundo da semana.
- **#1565 aberta**: tribo ROI & Portfólio com duas séries futuras de reunião; a tribo trocou de
  liderança e está redefinindo o dia. Há uma allowlist com ratchet em
  `676-recurring-meeting-rules.test.mjs`, então **não bloqueia** CI.
- **Trilha B (base legal dos 941 contatos externos)**: desbloqueada e não iniciada.
- Fechadas em 02-03/08: #1437, #1562, #1563, #1566.

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
