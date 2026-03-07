# Núcleo IA & GP — Backlog & Wave Planning
## Status: Março 2026
## Atualizado após estabilização de produção, revisão documental e alinhamento produto engenharia

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
| S-HF5 | Data Patch Follow Through | High | Open | Apply and verify specific cleanup patches such as Sarah LinkedIn restoration, Roberto role correction, and Deputy PM hierarchy adjustment. |

---

## 🌊 WAVE 3: Profile, Gamification & UX Excellence
**Foco:** Retenção de voluntários, UX impecável e inteligência de uso.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| S-RM2 | Completeness Bar & Timeline | High | Partial | Adaptive completeness bar and “Minha Jornada” timeline using cycle aware history. |
| S-RM3 | Gamification v2 | High | Partial | Lifetime XP, levels, achievements, and distinction between current cycle vs lifetime progress. |
| S-PA1 | Product Analytics | High | Planned | PostHog setup with authenticated tracking via Supabase UUID and protected iframe dashboards in `/admin/analytics`. |
| S8b | i18n Internal Pages | Medium | Partial | Apply i18n keys to `/admin`, `/attendance`, and modals. |
| S11 | UI Polish & Empty States | Medium | Partial | 404 page, loading states, actionable empty states, and graceful fallback content. |

---

## 🌊 WAVE 4: Admin Tiers, Integrations & Comms
**Foco:** Reduzir atrito do GP e melhorar comunicação e governança operacional.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| S-RM4 | Admin Tiers (ACL) | High | Partial | Implement access control tiers such as Superadmin, Admin, Leader, Observer across routes and RLS. |
| S-REP1 | Exportação VRMS (PMI) | High | Partial | CSV mastigado no `/admin` para Horas de Impacto e reporte PMI. |
| S10 | Credly Auto Sync | Medium | Planned | Edge Function or cron to auto sync badges weekly. |
| S-AN1 | Announcements System | Medium | Planned | Global banners and notifications at top of site. |
| S-DR1 | Disaster Recovery Doc | Low | Planned | POP de restauração de backup e PITR. |
| S-COM6 | Dashboard Central de Mídia | Medium | Planned | Looker Studio dashboard using YouTube native connector and LinkedIn/Instagram via Sheets automation, embedded in admin communications route. |

---

## 🌊 WAVE 5: The Knowledge Hub
**Foco:** Polinização cruzada de conhecimento, visibilidade entre tribos e acúmulo de patrimônio intelectual.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| S-KNW1 | Repositório Central de Recursos | Medium | Planned | Create `knowledge_assets` table for courses, references, webinars, linked to `tribe_id` and author. |
| S-KNW2 | Tribe Workspace | Medium | Planned | Create `/workspace` with relational views of artifacts in progress, studies, and events across tribes. |
| S-KNW3 | Sistema de Tags e Relações | Medium | Planned | Link final artifacts to upstream courses, studies, or events to preserve traceability. |
| S-KNW4 | Views Relacionais Governadas | Medium | Planned | Gallery board style views powered by Supabase data model and RLS, not external knowledge software. |

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
| No Security Scanning | High | Open | Enable Dependabot and CodeQL in GitHub. |
| Hardcoded strings | Medium | Open | Continue i18n first migration. |
| Legacy role columns still alive | High | Partial | Finish frontend migration to `operational_role` and `designations`, then hard drop `role` and `roles`. |
| Architectural guideline drift | High | Open | Enforce role model v3, cycle aware data, soft delete, and event driven integration discipline. |
| Route compatibility not tested | High | Open | Add smoke tests and deploy checklist. |

---

## 🧱 DATA / ARCHITECTURE FOUNDATIONS

### Approved architectural direction

- `members` is the current snapshot for identity, contact, auth, and current state.
- `member_cycle_history` is the historical fact table for role, tribe, and cycle participation.
- `operational_role` and `designations` are the target fields.
- `role` and `roles` are tolerated only during migration.
- The Hub remains the only source of truth for gamification and operational metrics.

### Required next technical steps

- [ ] Complete frontend reads from `operational_role` and `designations`.
- [ ] Render cycle history timeline from `member_cycle_history`.
- [ ] Add and validate `deputy_manager` visual treatment and ordering rules.
- [ ] Define hard drop window for `role` and `roles`.
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
1. Credly mobile paste fix  
2. Rank and gamification alignment with tier scoring  
3. Deputy PM hierarchy validation  
4. Smoke test routes and direct navigation  

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
