# Nucleo IA & GP — Backlog & Wave Planning
## Status: Marco 2026 (atualizado 2026-03-11)
## Sincronizado com producao: Git, Migracoes SQL (40/40) e 13 Edge Functions

**Board de sprints**: [GitHub Project — AI PM Hub](https://github.com/users/VitorMRodovalho/projects/1/) · Regras: `docs/project-governance/PROJECT_GOVERNANCE_RUNBOOK.md`

---

## LATEST UPDATE (2026-03-10)

### Entregue nesta sessao (Four Options Sprint)
- **S-KNW4 File Detective & Knowledge Sanitization**: Script `knowledge_file_detective.ts` para detectar apresentacoes orfas em `data/staging-knowledge/`. Artifacts page separada em "Artefatos Produzidos" vs "Materiais de Referencia". Botoes inline de edicao de tags para lideres/curadores via `curate_item` RPC.
- **S-KNW5 Kanban Curatorship Board**: `/admin/curatorship` refatorado de lista plana para board Kanban com 4 colunas (Pendente, Em Revisao, Aprovado, Descartado). Drag-and-drop com HTML5 API. Nova migration `list_curation_board` RPC.
- **S-OB1 Onboarding Intelligence**: Script `onboarding_whatsapp_analysis.ts` para NLP do chat WhatsApp de integracao (keyword extraction, FAQ detection, timeline analysis). Onboarding page redesenhada com progress tracker, accordion steps, fases (Boas-vindas/Configuracao/Integracao/Producao), e dicas data-driven.
- **S-AN1 Analytics 2.0**: Chart.js instalado. PostHog/Looker iframes substituidos por graficos nativos (Funnel bar, Radar spider, Impact doughnut, KPI cards, Cert Timeline line). Comms dashboard com bar chart de metricas por canal.

### Entregue anteriormente (CPO Production Audit)
- **S-HF10 Credly URL Persistence**: `saveSelf()` agora preserva `credly_url` existente quando campo nao e modificado; `verifyCredly()` persiste URL via `member_self_update` antes da verificacao. Fluxo completo: inserir URL → verificar → salvar funciona sem perda.
- **S-HF11 Gamification Toggle XP Vitalicio**: `setLeaderboardMode()` agora chama `ensureLifetimePointsLoaded()` antes de re-render; fix de conflito `bg-transparent`/`bg-navy` nos botoes de toggle (leaderboard + tribe ranking).
- **S-UX2 Explorar Tribos Universal**: Dropdown de tribos (desktop/drawer/mobile) carrega TODAS as tribos; tribos inativas aparecem com opacidade reduzida + icone de cadeado + tooltip "Tribo Fechada".
- **S-IA1 Help Publico**: `/admin/help` migrado para `/help` (publico para membros logados); topicos LGPD/Privacy ocultos para nao-admins; `/admin/help` redireciona 301 para `/help`.
- **S-IA2 Onboarding no Drawer**: Removido da navbar principal; movido para o Profile Drawer (grupo 'profile', `requiresAuth: true`, `minTier: 'member'`).
- **S-IA3 Webinars Placeholder**: `admin/webinars.astro` preenchido com UI "Em Breve" com 3 cards de features planejadas + access check admin.

### Entregue em sessoes anteriores (2026-03-09 a 2026-03-10)
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
| S-HF10 | Credly URL Persistence | Done | `saveSelf()` preserva URL existente; `verifyCredly()` persiste via RPC antes da verificacao. |
| S-HF11 | Gamification Toggle XP Vitalicio | Done | `ensureLifetimePointsLoaded()` pre-render + fix `bg-transparent` toggle conflict. |
| S-UX2 | Explorar Tribos Universal | Done | Dropdown carrega todas as tribos; inativas com opacidade + cadeado + tooltip. |
| S-IA1 | Help Publico (`/help`) | Done | Migrado de `/admin/help`; LGPD oculto para nao-admins; redirect 301. |
| S-IA2 | Onboarding no Drawer | Done | Removido da navbar principal; movido para Profile Drawer. |
| S-IA3 | Webinars Placeholder | Done | UI "Em Breve" com access check admin. |
| S-KNW4 | File Detective & Knowledge Sanitization | Done | Script + Produced/Reference sub-tabs + leader inline tag edit. |
| S-KNW5 | Kanban Curatorship Board | Done | 4-column Kanban com drag-and-drop + `list_curation_board` RPC. |
| S-OB1 | Onboarding Intelligence (WhatsApp NLP) | Done | Chat parser + redesigned onboarding com progress tracker. |
| S-AN1 | Analytics 2.0 (Chart.js) | Done | PostHog/Looker → native charts (funnel, radar, impact, cert timeline, comms). |

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

## WAVE 7: Data Ingestion Platform — CONCLUIDA
**Foco:** Ingerir todas as fontes de dados descentralizadas (Trello, Calendar, CSV Voluntarios, Miro) na plataforma como single source of truth.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W7.1 | Trello 5-Board Historical Import | High | Done | 5 boards → 119 cards imported (4 closed skipped). Boards: Comunicacao C3 (17), Articles (28), Artigos PM.com (3), Tribo 3 (34), Midias Sociais (37). |
| W7.2 | Google Calendar ICS Import | High | Done | 593 ICS events parsed → 87 Nucleo/PMI relevant → 67 imported (20 deduplicados). |
| W7.3 | Volunteer CSV Data Pipeline | High | Done | 6 CSVs → 143 aplicacoes (Ciclo 1: 8, Ciclo 2: 16, Ciclo 3: 119). 92 matched com membros existentes (64%). |
| W7.4 | Miro Board Links Import | Medium | Done | 445 linhas → 51 URLs unicas importadas para `hub_resources` (32 artigos ciclo 2, 6 noticias, 1 video, 1 curso, etc.). |
| W7.5 | Project Boards Schema | High | Done | Migration: `project_boards` + `board_items` tables com RLS, RPCs (`list_board_items`, `move_board_item`, `list_project_boards`). |
| W7.6 | Volunteer Applications Schema | High | Done | Migration: `volunteer_applications` table com RLS admin-only + `volunteer_funnel_summary` RPC. |

### Wave 7 Audit Results (2026-03-11)
- **Data totals**: 119 board items, 67 calendar events, 143 volunteer applications, 51 Miro links
- **RPC health**: `list_project_boards` (5 boards), `list_board_items` (OK), `volunteer_funnel_summary` (3 cycles)
- **Build**: clean | **Tests**: 13/13 | **Routes**: 16/16 → 200 | **Migrations**: 39/39 applied
- **Member matching**: 134 entries loaded, 92/143 volunteer apps matched (64%), Trello member match by name
- **Top certifications**: PMP (59), DASM (9), PMI-RMP (5), PMI-CPMAI (5)
- **Geographic spread**: MG (27), CE (20), GO (20), DF (16), 8 US-based, 2 Portugal

---

## WAVE 8: Reusable Kanban & UX Architecture — CONCLUIDA
**Foco:** Boards por tribo, analytics de processo seletivo, progressive disclosure tier-aware, legacy cleanup.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W8.1 | Universal Kanban Component | Low | Deferred | Refator para componente reutilizavel deferido ate segundo consumidor existir (tribo board reutiliza padrao visual). |
| W8.2 | Tribe Project Boards | High | Done | Aba "Quadro de Projeto" em `/tribe/[id]` com Kanban 5 colunas (backlog/todo/in_progress/review/done), drag-and-drop, create board. RPCs: `list_project_boards`, `list_board_items`, `move_board_item`. |
| W8.3 | Selection Process Analytics | High | Done | 4 graficos Chart.js na `/admin/analytics`: funil por ciclo, certs horizontais, geo treemap, snapshot diff Ciclo 3. Chama `volunteer_funnel_summary` RPC. |
| W8.4 | Tier-Aware Progressive Disclosure | Medium | Done | `getItemAccessibility()` retorna `{visible, enabled, requiredTier}`. Nav items desabilitados com opacity + lock icon + tooltip "Requer [tier]". LGPD-sensitive items permanecem ocultos. |
| W8.5 | Legacy Role Column Hard Drop | High | Done | Migration `20260312020000`: drop `role`, `roles` columns e `sync_legacy_role_columns` trigger. Frontend 100% em `operational_role` + `designations`. |

### Wave 8 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 13/13 | **Migrations**: 40/40
- **New features**: Tribe project boards (Kanban), Selection analytics (4 charts), Progressive disclosure (lock icons)
- **Tech debt resolved**: Legacy `role`/`roles` columns dropped, PostHog/Looker references superseded
- **Architecture**: `NavItem.lgpdSensitive` flag added, `ItemAccessibility` interface exported

---

## WAVE 9: Intelligence & Governance — PENDENTE
**Foco:** Frontend processo seletivo, journal de governanca, busca semantica, dashboards cross-source.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W9.1 | Selection Process Frontend | High | Planned | Pagina `/admin/selection` com import CSV, lista candidatos, comparacao snapshots. |
| W9.2 | Governance Change Request Journal | Medium | Planned | Frontend `/admin/governance` com CRUD de change requests e workflow de aprovacao. |
| W9.3 | Busca Semantica (Embeddings) | Low | Planned | pgvector sobre `artifacts`, `hub_resources`, `board_items`. Herdado de S-KNW6. |
| W9.4 | Cross-Source Analytics Dashboards | Medium | Planned | Visao unificada: volunteer pipeline + Kanban + comms + attendance + gamification. |

---

## WAVE 10: Scale, Multi Tenant & Global Impact — PENDENTE
**Foco:** Preparar o projeto para ser replicavel e internacionalizavel.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| S-RM5 | Multi-tenant Config | Medium | Planned | Admin config for `group_term`, cycle config, and webhooks. |
| S23 | Chapter Integrations | Medium | Planned | Event-driven integrations with local chapter portfolios and tools. |
| S24 | API for Chapters | Low | Planned | Read-only API for chapter impact and participation data. |
| S-SC1 | Multilingual Screenshots | Low | Planned | Automated screenshots for PT EN ES docs or release snapshots. |
| S-KNW7 | Gemini Extraction Pipeline | Low | Deferred | Extrair conteudo de `.docx` em `needs_extraction/` via Gemini API. |

---

## TECHNICAL DEBT & DEVOPS

| Issue | Impact | Status | Mitigation Plan |
|-------|--------|--------|-----------------|
| README History Lost | High | Addressed | Restored in docs refresh. |
| No Release Log | High | Addressed | `docs/RELEASE_LOG.md` mantido ativamente. |
| Semantic Versioning Missing | Medium | Open | Create automated release workflow and tags later. |
| No Security Scanning | High | Done | Dependabot + CodeQL habilitados. |
| Hardcoded strings | Medium | Done | i18n migration complete (400+ keys PT/EN/ES). |
| Legacy role columns | High | Done | `role`/`roles` dropped in Wave 8 (migration `20260312020000`). Frontend 100% on `operational_role`/`designations`. |
| PostHog/Looker dashboards | Medium | Superseded | Native Chart.js analytics replaced external iframes (S-AN1 + W8.3). |
| S-AN1 Rich Editor | Low | Open | Rich text editor (TipTap/Quill) para corpo de avisos. |
| S-AN1 Scheduling UX | Low | Open | Interface para agendar inicio/fim de exibicao dos avisos. |

---

## DATA / ARCHITECTURE FOUNDATIONS

### Approved architectural direction

- `members` is the current snapshot for identity, contact, auth, and current state.
- `member_cycle_history` is the historical fact table for role, tribe, and cycle participation.
- `operational_role` and `designations` are the target fields.
- `role` and `roles` have been dropped (Wave 8, migration `20260312020000`).
- The Hub remains the only source of truth for gamification and operational metrics.
- `DATA_INGESTION_POLICY.md` governs all ETL operations (sensitive data never uploaded).

### Required next technical steps

- [x] Complete frontend reads from `operational_role` and `designations`.
- [x] Render cycle history timeline from `member_cycle_history`.
- [x] Add and validate `deputy_manager` visual treatment and ordering rules.
- [x] Define hard drop window for `role` and `roles`.
- [x] Consent-aware analytics instrumentation without leaking PII.
- [x] Execute hard drop of `role` and `roles` columns (Wave 8, migration `20260312020000`).
- [x] Provision production analytics (PostHog/Looker superseded by native Chart.js — S-AN1 + W8.3).

---

## ANALYTICS GOVERNANCE

### Internal product analytics
Native Chart.js dashboards powered by Supabase RPCs:
- **Executive panel**: `exec_funnel_summary` (member engagement), `exec_skills_radar` (tribe comparison), `exec_cert_timeline` (cert progression)
- **Selection process**: `volunteer_funnel_summary` (cycle funnel, certs, geography) — LGPD admin-only
- **Communications**: Comms metrics bar charts in `/admin/comms`
- PostHog iframes **superseded** by native charts (S-AN1, Wave 8)

### Required analytics rules
- use `member_id` or at most `operational_role`
- do not send email or full name unless strictly required
- selection process data (`volunteer_applications`) restricted to admin tier via RLS + RPC guard
- maintain operational delete path for right to be forgotten
- restrict `/admin/analytics` by tier
- `lgpdSensitive` nav items remain fully hidden for non-authorized users

### External communication metrics
Native Supabase-based comms metrics replaced external Looker dependency. YouTube/LinkedIn/Instagram metrics managed via `comms_metrics` table and admin dashboard.

---

## PRODUCTION STATE SUMMARY (2026-03-11)

### Infrastructure
- **Git**: `origin/main` and `production/main` 100% synchronized
- **SQL Migrations**: 40/40 applied in production (Supabase) — Wave 7 data, Wave 8 schema cleanup
- **Edge Functions**: 13 active in production (all `--no-verify-jwt`)
- **Frontend**: Deployed via Cloudflare Pages (auto-deploy from main)
- **Storage**: `documents` bucket active with public read + authenticated upload

### Data Ingestion Scripts (Wave 7) — Executed 2026-03-11
- `scripts/trello_board_importer.ts`: 5 boards → 119 cards in `project_boards` + `board_items`
- `scripts/calendar_event_importer.ts`: ICS → 67 events in `events` (source=calendar_import)
- `scripts/volunteer_csv_importer.ts`: 6 CSVs → 143 applications in `volunteer_applications` (92 matched)
- `scripts/miro_links_importer.ts`: CSV → 51 links in `hub_resources` (source=miro_import)

### Navigation (`navigation.config.ts`)
- 19 items covering all routes with tier-based ACL
- Home anchors (10), Tools (5), Member (2), Profile (1), Admin (5)
- Progressive disclosure: disabled items with lock icon + tooltip for insufficient tier
- LGPD-sensitive items fully hidden for non-authorized (new `lgpdSensitive` flag)
- No orphan routes (legacy aliases `/teams`, `/rank`, `/ranks` are intentional redirects)

### Schema Changes (Wave 8)
- Dropped `role`, `roles` columns and `trg_sync_legacy_role` trigger from `members`
- New `NavItem.lgpdSensitive` flag and `ItemAccessibility` interface in `navigation.config.ts`

### Documentation
- `docs/RELEASE_LOG.md`: Up to date (2026-03-11)
- `docs/PERMISSIONS_MATRIX.md`: Up to date (2026-03-10)
- `backlog-wave-planning-updated.md`: This file — synchronized

---

## Notes for the dev team

This backlog now reflects the actual state of production. All items marked Done have been verified against deployed code, applied migrations, and active Edge Functions. Items marked "Planned" are genuine future work with no code in the repository.
