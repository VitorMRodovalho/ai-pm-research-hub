# p91 — Auditoria da Jornada de Seleção (PMI VEP → Onboarding → Entrevista)

**Data:** 2026-05-05
**Origem:** Investigação iniciada por relato do candidato William Junio ("link não funciona") em thread Gmail 19ddab9069399422 / 19dda8b1571f790a.
**Status:** Bugs catalogados, recovery imediato executado, fix structural diferido para sessão p92 dedicada (decisão PM).

---

## 1. Bugs estruturais identificados

### Bug #1 — Rendering de templates (FIXED em produção)

**Onde:** `supabase/migrations/20260516220000_phase_b_pmi_journey_v4_one_off_direct_insert.sql` rewriteu `campaign_send_one_off` e dropou `'variables', p_variables` do JSONB `audience_filter`. Migração `20260516230000` (slot seguinte) restaurou. Live RPC em produção HOJE = OK.

**Impacto:** 8 emails do batch 04-29 12:16 saíram com `{{first_name}}`, `{{onboarding_url}}` etc. literais (renderizados não-substituídos). Botão "Continuar onboarding" tinha `href="{{onboarding_url}}"` — nada acontecia ao clicar.

**Detecção:** Reply do William em thread Gmail quotando o body do welcome com placeholders intactos.

---

### Bug #2 — Worker não filtra por VEP `_bucket` (AINDA EM PROD)

**Onde:** `cloudflare-workers/pmi-vep-sync/src/db.ts:121-194` (`upsertSelectionApplication`) faz lookup compound (vep_application_id, vep_opportunity_id). Se ausente → `was_new=true` → `index.ts:268` chama `dispatchWelcome` SEM nenhum check de `_bucket`/`statusId` de VEP.

**Browser script:** `cloudflare-workers/pmi-vep-sync/scripts/extract_pmi_volunteer.js` linha 7 declara: *"varre as 3 abas (submitted/qualified/rejected)"*. Manda TUDO.

**Impacto:** 4 welcomes inválidos no batch 04-29:
| Email | Nome | VEP `_bucket` | VEP `statusId` |
|---|---|---|---|
| anagatcavalcante@gmail.com | Ana Carla Cavalcante | qualified | 5 (Active) — já líder PMI-CE |
| hayala.curto@gmail.com | Hayala Curto | qualified | 5 — já líder PMI-MG |
| maklemz@gmail.com | Marcos Klemz | qualified | 5 — já líder PMI-MG |
| adalbertoneris@gmail.com | Adalberto Neris | rejected | 4 (OfferNotExtended) — declined 2025-12-23 |

**Recovery:** Tokens anulados em 2026-05-05 05:35 UTC. PM avisou no grupo de liderança. Adalberto recebe apenas anulação + audit log.

**Fix proposto (sessão p92):**
- Opção 3 defesa em profundidade: browser script ainda manda tudo (capturar dados), worker SÓ dispatcha welcome se `_bucket = 'submitted'` AND `statusId = 2`.
- Adicionar guard antes do `dispatchWelcome` em `index.ts:268`.

---

### Bug #3 — Bulk import via SQL não dispara welcome (AINDA EM PROD)

**Onde:** Worker SÓ dispatcha welcome quando `was_new=true` no upsert via worker. Linhas inseridas via bulk SQL (CSV import inicial, /admin/selection import) bypassam o worker → never trigger welcome.

**Magnitude:**
- 19 candidatos com `status='submitted'` no plataforma + `_bucket='submitted'` no PMI VEP
- Inseridos via bulk em 2026-04-01 (8 candidatos), 2026-04-15 (10 candidatos), 2026-04-21 (1 candidato — Jessé Filipe)
- **Mais antigo aguarda há 62 dias** (João Uzejka — VEP 2026-03-04, mas ele tem token consumed via emissão manual durante criação da jornada por PM/Claude)
- Outros 18 não receberam NENHUMA notificação

| # | Email | Nome | VEP submitted em | Chapter |
|---|---|---|---|---|
| 1 | edinansoares@yahoo.com.br | Edinan Soares | 2026-03-24 | PMI-MG |
| 2 | alexandre.fortes@gmail.com | Alexandre Fortes | 2026-03-24 | PMI-MG |
| 3 | blendatec@gmail.com | Blenda Amorim | 2026-03-24 | "MG e DF" |
| 4 | hectorrigon@gmail.com | Hector Rigon | 2026-03-24 | (não filiado) |
| 5 | carla.copasa@gmail.com | Carla Rosa | 2026-03-24 | PMI-MG |
| 6 | cosf.cristiano@gmail.com | Cristiano Filho | 2026-03-26 | PMI-DF |
| 7 | andrefga@hotmail.com | Andre Abreu | 2026-03-28 | PMI-PE |
| 8 | eduardoluz.pm@gmail.com | Eduardo Luz | 2026-04-07 | PMI-RS (já voluntário ativo) |
| 9 | bruna.soares@bsconsultoriaempresarial.com.br | Bruna Soares | 2026-04-10 | PMI-MG |
| 10 | marcio.pimenta@gmail.com | Marcio Pimenta | 2026-04-11 | PMI-RJ |
| 11 | quintanaluise75@gmail.com | Luíse Quintana | 2026-04-13 | PMI-RS |
| 12 | zomer.bruna@gmail.com | Bruna Lima Zomer | 2026-04-13 | PMI-RS |
| 13 | matheusnovellino@hotmail.com | Matheus Teixeira | 2026-04-13 | PMI-RIO |
| 14 | tielealineceron@gmail.com | Tiele Lara | 2026-04-13 | (não filiado) |
| 15 | claudio.bms@hotmail.com | Claudio Sousa | 2026-04-14 | PMI-MG |
| 16 | cristianonunes9104@gmail.com | CRISTIANO NUNES | 2026-04-14 | PMI-MG |
| 17 | rfbellotti@gmail.com | Rafael Bellotti | 2026-04-15 | PMI-RS |
| 18 | jessefilipe@gmail.com | Jessé Filipe | 2026-04-17 | PMI-RS |

**Decisão PM 2026-05-05:** "antes temos que resolver os erros da jornada e ai sim fazermos o disparo a estes pendentes". Dispatch 18 BLOQUEADO até bugs A-D corrigidos.

**Fix proposto (sessão p92):**
- Reissue + dispatch welcome via campaign_send_one_off batch script após fixes
- OU: trigger one-shot RPC `dispatch_pending_welcomes()` que escaneia selection_applications.status='submitted' sem onboarding_token e re-issue

---

### Bug #4 — Apps Script Calendar webhook nunca foi configurado

**Onde:** Endpoint `/api/calendar-webhook` em `src/pages/api/calendar-webhook.ts` está LIVE em produção (responde HTTP 500 sem auth válida — confirma que está acessível).

**Mas:** `docs/specs/p87-calendar-webhook-apps-script.md` declara *"Status: Endpoint LIVE p87. **Apps Script setup pending PM action.**"*

**Impacto:** Quando candidato (após welcome → onboarding → consent → vídeo → AI → peer review) recebe link de booking no Calendar, ele agenda. Mas o trigger do Apps Script no `nucleoia@pmigo.org.br` Calendar NUNCA foi criado. Bookings não sincronizam para `selection_interviews` table. Workflow para no momento do agendamento.

**Estado evidência:**
- 0 interviews scheduled no plataforma para batch p82+ (post-29/abr)
- 0 gate_attempts logged (P0001-P0003 nunca disparou)

**Fix proposto (sessão p92):**
- PM action: criar Apps Script project bound to nucleoia@pmigo.org.br conforme spec p87
- Configurar trigger "onCalendarEventCreated"
- Smoke test com booking real

---

### Bug #5 — Workflow de peer review não tem trigger / assignment

**Onde:** Não existe automação que invite/assign peers para avaliar candidatos.

**Estado atual:**
- 7 candidatos com AI analysis complete (Danilo, THAYANNE, Maria, João Coelho, Luciana, LUIZ, João Uzejka)
- 0 peer evaluations registradas pra esses 7
- Peers (membros do selection_committee?) não recebem notification quando AI completa
- Recrutadores precisam manualmente abrir /admin/selection e clicar "avaliar" um a um

**Gate de schedule_interview** (migration 20260516380000) bloqueia P0002 GATE_NO_PEER_REVIEW se < 2 peer evals. Bloqueio funciona. Mas upstream nunca dispara o convite.

**Fix proposto (sessão p92):**
- Trigger pós-`compute_application_scores` ou pós-AI-analysis-complete que:
  1. Identifica peer reviewers ativos (`selection_committee` role IN ('peer_reviewer','interviewer'))
  2. Cria notifications + envia email batch (template `peer_review_request`)
  3. Marca application status → `peer_review_pending` para visibility
- Ou alternativa: round-robin assignment sob demanda

---

### Bug #6 — Re-agendamento não tem feedback loop completo

**Onde:** RPC `request_interview_reschedule` (migration 20260516320000) existe e:
- Marca `selection_applications.interview_status = 'needs_reschedule'`
- Envia email `interview_reschedule_request` ao candidato com booking_url

**Gap:** Não há rastreamento de:
- Se candidato re-booked (depende de Bug #4 fix — Apps Script sync)
- Se candidato ignorou (precisa nudge cron?)
- Se interviewer/PM concordou com nova data

**Fix proposto (sessão p92):**
- Após Apps Script fix (Bug #4), webhook idempotente atualiza interview record
- Adicionar dashboard widget /admin/selection com lista de "reschedules pendentes"
- Cron diário: nudge candidato 3 dias após reschedule sem nova booking

---

### Bug #7 — /admin/selection lista lacks indicators agregados

**Onde:** RPC `get_selection_dashboard` retorna por candidato apenas:
- scores (objective, final, research, leader, ranks)
- status (high-level)
- interview_status (apenas `needs_reschedule`)
- onboarding_pct (apenas para approved/converted)
- credly_url + photo_url (matched member)

**Missing per PM 2026-05-05:**
- AI já pre-avaliou? (boolean derivado de `consent_ai_analysis_at IS NOT NULL AND ai_analysis IS NOT NULL`)
- Quantos peers já avaliaram? (count from `selection_evaluations`)
- Tem entrevista marcada? (boolean derivado de `selection_interviews` row scheduled/done)
- Token consumed? (já entrou no portal?)
- Vídeo screening enviado?

**Fix proposto (sessão p92):**
- Estender `get_selection_dashboard` com 5 colunas booleanas/numéricas
- UI columns adicionais com badges color-coded (verde se done, cinza se pending)
- Filtros adicionais: "AI complete", "≥1 peer eval", "≥2 peer evals", "interview scheduled"

---

## 2. Recovery imediato executado (2026-05-05 ~05:35-05:47 UTC)

| Ação | Detalhes |
|---|---|
| Anular 4 tokens inválidos | UPDATE expires_at=now() para Hayala/Ana Carla/Marcos/Adalberto. Audit log entry cada |
| Welcome correto Herlon | extend token 14d + dispatch via campaign_send_one_off. Send `bf21ab32`, resend `c2111bc2`, delivered |
| Welcome correto Ana Pacheco | extend + dispatch. Send `cd93951c`, resend `ac7fa21e`, delivered |
| Welcome correto DJEIMIYS | extend + dispatch. Send `64c06a27`, resend `4778119f`, delivered |
| Gmail draft William | Reply ao thread `19ddab9069399422` com App 1 + App 2 links. Draft id `r-5580222886714244339` em `nucleoia@pmigo.org.br` Drafts. Tokens estendidos |
| Audit log | 7 entries em admin_audit_log: 4 annul, 1 Herlon, 1 William, 2 Ana Pacheco/DJEIMIYS |

## 3. Pendentes para próxima sessão (p92 dedicada)

Per PM decisão 2026-05-05:

1. **Worker filtering fix** — Bug #2 (Opção 3 defesa em profundidade)
2. **Apps Script Calendar setup** — Bug #4 (PM action) + smoke test E2E
3. **Peer review trigger workflow** — Bug #5 (RPC + notifications + email template)
4. **Admin /selection indicators** — Bug #7 (RPC extension + UI columns)
5. **Reschedule feedback loop** — Bug #6 (após #4 done)
6. **Bulk dispatch 18 welcomes pending** — Bug #3 (após #1, #2, #4, #5 done)
7. **Audit Ana Karina** — abriu welcome 04-30 16:15 mas nunca clicou (5+ dias). WhatsApp follow-up?
8. **Vitor envia Gmail draft William** (manual)
9. **Vitor confirma se a Ana Karina email está em spam** (verificar via gmail mcp se candidato respondeu reclamando)

## 4. Sediment patterns p91

1. **`audience_filter.variables` é load-bearing** — sem essa key no JSONB, send-campaign EF renderiza placeholders literalmente. Migration drift entre 220000 e 230000 mostra que mudanças nesta estrutura têm blast radius alto.

2. **Worker `was_new=true` é o único trigger de welcome** — bulk imports SQL bypassam. Toda mudança no fluxo de cadastro deve ter um trigger explícito independente de "primeira INSERT pelo worker".

3. **Browser script + worker é distributed system** — script roda no console do PM, worker recebe. Filtros precisam estar em **ambos** (defesa em profundidade) para resistir a regressões em qualquer lado.

4. **Setup steps "PM action" tendem a ficar pendentes** — Apps Script p87 ficou pendente 5+ dias. Próximas integrações com setup manual precisam de checklist explícito + lembrete recurrente.

5. **Schedule_interview gate sem upstream peer review trigger = workflow stall** — adding gates sem tornar workflow auto-progressivo cria backlog invisível. Cada novo gate precisa de um "happy path" automatizado para deixar candidatos progredirem.

6. **Listas admin precisam status agregados** — clicar 1 a 1 não escala >20 candidatos. Indicadores boolean + counts no row level são essenciais para PM operacional.
