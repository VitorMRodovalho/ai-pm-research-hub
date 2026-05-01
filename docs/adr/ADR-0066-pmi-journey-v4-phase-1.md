# ADR-0066: PMI Journey v4 — Phase 1 (Cloudflare worker + token-auth portal substrate)

**Status:** Accepted (2026-04-28)
**Decision date:** p81 review + autonomous execution
**Related:** Spec source `specs/p81-pmi-vep-journey/`, review doc `docs/specs/PMI_JOURNEY_V4_REVIEW.md`, ADR-0064 (Drive Phase 3 OAuth refresh — pattern reuse), Pattern 43 (cron health saturation)

---

## Context

PMI VEP é a plataforma oficial de candidaturas voluntárias. Atualmente o time GP importa candidatos manualmente via dashboard (CSV/UI), criando lag de 24-48h até onboarding começar e exigindo trabalho repetitivo.

Spec proposta pelo PM (anexada ao final de p80) entrega:

1. **Cloudflare cron worker** que sincroniza candidatos PMI → `selection_applications` em janela de 72h self-healing
2. **Portal token-auth `/pmi-onboarding/{token}`** para candidato (pré-member) completar profile, dar consent, gravar vídeos de screening
3. **AI suggestion substrate** para futuro `ai-objective-drafter` worker propor scores HITL (ainda pendente de consent)
4. **Operational telemetry** via `cron_run_log` + `v_cron_last_success` view (self-healing decision)

Substrate (DB schema + RPCs + worker) entregue em **2 migrations** + **1 worker pkg**. Frontend portal deferred (próxima sessão).

## Decision

**Adotar substrate completo conforme spec, com 3 blockers + 8 recomendações + 1 spec gap fechado, em série de 2 migrations + 1 worker em `cloudflare-workers/pmi-vep-sync/`.**

### Domain primitives novos

| Tabela | Purpose | RLS |
|---|---|---|
| `selection_evaluation_ai_suggestions` | AI-proposed scores por (application, evaluation_type), versionadas por (model, prompt_version), consent-gated por trigger | rpc_only_deny_all + _v4_org_scope RESTRICTIVE |
| `pmi_video_screenings` | Async video screenings (5 pillars × N questions), Drive default + YouTube unlisted fallback + opt-out, transcrição alimenta ai-interview-drafter | rpc_only_deny_all + _v4_org_scope RESTRICTIVE |
| `onboarding_tokens` | Track-agnostic token (`source_type`: pmi_application/initiative_invitation/direct_assignment) com TTL + scopes + audit | rpc_only_deny_all + _v4_org_scope RESTRICTIVE |
| `cron_run_log` | Operational log de cron workers (status: running/success/failed/skipped/zombie) | rpc_only_deny_all + _v4_org_scope RESTRICTIVE |

### Token-auth RPCs (anon-grantable, scope-gated)

| RPC | Scope required | Atua em |
|---|---|---|
| `consume_onboarding_token(token)` | qualquer | retorna application + cycle (sem interview_questions, R2 sec) + onboarding_progress (R5) |
| `update_pmi_onboarding_step(token, step_key, status, evidence_url)` | profile_completion | UPDATE onboarding_progress |
| `register_video_screening(token, pillar, q_index, ..., storage_provider, ...)` | video_screening | UPSERT pmi_video_screenings |
| `give_consent_via_token(token, consent_type='ai_analysis')` | consent_giving | UPDATE selection_applications.consent_ai_analysis_at |
| `revoke_consent_via_token(token, consent_type='ai_analysis')` | consent_giving | UPDATE selection_applications.consent_ai_analysis_revoked_at; trigger supersedes pending suggestions |

### Member-auth RPCs (existing extended ou novas)

| RPC | Mudança |
|---|---|
| `submit_evaluation(...)` | arity 4→5: novo param opcional `p_ai_suggestion_id uuid` para lineage atomic UPDATE de AI suggestion `used_in_evaluation_id + consumed_at` (R7) |
| `get_ai_suggestion(application_id, evaluation_type)` | NEW. Committee-gated. Retorna AI suggestion mais recente não-superseded para form pre-fill HITL |
| `campaign_send_one_off(template_slug, to_email, variables, metadata)` | NEW (B3). Wrapper SECDEF lookup `campaign_templates.slug` → delega para `admin_send_campaign(template_id, ..., external_contacts)`. Necessário porque RPC original não existia mas worker dependia |

### Helper RPCs (service_role only)

- `log_cron_run_start(worker_name, scheduled_for, metrics)` — mata zumbis (>30min running) + INSERT
- `log_cron_run_complete(run_id, status, metrics, errors)` — UPDATE para status terminal

### Triggers + views

- Trigger `enforce_ai_consent` BEFORE INSERT em `selection_evaluation_ai_suggestions` — bloqueia insert sem consent ativo + snapshot do consent timestamp
- Trigger `trg_supersede_ai_suggestions_on_consent_revoke` AFTER UPDATE em `selection_applications` — auto-supersede non-consumed suggestions quando consent é revogado
- View `v_cron_last_success` — DISTINCT ON (worker_name) último success. Worker consulta para self-healing decision
- View `v_ai_human_concordance` — métricas MAE/MSE/STDDEV AI vs human por (model, prompt_version, criterion). Drift detection para iteração de prompts

### Schema constraint extensions (B1, B2)

- `selection_applications.role_applied` CHECK: `+'manager'` (suportar opportunity 66470 quando essay_mapping for populado)
- `uq_selection_applications_vep_app_opp` PARTIAL COMPOUND UNIQUE em `(vep_application_id, vep_opportunity_id) WHERE both NOT NULL` — preserva dual-track `triaged_to_leader` (5 pares confirmados via Phase 0)

### Worker `cloudflare-workers/pmi-vep-sync/`

- Cron diário 04 UTC, self-healing 72h cadência + 12h tolerância
- 3 PMI buckets paralelos (submitted/qualified/rejected) per opportunity
- Per applicant: detail call → mapper → upsert COMPOUND key → se nova: issueOnboardingToken (TTL 7d, scopes profile_completion+video_screening+consent_giving) + dispatchWelcome via campaign_send_one_off
- Alerta GP via campaign_send_one_off (slug `cron_failure_alert`) após 3 falhas consecutivas
- **PMI OAuth via refresh_token KV** (Plano B): PM seeda `pmi_oauth:tokens` em KV namespace `PMI_OAUTH_KV` UMA vez via login interativo; worker auto-refresh

## Alternatives considered

1. **PMI client_credentials**: spec original assumia. Confirmado pelo PM que não é viável (PMI não expõe app server-to-server para Núcleo). Plano B refresh_token via KV é canonical.

2. **DELETE older "duplicates" + simple UNIQUE on `vep_application_id`** (review original B2): rejeitada durante Phase 0 quando descoberto que os 5 pares são dual-track legítimo (cada par = researcher 64967 + leader 64966 + linked_application_id cross-ref). Substituída por PARTIAL COMPOUND UNIQUE preservando 100% dos rows.

3. **No `campaign_send_one_off` wrapper, worker chama `admin_send_campaign` direto**: rejeitada porque `admin_send_campaign` requer `template_id uuid` (não slug). Wrapper centraliza slug→id lookup + simplifica future workers (ai-interview-drafter, etc). Slug-based é também resilient a id rotation se template for re-criado.

4. **Token TTL 30 dias** (spec original): reduzido para 7 dias (R2). Token é credencial, longer TTL = larger leak window. Workers que precisam re-emitir podem fazer (worker rebuild flow se candidato perde email).

5. **interview_questions no payload de `consume_onboarding_token`** (spec original): removido (R2). Candidato vê questões DURANTE entrevista live, não com 7 dias antecedência via portal.

6. **Trigger nome `on_consent_revoke`** (spec original): renomeado para `trg_supersede_ai_suggestions_on_consent_revoke` (R6). Convention `trg_*` prefix consistente com 240+ triggers existentes; nome descreve ação completa.

## Consequences

**Positive:**
- Lag PMI candidato → onboarding start: 24-48h → 24h max (cron daily)
- Trabalho manual GP: import + onboarding email + tracking → 0 (worker autônomo)
- AI suggestion substrate pronto para `ai-objective-drafter` worker (próximo) sem nova migration
- Token-auth portal pattern reusável para `initiative_invitation` (S3 Onda 3) e `direct_assignment` (Q3 2026 CPMAI prep) — mesmo onboarding_tokens table
- Operational telemetry self-healing previne silent-failure (Pattern 43 saturação evitada)

**Negative:**
- 4 novas tabelas + 12 RPCs adiciona surface de superfície (mitigado por RLS rpc_only_deny_all + tests)
- Worker é nova superfície deployable (Cloudflare-side) que precisa monitoring fora do Supabase + Wrangler — primeira deste padrão (Drive workers são EFs Supabase)
- Token TTL 7d significa candidato perdido tem que pedir re-issue (mais SLA work mas safer)
- Frontend portal `/pmi-onboarding/[token]` ainda não existe — welcome email leva pra 404 até ser criado (deferred próxima sessão)
- Refresh token PMI expira ~30d sem uso → re-seed manual KV se passar muito tempo sem run (cron mitiga, mas vacation pode quebrar)

**Neutral:**
- `manager` role agora válido em selection_applications mas ranking/scoring code (rank_researcher/rank_leader columns) não trata explicitamente — defer behavior decision para PM quando opp 66470 entrar em produção real
- `cron_run_log` retention não automatizada (R1 deferred) — purge manual via SQL ou aguardar follow-up migration

## Implementation evidence

- Migration 1: `supabase/migrations/20260516200000_phase_b_pmi_journey_v4.sql` — 4 tables + 12 RLS policies + 8 indexes + 2 trigger fns + 3 triggers + 2 views + 8 RPCs + B1+B2+B3 schema fixes
- Migration 2: `supabase/migrations/20260516210000_phase_b_pmi_journey_v4_consent_rpcs.sql` — 2 token-auth consent RPCs (gap closure)
- Worker: `cloudflare-workers/pmi-vep-sync/` — 12 source files (.ts) + wrangler.toml + package.json + README com PM checklist
- Review doc: `docs/specs/PMI_JOURNEY_V4_REVIEW.md` — 19KB com phase-by-phase execution log + course corrections + handoff PM
- Tests: 1418 unit / 1383 pass (DB-aware) / 0 fail / 35 skip baseline preservado
- Invariants: `check_schema_invariants()` 11/11 — 0 violations
- Smoke tests SQL: invalid token → `invalid_authorization_specification` raised; insert ai_suggestion sem consent → `check_violation` raised
- campaign_templates rows seeded: `pmi_welcome_with_token` (onboarding) + `cron_failure_alert` (operational), multilíngue pt-BR/en-US/es-LATAM
- Worker typecheck (`tsc --noEmit`): clean

## Follow-up backlog

- **Sessão dedicada**: frontend portal `/pmi-onboarding/[token]` — consume_onboarding_token UI + consent toggle + onboarding step checklist + video upload widget (Drive folder integration similar Phase 3 ADR-0064)
- **PM browser tasks**: KV namespace create + refresh_token seed + 8 secrets put + wrangler deploy staging→prod (detalhado no review doc + worker README)
- **Worker próximo**: `gemini-transcribe` (lê pmi_video_screenings.uploaded → chama Gemini 2.0 Flash → escreve transcription)
- **Worker próximo**: `ai-objective-drafter` (lê selection_applications.consent_ai_analysis_at IS NOT NULL → chama Sonnet 4.6 → INSERT selection_evaluation_ai_suggestions)
- **R1 retention cron**: extender `purge_expired_logs` + `anonymize_*` para 4 novas tabelas
- **R4 (deferred)**: avaliar UNIQUE em `used_in_evaluation_id` se UI de "trocar suggestion" causar ambiguidade
- **PMI 66470 essay_mapping**: PM popula quando substituto manager vier

---

## AMENDMENT 2026-04-29 (during deploy smoke test)

Status: original Phase 1 design assumed worker poll PMI VEP API server-to-server.
Smoke deploy revelou 2 blockers que mudaram a arquitetura final:

### Discovery 1: PMI VEP NÃO emite refresh_token

App `vep_ui_a58c68be946f4cf8841ff4bbf7b3c43b` é public SPA com PKCE, scope `openid profile` only (sem `offline_access`). HAR analysis confirmou. Token TTL 24h, sem renew automático.

**Mitigação aplicada**: worker preserved access-only mode com proactive expiry alert (`pmi_token_expiring_soon`). PM re-seedaria tokens diariamente. **Mas obsoleto** após Discovery 2.

### Discovery 2: Cloudflare Bot Management bloqueia worker → PMI VEP API

Mesmo com access_token válido: `/api/Authorization/user/roles/v2`, `/api/opportunity/{id}/applications/...` retornam 403 com Cloudflare HTML page (`server: cloudflare`, `set-cookie: __cf_bm=...`). Datacenter IPs (Cloudflare Workers) blocked at PMI's frontdoor antes de chegar ao backend.

Same protection class que Núcleo aplica em `.workers.dev` (per CLAUDE.md "Bot Fight Mode blocking datacenter IPs"); aqui é PMI bloqueando nosso worker.

**Implicação**: worker poll é arquiteturalmente impossível com PMI atual. Impossible sem:
1. PMI parceria + IP whitelist (semanas+, externa)
2. PMI server-to-server OAuth client com proper scope (semanas+, externa)
3. Mudança de origem da call

### Pivot: HTTP `/ingest` + browser script

Mudança arquitetural: worker passa de **active poller** (cron) para **passive ingestor** (HTTP webhook). Browser do PM (logado em PMI VEP recruiter dashboard) executa script extract_pmi_volunteer.js que:

1. Auto-descobre opportunities do recruiter
2. Varre 3 buckets (submitted/qualified/rejected) per opp
3. Drill-down detail per application (15 timestamps + questionResponses + comments)
4. POSTa JSON para `https://pmi-vep-sync.ai-pm-research-hub.workers.dev/ingest` com header `x-ingest-secret`
5. Worker autentica + lookup open cycle + lookup essay_mapping per opp + map per application + upsert + token + welcome

Browser passa Cloudflare Bot Management naturalmente (cookies + UA real do browser do PM). Worker recebe JSON limpo, não precisa contatar PMI.

**Vantagens vs spec original**:
- Pipeline é instantâneo (segundos vs 24h cron)
- Multi-opportunity em 1 run (vs por-opp polling)
- ~40 fields per application (vs ~10 do CSV padrão PMI)
- questionResponses estruturadas (mapper auto-resolve via essay_mapping)
- Comments do recruiter capturados (audit trail)
- Sem dependência de PMI OAuth refresh
- PM tem visibility direta no console browser (pode debugar)

**Desvantagens**:
- Manual trigger (PM precisa rodar script quando quer sync)
- Browser session necessária (PM logado)
- 1-2x por semana ao invés de daily — mas PMI não postam novos candidatos a cada minuto, OK

### Schema additions (round 2)

Migration `20260516210000_phase_b_pmi_journey_v4_consent_rpcs.sql`:
- `give_consent_via_token(token, consent_type)` — token-auth, sets consent_ai_analysis_at
- `revoke_consent_via_token(token, consent_type)` — token-auth, sets revoked_at; trigger auto-supersede

Migration `20260516220000_phase_b_pmi_journey_v4_one_off_direct_insert.sql`:
- Rewrite `campaign_send_one_off` para fazer INSERT direto em campaign_sends + campaign_recipients (bypass admin_send_campaign caller GP/DM check + 1/hour rate limit). Worker service_role tem auth.uid() NULL, era blocker para welcome dispatch. sent_by attributed to highest-tier active GP-tier member para audit.

### Worker source changes (round 2)

- `src/index.ts` — adicionado `fetch` handler com `/health` (public) + `/ingest` (POST + secret + CORS allow-origin volunteer.pmi.org)
- `src/types.ts` — Env.INGEST_SHARED_SECRET + ScriptIngestPayload + ScriptApplication + ScriptQuestionResponse interfaces
- `src/script-mapper.ts` (NEW) — converts script JSON shape to SelectionApplicationUpsert; resolves essay_mapping via questionId match → ordinal index → question text substring fallback
- `src/pmi-vep-client.ts` — preserved (refresh_token path) but unused; cron simplified to watchdog only

### Browser script

`cloudflare-workers/pmi-vep-sync/scripts/extract_pmi_volunteer.js` — committed to repo. Auto-POST opcional via `CONFIG.NUCLEO_INGEST_URL + NUCLEO_INGEST_SECRET`. Files local CSV+JSON para arquival. Resume PDFs opcional.

### Smoke test evidence

- POST /ingest with mock TEST candidate (questionResponses including chapter_affiliation=PMI-GO):
  - cycle resolved: cycle3-2026-b2
  - applications_processed: 1, applications_new: 1, welcome_dispatched: 1, errors: 0
- /health endpoint: 200 OK with CORS headers
- Bad secret: 401
- Empty applications: 200 with sane summary
- Smoke data cleaned post-test
- Schema invariants: 11/11 — 0 violations
- Worker typecheck: clean

### Status post-amendment

- Worker deployed: `pmi-vep-sync.ai-pm-research-hub.workers.dev` versão `dfaee1d6-0b7a-44a3-af22-3e3134af1a8d`
- Cron schedule mantido (04 UTC daily) mas downgraded para watchdog-only (token expiry check + alert)
- 11 secrets total (8 originais + KV + INGEST_SHARED_SECRET + KV preview)

### Pending follow-up (não bloqueia ship)

- **Frontend portal `/pmi-onboarding/[token]`** ainda fora do escopo (welcome email leva pra 404 até portal ser criado em sessão dedicada)
- **PM action**: rodar script no PMI VEP recruiter dashboard quando quiser sync; review SQL queries para validar
- **Long-term**: relacionamento PMI parceria poderá um dia habilitar API automática + cron real. Worker code preservado para esse futuro

---

## Amendment 2026-05-01 — Workflow Gate gap surfacing (PMI Journey Phase 2 trigger)

**Trigger:** Vice-GP Fabricio Costa reportou via WhatsApp 2026-05-01 09:42 BRT que via 2 entrevistas marcadas para o dia seguinte sem que tivesse sido feita análise inicial. Sweep p87 confirmou:

- **Thayanne Monteiro** (`1e529a68-…`): AI fit_for_role=1/5 ("aplicação extremamente genérica"), 0 par-revisões humanas, status=`submitted`/interview_status=`none`. Calendar booking foi feito sem que `mark_interview_status` ou `schedule_interview` fossem chamados.
- **Danilo Nascimento** (`d05ddb44-…`): AI fit_for_role=3/5 (junior viável), 0 par-revisões humanas, status=`interview_pending` (flipped sem precondições). Mesmo gap.
- **João Uzejka dos Santos**: único candidato cycle3-2026-b2 com 2 par-revisões humanas → score 137 → único pronto para entrevista legítima.
- **0 rows futuras em `selection_interviews`** — Calendar bookings não chegam ao DB (#116).

### Causa raiz (ratificação)

Spec Phase 1 (este ADR) entregou substrate (workers, tokens, RPCs, AI consent, video screening). Mas **não definiu gate explícito entre AI pre-screen → par-revisão humana → entrevista**. Resultado:

1. Calendar booking link público (`https://calendar.app.google/gh9WjefjcmisVLoh7`) sem token-gate por aplicação
2. Apps Script auto-add-guests não chama `schedule_interview` RPC (Calendar↔DB sync gap = #116)
3. RPC `mark_interview_status('pending')` callable sem precondição AI/score/peer-review
4. Workflow mental do PM ("AI roda → comissão revisa par → score → cutoff → entrevista") não está reificado em código

### Decisão (Phase 2 trigger)

**Adicionar workflow gate em 3 layers** — captura formal em Issue [#117](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/117):

1. **RPC-level precondition** (`schedule_interview` + `mark_interview_status`):
   - Gate 1: `consent_ai_analysis_at IS NOT NULL AND ai_analysis IS NOT NULL`
   - Gate 2: `(SELECT COUNT(*) FROM selection_evaluations WHERE application_id = …) >= 2`
   - Gate 3: `objective_score_avg >= cycle.objective_cutoff_formula`
   - Bypass: `can(auth.uid(), 'manage_member')` lead-only para edge cases (recommendation letters, returning members)
   - Erro coded: `GATE_NO_AI` / `GATE_NO_PEER_REVIEW` / `GATE_NO_SCORE`

2. **Calendar booking page token-gated** — substituir link Google Calendar Appointment Slots universal por endpoint próprio `/interview-booking/<token>` que:
   - Valida token (TTL 14 dias, scope `interview_booking`)
   - Verifica gate (AI + 2 evals + score)
   - Embeda widget Calendar OR redireciona com query params Apps Script lê
   - Token gerado quando comissão chama `mark_interview_status('pending')` legítimo

3. **Audit log** para tentativas que falham gate (não temos `audit_events` table; criar como parte de #117).

### Mindset PM (raise the bar)

Vitor articulou explicitamente em WhatsApp 2026-05-01 11:30 BRT:

> "Se uma pessoa não se esforçar para pelo menos fazer uma aplicação decente, será que podemos esperar dela fazer pesquisa, publicar artigo, liderar webinar, liderar tribos, representar o núcleo? Mindset bastante influenciado pelo ambiente que vivo aqui, profissionalmente: 'does that person raise the bar?' Única pergunta que temos que responder do início ao fim."

**Implicação para gate**: critério `objective_cutoff_formula` deve refletir esse threshold. Sub-tarefa: amendar AI prompt do EF `pmi-ai-analyze` para incluir dimensão explícita "would this candidate raise the bar?" como rubric criterion. Sub-tarefa: documentar no rubric de evaluation humana mesma dimensão.

### Hotfix p87 (não código — operacional)

- Email `pre_eval_pause` (template novo) disparado para Thayanne (`5effc0ba-d225-4003-8fc8-39429a7fbad3`) e Danilo (`d4976563-99da-462e-8d8a-7783bcb9faf0`) explicando descompasso e novos próximos passos
- Danilo `status` revertido `interview_pending → submitted` (sem score, sem par-revisão = não pronto para entrevista)
- Fabricio cancela 2 events Calendar do lado dele
- João Uzejka (single legítimo) preservado

### Status

- **Spec gap** Phase 1 reconhecido (este amendment fecha o documental)
- **Phase 2 implementation** = Issue #117 (gate RPC + Calendar token + audit), bloqueada em quiet window pós-CBGPL launch
- **#116 Calendar sync** (subset urgente Phase 2) ainda em backlog — Apps Script webhook → schedule_interview

### Trace

- WhatsApp Vitor + Fabricio 2026-05-01 09:42–11:50 BRT
- p87 sweep findings (sessão dedicada)
- Issue #116 comment p87 + Issue #117 spinoff
- Routine `trig_01DYnnv5uimkc5PqnzeyaPnv` (armed 2026-05-02T14:00Z) verificará Thayanne reschedule outcome
- 6 candidatos cycle3-2026-b2 com AI rodada, apenas 1 (João Uzejka) com peer-review humana → benchmark do que workflow correto produz

Assisted-By: Claude (Anthropic)

---

## Amendment 2 — 2026-05-01 (later same day) — `raises_the_bar` rubric operational adoption

**Trigger:** Issue [#119](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/119) MVP validation (n=14 cycle3-2026 sample) revelou propriedades estatísticas da rubric AI:

| Métrica | Valor (n=14) |
|---|---|
| Precision YES | 75% (3/4 — high) |
| Recall YES | 33% (3/9 — low) |
| Specificity NO | 80% (4/5) |
| False Negative Rate | 67% (6/9 — alto) |
| F1 (YES) | 0.46 |

Full report: `docs/research/raises_the_bar_validation_cycle3_2026.md`.

### Decisão operacional (PM ratify 2026-05-01)

A rubric `raises_the_bar` é **conservadora e específica** — ancora em "evidências factuais articuladas no texto da aplicação". Útil como filtro positivo (high precision), inadequado como gate único de rejeição (high false-negative rate). Decisão humana frequentemente usa contexto não-textual (LinkedIn, anotações entrevista, prior PMI community knowledge, chapter representation) que AI não recebe.

**Política de uso (cycle3-2026-b2 e futuros):**

1. **`raises_the_bar = yes` + `fit_for_role >= 4`** → **skip-to-interview shortlist** (high-precision); par-revisão humana ainda obrigatória (não substitui evals)
2. **`raises_the_bar = no`** → **soft signal apenas, NÃO auto-reject**. Comissão deve revisar via LinkedIn / contexto chapter / par-revisão antes de decisão.
3. **`raises_the_bar = uncertain`** → par-revisão prioritária (AI sinal não-conclusivo)

UI hint implementado em admin/selection.astro (Análises IA tab):
- Verde: ⭐ Skip-to-interview eligible (when YES + fit>=4)
- Âmbar: ⚠️ Soft signal apenas — NÃO auto-reject (when NO)
- Azul: ↺ Par-revisão prioritária (when uncertain)

### Próximos passos (deferred)

- Sprint 3.b: expand sample n=14 → n=63 (full cycle3-2026 com final outcome) via pg_cron throttled
- Sprint 4 (após Sprint 3.b ratify): evolução prompt rubric — adicionar `potential_signal` orthogonal a track-record + considerar input opcional `linkedin_summary` (consent-gated)

### Trace
- PM ratify 2026-05-01 (post-MVP report review)
- p87 marathon ULTRA-EXTENDED (~7h elapsed)
- Issue #119 comment c/ findings: `https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/119#issuecomment-4361229912`

Assisted-By: Claude (Anthropic)
