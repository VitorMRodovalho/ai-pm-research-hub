# SPEC — ÉPICO D: detecção + nudge ao GP do funil de seleção "stuck pós-convite"

**Status:** council OK — data-architect **GO-with-changes** (5 mudanças aplicadas; 4 questões §7 resolvidas)
**Origin:** discovery `PRE_ONBOARDING_JOURNEY_DISCOVERY_2026-06-16.md` §ÉPICO D (gaps D5+D3, seed de D1).
**Decisão PM (2026-06-17):** (1) pivotar H4→ÉPICO D (coorte literal do H4 = 0 ao vivo); (2) começar
pela fatia **"Detecção + nudge ao GP (DB-first)"** — não o painel FE (D1) nem auto-rescue (D3).
**Escopo:** 1 PR DB-first. Sem FE. Reusa `sla_policies` (J4) e o delivery-mode ADR-0022.

---

## 1. Problema (aterrado ao vivo — cycle4-2026, 2026-06-17)

O discovery escopou **D2** (auto-dispatch de convite) como o 🔴 central. **Ao vivo D2 está resolvido**:
os 11 `interview_pending` têm `cutoff_approved_email_sent_at` setado (convite enviado); `pending_no_invite = 0`.

O 🔴 vivo real é **pós-convite** — candidatos convidados que caem num buraco **invisível aos crons atuais**:

- `_selection_interview_overdue_cron` (job48) só seleciona entrevistas **com linha** `selection_interviews`
  e `status IN ('scheduled','rescheduled')` + `scheduled_at < now()-grace`. Logo:
  - **Convidado-nunca-agendou** → não tem linha de entrevista → nunca entra em `stale_pairs` → invisível. **(= D5)**
  - **No-show** → linha vira `status='noshow'` ∉ (scheduled,rescheduled) → invisível; ninguém re-convida. **(= D3)**
- Não há agregação "ação minha hoje" por tipo-de-problema para o GP. **(= D1, fica para PR posterior)**

Coorte viva (todos convidados, todos invisíveis aos crons):

| Candidato | Idade | Sinal | Bucket |
|---|---|---|---|
| Hector Rigon | 86d | convidado, **sem linha de entrevista** | invited_never_booked |
| Djeimiys Wille | 57d | idem | invited_never_booked |
| Francisco | 28d | idem | invited_never_booked |
| Luã / Evilasio / Lizzie | 8–18d | idem (envelhecendo) | invited_never_booked |
| Edinan Soares | 86d | **no-show 05/06, sem recuperação** | noshow_not_recovered |
| Bruna Zomer | 66d | reschedule→noshow→cancel, nunca completou | noshow_not_recovered |

Falso-positivo a **excluir**: Hanae (linha cancelada + linha `scheduled` futura 23/06 = reschedule legítimo).

---

## 2. Objetivo

Tornar o stuck pós-convite **visível e cobrável pelo GP**: um cron diário classifica os candidatos
parados por tipo de problema e **notifica os managers (GP)** com link direto para a candidatura. Não age
sobre o candidato (sem comms externas automáticas — isso é D3 auto-rescue, fatia posterior).

## 3. Não-objetivos (FORA deste PR)

- Painel FE "ação minha hoje" (D1) — PR posterior, consome a mesma lógica de detecção.
- Auto-rescue / re-convite automático do candidato (D3) — risco de comms externas; depois que o GP confiar nos sinais.
- Bucket "múltiplas-falhas" como classe separada (threshold é **contagem**, não intervalo → não cabe em `sla_policies`; Bruna já cai em noshow_not_recovered). Adiar.
- Bucket "cancelado-sem-rebooking" (ex.: Cristiano, recuperando) — **questão aberta p/ data-architect** (§7).
- Corrigir os 2 bugs de RPC achados (`get_selection_health` → `column t.created_at does not exist`; `get_selection_dashboard` 274k chars sem paginação) — **logar no backlog**, não neste PR.

---

## 4. Design DB-first

### 4.1 RPC `detect_stuck_selection_funnel(p_dry_run boolean DEFAULT true) RETURNS jsonb`
- `SECURITY DEFINER`, `SET search_path=''`, `REVOKE` de PUBLIC (padrão dos crons `_selection_*`).
- **Header obrigatório:** comentário `-- fast-path stakeholder fan-out per ADR-0011 Amendment A — enumerates operational_role='manager' without can_by_member per approved exception.` (senão `rpc-v4-auth.test.mjs` pode flagear o uso de `operational_role`).
- Espelha o shape de `_selection_interview_overdue_cron`: classifica → idempotência 7d → INSERT em `notifications` (só se `NOT p_dry_run`) → retorna `jsonb_build_object('success', true, 'dry_run', p_dry_run, 'invited_never_booked', N, 'noshow_not_recovered', M, 'inserted', K, 'run_at', now())`.
- Escopo: candidaturas do **ciclo ativo** (último `selection_cycles` por `created_at`), `status='interview_pending'`.

**Bucket A — `invited_never_booked`** (= D5):
- `status='interview_pending'`
- `cutoff_approved_email_sent_at IS NOT NULL`
- `interview_reschedule_requested_at IS NULL` (reschedule ativo → job33 cuida). **Contrato:** este campo segue "NULL = sem reschedule pendente"; só job33/`process_pending_reschedule_nudges` o gerencia. Se o contrato quebrar upstream, o bucket A gera falso-negativo silencioso.
- **NÃO EXISTE** linha em `selection_interviews` para a app (truly never booked)
- `now() - cutoff_approved_email_sent_at > sla('interview_booking_grace')` (default **10 days** — data-architect: 7d pegaria candidatos de 6-8d ainda na 1ª semana pós-convite; GP ajusta via UI J4)

**Bucket B — `noshow_not_recovered`** (= D3):
- `status='interview_pending'`
- existe linha `selection_interviews` com `status='noshow'`
- **NÃO EXISTE** linha **posterior ao último noshow** com `status IN ('scheduled','completed')` — qualificar temporalmente: `created_at > (SELECT max(created_at) FROM selection_interviews WHERE application_id=app.id AND status='noshow')` (evita falso-negativo de completed-antes-de-noshow)
- **NÃO EXISTE** linha com `scheduled_at > now()` e `status IN ('scheduled','rescheduled')` (sem futuro agendado → exclui Hanae)
- `now() - (max scheduled_at das linhas noshow) > sla('noshow_recovery_grace')` (default **3 days**)

Prioridade: B antes de A (se a app tem noshow, classifica como noshow_not_recovered, não como never_booked — embora os predicados sejam mutuamente exclusivos por "NÃO EXISTE linha" em A).

### 4.2 Destinatário do nudge
- **GP managers**: `members WHERE operational_role='manager'` (ao vivo: Vitor, Fabricio).
- 1 notificação por `(manager, application, bucket-type)`.
- **Idempotência:** não inserir se já existe `notifications` com `recipient_id=v_manager_id` + `source_type='selection_application'` + `source_id=app.id` + `type IN ('selection_candidate_unbooked','selection_noshow_unrecovered')` nos últimos **7 dias** (filtrar pelos 2 types novos, não type genérico — evita colisão com outras notificações da mesma candidatura; espelha a janela do job48).

### 4.3 Tipos de notificação (novos) + delivery-mode (ADR-0022)
- `selection_candidate_unbooked` → `digest_weekly`
- `selection_noshow_unrecovered` → `digest_weekly`
- **NÃO** redefinir `_delivery_mode_for`: ambos resolvem via o branch **ELSE = `digest_weekly`** já existente. O `adr-0022-delivery-mode.test.mjs` (linha 95) **pula** tipos digest_weekly na checagem de paridade do helper, então registro no catálogo basta — e evita transcrever o corpo inteiro daquela função (risco de Phase-C drift). `delivery_mode` na coluna via `public._delivery_mode_for(type)` (decisão final, desvio do rascunho — review LOW).
- Justificativa do modo: igual a `selection_interview_overdue` (`digest_weekly`). A linha in-app aparece **imediatamente** (visível no sino); o `digest_weekly` só governa a cadência de **e-mail**, evitando spam ao GP a cada run diário.
- `title`/`body` PT-BR, com nome do candidato + idade + ação ("Abrir candidatura em /admin/selection"). `link = '/admin/selection/applications/'||application_id`.

### 4.4 Config SLA (reusa tabela `sla_policies` do J4)
Inserir 2 rows (a UI admin do J4 as exibe automaticamente — lê `from('sla_policies').select()`):
- `interview_booking_grace` = `'10 days'` — "Prazo após o convite (cutoff approved) sem agendar antes de o GP ser alertado (detect_stuck_selection_funnel)."
- `noshow_recovery_grace` = `'3 days'` — "Prazo após um no-show sem recuperação antes de o GP ser alertado (detect_stuck_selection_funnel)."
- RPC lê via `SELECT value_interval ... WHERE policy_key=...` com **fallback ao literal** se NULL (padrão dos crons J4).

### 4.5 Cron
- `cron.schedule('detect-stuck-selection-funnel-daily', '0 16 * * *', $$SELECT public.detect_stuck_selection_funnel(p_dry_run := false)$$)` (16:00 UTC — após overdue 14:00 e stuck-rescue 15:00).

### 4.6 Invariante
**Nenhum invariante novo** — é detecção/notificação efêmera (como `detect_inactive_members`); sem fonte estrutural imutável. Guard = idempotência + escopo do ciclo ativo.

---

## 5. GC-097 / migração
- DDL **só** via `apply_migration`; depois `Write` do arquivo local `supabase/migrations/<ts>_d_stuck_funnel_detection.sql`, `supabase migration repair --status applied <ts>`, `NOTIFY pgrst,'reload schema'`.
- `prokind='f'`; corpo da fn **sem** comentário inline que nomeie outras funções (sediment Phase-C).
- Verificar shadow UTC pós-apply → repair no ts canônico + DELETE shadow (não tocar baselines name=null).

## 6. Testes
- `tests/contracts/D-stuck-funnel.test.mjs`: offline (RPC existe, 2 buckets, 2 sla keys, 2 tipos no delivery-mode, cron registrado, idempotência 7d, exclusão de futuro-agendado, escopo ciclo-ativo, sem números hardcoded de coorte) + DB-gated (dry_run não insere; probe).
- Atualizar `adr-0022-delivery-mode.test.mjs` para os 2 tipos novos.
- 2 whitelists (package.json) para o novo arquivo.
- Probe ROLLBACK: criar app fake never_booked em tx → `detect_stuck_selection_funnel(true)` conta → rollback (prod intacto).

## 7. Questões resolvidas (data-architect 2026-06-18)
1. **Destinatário**: **só managers** (`operational_role='manager'`). ADR-0011 Amendment A cobre fan-out direto; committee não tem autoridade de re-ação (re-convidar/encerrar é do GP). Committee = D1 (FE), depois.
2. **booking_grace**: **10 days** (default conservador; GP reduz via UI J4 sem migração). 7d alarmaria candidatos na 1ª semana pós-convite.
3. **Bucket cancelado-sem-rebooking**: **adiar**. Sinal fraco; tabela sem `cancelled_by` (cancel-pelo-entrevistador vs candidato ambíguo); coorte crítica já coberta por A+B. Follow-up PR.
4. **source_type**: **`'selection_application'`** + `source_id=app.id`. Objeto stuck é a candidatura (bucket A nem tem entrevista). Sem colisão com overdue (`selection_interview`).
