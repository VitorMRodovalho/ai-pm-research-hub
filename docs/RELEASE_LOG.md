# Release Log

## 2026-03-08 — S-KNW2: Admin CRUD para hub_resources (Knowledge Hub)

### Escopo
CRUD admin para recursos curados (cursos, referências, webinars). Tabela `hub_resources` separada de `knowledge_assets` (sync/embeddings).

### Entregas
- Migration `20260308170000_hub_resources.sql` (asset_type, title, description, url, tribe_id, author_id, course_id, is_active)
- Nova aba Admin "📚 Recursos" com listagem, form, edição inline e toggle ativo/inativo
- i18n PT/EN/ES para admin.knowledge.*
- RLS: select público (ativo); select/insert/update (can_manage_knowledge); delete (superadmin)

### Próximos passos
- Rota `/workspace` pública para consulta de recursos (S-KNW2 expandido)
- Link artifacts ↔ hub_resources (S-KNW3)

---

## 2026-03-08 — S-KNW1: knowledge_assets table (backend runway)

### Escopo
Preparar schema para Wave 5 Knowledge Hub. Tabela `knowledge_assets` existe para sync/embeddings; `hub_resources` criada para CRUD manual.

### Entregas
- Migration `20260308150000_knowledge_assets.sql`, `20260308160000` (manager select), `20260308170000_hub_resources.sql`
- Docs pack: audit, rollback, runbook (knowledge_assets)

---

## 2026-03-08 — S-AN1: Announcements i18n

### Escopo
Migrar strings hardcoded da seção Avisos Globais (admin) para i18n PT/EN/ES.

### Entregas
- Form: título, tipo, mensagem, link URL/texto, expira em, placeholders, botão publicar
- Lista: empty state, status (Inativo/Expirado/Ativo), botões Desativar/Ativar
- Chaves `admin.announcements.*` em pt-BR, en-US, es-LATAM

### Pendente (S-AN1)
- **Rich editor opcional**: editor de texto rico para corpo do aviso (ex.: TipTap, Quill)
- **Scheduling UX**: interface para agendar início/fim de exibição dos avisos

---

## 2026-03-08 — S-REP1 VRMS i18n + QA/QC workflow

### S-REP1: VRMS export i18n
- Coluna "PMI ID" → `t('admin.reports.colPmiId', lang)`
- Contador "X voluntários · Yh" → `admin.reports.vrmsCountFormat` PT/EN/ES

### QA/QC
- `docs/QA_RELEASE_VALIDATION.md`: seção "Automação recomendada" — assistente executa `npm test && npm run build && npm run smoke:routes` após cada sprint
- `SPRINT_IMPLEMENTATION_PRACTICES.md`: checklist inclui validação automatizada obrigatória

---

## 2026-03-08 — S-PA1 + S11 polish (analytics i18n, loading strings)

### S-PA1: Analytics consent status i18n
- Bug: `/admin/analytics` exibia literais `{t('admin.analytics.consentGranted', lang)}` em vez de traduções
- Fix: `ANALYTICS_I18N` via `define:vars` + `window.__ANALYTICS_I18N`; `renderConsentStatus()` lê valores reais

### S11: Loading strings i18n
- TrailSection: "Carregando..." → `t('common.loading', lang)`
- profile: "Carregando perfil…" → `t('profile.loading', lang)`
- admin/member/[id]: "Carregando…" → `t('admin.loadingMembers', lang)`

---

## 2026-03-08 — Admin allocation 400 fix (admin_force_tribe_selection)

### Escopo
Corrigir erro 400 Bad Request ao alocar pesquisadores pendentes no pool (botão Alocar → escolher tribo → confirmar).

### Causa provável
`admin_get_tribe_allocations` retorna objetos com `id` (de members), mas o frontend usava `m.member_id` que podia ser undefined. Isso enviava a string "undefined" como `p_member_id`, causando 400 (UUID inválido).

### Correção
- `data-member-id`: usar `m.id ?? m.member_id ?? ''` para cobrir ambos os formatos de resposta
- `confirmAllocate`: validar memberId antes de chamar RPC; tratar `error` do Supabase; `parseInt(..., 10)` explícito

---

## 2026-03-08 — S11 polish + define:vars sustainability (Sprint increment)

### S11: Painel executivo i18n
- Painel Executive (observer tier): loading e empty states migrados para ADMIN_I18N
- Chaves: admin.exec.noCohortData, funnelNoData, funnelError, certError, radarError, noRadarData
- PT/EN/ES parity

### Sustentabilidade
- Regra 0 em `.cursorrules`: nunca combinar define:vars com import no mesmo script Astro
- Previne regressão "Cannot use import statement outside a module"

---

## 2026-03-08 — Admin page fix: define:vars + import (Critical)

### Escopo
Corrigir erro "Cannot use import statement outside a module" na página `/admin` que mantinha "Verificando acesso" indefinidamente.

### Causa raiz
Em Astro, `<script define:vars={{ ... }}>` aplica implicitamente `is:inline`, impedindo o bundler de processar imports. O script era enviado ao navegador com `import` em texto, gerando SyntaxError.

### Solução
- Separar em dois scripts: (1) `is:inline define:vars` que injeta em `window.__ADMIN_I18N`; (2) script normal com imports que lê de `window.__ADMIN_I18N`
- Aplicada a mesma correção em `/profile` e `/admin/member/[id]` (preventivo)

### Validação
- `npm run build` passou
- QA/QC: criar `docs/QA_RELEASE_VALIDATION.md` com checklist de console e cross-browser para releases futuros

### Aprendizado para QA/QC
- Toda release validar console F12 em rotas principais (evitar erros de script)
- Toda release validar usabilidade em Windows, Mac, iPhone, Android

---

## 2026-03-08 — S8b i18n closure (Done)

### S8b: Modal Edit Member + CSV headers
- Eixo 1/2/3 labels e descrições
- Oprole options (Gerente, Deputy, Líder, etc.)
- Designações (incl. Co-GP)
- Tier hint, Capítulo, Status
- CSV VRMS e Member: headers + Sim/Não nas células
- admin.desig.coGp adicionado

---

## 2026-03-08 — S8b i18n long-tail (Sprint increment)

### S8b: i18n admin loadMyTribe, exec panel, cycle-history prompts
- Admin My Tribe: noAllocation, settings/members/attendance titles, meeting slots, saved, researchers pending
- Admin exec panel: chapters/cert/tribes titles; labelActive, labelLeadership, labelResearchers, artifactsInReview, coursesCompleted
- editCycleRecord prompts: opRole, desigs, tribeName, notes — PT/EN/ES
- Cycle history cards: Papel, Designações
- Days of week: common.days.sun..sat
- TribesSection: partialContentWarning para viewWarnings

---

## 2026-03-08 — S-PA2-UI-BIND + S11 + S8b i18n (Sprint increment)

### S-PA2-UI-BIND: Painel executivo ligado aos RPCs
- **exec_funnel_summary**: Funil de qualificação (ativos, Credly, trilha completa, Tier 1/2+, artefatos publicados) com barras de progresso
- **exec_cert_timeline**: Timeline de certificação por coorte (12 meses) — barras por mês
- **exec_skills_radar**: Radar de competências Credly por eixo — barras por radar_axis
- Painel Executive (tier observer) agora consome RPCs; loading + fallback de erro por bloco
- escapeHtml adicionado para XSS nos labels dinâmicos

### S11: Empty states acionáveis em gamification
- setPanelMessage aceita CTA opcional (text, onclick)
- Leaderboard vazio: botão "Sincronizar Pontos + Credly" quando logado
- Meus Pontos vazio: mesmo CTA para disparar sync

### S8b: i18n cycle-history e profile (commit 9ae54a9)
- Admin: toasts ciclo adicionado/atualizado/removido; seção add ciclo; todos ciclos; ativo/inativo/atual
- Profile: email adicionado/removido; já cadastrado; erros; confirm de remoção

---

## 2026-03-08 — Production Release (EPIC #52, #51–55)

### Escopo
Deploy consolidado: Event Delegation completo, setup replicável, Credly mobile, smoke i18n, documentação.

### Entregas
- Event Delegation: attendance, admin (cycle/slot), profile, artifacts, admin/member (#51, #53)
- EPIC #52 SaaS Readiness + filhos: setup replicabilidade (#54), Credly mobile + smoke (#55)
- docs/REPLICATION_GUIDE.md, docs/RELEASE_PROCESS.md, docs/AGENT_BOARD_SYNC.md, docs/AI_DB_ACCESS_SETUP.md
- npm run db:types, .env.example expandido

### Validação
- npm test ✅ | npm run build ✅ | npm run smoke:routes ✅

### 2026-03-08 — Próximos passos acionáveis
- **#56** S-HF5: Executar Data Patch em produção (manual)
- **#57** S-COM6: Deploy sync-comms-metrics + secrets (manual)
- **#58** S10: Configurar Credly Auto Sync — GitHub secrets (manual)
- DEPLOY_CHECKLIST atualizado com links para as issues

### 2026-03-08 — S8b: ADMIN_I18N fix + i18n tier header
- **Bug fix**: ADMIN_I18N exibia literais `{t('key', lang)}` em vez de traduções
- Solução: valores reais via `t()` no frontmatter; passagem ao client via `define:vars`
- Tier header (leader/observer): `admin.tier.leaderTitlePrefix`, `tierLeaderSubtitle`, `tierMyTribe`, `tierExecTitle`, `tierExecSubtitle` em PT/EN/ES

---

## 2026-03-08 — Event Delegation: Attendance + Admin (cycle/slot handlers)

### Scope
Migrate remaining inline `onclick` handlers to Event Delegation (.cursorrules compliant, XSS hardening).

### Delivered
- **attendance.astro**:
  - `checkIn`, `openRoster`, `openEditEvent`, `togglePresence` → `data-*` + delegation
  - Added `escapeAttr()` for all dynamic attributes; `__attendanceEventsById` lookup for `openEditEvent`
- **admin/index.astro**:
  - `openEditMember` → `data-member-id` + lookup from `memberListCache` (removed `JSON.stringify(m)`)
  - `openCycleHistory` → `data-member-id`, `data-member-name`
  - `editCycleRecord`, `deleteCycleRecord`, `addCycleRecord` → `btn-edit-cycle-record`, `btn-delete-cycle-record`, `btn-add-cycle-record`
  - `deleteSlot`, `addSlot`, `saveTribeSettings` → `btn-delete-slot`, `btn-add-slot`, `btn-save-tribe`
  - Single `document` listener `__adminCycleSlotBound` for all handlers
- **README.md**: Updated "Immediate Engineering Priorities" item 3 with progress and remaining handlers
- **docs/RELEASE_PROCESS.md**: Processo de release para produção com changelog e sync com Project Board

### Validation
- `npm run build` passed

### 2026-03-08 (continuação) — Event Delegation closure (#53, EPIC #52)
- **profile.astro**: `removeSecondaryEmail` → `btn-remove-secondary-email` + `data-email-idx`
- **artifacts.astro**: `editArtifact`, `openReview` → `btn-edit-artifact`, `btn-review-artifact` + `__artifactsById` cache
- **admin/member/[id].astro**: `toggleRole`, `inactivateMember`, `reactivateMember` → delegation + `data-role`, `data-member-id`, `data-member-name`
- EPIC #52 (SaaS Readiness) criado; issue #53 concluída

### 2026-03-08 — Setup para replicabilidade (#54, EPIC #52)
- **docs/REPLICATION_GUIDE.md** — Guia para replicar o Hub em outro projeto/chapter
- **docs/CURSOR_SETUP.md** — Fluxo rápido clone→run; tabela de variáveis; link para REPLICATION_GUIDE
- **.env.example** — Documentação por variável; DATABASE_URL opcional; referência a REPLICATION_GUIDE

### 2026-03-08 — Credly mobile paste + smoke i18n
- **profile.astro**: Credly paste 100ms delay (iOS); input debounce 300ms como fallback
- **smoke-routes.mjs**: rotas /en e /es adicionadas

---

## 2026-03-08 — Sprint Sanation: P0 Foundation & Security Scanning

### Scope
Prepare project for resumed sprint execution: close P0 gaps, enable security scanning, document production runbooks.

### Delivered
- **Dependabot**: `.github/dependabot.yml` — weekly npm dependency updates, label `dependencies`
- **CodeQL**: `.github/workflows/codeql-analysis.yml` — security analysis on push/PR to main
- **HF5 Production Runbook**: `docs/migrations/HF5_PRODUCTION_RUNBOOK.md` — step-by-step for executing HF5 data patch in production
- **Sprint Sanation Plan**: `docs/SPRINT_SANATION_PLAN.md` — phased plan: P0 completion → operational follow-ups → feature sprints
- **Backlog updates**: Technical debt "No Security Scanning" marked done; deputy_manager validation marked done

### Validation captured
- local `npm test` and `npm run build` passed

### Follow up still required
- Execute HF5 data patch in production per runbook; then update this release log
- Deploy `sync-comms-metrics` and configure secrets (S-COM6 follow-up)

### Bugfix (same session)
- Fixed `TribesSection.astro` SSR error: `initialCounts is not defined`. Added `initialCounts = {}` for SSR; slot counts still hydrate client-side from Supabase.

---

## 2026-03-08 — S-COM6, S-AN1, S10 Sprint Increments

### Scope
Advance Wave 4 features: dedicated Comms dashboard, Announcements security fix, Credly auto-sync workflow.

### Delivered
- **S-COM6 Dashboard Central de Mídia**:
  - New route `/admin/comms` with ACL gate (admin tier)
  - Looker iframe when `PUBLIC_LOOKER_COMMS_DASHBOARD_URL` is set
  - Native table from `comms_metrics_latest_by_channel` RPC when Looker not configured
  - Card added to admin reports panel; i18n PT/EN/ES
- **S-AN1 Announcements**:
  - Replaced inline `onclick` with Event Delegation (`.cursorrules` compliant)
  - Added `escapeHtml` for all user/DB content in banners (XSS hardening)
- **S10 Credly Auto Sync**:
  - GitHub Action `.github/workflows/credly-auto-sync.yml` — weekly Monday 08:00 UTC
  - Invokes `sync-credly-all` with service role; requires `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`
- Smoke routes: added `/admin/comms` to `scripts/smoke-routes.mjs`

### S-DR1 + Admin Security (2026-03-08)
- **docs/DISASTER_RECOVERY.md** — POP Supabase (backup, PITR, dump), Cloudflare rollback, checklist de incidente
- **Admin Event Delegation** — openAllocate, toggleAnnouncement, deleteAnnouncement migrados de `onclick` para `data-*` + `addEventListener` (.cursorrules compliant, XSS hardening)

### Deploy / config follow-up (2026-03-08)
- **docs/DEPLOY_CHECKLIST.md** — master checklist: HF5, sync-comms-metrics, Credly workflow, env vars
- **.env.example** — expanded with optional vars (Looker, PostHog, sync secrets)
- **.github/workflows/comms-metrics-sync.yml** — ingestão diária de comms (07:30 UTC); manual ou agendada

### Validation captured
- `npm test` and `npm run build` passed

---

## 2026-03-08 — Governance Reorganization (Parent/Child Work Packages)

### Scope
Reorganize roadmap execution to prevent out-of-sequence delivery and recurrent regressions caused by feature-first flow without explicit dependency gates.

### Delivered
- created EPIC parent issues in `ai-pm-hub-v2`:
  - `#47` Foundation Reliability Gate
  - `#48` Comms Operating System
  - `#49` Knowledge Hub Sequential Delivery
  - `#50` Scale, Data Platform & FinOps
- mapped child sprint issues under each EPIC with gate criteria (entry/exit) and dependency flow.
- documented sequential grouped roadmap and governance rules:
  - `docs/project-governance/ROADMAP_SEQUENCIAL_AGRUPADO.md`
- added governance helper scripts:
  - `scripts/roadmap_sequence_report.sh`
  - `scripts/sync_project_roadmap_sequence.sh`
- updated `backlog-wave-planning-updated.md` with mandatory parent/child execution policy.

### Notes
- GitHub Project GraphQL quota hit during final board-view synchronization. All issue-level regrouping is complete; project view sync script is ready to run after quota reset.

## 2026-03-08 — Wave 4 Sprint Increment (S-COM6 COMMS_METRICS_V2)

### Scope
Add an operational ingestion backbone for communications KPIs with SQL-governed observability.

### Delivered
- created new edge function:
  - `supabase/functions/sync-comms-metrics/index.ts`
  - supports secret-based auth (`SYNC_COMMS_METRICS_SECRET`)
  - supports external fetch (`COMMS_METRICS_SOURCE_URL` + optional token) or manual payload (`rows`)
  - normalizes metrics and upserts into `comms_metrics_daily`
  - writes execution telemetry to `comms_metrics_ingestion_log`
- added migration pack for V2 ingestion:
  - `supabase/migrations/20260308003330_comms_metrics_v2_ingestion.sql`
  - `docs/migrations/comms-metrics-v2-ingestion.sql`
  - `docs/migrations/comms-metrics-v2-ingestion-audit.sql`
  - `docs/migrations/comms-metrics-v2-ingestion-rollback.sql`
  - `docs/migrations/COMMS_METRICS_V2_RUNBOOK.md`
- SQL additions include:
  - ingestion log table with run-level telemetry
  - admin-level RLS policies for ingestion logs
  - `public.can_manage_comms_metrics()` helper function
  - `public.comms_metrics_latest_by_channel(p_days)` RPC-ready read function

### Validation captured
- local tests pass (`npm test`)
- migration and function package prepared for production apply/deploy

### Follow up still required
- deploy `sync-comms-metrics` in production
- configure secrets in Supabase project
- run V2 audit SQL after first production sync

## 2026-03-08 — Wave 4 Sprint Increment (S-RM4 ACL Hardening v1)

### Scope
Reduce authorization drift by centralizing admin tier checks and reusing them across critical admin routes.

### Delivered
- centralized ACL utilities in `src/lib/admin/constants.ts`:
  - `resolveTierFromMember`
  - `hasMinimumTier`
  - `canAccessAdminRoute`
  - route-level minimum tier map for:
    - `admin_panel`
    - `admin_analytics`
    - `admin_member_edit`
- `/admin` now uses centralized tier resolution/gate for panel access
- `/admin/analytics` gate now uses centralized ACL helper
- `/admin/member/[id]` gate now uses centralized ACL helper and includes robust boot fallback:
  - nav member
  - session + `get_member_by_auth`
  - deterministic redirect on deny

### Validation captured
- local `npm run build` passed after ACL hardening changes

### Follow up still required
- extend centralized ACL checks to additional privileged actions (non-route actions/buttons)
- align RLS policy naming/docs with same tier matrix for backend parity

### Completion update (same day)
- delivered `S-RM4 v2` with in-page action ACL guards in `/admin`:
  - added reusable guard helpers (`ensureAdminAction`, `ensureLeaderAction`)
  - protected privileged actions against console-trigger bypass:
    - tribe allocation and member edit actions
    - announcements CRUD actions
    - reports/snapshot preview + export actions
    - cycle history write actions (superadmin-only via centralized ACL)
    - tribe settings/slots actions (leader+)
- local `npm run build` passed after ACL action hardening

## 2026-03-08 — Wave 4 Sprint Increment (S-PA1 Product Analytics v1)

### Scope
Start analytics governance rollout with protected access and iframe-first dashboards.

### Delivered
- created new protected route:
  - `/admin/analytics` with tier gate (`superadmin` and `admin` only)
  - denied state for non-authorized users
- analytics embeds configured by environment variables:
  - `PUBLIC_POSTHOG_PRODUCT_DASHBOARD_URL`
  - `PUBLIC_LOOKER_COMMS_DASHBOARD_URL`
- added analytics shortcut card in `/admin` reports panel
- privacy hardening in PostHog identify (`BaseLayout`):
  - removed `name` and `email` from identify payload
  - kept `member_id` + minimal operational metadata

### Validation captured
- local `npm run build` passed after analytics route and privacy changes

### Follow up still required
- provision production dashboard URLs in environment
- optional consent/opt-out toggle in UI for session replay controls

### Completion update (same day)
- delivered `S-PA1 v2` with consent-aware controls:
  - new consent card in `/admin/analytics` (`Allow Analytics` / `Revoke Analytics`)
  - local consent state persisted in browser (`analytics_consent`)
  - global listener applies PostHog `opt_in_capturing`/`opt_out_capturing`
  - session replay starts/stops based on consent state
  - PostHog identify now runs only when consent is granted
- local `npm run build` passed after consent and privacy updates

## 2026-03-08 — Wave 4 Sprint Increment (S-ADM2 Leadership Snapshot v1)

### Scope
Deliver first operational version of leadership training snapshot in `/admin` for management visibility.

### Delivered
- added new `Leadership Training Snapshot` block in admin reports panel with:
  - active base size
  - mini-trail status counters (`Trilha Concluída`, `Em Progresso`, `Bloqueados 0/8`)
  - completion bars by chapter
  - completion bars by tribe
  - recent Credly certification feed with member/chapter/tribe/date/XP
- data sources combined client-side:
  - `members` (active operational base)
  - `course_progress` (8 official mini-trail course codes)
  - `gamification_points` filtered by `Credly:%`

### Validation captured
- local `npm run build` passed after admin changes

### Follow up still required
- i18n keys for new S-ADM2 copy
- optional filters (chapter/tribe/date window) and export CSV for snapshot

### Completion update (same day)
- delivered `S-ADM2 v2` in `/admin` reports:
  - snapshot filters: chapter, tribe, from, to
  - CSV export for per-member snapshot rows
  - i18n keys added for new snapshot labels/actions/messages in PT/EN/ES
- local `npm run build` passed after v2 changes

## 2026-03-08 — Wave 3 Sprint Increment (S11 UI Polish / Empty States)

### Scope
Improve UX clarity on internal pages with better loading placeholders and actionable empty states.

### Delivered
- `/artifacts`:
  - replaced plain "Carregando..." text with skeleton rows in all tab panels
  - added richer empty states with CTA for:
    - catalog (login CTA for guests, submit CTA for logged users)
    - my artifacts (submit CTA)
    - review queue (clear empty-state messaging)
- `/attendance`:
  - replaced initial loading placeholders in events/ranking with skeleton rows
  - events tab empty state now includes contextual CTA:
    - managers/leaders: `+ Novo Evento`
    - others: `Atualizar`
  - ranking tab empty state now explains when data will appear

### Validation captured
- local `npm run build` passed after UI changes

## 2026-03-08 — HF5 Data Patch Follow Through (SQL Pack)

### Scope
Prepare a deterministic, idempotent data-cleanup pack for legacy member inconsistencies called out in HF5.

### Delivered
- added migration-ready SQL files:
  - `docs/migrations/hf5-audit-data-patch.sql` (pre/post audit)
  - `docs/migrations/hf5-apply-data-patch.sql` (idempotent patch)
- patch behaviors:
  - restores Sarah LinkedIn only when blank and only from an existing matching non-empty source
  - aligns `members.operational_role/designations` with active `member_cycle_history` snapshot
  - enforces deputy hierarchy consistency (`deputy_manager` must include `co_gp`; `manager` must not carry `co_gp`)

### Validation captured
- SQL syntax reviewed locally and designed to be safely re-runnable
- no runtime codepath changes introduced (DB migration pack only)

### Follow up still required
- execute audit -> apply -> audit in production SQL editor
- if Sarah LinkedIn remains blank after run, apply a one-off manual update with canonical URL

## 2026-03-08 — Wave 3 Sprint Increment (S8b Internal i18n, Attendance Shell)

### Scope
Advance internal-page localization with a low-risk first pass on the attendance route.

### Delivered
- `/attendance` now resolves active language from URL and applies existing i18n keys for:
  - page metadata title
  - auth gate title/description/button
  - loading states
  - tab labels
  - section headers and refresh label
  - empty-state no-events copy

### Validation captured
- local `npm run build` passed after attendance i18n changes

### Follow up still required
- continue i18n migration on `/admin` and remaining internal flows

### Completion update (same day)
- attendance modal components localized with `attendance.modal.*` keys in PT/EN/ES:
  - `NewEventModal`
  - `RecurringModal`
  - `EditEventModal`
  - `RosterModal`
- `/admin` received first i18n shell pass with localized:
  - page title/meta/subtitle
  - restricted access state
  - access checking/loading strings
  - top stats labels
  - primary tab labels
  - pending pool heading
- `/admin` i18n expanded to filters and reports panel labels:
  - member filters (search/chapter/role/designation/status/login/tribe/clear)
  - VRMS/report card labels and preview table headers
  - member export labels and descriptions
- `/admin` i18n expanded again with:
  - allocation/edit/cycle-history modal labels
  - loading string for announcements
  - critical dynamic admin toast/confirm messages migrated to `admin.msg.*`
  - slot settings validations/success messages migrated to `admin.msg.*`
  - locale parity fix for `admin.msg.saveError` across PT/EN/ES

## 2026-03-08 — Wave 3 Sprint Increment (S-UX1 Trail Clarity)

### Scope
Improve researcher clarity for mini trail completion status directly in gamification workflows.

### Delivered
- added logged-in trail clarity card in `/gamification` with:
  - explicit progress indicator (`X de Y cursos concluídos`)
  - completion percentage bar
  - missing course list required to finish the mini trail
  - in-progress course list when applicable
- card refreshes after sync workflow execution to keep status aligned with latest backend updates

### Validation captured
- local `npm run build` passed after UI and query changes

## 2026-03-08 — Wave 3 Sprint Increment (S-RM3 Gamification XP Split)

### Scope
Advance Gamification v2 with explicit distinction between current cycle points and lifetime XP.

### Delivered
- `/gamification` leaderboard now supports mode switch:
  - `Ciclo Atual` (existing cycle ranking source)
  - `XP Vitalício` (aggregated from `gamification_points` per member)
- ranking rows now display both references simultaneously (current cycle vs lifetime) to reduce interpretation drift
- `Meus Pontos` panel now labels total as lifetime XP and shows current cycle points explicitly

### Validation captured
- local `npm run build` passed after gamification changes

### Follow up still required
- continue with `S-UX1` trail clarity item in Wave 3

### Completion update (same day)
- cycle vs lifetime distinction was extended to:
  - tribe ranking panel (mode switch + recalculated score basis)
  - achievements panel context (lifetime XP with current-cycle reference)
- S-RM3 scope considered complete for current sprint baseline

## 2026-03-08 — Wave 3 Sprint Increment (S-RM2 Profile Journey)

### Scope
Advance Wave 3 by delivering profile journey visibility and cycle-aware completeness improvements.

### Delivered
- profile data loading now treats `member_cycle_history` as first-class context with fallback safety
- added `Resumo da Jornada` card in `/profile` with:
  - total cycles
  - current cycle label
  - first join date
  - latest activation date
- timeline section hardened with explicit empty state when no cycle history exists
- completeness signal for operational members now checks cycle context from history (`Vínculo de ciclo`) instead of relying only on local snapshot fields

### Validation captured
- local `npm run build` passed after profile changes

### Follow up still required
- continue Wave 3 with `S-RM3` (lifetime XP vs current cycle split)
- continue Wave 3 with `S-UX1` (explicit per-member trail completion + missing course list)

## 2026-03-08 — Gamification Stability Sprint (S-HF6 + S-HF7)

### Scope
Close critical stabilization items in gamification UX and data consistency between trail progress and score surfaces.

### Delivered
- `S-HF7` completed in `/gamification`:
  - added bounded query timeout for secondary panels
  - added defensive `try/catch` and explicit error render paths for tabs that previously could remain in indefinite loading
- `S-HF6` completed in `sync-credly-all`:
  - legacy hardening now also syncs trail completion into `course_progress` when member has legacy Credly badges but no current `credly_url`
  - added reconciliation metric `legacy_trail_synced` in bulk sync report

### Validation captured
- local `npm run build` passed after frontend hardening changes
- `sync-credly-all` deployed in production as version 9
- member-level SQL validation confirmed trail state consistency (7 completed, 1 in progress) for sampled account

### Follow up still required
- keep recurring audit for legacy points drift and duplicate `member_id + reason` rows in `gamification_points`
- continue Wave 3 planned items (`S-RM2`, `S-RM3`, `S-UX1`)

## 2026-03-08 — Credly Data Sanitization and Dedup Hardening

### Scope
Production hardening to eliminate legacy Credly scoring drift and enforce safer dedup behavior for gamification records.

### Delivered
- `verify-credly` updated with Tier 2 expansion (`business intelligence`, `scrum foundation`, `sfpc`)
- `verify-credly` scoring upsert hardened to:
  - keep a single `gamification_points` record per `member_id + reason`
  - update points when classification changes
  - delete duplicate residual rows
- manual trail cleanup hardened from case-sensitive `like` to case-insensitive `ilike` for `Curso:CODE` legacy patterns
- `sync-credly-all` hardened to process active members without `credly_url` when `credly_badges` exists, sanitizing `tier/points` and recalculating related Credly point entries
- production data cleanup executed:
  - `system_tier` nulls reduced to zero in JSON badge payloads
  - legacy Tier 1 row (`PMP` with 10 points) corrected to 50 points

### Validation captured
- `verify-credly` deployed as active version 13
- `sync-credly-all` deployed as active version 8
- audit query for null tiers returned `0`
- targeted query confirmed BI/SFPC at `25` points

### Follow up still required
- run periodic audit query for `member_id + reason` duplicates in `gamification_points`
- complete UI alignment and loading fixes tracked in `S-HF6` and `S-HF7`

## 2026-03-07 — Stabilization Hotfix Train

### Scope
Production stabilization covering route compatibility, SSR safety, and documentation discipline.

### Included changes

#### `6f1593d`
**Message:** `fix: add Cloudflare Pages SPA fallback redirects`

**Why**
Reduce direct navigation failures and improve resilience for non standard entry paths on Cloudflare Pages.

#### `f33afce`
**Message:** `fix: add legacy route aliases for team and rank pages`

**Why**
Restore compatibility for old or live links still pointing to:
- `/teams`
- `/rank`
- `/ranks`

#### `87cde9a`
**Message:** `fix: guard tribes deliverables mapping against missing data`

**Why**
Prevent SSR failure in `TribesSection.astro` when static data is incomplete or optional.

### Validation captured
- local `npm run build` passed
- local `npm run dev -- --host 0.0.0.0 --port 4321` started successfully
- local access confirmed through `http://localhost:4321/`

### Known follow up
- production propagation of aliases should still be smoke tested
- SSR safety audit should continue in other sections
- docs were behind the code and are now being corrected

---

## 2026-03-07 — Credly Tier Scoring Expansion

### Scope
Backend scoring logic for Credly verification was expanded beyond the older coarse behavior.

### Delivered
- tier based certification scoring in the verification flow
- richer scoring breakdown in backend response
- improved zero match handling

### Important caveat
This release is **not complete from a product standpoint** because rank and gamification UI surfaces still need alignment with the new scoring logic.

### Operational note
When backend truth and frontend experience diverge, the release log must say so plainly instead of pretending the feature is done. Reality is stubborn like that.

---

## Release policy from now on

Every production affecting hotfix, stabilization batch, or materially visible backend change should create or update an entry in this file.

Automated semantic versioning can come later. Team memory cannot.
