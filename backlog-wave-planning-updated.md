# Nucleo IA & GP — Backlog & Wave Planning
## Status: Marco 2026 (atualizado 2026-03-10)
## Sincronizado com producao: Git, Migracoes SQL (33/33) e 13 Edge Functions

**Board de sprints**: [GitHub Project — AI PM Hub](https://github.com/users/VitorMRodovalho/projects/1/) · Regras: `docs/project-governance/PROJECT_GOVERNANCE_RUNBOOK.md`

---

## LATEST UPDATE (2026-03-10)

### Entregue nesta sessao
- **UX Housekeeping**: Upload best practices banners (admin + artifacts), file validation 15MB, formatos expandidos (.pdf/.pptx/.png/.jpg)
- **ETL Pipeline**: Politica de governanca de dados (`DATA_INGESTION_POLICY.md`), pipeline 3 fases (prepare/curate/upload), quarentena AI Safety para .md, isolamento de .docx, flagging de copyright para PDFs
- **Documentacao**: RELEASE_LOG, PERMISSIONS_MATRIX e este backlog sincronizados com estado exato de producao

### Entregue em sessoes anteriores (2026-03-09 a 2026-03-10)
- **Sprint 4**: Seletor Global de Tribos (dropdown interativo Nav.astro) + Sistema de Notificacao de Alocacao (`send-allocation-notify` + Admin UI)
- **Sprint 2+3**: Filtros de artefatos por taxonomy_tags + Validacao de deliverables/My Week existentes
- **Sprint 1**: Leaderboard cycle-aware (VIEW + RPC), trail per-course status, XP por ciclo no perfil
- **Wave 4 Completa**: Governanca operacional, lifecycle management (4 RPCs), onboarding global, comms integration, webinars, curadoria
- **Wave 5 Fase 1**: Interface de curadoria `/admin/curatorship`, auto-tag, dynamic email signatures
- **P0 Bugfixes**: Tribe counter 0/6, curatorship logout, comms infinite loading
- **S-PRES1**: Presentation Module com ACL democratico
- **P2**: LGPD visual masks, native analytics, Superadmin navigation
- **P3**: Trello/Calendar import, PDF upload, webinar pipeline

---

## ROADMAP REORGANIZATION (2026-03-08)

Para eliminar execucao fora de sequencia e reduzir regressoes, o backlog opera com pacote pai -> atividades filhas.

### Pacotes Pai (EPICs)

1. `P0 Foundation Reliability Gate` (issue `#47`) — Concluido
2. `P1 Comms Operating System` (issue `#48`) — Concluido
3. `P2 Knowledge Hub Sequential Delivery` (issue `#49`) — Concluido (Wave 5 Fase 1)
4. `P3 Scale, Data Platform & FinOps` (issue `#50`) — Em progresso (Wave 6)

### Regra de execucao

- Nenhuma tarefa sai de `Backlog/Ready` para `In progress` sem:
  - vinculo com EPIC pai;
  - dependencias front/back/SQL/integrador explicitas;
  - criterios de entrada e saida definidos.
- Feature de frontend sem backend/API/SQL pronto nao avanca para desenvolvimento.
- Quando houver risco de regressao em producao, prioridade volta para `P0 Foundation`.

---

## COMPLETED / STABILIZED

| Sprint / Linha | Deliverable | Status |
|----------------|-------------|--------|
| S2 | Index migration: 10 sections + core data files | Production |
| S3 | Attendance page: KPIs, events, roster, modals | Production |
| S4 | Artifact tracking + enriched profile | Production |
| S5 | i18n infrastructure + PT EN ES public index | Production |
| S6 | Gamification base: leaderboard, points, certificates | Production |
| S7 | Admin dashboard: tribe management + member CRUD | Production |
| RM | LinkedIn OIDC login button | Production |
| RM | Member photo storage setup | Production |
| RM | Cloudflare Pages SPA fallback redirects | Production |
| RM | Legacy route aliases `/teams`, `/rank`, `/ranks` | Production |
| RM | SSR guard in `TribesSection.astro` for missing `deliverables` | Production |
| RM | Credly Edge Function with tier based badge scoring | Backend Production |
| RM | Initial release log discipline adopted | Documentation Governance |

---

## HOTFIX / STABILIZATION ITEMS (Todos Resolvidos)

| ID | Feature | Status | Resolucao |
|----|---------|--------|-----------|
| S-HF1 | Credly Mobile Paste Fix | Done | Credly URL normalizes/validates paste input. |
| S-HF2 | Rank UI Alignment with Credly Tiers | Done | Gamification UI surfaces Credly tier totals. |
| S-HF3 | Post Deploy Smoke Test | Done | Repeatable route smoke script. |
| S-HF4 | SSR Safety Audit | Done | SSR-safe guards/fallbacks. |
| S-HF5 | Data Patch Follow Through | Done | SQL pack executed. |
| S-HF6 | Source of Truth Drift (Trail vs Gamification) | Done | Reconciliation in `sync-credly-all`. |
| S-HF7 | Gamification Secondary Tabs Stuck on Loading | Done | Timeout + error fallback. |
| S-HF8 | Credly Legacy Sanitization & Dedup | Done | Tier 2 expansion + dedup hardening. |
| S-HF9 | Edge Functions no Repo | Done | Todas as 13 Edge Functions versionadas em `supabase/functions/`. |

---

## WAVE 3: Profile, Gamification & UX Excellence — CONCLUIDA

| ID | Feature | Status |
|----|---------|--------|
| S-RM2 | Completeness Bar & Timeline | Done |
| S-RM3 | Gamification v2 (Cycle vs Lifetime) | Done |
| S-UX1 | Trilha Progress Clarity for Researchers | Done |
| S-PA1 | Product Analytics (iframe + consent) | Done |
| S8b | i18n Internal Pages | Done |
| S11 | UI Polish & Empty States | Done |
| S-AUD1 | TribesSection i18n | Done |
| S-CFG1 | MAX_SLOTS single source | Done |
| Sprint 1 | Cycle-aware leaderboard VIEW + get_member_cycle_xp RPC + per-course trail | Done |

---

## WAVE 4: Admin Tiers, Integrations & Comms — CONCLUIDA

| ID | Feature | Status |
|----|---------|--------|
| S-RM4 | Admin Tiers (ACL) — centralized + in-page guards | Done |
| S-REP1 | Exportacao VRMS (PMI) — CSV + i18n | Done |
| S-ADM2 | Leadership Training Progress Snapshot — filters + CSV export | Done |
| S-ADM3 | Member Lifecycle Management — 4 SECURITY DEFINER RPCs | Done |
| S10 | Credly Auto Sync — GitHub Action weekly | Done |
| S-AN1 | Announcements System — banners + CRUD + XSS | Done (rich editor pendente) |
| S-DR1 | Disaster Recovery Doc | Done |
| S-COM1 | Communications Team Integration — designations backfill | Done |
| S-COM6 | Dashboard Central de Midia — `/admin/comms` | Done |
| S-COM7 | Global Onboarding Broadcast Engine | Done |
| S-PA2 | Admin Executive Visual Dashboards | Done |
| W4.4 | Navigation Config integration (tier-based dynamic menus) | Done |
| W4.10 | Central de Ajuda do Lider (`/admin/help`) | Done |
| Sprint 4 | Global Tribe Selector (dropdown Nav.astro) | Done |
| Sprint 4 | Allocation Notification (`send-allocation-notify` + Admin UI) | Done |

---

## WAVE 5 FASE 1: Knowledge Hub — CONCLUIDA

| ID | Feature | Status |
|----|---------|--------|
| S-KNW1 | Repositorio Central de Recursos (`hub_resources`) | Done |
| S-KNW2 | Workspace publico (`/workspace`) | Done |
| S-KNW3 | Artifact Tag Filtering (taxonomy_tags) | Done |
| S-PRES1 | Presentation Module (ACL democratico, /presentations) | Done |
| Curadoria | Interface `/admin/curatorship` (approve/edit/discard) | Done |
| Auto-tag | Sugestao automatica de tags por keywords | Done |
| ETL | Pipeline 3 fases (prepare/curate/upload) + DATA_INGESTION_POLICY.md | Done |
| UX | Upload best practices banners + file validation 15MB | Done |

---

## WAVE 5 FASE 2: Knowledge Intelligence — PENDENTE
**Foco:** Correlacao conhecimento-certificacao, views relacionais e busca semantica.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| S-KNW4 | Views Relacionais Governadas | Medium | Planned | Gallery/board-style views powered by Supabase data model and RLS. |
| S-KNW5 | Knowledge-Certification Correlation | Medium | Planned | Correlate `hub_resources` consumption with course/certification progress. |
| S-KNW6 | Busca Semantica (Embeddings) | Low | Planned | Vector search via `knowledge_assets` + pgvector para busca por significado. |
| S-KNW7 | Gemini Extraction Pipeline | Low | Planned | Extrair conteudo de `.docx` em `needs_extraction/` via Gemini API. |

---

## WAVE 6: Scale, Multi Tenant & Global Impact — PENDENTE
**Foco:** Preparar o projeto para ser replicavel e internacionalizavel.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| S-RM5 | Multi-tenant Config | Medium | Planned | Admin config for `group_term`, cycle config, and webhooks. |
| S23 | Chapter Integrations | Medium | Planned | Event-driven integrations with local chapter portfolios and tools. |
| S24 | API for Chapters | Low | Planned | Read-only API for chapter impact and participation data. |
| S-SC1 | Multilingual Screenshots | Low | Planned | Automated screenshots for PT EN ES docs or release snapshots. |
| DS-1 | Data Science PMI-CE | Medium | Planned | Dashboards analiticos para o capitulo PMI-CE com metricas de impacto. |

---

## TECHNICAL DEBT & DEVOPS

| Issue | Impact | Status | Mitigation Plan |
|-------|--------|--------|-----------------|
| README History Lost | High | Addressed | Restored in docs refresh. |
| No Release Log | High | Addressed | `docs/RELEASE_LOG.md` mantido ativamente. |
| Semantic Versioning Missing | Medium | Open | Create automated release workflow and tags later. |
| No Security Scanning | High | Done | Dependabot + CodeQL habilitados. |
| Hardcoded strings | Medium | Done | i18n migration complete (400+ keys PT/EN/ES). |
| Legacy role columns still alive | High | Partial | Frontend migrated to `operational_role`/`designations`. Hard drop of `role`/`roles` pendente. |
| S-AN1 Rich Editor | Low | Open | Rich text editor (TipTap/Quill) para corpo de avisos. |
| S-AN1 Scheduling UX | Low | Open | Interface para agendar inicio/fim de exibicao dos avisos. |

---

## DATA / ARCHITECTURE FOUNDATIONS

### Approved architectural direction

- `members` is the current snapshot for identity, contact, auth, and current state.
- `member_cycle_history` is the historical fact table for role, tribe, and cycle participation.
- `operational_role` and `designations` are the target fields.
- `role` and `roles` are tolerated only during migration.
- The Hub remains the only source of truth for gamification and operational metrics.
- `DATA_INGESTION_POLICY.md` governs all ETL operations (sensitive data never uploaded).

### Required next technical steps

- [x] Complete frontend reads from `operational_role` and `designations`.
- [x] Render cycle history timeline from `member_cycle_history`.
- [x] Add and validate `deputy_manager` visual treatment and ordering rules.
- [x] Define hard drop window for `role` and `roles`.
- [x] Consent-aware analytics instrumentation without leaking PII.
- [ ] Execute hard drop of `role` and `roles` columns.
- [ ] Provision production dashboard URLs for PostHog/Looker.

---

## ANALYTICS GOVERNANCE

### Internal product analytics
Use PostHog through protected iframe dashboards. Native analytics via `exec_funnel_summary` and `exec_skills_radar` RPCs for executive panel.

### Required analytics rules
- use `member_id` or at most `operational_role`
- do not send email or full name unless strictly required
- mask all input fields in session replay
- maintain operational delete path for right to be forgotten
- restrict `/admin/analytics` by tier

### External communication metrics
Use Looker Studio for YouTube, LinkedIn, and Instagram funnel-style KPIs through low-maintenance connectors and automation.

---

## PRODUCTION STATE SUMMARY (2026-03-10)

### Infrastructure
- **Git**: `origin/main` and `production/main` 100% synchronized
- **SQL Migrations**: 33/33 applied in production (Supabase)
- **Edge Functions**: 13 active in production (all `--no-verify-jwt`)
- **Frontend**: Deployed via Cloudflare Pages (auto-deploy from main)
- **Storage**: `documents` bucket active with public read + authenticated upload

### Navigation (`navigation.config.ts`)
- 19 items covering all routes with tier-based ACL
- Home anchors (10), Tools (5), Member (2), Profile (1), Admin (5)
- No orphan routes (legacy aliases `/teams`, `/rank`, `/ranks` are intentional redirects)

### Documentation
- `docs/RELEASE_LOG.md`: Up to date (2026-03-10)
- `docs/PERMISSIONS_MATRIX.md`: Up to date (2026-03-10)
- `backlog-wave-planning-updated.md`: This file — synchronized

---

## Notes for the dev team

This backlog now reflects the actual state of production. All items marked Done have been verified against deployed code, applied migrations, and active Edge Functions. Items marked "Planned" are genuine future work with no code in the repository.
