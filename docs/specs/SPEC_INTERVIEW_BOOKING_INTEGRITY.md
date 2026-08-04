# SPEC - Integridade do agendamento de entrevista (gate único + resolução de candidato + robustez do webhook)

**Origem:** auditoria da jornada do candidato (`docs/audit/2026-08-03_AUDITORIA_JORNADA_CANDIDATO.md`), etapa 1.
**Status:** proposta. Nenhuma cirurgia executada.
**Data da medição:** 2026-08-03 23:36-23:55 UTC. Todo número abaixo saiu de consulta ao vivo nessa janela.
**Repo público:** candidatos aparecem por papel ou por id. Não incluir e-mail nem nome.

---

## 1. Por que esta spec existe

A plataforma tem quatro caminhos que colocam uma candidatura em estágio de entrevista, e
nenhum deles verifica se a fase objetiva terminou. Em paralelo, reservas reais de candidato
não chegam a virar entrevista, por dois motivos diferentes entre si, e quem leva no-show fica
num beco sem saída. As coisas se somam: o funil aceita quem não deveria entrar e perde quem
deveria.

**Correção importante em relação ao handoff de 03/08:** o handoff propôs pôr o gate na
fonte compartilhada `match_booking_application`. **Isso cobre 2 dos 4 escritores.** A função
resolve *qual candidatura* corresponde a uma reserva; ela não é atravessada pelo trigger nem
pelo `mark_interview_status`, que escrevem em `selection_applications` direto. Ver §4.1.

---

## 2. As quatro classes de falha

### Classe A - o gate de objetiva vive na implementação morta

`sync_calendar_booking_to_interview` **tem** o gate do #1450 (`IF v_app.objective_score_avg
IS NULL THEN ... RETURN warning`), mas disparou 1 vez na vida (2026-05-06). Quem sincroniza
de verdade é `src/pages/api/calendar-webhook.ts`, que não tem o gate.

Escritores que levam a candidatura a estágio de entrevista, verificados no corpo vivo:

| escritor | tipo | tem gate de objetiva | audita |
|---|---|---|---|
| `src/pages/api/calendar-webhook.ts` | rota Astro, `service_role` | não | sim |
| `_trg_sync_interview_to_app_status` | trigger AFTER INSERT OR UPDATE OF status, conducted_at em `selection_interviews` | não | não |
| `mark_interview_status` | RPC SECDEF | não | não |
| `recompute_application_status`, ramo `WHEN sched_active` | RPC SECDEF, cron job 49 (13:00 UTC) | não | sim |

⚠️ **Corrigir só o webhook não basta.** O cron 49 recalcula `canonical = 'interview_scheduled'`
sempre que existe linha de entrevista em `scheduled`/`rescheduled`, e ratifica o estado errado
todo dia. E o trigger refaz o mesmo a cada INSERT de entrevista.

**Dano vivo no ciclo aberto** (medido 03/08 23:52 UTC):

| status | n | sem `objective_score_avg` |
|---|---|---|
| interview_pending | 7 | 1 |
| interview_scheduled | 2 | 2 |
| interview_done | 0 | 0 |
| interview_noshow | 1 | 1 |
| final_eval | 3 | 1 |

**5 candidaturas em estágio de entrevista sem nota objetiva.** O PM já decidiu manter as que
estão lá e corrigir o processo; o gate portanto não pode invalidar linha existente.

### Classe B - resolução do candidato por e-mail divergente

O candidato agenda com e-mail pessoal diferente do e-mail da candidatura. A ponte de e-mail
alternativo resolve via `member_emails`, que só cobre **membros**; candidato não é membro, então
**a ponte é inerte por construção**.

Medido: desde 01/07, **6 endereços** de candidato real chegaram ao webhook sem candidatura
correspondente.

### Classe C - o payload traz o convidado errado (nova, não estava na auditoria)

O Apps Script dispara o webhook **uma vez por convidado** do evento: o mesmo `calendar_event_id`
aparece no log com endereços diferentes (candidato, PM, co-GP, avaliador). Quando o endereço do
candidato **não** é enviado, a reserva se perde inteira, **com os dois lados corretos** - o
e-mail da candidatura bate, o status está na allow-list, e mesmo assim nada acontece.

Caso medido: evento `bsb4n49e06al6cj95mdivgqkp8@google.com` (10/08 19:30 BRT). **70 tentativas**
entre 03/08 17:51 e 23:36, todas com `guest_email` = o e-mail do PM. O endereço do candidato
nunca foi enviado. Às 17:51 o status dele era `interview_scheduled`, que está na allow-list:
**com o payload certo teria casado.** Consequência real: ele auto-reagendou 4h47 antes da
entrevista de 03/08, a plataforma não viu, e ele foi marcado `noshow` por uma entrevista que
já tinha movido.

**Resumo do estrago:** 10 eventos de calendário desde 01/07 não viraram entrevista.

### Classe D - quem leva no-show não consegue reagendar

`match_booking_application` só aceita `submitted, screening, objective_eval, objective_cutoff,
interview_pending, interview_scheduled`. `interview_noshow` fica de fora, e
`recompute_application_status` também o trata como **terminal** (está na lista de exclusão do
`WHERE cur NOT IN (...)`). Efeito combinado: um no-show é um beco sem saída - nem o reagendamento
casa, nem o pipeline volta a andar sozinho depois da entrevista de recuperação.

---

## 3. Requisitos

### R1 - gate único de fase objetiva
Uma candidatura não entra em `interview_scheduled` sem `objective_score_avg`, **por qualquer
caminho**, incluindo caminhos que ainda não existem.

- R1.1 O gate é aplicado num ponto que os 4 escritores atravessam obrigatoriamente.
- R1.2 O gate **recusa e registra**; nunca falha calado (ver `reference-plpgsql-null-condition-skips-raise`).
- R1.3 Linhas já em estágio de entrevista sem nota objetiva **não são invalidadas** (decisão do PM).
- R1.4 Existe caminho explícito de exceção para o GP, auditado, com motivo obrigatório.
- R1.5 O gate não pode bloquear **reagendamento** de entrevista já materializada (a idempotência vem antes do gate, como já é no corpo do `sync_calendar_booking_to_interview`).

### R2 - resolução de candidato independente de `member_emails`
- R2.1 A resolução por e-mail alternativo cobre **candidatos**, não só membros.
- R2.2 Zero risco de match cruzado entre candidatos distintos: o match primário sempre vence, e o alternativo exige prova de mesma pessoa.
- R2.3 Falha de resolução vira item acionável, não linha de log repetida.

### R3 - o webhook não pode depender de qual convidado o Apps Script escolheu
- R3.1 O payload carrega **todos** os convidados do evento, não um por chamada; ou o webhook resolve o evento por `calendar_event_id` além do e-mail.
- R3.2 Convidado conhecido como não-candidato (PM, co-GP, avaliadores) não gera `calendar_booking_unmatched`.
- R3.3 Uma reserva só é declarada não casada depois de tentar **todos** os convidados.

### R4 - retry com backoff e dead-letter
- R4.1 Tentativa repetida do mesmo `calendar_event_id` não gera linha nova de auditoria indefinidamente. Medido: **5.693 linhas** para um único agendamento; **70 e contando** para o de 10/08, ainda rodando enquanto esta spec é escrita.
- R4.2 Após N tentativas, o evento vai para uma fila de exceção visível ao GP.
- R4.3 O contador de tentativas é observável sem varrer `admin_audit_log`.

### R5 - saída do no-show
- R5.1 Reagendamento após no-show casa (allow-list admite `interview_noshow`).
- R5.2 Após a entrevista de recuperação, o pipeline avança sem intervenção manual.
- R5.3 A decisão de reabrir um no-show é do GP e fica auditada (um no-show legítimo não deve voltar sozinho).

---

## 4. Desenho proposto

### 4.1 Onde o gate único realmente cabe

O ponto que os 4 escritores atravessam **não** é `match_booking_application` (só 2 passam por
ela). É a **escrita em `selection_applications.status`**. Duas opções:

**Opção 1 (recomendada) - trigger BEFORE UPDATE em `selection_applications`.**
Recusa a transição `* → interview_scheduled` quando `objective_score_avg IS NULL`, salvo
override explícito.

- Cobre os 4 escritores por construção, e o 5º que aparecer depois.
- Atende R1.3 naturalmente: só olha a *transição*, não o estado em repouso, então as 5 linhas atuais ficam onde estão.
- R1.4 via `platform_settings` ou coluna de override na própria candidatura, gravada por RPC do GP com motivo.
- Risco: um trigger que levanta exceção derruba o `UPDATE` inteiro do chamador. O cron 49 processa em laço, uma candidatura por iteração, com `UPDATE ... WHERE id = ... AND status = ...`; uma exceção aborta a função toda. **Mitigação:** o trigger não levanta exceção - ele *suprime a transição* (retorna `OLD.status`) e registra `selection.interview_stage_blocked`. Suprimir com registro atende R1.2; suprimir calado não.

**Opção 2 - helper compartilhado `_can_enter_interview_stage(app_id)` chamado pelos 4.**
Mais explícito e mais fácil de testar unitariamente, mas depende de disciplina: é exatamente
o padrão que produziu a Classe A (o gate existia, num dos caminhos).

> Decisão pendente do PM entre 1 e 2. A recomendação é a 1, com a mitigação de supressão-com-registro.

### 4.2 Resolução de candidato (R2)

Trocar a ponte `member_emails` por resolução própria de candidatura:

- Match primário: `LOWER(TRIM(a.email)) = guest` (como hoje).
- Match alternativo: contra um conjunto de e-mails **da candidatura**, não do membro. Exige campo novo (`selection_applications.alternate_emails text[]`, ou tabela `selection_application_emails`) alimentado por: e-mail do VEP, e-mail declarado no formulário, e e-mail usado em agendamento anterior já confirmado.
- Enquanto o campo não existir, a Classe B não tem correção automática: cada caso vira reparo manual. Isso precisa estar dito na issue, não implícito.

### 4.3 Robustez do webhook (R3, R4)

- O Apps Script passa a enviar `guests: string[]` em vez de `guest_email` único. O webhook mantém compatibilidade com o campo antigo por um ciclo.
- O webhook resolve contra **todos** os convidados e só registra não-casamento se **nenhum** casar.
- Lista de e-mails institucionais conhecidos (`platform_settings`) que nunca são candidatos: não entram na tentativa e não geram log.
- Contador por `calendar_event_id` em tabela própria, com backoff e corte após N.

### 4.4 Saída do no-show (R5)

- `interview_noshow` entra na allow-list de `match_booking_application`, **atrás de flag**: só casa se o GP tiver reaberto, ou se a política for reabrir automaticamente (decisão de processo, não técnica).
- `recompute_application_status` precisa de caminho de saída de `interview_noshow` quando existe entrevista conduzida posterior. Hoje é terminal, o que significa que o candidato reagendado de 10/08 **não avança sozinho** depois da entrevista.

---

## 5. Fora de escopo

- Migração da trilha de pesquisador para calendário institucional (depende de decisão do PM, pendência 3 do handoff).
- Round-robin de avaliadores e a URL de agendamento faltante de um dos avaliadores (pendência 1).
- Dono do schedule `cycle_fallback` (pendência 2).
- #1277 (35 ghosts, 2 leads sem follow-up), fila de e-mail, os 11 crons um a um, etapa pós-entrevista. Esses entram no gap assessment, não aqui.

---

## 6. Plano de teste

| # | Teste | Classe |
|---|---|---|
| T1 | Cada um dos 4 escritores, com `objective_score_avg IS NULL`, não leva a candidatura a `interview_scheduled`, e cada um deixa registro | A / R1.1 |
| T2 | Mutação: remover o gate faz T1 falhar (se passar sem o gate, o gate é decorativo) | R1.2 |
| T3 | As 5 candidaturas atuais em estágio de entrevista sem nota objetiva continuam onde estão após a migration | R1.3 |
| T4 | Reagendamento de entrevista já materializada passa mesmo sem nota objetiva | R1.5 |
| T5 | Reserva com e-mail alternativo de candidatura casa; e-mail de outro candidato não casa | R2.1 / R2.2 |
| T6 | Evento com 4 convidados, sendo 1 candidato em qualquer posição da lista, casa | R3.1 / R3.3 |
| T7 | Evento sem nenhum candidato entre os convidados gera **1** item de exceção, não N linhas de log | R3.2 / R4.1 |
| T8 | Após N tentativas o evento aparece na fila de exceção | R4.2 |
| T9 | Reagendamento após no-show casa quando reaberto e não casa quando não reaberto | R5.1 |
| T10 | Entrevista conduzida após no-show reaberto avança o pipeline | R5.2 |

⚠️ Os testes DB-aware rodam serial (`--test-concurrency=1`) contra a base de produção. Conferir o
número de skips, não só `fail 0` (ver `reference-npm-test-needs-env-exported-or-548-skip`).

---

## 7. Ordem de execução

1. Esta spec aprovada pelo PM (decisão pendente: Opção 1 vs 2 em §4.1; política de reabertura de no-show em §4.4).
2. Gap assessment por etapa da jornada.
3. Resolver a fila de e-mail **antes** de qualquer aborto de cron. ⚠️ Os jobs 9 (`send-notification-emails`) e 30 (`dispatch-pending-emails`) entregam e-mail da plataforma inteira; pausá-los derruba tudo, e pausar os geradores não drena o que já está na fila.
4. Issues cirúrgicas, uma por classe.
