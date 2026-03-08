# Núcleo IA & GP — Backlog & Wave Planning
## Status: Março 2026
## Atualizado após estabilização de produção, revisão documental e alinhamento produto engenharia

**Board de sprints**: [GitHub Project — AI PM Hub](https://github.com/users/VitorMRodovalho/projects/1/) · Regras: `docs/project-governance/PROJECT_GOVERNANCE_RUNBOOK.md`

---

## 🧭 ROADMAP REORGANIZATION (2026-03-08)

Para eliminar execução fora de sequência e reduzir regressões, o backlog passa a operar com pacote pai -> atividades filhas.

### Pacotes Pai (EPICs)

1. `P0 Foundation Reliability Gate` (issue `#47`)
2. `P1 Comms Operating System` (issue `#48`)
3. `P2 Knowledge Hub Sequential Delivery` (issue `#49`)
4. `P3 Scale, Data Platform & FinOps` (issue `#50`)

### Regra de execução

- Nenhuma tarefa sai de `Backlog/Ready` para `In progress` sem:
  - vínculo com EPIC pai;
  - dependências front/back/SQL/integrador explícitas;
  - critérios de entrada e saída definidos.
- Feature de frontend sem backend/API/SQL pronto não avança para desenvolvimento.
- Quando houver risco de regressão em produção, prioridade volta para `P0 Foundation`.

### Sobre itens abertos em Wave 2/3 enquanto Wave 4 avançou

Isso ocorreu por execução orientada a incidentes de produção (hotfixes) sem gate formal de pacote pai. A reorganização acima passa a ser obrigatória para manter sequência e previsibilidade.

---

## ✅ COMPLETED / STABILIZED

| Sprint / Linha | Deliverable | Status |
|----------------|-------------|--------|
| S2 | Index migration: 10 sections + core data files | ✅ Production |
| S3 | Attendance page: KPIs, events, roster, modals | ✅ Production |
| S4 | Artifact tracking + enriched profile | ✅ Production |
| S5 | i18n infrastructure + PT EN ES public index | ✅ Production |
| S6 | Gamification base: leaderboard, points, certificates | ✅ Production |
| S7 | Admin dashboard: tribe management + member CRUD | ✅ Production |
| RM | LinkedIn OIDC login button | ✅ Production |
| RM | Member photo storage setup | ✅ Production |
| RM | Cloudflare Pages SPA fallback redirects | ✅ Production |
| RM | Legacy route aliases `/teams`, `/rank`, `/ranks` | ✅ Production |
| RM | SSR guard in `TribesSection.astro` for missing `deliverables` | ✅ Production |
| RM | Credly Edge Function with tier based badge scoring | ✅ Backend Production |
| RM | Initial release log discipline adopted | ✅ Documentation Governance |

---

## 🚨 OPEN HOTFIX / STABILIZATION ITEMS

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| S-HF1 | Credly Mobile Paste Fix | Critical | ✅ Done | Credly URL now normalizes/validates paste input (trim/query/trailing slash) in profile and edge verification flow. |
| S-HF2 | Rank UI Alignment with Credly Tiers | Critical | ✅ Done | Gamification UI now surfaces Credly tier totals and per-tier breakdowns aligned with backend scoring model. |
| S-HF3 | Post Deploy Smoke Test | High | ✅ Done | Added repeatable route smoke script for `/`, `/attendance`, `/gamification`, `/artifacts`, `/profile`, `/admin`, `/teams`, `/rank`, `/ranks`. |
| S-HF4 | SSR Safety Audit | High | ✅ Done | Added SSR-safe guards/fallbacks in high-risk sections for optional list data. |
| S-HF5 | Data Patch Follow Through | High | In Progress (SQL pack ready 2026-03-08) | Added idempotent SQL pack (`docs/migrations/hf5-apply-data-patch.sql` + `hf5-audit-data-patch.sql`) for Sarah LinkedIn restoration, Roberto role correction by active cycle history, and Deputy PM hierarchy consistency checks/fixes. |
| S-HF6 | Source of Truth Drift (Trail vs Gamification) | Critical | ✅ Done (2026-03-08) | Reconciliation hardening in `sync-credly-all` now also syncs legacy trail completions into `course_progress`, keeping `/#trail` and `/gamification` aligned. |
| S-HF7 | Gamification Secondary Tabs Stuck on Loading | Critical | ✅ Done (2026-03-08) | Added timeout and robust error fallback on secondary tab loaders in `/gamification`, removing indefinite "Carregando..." hangs. |
| S-HF8 | Credly Legacy Sanitization & Dedup | Critical | ✅ Done (2026-03-08) | Promoted BI/SFPC to Tier 2, deployed `verify-credly` + `sync-credly-all` hardening, sanitized `tier=null`, removed duplicate handling gaps, and corrected legacy Tier 1 rows still at 10 points. |

---

## 🌊 WAVE 3: Profile, Gamification & UX Excellence
**Foco:** Retenção de voluntários, UX impecável e inteligência de uso.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| S-RM2 | Completeness Bar & Timeline | High | ✅ Done (2026-03-08) | Profile now renders adaptive completeness + “Resumo da Jornada” and timeline backed by `member_cycle_history` with safe fallback when history is unavailable. |
| S-RM3 | Gamification v2 | High | ✅ Done (2026-03-08) | Cycle vs lifetime split now implemented across individual leaderboard, tribe ranking, achievements context, and my points summary. |
| S-UX1 | Trilha Progress Clarity for Researchers | High | ✅ Done (2026-03-08) | `/gamification` now shows logged-in mini trail clarity card with explicit progress (`X de Y`) and missing/in-progress course list. |
| S-PA1 | Product Analytics | High | Partial (v3 2026-03-08) | Route + iframe + consent toggle; consent status labels agora i18n (PT/EN/ES) em vez de literais. |
| S8b | i18n Internal Pages | Medium | ✅ Done (2026-03-08) | Admin completo: modal Eixo 1/2/3, oprole options, desig labels, CSV headers (VRMS + Member), Sim/Não. Attendance, profile, artifacts, gamification, TribesSection. PT/EN/ES parity. |
| S11 | UI Polish & Empty States | Medium | Partial (2026-03-08) | Skeleton + empty states; admin exec i18n; TrailSection/profile/admin-member loading → i18n; .cursorrules define:vars. |

---

## 🌊 WAVE 4: Admin Tiers, Integrations & Comms
**Foco:** Reduzir atrito do GP e melhorar comunicação e governança operacional.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| S-RM4 | Admin Tiers (ACL) | High | Partial (v2 delivered 2026-03-08) | Centralized ACL now gates both critical routes and privileged in-page actions (allocation, member edits, announcements, reports exports, leadership snapshot actions, cycle-history writes, tribe settings), reducing console-trigger bypass risk. |
| S-REP1 | Exportação VRMS (PMI) | High | Partial (2026-03-08) | CSV preview + download; colPmiId e vrmsCountFormat i18n PT/EN/ES. |
| S-ADM2 | Leadership Training Progress Snapshot | High | Partial (v2 delivered 2026-03-08) | `/admin` reports snapshot now has filters (capítulo/tribo/período), CSV export, and i18n keys for PT/EN/ES, in addition to completion/blocking and recent Credly insights. |
| S10 | Credly Auto Sync | Medium | Partial (2026-03-08) | GitHub Action `credly-auto-sync.yml` runs weekly (Monday). Requires SUPABASE_SERVICE_ROLE_KEY. Manual trigger via workflow_dispatch. |
| S-AN1 | Announcements System | Medium | Partial (2026-03-08) | Banners + CRUD + Event Delegation + XSS; form e lista i18n PT/EN/ES. **Pendente documentado**: rich editor opcional, scheduling UX (agendar início/fim). |
| S-DR1 | Disaster Recovery Doc | Low | ✅ Done (2026-03-08) | `docs/DISASTER_RECOVERY.md` — POP Supabase (backup, PITR, dump), Cloudflare rollback, checklist. |
| S-COM6 | Dashboard Central de Mídia | Medium | Partial (UI delivered 2026-03-08) | `/admin/comms` route with Looker iframe or native table from `comms_metrics_latest_by_channel`. Backend: sync-comms-metrics, SQL pack. Pending: deploy sync-comms-metrics in prod. |
| S-PA2 | Admin Executive Visual Dashboards (ROI PMI) | High | Partial (2026-03-08) | Painel executivo conectado a exec_funnel_summary, exec_cert_timeline, exec_skills_radar RPCs. Funil, timeline de coortes e radar de competências com barras nativas. |

---

## 🌊 WAVE 5: The Knowledge Hub
**Foco:** Polinização cruzada de conhecimento, visibilidade entre tribos e acúmulo de patrimônio intelectual.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| S-KNW1 | Repositório Central de Recursos | Medium | Partial (2026-03-08) | Migration `knowledge_assets`/`hub_resources`; RLS + docs pack. |
| S-KNW2 | Tribe Workspace | Medium | Partial (2026-03-08) | CRUD admin para `hub_resources` (aba Recursos). **Pendente**: rota `/workspace` pública com views relacionais. |
| S-KNW3 | Sistema de Tags e Relações | Medium | Planned | Link final artifacts to upstream courses, studies, or events to preserve traceability. |
| S-KNW4 | Views Relacionais Governadas | Medium | Planned | Gallery board style views powered by Supabase data model and RLS, not external knowledge software. |
| S-KNW5 | Knowledge-Certification Correlation Layer | Medium | Planned | Correlate `knowledge_assets` consumption with course/certification progress to evidence the Hub as catalyst of qualification outcomes. |

---

## 🌍 WAVE 6: Scale, Multi Tenant & Global Impact
**Foco:** Preparar o projeto para ser replicável e internacionalizável.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| S-RM5 | Multi tenant Config | Medium | Planned | Admin config for `group_term`, cycle config, and webhooks. |
| S23 | Chapter Integrations | Medium | Planned | Event driven integrations with local chapter portfolios and tools. |
| S24 | API for Chapters | Low | Planned | Read only API for chapter impact and participation data. |
| S-SC1 | Multilingual Screenshots | Low | Planned | Automated screenshots for PT EN ES docs or release snapshots. |

---

## 🛠️ TECHNICAL DEBT & DEVOPS

| Issue | Impact | Status | Mitigation Plan |
|-------|--------|--------|-----------------|
| README History Lost | High | Addressed in docs refresh | Restore pilot 2024 history, quadrants, multilingual positioning, and current stack without losing operational context. |
| No Release Log | High | Addressed in docs refresh | Maintain `docs/RELEASE_LOG.md` for hotfixes and production changes from now on. |
| Semantic Versioning Missing | Medium | Open | Create automated release workflow and tags later, but do not block manual release notes now. |
| No Security Scanning | High | ✅ Done (2026-03-08) | Dependabot (`.github/dependabot.yml`) + CodeQL (`.github/workflows/codeql-analysis.yml`) habilitados. |
| Hardcoded strings | Medium | Open | Continue i18n first migration. |
| Legacy role columns still alive | High | Partial | Finish frontend migration to `operational_role` and `designations`, then hard drop `role` and `roles`. |
| Architectural guideline drift | High | Open | Enforce role model v3, cycle aware data, soft delete, and event driven integration discipline. |
| Route compatibility not tested | High | Addressed | Smoke tests added and validated in deploy checklist. |
| SQL architecture not tracked in every sprint | High | In Progress | Mandatory DB gate for admin/analytics increments: include migration in `supabase/migrations` + docs pack (`apply/audit/rollback/runbook`) and capture evidence in `docs/RELEASE_LOG.md`. |

---

## 🧱 DATA / ARCHITECTURE FOUNDATIONS

### Approved architectural direction

- `members` is the current snapshot for identity, contact, auth, and current state.
- `member_cycle_history` is the historical fact table for role, tribe, and cycle participation.
- `operational_role` and `designations` are the target fields.
- `role` and `roles` are tolerated only during migration.
- The Hub remains the only source of truth for gamification and operational metrics.

### Required next technical steps

- [x] Complete frontend reads from `operational_role` and `designations`.
- [x] Render cycle history timeline from `member_cycle_history`.
- [x] Add and validate `deputy_manager` visual treatment and ordering rules (TeamSection, profile, admin).
- [x] Define hard drop window for `role` and `roles`.
- [ ] Add consent aware analytics instrumentation without leaking PII.

---

## 📊 ANALYTICS GOVERNANCE

### Internal product analytics
Use PostHog through protected iframe dashboards. Do not build custom charts in Astro unless there is a very strong product need.

### Required analytics rules
- use `member_id` or at most `operational_role`
- do not send email or full name unless strictly required
- mask all input fields in session replay
- maintain operational delete path for right to be forgotten
- restrict `/admin/analytics` by tier

### External communication metrics
Use Looker Studio for YouTube, LinkedIn, and Instagram funnel style KPIs through low maintenance connectors and automation.

---

## 📋 RECOMMENDED EXECUTION ORDER

### Sessão 1 — House on fire first
1. Unificar Source of Truth de trilha vs gamificação (`S-HF6`)  
2. Corrigir loading infinito das abas secundárias em `/gamification` (`S-HF7`)  
3. Deputy PM hierarchy validation  
4. Smoke test routes and direct navigation  

### Sprint operacional imediata — 2026-03-08 to 2026-03-12
1. Monitorar pós deploy de `S-HF6` e `S-HF7` com amostragem de membros com e sem `credly_url`.  
2. Consolidar query de auditoria recorrente para duplicatas e pontos legados Credly.  
3. Registrar evidências no `docs/RELEASE_LOG.md` para cada correção com validação pós deploy.  

### Próxima sprint recomendada — 2026-03-12 to 2026-03-19 (Wave 3)
1. Entregar `S-RM2` (Completeness Bar & Timeline) com dados 100% em `member_cycle_history`.  
2. Avançar `S-RM3` (Gamification v2) com separação explícita de XP vitalício vs ciclo atual.  
3. Iniciar `S-UX1` para explicitar “X de 8 cursos” + pendências individuais de trilha para pesquisador.  

### Sessão 2 — Finish migration discipline
1. Frontend reads from `operational_role` and `designations` only  
2. Timeline from `member_cycle_history`  
3. Cleanup SQL patches and validation  

### Sessão 3 — Product intelligence
1. PostHog iframe analytics route  
2. Looker Studio communications dashboard plan  
3. i18n internal pages and UX polish  

### Sessão 4 — Knowledge hub runway
1. Define knowledge asset schema  
2. Design `/workspace` relational views  
3. Preserve cross tribe visibility without turning the Hub into Miro chaos with prettier fonts

---

## Notes for the dev team

This backlog reflects a simple truth: some backend and hotfix work is already delivered while related UI and operational validation are still pending. Marking everything green because code landed somewhere is how teams accidentally summon chaos goblins.
