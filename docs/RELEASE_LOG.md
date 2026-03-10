# Release Log

## 2026-03-11 — v0.9.0 Wave 11: Doc Hygiene, Site Config & S-AN1 Closure

### Scope
Wave 11 corrects documentation staleness, adds site hierarchy checkpoint to sprint closure, delivers S-RM5 site config (multi-tenant base), and closes S-AN1 Rich Editor as partial.

### Doc Hygiene
- **Backlog**: Tech debt S-AN1 Scheduling UX → Done (W10.4); S-AN1 Rich Editor → Partial (markdown preview W10.5). LATEST UPDATE updated for Waves 9-10.
- **AGENTS.md**: Migrations count 40+ → 41 applied.
- **PERMISSIONS_MATRIX**: Date 2026-03-10 → 2026-03-11 in backlog Production State.
- **SPRINT_IMPLEMENTATION_PRACTICES**: Site hierarchy checkpoint added to Phase 2 Audit.

### S-RM5 Site Config
- **Migration** `20260312040000_site_config.sql`: Table `site_config` (key, value JSONB, updated_at, updated_by). RLS: admin read, superadmin write.
- **RPCs**: `get_site_config()` (admin+), `set_site_config(p_key, p_value)` (superadmin only).
- **Page**: `/admin/settings` — fields group_term, cycle_default, webhook_url. Superadmin only.
- **Nav**: `admin-settings` in navigation.config.ts, AdminNav.astro, Nav.astro (minTier: superadmin).
- **PERMISSIONS_MATRIX**: Section 3.16 Site Config.

### Files Changed
- `supabase/migrations/20260312040000_site_config.sql` (new)
- `src/pages/admin/settings.astro` (new)
- `src/lib/navigation.config.ts` (admin-settings)
- `src/components/nav/AdminNav.astro` (settings link)
- `src/components/nav/Nav.astro` (admin-settings icon, adminSettings i18n)
- `src/lib/admin/constants.ts` (admin_settings in AdminRouteKey, ROUTE_MIN_TIER)
- `src/i18n/pt-BR.ts`, `en-US.ts`, `es-LATAM.ts` (nav.adminSettings)
- `backlog-wave-planning-updated.md` (doc hygiene, Wave 11 CONCLUIDA)
- `AGENTS.md` (migrations 41)
- `docs/PERMISSIONS_MATRIX.md` (3.16, admin-settings in code mapping)
- `docs/project-governance/SPRINT_IMPLEMENTATION_PRACTICES.md` (site hierarchy checkpoint)
- `docs/GOVERNANCE_CHANGELOG.md` (Wave 11 decisions)
- `docs/RELEASE_LOG.md` (this entry)

### Audit Results
- Build: clean | Tests: 13/13 | Migrations: 42/42

---

## 2026-03-11 — v0.8.0 Wave 10: Site-Hierarchy Integrity & UX Polish

### Scope
Wave 10 fixes site-hierarchy gaps (missing nav entries), updates PERMISSIONS_MATRIX, and delivers announcement scheduling UX plus markdown preview.

### Site-Hierarchy Fixes
- **Admin Analytics Nav**: Added `admin-analytics` to navigation.config.ts, AdminNav.astro (between panel and comms), Nav.astro drawer icons, i18n keys.
- **Admin Curatorship Route Key**: Added `admin_curatorship` to AdminRouteKey type and ROUTE_MIN_TIER (observer) in constants.ts.

### PERMISSIONS_MATRIX
- Sections 3.13 (Tribe Project Boards), 3.14 (Selection Process LGPD), 3.15 (Progressive Disclosure).
- Code mapping table updated with admin-curatorship, admin-selection, admin-analytics.

### Announcement UX (S-AN1)
- **Scheduling**: Date-time pickers for `starts_at` and `ends_at`; validation that start < end; "Agendado" badge when `starts_at` is in the future.
- **Markdown Preview**: Toggle Editar/Visualizar for message body; textarea + inline preview with **bold**, *italic*, `code`, and line breaks.

### Files Changed
- `src/lib/navigation.config.ts` (admin-analytics nav item)
- `src/components/nav/AdminNav.astro` (analytics link)
- `src/components/nav/Nav.astro` (admin-analytics icon, adminAnalytics i18n)
- `src/lib/admin/constants.ts` (admin_curatorship route key)
- `src/pages/admin/index.astro` (announcement scheduling, markdown preview)
- `src/i18n/pt-BR.ts`, `en-US.ts`, `es-LATAM.ts` (labelStarts, statusScheduled, previewToggle, editToggle)
- `docs/PERMISSIONS_MATRIX.md` (Wave 8-9-10 sections)
- `backlog-wave-planning-updated.md` (Wave 10 CONCLUIDA)

### Audit Results
- Build: clean | Tests: 13/13 | Lint: 0 errors

---

## 2026-03-11 — v0.7.0 Wave 9: Intelligence & Cross-Source Analytics

### Scope
Wave 9 delivers the Selection Process frontend, cross-source analytics dashboard, and comprehensive documentation reform including the formalized 5-phase sprint closure routine.

### New Pages
- **`/admin/selection`**: Full Selection Process management page with cycle filter tabs (All/C1/C2/C3), KPI summary cards, paginated searchable applicant table (LGPD admin-only), Ciclo 3 snapshot comparison, and CSV import guide. Powered by new `list_volunteer_applications` RPC.

### New RPCs (migration `20260312030000`)
- `list_volunteer_applications(p_cycle, p_search, p_limit, p_offset)`: Paginated, searchable volunteer applications list with member match info. Admin-only permission check.
- `platform_activity_summary()`: Cross-source analytics aggregating members, artifacts, events, boards, comms, volunteer apps, and monthly activity timeline. Admin-only.

### Analytics Enhancements
- **Cross-source "Visao Geral da Plataforma"** section in `/admin/analytics`: 6 KPI cards, platform health doughnut (member data completeness), activity timeline line chart (events/artifacts/broadcasts per month over 6 months).

### Documentation Reform
- **AGENTS.md**: Full refresh -- role model convention updated (dropped, not transitional), analytics convention fixed (Chart.js native, not PostHog iframes), blocked agents section removed, sprint closure routine added, Quick Reference and "Where key things live" updated with scripts/ and data/ folders.
- **SPRINT_IMPLEMENTATION_PRACTICES.md**: 5-phase sprint closure routine formalized (Execute, Audit, Fix, Docs, Deploy) with detailed checklists per phase.
- **DEPLOY_CHECKLIST.md**: PostHog/Looker dashboard URLs marked as superseded.

### Navigation
- New `admin-selection` nav item with `lgpdSensitive: true` in navigation.config.ts
- AdminNav.astro updated with selection link
- i18n keys added for PT-BR, EN-US, ES-LATAM

### Files Changed
- `src/pages/admin/selection.astro` (new)
- `src/pages/admin/analytics.astro` (cross-source dashboard)
- `src/lib/admin/constants.ts` (admin_selection route key)
- `src/lib/navigation.config.ts` (admin-selection nav item)
- `src/components/nav/AdminNav.astro` (selection link)
- `src/components/nav/Nav.astro` (selection drawer icon + i18n key)
- `src/i18n/pt-BR.ts`, `src/i18n/en-US.ts`, `src/i18n/es-LATAM.ts` (nav.adminSelection)
- `supabase/migrations/20260312030000_list_volunteer_applications_rpc.sql` (new)
- `AGENTS.md` (reformed)
- `docs/project-governance/SPRINT_IMPLEMENTATION_PRACTICES.md` (5-phase routine)
- `docs/DEPLOY_CHECKLIST.md` (PostHog/Looker superseded)
- `backlog-wave-planning-updated.md` (Wave 9 CONCLUIDA)
- `docs/RELEASE_LOG.md` (this entry)
- `docs/GOVERNANCE_CHANGELOG.md` (Wave 9 decisions)

### Audit Results
- Build: clean | Tests: 13/13 | Lint: 0 errors | Migrations: 41/41

---

## 2026-03-11 — v0.6.0 Wave 8: Reusable Kanban & UX Architecture

### Scope
Wave 8 delivers tribe project boards, selection process analytics, tier-aware progressive disclosure, and legacy schema cleanup. Closes all high-priority items from the reorganized backlog.

### New Features
- **Tribe Project Boards (W8.2)**: New "Quadro de Projeto" tab in `/tribe/[id]` with 5-column Kanban (backlog, todo, in_progress, review, done), HTML5 drag-and-drop for leaders, create-board for empty tribes. Powered by `list_project_boards`, `list_board_items`, `move_board_item` RPCs.
- **Selection Process Analytics (W8.3)**: 4 new Chart.js charts in `/admin/analytics`: cycle funnel (grouped bars), certification distribution (horizontal bars), geographic treemap, Ciclo 3 snapshot comparison. Calls `volunteer_funnel_summary` RPC. Admin-only (LGPD).
- **Tier-Aware Progressive Disclosure (W8.4)**: New `getItemAccessibility()` function returns `{visible, enabled, requiredTier}`. Nav items for insufficient tiers show as disabled with lock icon, opacity, and tooltip. LGPD-sensitive items fully hidden via `lgpdSensitive` flag. Applied to both desktop nav, mobile menu, and profile drawer.

### Schema Changes
- **Migration `20260312020000_drop_legacy_role_columns.sql`**: Drops `role`, `roles` columns and `trg_sync_legacy_role` trigger from `members` table. Frontend fully migrated to `operational_role` + `designations`.

### Architecture Changes
- `NavItem` interface: added `lgpdSensitive?: boolean` property
- New `ItemAccessibility` interface exported from `navigation.config.ts`
- New `getItemAccessibility()` function (backward-compatible, `isItemVisible` now delegates to it)
- Nav.astro: `getItemAccessClient()` + `TIER_LABELS` for client-side tier name resolution

### Tech Debt Resolved
- Legacy `role`/`roles` columns fully dropped (migration + types cleanup)
- PostHog/Looker references in backlog marked as superseded by native Chart.js
- Analytics governance section updated to reflect current native architecture

### Files Changed
- `src/pages/tribe/[id].astro` (board tab + Kanban panel + drag-drop + create board)
- `src/pages/admin/analytics.astro` (4 selection process charts)
- `src/lib/navigation.config.ts` (lgpdSensitive, ItemAccessibility, getItemAccessibility)
- `src/components/nav/Nav.astro` (progressive disclosure rendering)
- `supabase/migrations/20260312020000_drop_legacy_role_columns.sql` (new)
- `backlog-wave-planning-updated.md` (Wave 8 marked CONCLUIDA, tech debt cleaned)
- `docs/RELEASE_LOG.md` (this entry)
- `docs/GOVERNANCE_CHANGELOG.md` (Wave 8 decisions)

### Audit Results
- Build: clean | Tests: 13/13 | Lint: 0 errors | Migrations: 40/40

---

## 2026-03-11 — v0.5.0 Wave 7: Data Ingestion Platform

### Scope
Comprehensive data ingestion sprint to consolidate all decentralized data sources (Trello, Google Calendar, PMI Volunteer CSVs, Miro board) into the platform database as single source of truth. Includes new DB tables, RLS policies, RPCs, and 4 importer scripts.

### New Database Tables
- `project_boards`: Kanban-style project boards for tribes and subprojects (source: manual/trello/notion/miro/planner)
- `board_items`: Cards within project boards with full Kanban workflow (backlog/todo/in_progress/review/done/archived)
- `volunteer_applications`: PMI volunteer application data per cycle/snapshot with LGPD admin-only access

### New Migrations
- `20260312000000_project_boards.sql`: project_boards + board_items tables, RLS, RPCs (list_board_items, move_board_item, list_project_boards), updated trello_import_log constraints
- `20260312010000_volunteer_applications.sql`: volunteer_applications table, RLS (admin-only), volunteer_funnel_summary RPC

### New RPCs
- `list_board_items(p_board_id, p_status)`: Returns board items with assignee info, ordered by position
- `move_board_item(p_item_id, p_new_status, p_position)`: Moves items with permission checks
- `list_project_boards(p_tribe_id)`: Lists active boards with item counts
- `volunteer_funnel_summary(p_cycle)`: Returns analytics by cycle, certifications, and geography

### New Scripts
- `scripts/trello_board_importer.ts`: Parses 5 Trello JSON exports (123 cards total), maps lists to status, labels to tags, Trello members to DB members by name match, inserts into project_boards + board_items, logs to trello_import_log
- `scripts/calendar_event_importer.ts`: Parses Google Calendar ICS export, filters ~30 Nucleo/PMI events, inserts into events table with source=calendar_import and dedup via calendar_event_id
- `scripts/volunteer_csv_importer.ts`: Parses 6 PMI volunteer CSVs (Ciclos 1-3, ~779 rows), cross-references with members by email, stores with cycle + snapshot_date metadata for diff analysis
- `scripts/miro_links_importer.ts`: Parses Miro board CSV (445 lines), extracts categorized links (Videos, Courses, Articles, Books, News), inserts into hub_resources with URL dedup

### Backlog Reconciliation
- Created Wave 7 (Data Ingestion), Wave 8 (Reusable Kanban), Wave 9 (Intelligence & Governance), Wave 10 (Scale)
- S-KNW4 (Views Relacionais) reframed as W8.1+W8.2 (Universal Kanban + Tribe Boards)
- DS-1 (Data Science PMI-CE) absorbed into W8.3 + W9.4
- P3 Trello/Calendar Import accelerated from Wave 6 to Wave 7
- S-KNW5 → W9.4, S-KNW6 → W9.3, S-KNW7 → Deferred to Wave 10

### Files Changed
- `supabase/migrations/20260312000000_project_boards.sql` (new)
- `supabase/migrations/20260312010000_volunteer_applications.sql` (new)
- `scripts/trello_board_importer.ts` (new)
- `scripts/calendar_event_importer.ts` (new)
- `scripts/volunteer_csv_importer.ts` (new)
- `scripts/miro_links_importer.ts` (new)
- `backlog-wave-planning-updated.md` (updated: Wave 7-10 roadmap)
- `docs/RELEASE_LOG.md` (this file)
- `docs/GOVERNANCE_CHANGELOG.md` (updated)

### Execution Results (Production Audit 2026-03-11)

**Trello Import**: 5 boards created, 119/123 cards imported (4 closed skipped)
- Comunicacao Ciclo 3: 17 cards
- Articles (cross-tribe): 28 cards (1 duplicate skipped)
- Artigos ProjectManagement.com: 3 cards
- Tribo 3 Priorizacao: 34 cards (1 closed skipped)
- Midias Sociais: 37 cards (2 closed skipped)
- Board items by status: backlog (43), done (27), review (22), todo (18), in_progress (9)

**Calendar Import**: 593 ICS events parsed, 87 Nucleo/PMI-relevant, 67 imported (20 dedup/existing)

**Volunteer Import**: 143/143 rows imported (0 errors)
- Ciclo 1: 8 applications (6 matched to members)
- Ciclo 2: 16 applications (11 matched)
- Ciclo 3: 119 applications (75 matched)
- Overall member match rate: 64% (92/143)
- Top certifications: PMP (59), DASM (9), PMI-RMP (5), PMI-CPMAI (5)
- Geographic: MG (27), CE (20), GO (20), DF (16), US (10), PT (2)

**Miro Import**: 51/51 unique URLs imported into hub_resources
- By section: artigo ciclo 2 (32), noticias (6), cronograma (4), tribo 3 (2), others (7)

**Audit Checklist**: All green
- Build: clean | Tests: 13/13 pass | Routes: 16/16 return 200
- Migrations: 39/39 applied | RPCs: all healthy | Git: clean

### Lessons Learned

1. **CSV row counts mislead**: Multi-line essay answers cause `wc -l` to overcount (779 lines vs 143 actual rows). Always use proper CSV parsers, never line counting.
2. **Calendar keyword filters need both include and exclude lists**: Generic "PMI" matches global conferences. The exclude list (PMI Annual, PMI in Portunol, TED@PMI) correctly filtered noise.
3. **Miro board is asymmetric**: 63% of links came from one section (artigo ciclo 2). The board was being used as an article reference tracker, not a balanced resource library. This insight should inform hub_resources curation.
4. **Member matching by email is reliable; by name is fragile**: Volunteer CSVs match by email (64% hit rate). Trello boards only have usernames (no emails), so name matching is best-effort. Future imports should prioritize email-based matching.
5. **Service role key via CLI is the safest pattern**: Using `npx supabase projects api-keys` avoids storing secrets in .env files.

---

## 2026-03-10 — v0.4.0 Four Options Sprint: Knowledge, Kanban, Onboarding NLP, Analytics 2.0

### Scope
Four parallel feature tracks: Knowledge Hub sanitization and UX, Kanban curatorship board,
onboarding intelligence from WhatsApp NLP analysis, and native Chart.js analytics replacing
external iframe dashboards.

### Changes

**Option 1: Knowledge Hub Sanitization (S-KNW4)**
- Created `scripts/knowledge_file_detective.ts`: scans `data/staging-knowledge/` for orphaned
  presentation files, cross-references with `artifacts` table, outputs JSON report
- `artifacts.astro`: Added category sub-tabs "Artefatos Produzidos" (article, framework, ebook,
  toolkit) vs "Materiais de Referencia" (presentation, video, other)
- `artifacts.astro`: Inline tag edit buttons for leaders/curators on catalog cards, using
  existing `curate_item` RPC with `p_action: 'update_tags'`

**Option 2: Kanban Curatorship Board (S-KNW5)**
- `admin/curatorship.astro`: Full rewrite from flat list to 4-column Kanban board
  (Pendente / Em Revisao / Aprovado / Descartado)
- HTML5 Drag and Drop API for card movement between columns
- New migration: `20260311000000_curatorship_kanban_rpc.sql` with `list_curation_board` RPC
  returning items from both `artifacts` and `hub_resources` across all statuses
- Graceful fallback to `list_pending_curation` if new RPC not yet applied

**Option 3: Onboarding Intelligence (S-OB1)**
- Created `scripts/onboarding_whatsapp_analysis.ts`: parses WhatsApp group export,
  extracts FAQ/pain points via keyword + question detection, timeline analysis,
  sender participation, themed insights
- `onboarding.astro`: Complete redesign with:
  - Progress tracker bar with localStorage persistence
  - 4 phases: Boas-vindas, Configuracao, Integracao, Producao
  - Accordion-style expandable step cards
  - Data-driven tips from WhatsApp analysis insights
  - Smart deadline countdown banner
  - Completion celebration banner

**Option 4: Analytics 2.0 (S-AN1)**
- Installed `chart.js` v4 (~71KB gzip, tree-shaken)
- `admin/index.astro` Analytics tab: Replaced PostHog + Looker iframes with 4 native Chart.js
  panels (Funnel horizontal bar, Radar spider, Impact doughnut, KPI cards)
- `admin/analytics.astro`: Full rewrite with Chart.js charts (funnel bar, radar spider,
  certification timeline line chart) replacing HTML progress bars
- `admin/comms.astro`: Added channel metrics bar chart above existing tables

### Files changed
- `src/pages/artifacts.astro` (category sub-tabs + inline tag editor)
- `src/pages/admin/curatorship.astro` (Kanban rewrite)
- `src/pages/onboarding.astro` (progress tracker redesign)
- `src/pages/admin/analytics.astro` (Chart.js upgrade)
- `src/pages/admin/index.astro` (native charts replacing iframes)
- `src/pages/admin/comms.astro` (channel metrics chart)
- `package.json` + `package-lock.json` (chart.js dependency)
- `backlog-wave-planning-updated.md` (sprint entries)

### Files created
- `scripts/knowledge_file_detective.ts`
- `scripts/onboarding_whatsapp_analysis.ts`
- `supabase/migrations/20260311000000_curatorship_kanban_rpc.sql`

### Migrations
- `20260311000000_curatorship_kanban_rpc.sql`: `list_curation_board(p_status)` RPC

### Validation
- `npm test`: 13/13 passing
- `npm run build`: 0 errors
- Tag: `v0.4.0`

---

## 2026-03-10 — v0.3.0 CPO Production Audit: Profile, Gamification, Nav & IA Hotfixes

### Scope
Six hotfixes and UX adjustments identified during CPO production audit, targeting
profile data persistence, gamification toggle behavior, tribe discovery UX, and
information architecture (help, onboarding, webinars).

### Changes

**S-HF10 — Credly URL Persistence (Profile)**
- `saveSelf()` now preserves existing `credly_url` when the field is not modified
- `verifyCredly()` persists URL via `member_self_update` RPC before invoking the edge function
- Full flow: enter URL, verify, save — URL survives page navigation

**S-HF11 — Gamification Toggle (XP Vitalicio vs Ciclo Atual)**
- `setLeaderboardMode()` made async; calls `ensureLifetimePointsLoaded()` before re-render
- Fixed `bg-transparent` / `bg-navy` toggle conflict on both leaderboard and tribe ranking buttons
- Default view changed from "Ciclo Atual" to "XP Vitalicio" (lifetime)

**S-UX2 — Universal Tribe Visibility**
- Tribe dropdown (desktop, mobile, drawer) now queries ALL tribes (removed `.eq('is_active', true)`)
- Inactive tribes render with `opacity-50`, lock icon, and tooltip "Tribo Fechada"
- Active tribes remain fully interactive with WhatsApp links

**S-IA1 — Help Page Made Public**
- `/admin/help` migrated to `/help` with `minTier: 'member'`
- LGPD/privacy topics hidden client-side for non-admin users
- `/admin/help` returns 301 redirect to `/help`

**S-IA2 — Onboarding Moved to Profile Drawer**
- Removed from main navbar (`section: 'main'`)
- Relocated to profile drawer (`section: 'drawer'`, `group: 'profile'`)
- `requiresAuth: true`, `minTier: 'member'`

**S-IA3 — Admin Webinars Placeholder**
- `admin/webinars.astro` now renders "Em Breve / Módulo em Construção" UI
- Three feature preview cards (live sessions, recordings, certificates)
- Admin-gated access check

### Files changed
- `src/pages/profile.astro` (Credly persistence logic)
- `src/pages/gamification.astro` (toggle fix + default mode)
- `src/components/nav/Nav.astro` (universal tribes + drawer icons)
- `src/components/nav/AdminNav.astro` (help link update)
- `src/lib/navigation.config.ts` (help, onboarding, drawer routing)
- `src/pages/help.astro` (NEW — public help page)
- `src/pages/admin/help.astro` (301 redirect)
- `src/pages/admin/webinars.astro` (coming soon UI)
- `backlog-wave-planning-updated.md` (session log)
- `.gitignore` (consolidated `data/` exclusion)
- `docs/PERMISSIONS_MATRIX.md` (updated matrix + code mapping)
- `docs/GOVERNANCE_CHANGELOG.md` (IA decisions)

### Migrations
None required. All changes are frontend/navigation only.

### Validation
- `npm test`: 13/13 passing
- `npm run build`: 0 errors
- Tag: `v0.3.0`

---

## 2026-03-10 — Data Science: Unified Temporal Conversion KPI + DB Enrichment (1.2 v2)

### Scope
Complete rewrite of conversion analysis using a unified temporal dimension. All VRMS CSV exports (6 files across 3 cycles) and Excel-embedded sheets (4 sheets) are merged into a single timeline per person. For each active member per cycle in Supabase, the script compares their **oldest** VRMS snapshot vs **newest** to detect real membership and chapter conversions.

### Business model clarification (from CPO)
- VRMS opportunity = 1 year (2 semesters). C1 expired end-2025, C2 active until mid-2026, C3 is new.
- C1 member reapplying in C3 = retention success.
- Conversion = person had no PMI membership or no partner chapter at earliest snapshot, but has it at latest snapshot or `pmi_id_verified=true` in DB.

### What was changed
- **`scripts/data_science/1.2_kpi_and_enrichment.ts`** — Full rewrite:
  - **Unified timeline**: 6 CSVs + 4 Excel sheets → 217 records, 71 unique emails, sorted by date per person
  - **Per-cycle analysis**: For each DB member in cycle, find oldest→newest VRMS snapshot, compare membership status
  - **Retention tracking**: C1→C3 and C2→C3 member continuity
  - **Enrichment**: Missing pmi_id, state, name in Supabase recoverable from VRMS

### Results (2026-03-10)

**Ciclo 3 (45 members, 43 with VRMS data):**
- **8 Novos Membros PMI**: Thiago Freire, Erick Oliveira, Ana Carla Cavalcante, Fabricia Maciel, Ricardo Santos (reactivation as Retiree), Gerson Albuquerque Neto, Paulo Alves De Oliveira Junior, Guilherme Matricarde
- **10 Novos Filiados ao Capítulo**: Same 8 above + Rodolfo Santana (had Individual Membership, added PMI-MG) + Jefferson Pinto (had Portugal Chapter, added PMI-DF)
- 2 members without VRMS data (Maria Luiza, Vitor Rodovalho)

**Ciclos 1-2 (3 + 24 members):**
- C1: 3 members, all without VRMS data (pilot members, no CSV exports available)
- C2: 24 members, 13 with VRMS data, 11 without (PMI-CE CSVs pending from CPO)
- 0 conversions detected in available C2 data (all 13 matched members already had membership+chapter at signup)

**Retenção:**
- C1 → C3: 1/3 retained (Vitor Rodovalho)
- C2 → C3: 12/24 continued

**Enrichment (5 actionable updates):**
- Lucas Vasconcelos: pmi_id=9925958, state=CE
- Herlon Sousa: pmi_id=5592639, state=CE, fuller name
- Werley Miranda: pmi_id=6570792, state=GO
- Letícia Vieira: fuller name (LETÍCIA RODRIGUES VIEIRA)
- Guilherme Matricarde: name correction

### Outputs
- `data/ingestion-logs/kpi_cycle3_exact_conversion.json`
- `data/ingestion-logs/kpi_cycle1_2_heuristic_conversion.json`
- `data/ingestion-logs/db_missing_data_enrichment.json`

### How to run
```bash
npx tsx scripts/data_science/1.2_kpi_and_enrichment.ts
```

### Files changed
- `scripts/data_science/1.2_kpi_and_enrichment.ts` (rewritten)

### Pending
- CSVs do capítulo CE para Ciclos 1-2 (CPO fornecerá futuramente)
- Mesma análise será repetida no semestre seguinte para C2→C4

---

## 2026-03-10 — UX Housekeeping: Upload Best Practices & File Validation

### Scope
Educate users on R&D sharing best practices without bureaucratizing the upload flow.

### Admin Knowledge Tab (`/admin/index.astro`)
- **Best Practices Banner**: Amber gradient callout panel above the PDF upload section with 4 rules:
  - Maximum file size: 15 MB per file
  - Compression recommendation (ILovePDF, SmallPDF)
  - Copyright policy: prefer sharing Original Link for protected books/articles
  - Accepted formats: PDF, PPTX, PNG, JPG
- **Expanded file input**: `accept` attribute now includes `.pdf,.pptx,.png,.jpg,.jpeg` (was `.pdf` only)
- **Live validation**: On file selection, validates size (15MB) and type. On violation:
  - Error message appears below input
  - Upload button disabled with `opacity-50` + `cursor-not-allowed`
  - File input cleared automatically
- **Dynamic MIME**: Upload handler resolves content type from extension (was hardcoded `application/pdf`)

### Artifacts Modal (`/artifacts.astro`)
- **Best Practices Callout**: Emerald gradient panel inside the submit/edit modal:
  - Valid artifacts: Frameworks, Tribe Presentations, R&D Summaries, Published Articles
  - Invalid artifacts: Unformatted Word drafts, legacy .doc files, personal notes
  - Tip: Always prefer sharing a link (Google Docs, Drive) instead of uploading
- **New file input**: `type="file"` with same `accept` and 15MB validation as admin
- **Upload integration**: If file is attached, `saveArtifact()` uploads to Supabase Storage
  (`documents` bucket, `knowledge-pdfs/` folder) before creating the artifact record.
  The public URL is automatically set as the artifact's URL.

### i18n
- 13 new keys added to PT-BR, EN-US, ES-LATAM:
  - `upload.bestPractices.*` (title, maxSize, compress, copyright, formats)
  - `upload.validation.*` (tooLarge, invalidType)
  - `upload.label.*` (file, orFile)
  - `artifacts.bestPractices.*` (title, valid, invalid, tip)

### Files changed
- `src/pages/admin/index.astro` (banner HTML + validation JS)
- `src/pages/artifacts.astro` (callout HTML + file input + upload logic)
- `src/i18n/pt-BR.ts`, `en-US.ts`, `es-LATAM.ts` (13 keys each)

### Validation
- `npx astro build` passed with 0 errors
- Committed and pushed to origin/main + production/main

---

## 2026-03-10 — Data Governance & ETL Pipeline (Bulk Knowledge Ingestion)

### Scope
Architect and execute a 3-phase ETL pipeline for ingesting 2 years of Google Drive
historical data (712 files across `geral` and `adm` categories) into the Knowledge Hub,
with strict LGPD compliance and AI safety guardrails.

### ACAO 1: Data Governance Manifest
- Created `docs/project-governance/DATA_INGESTION_POLICY.md` (private, gitignored)
- Establishes rules for:
  - **Data classification**: `sensitive` (never uploaded), `geral` (public knowledge), `adm` (governance)
  - **PII isolation**: VRMS, Excel attendance, WhatsApp exports processed locally only
  - **Mandatory audit trail**: All mutations logged to `broadcast_log` or local logs
  - **Allowed/blocked file types**: Explicit whitelist for Storage uploads

### ACAO 2: 3-Phase ETL Pipeline (`scripts/bulk_knowledge_ingestion/`)

**Phase 1 — `1_prepare_files.ts`**:
- Reads `geral/` and `adm/` folders recursively from `data/raw-drive-exports/`
- SHA-256 hash deduplication (712 files -> unique set)
- Filename sanitization to kebab-case ASCII
- Tag inference from folder paths (e.g., `tribo-0X`, `ciclo-Y`, `meeting_minutes`, `governance`)
- Copies unique files to `data/staging-knowledge/`
- Generates `upload_manifest.json` with metadata, tags, and asset types

**Phase 1.5 — `1.5_curate_manifest.ts`** (AI Safety & Copyright Triage):
- **Markdown quarantine**: `.md`/`.markdown` files removed from upload manifest,
  tagged `raw_notes`, moved to `quarantine_md/`. Prevents "prompt poisoning" of
  downstream LLM pipelines reading the Storage bucket.
- **Docx/Doc isolation**: `.doc`/`.docx` files removed from manifest, moved to
  `needs_extraction/` for future Gemini-assisted content extraction.
- **Copyright flagging**: PDFs > 15MB or with names suggesting external books/articles
  (keywords: "book", "guide", "harvard", etc.) marked `pending_copyright_review`.
- Outputs `upload_manifest_curated.json` with only approved/flagged files.

**Phase 2 — `2_execute_upload.ts`**:
- Reads manifest (supports `--manifest` flag for curated version)
- Uploads to Supabase Storage `documents` bucket
- Inserts records into `hub_resources` with `source='bulk-drive-import'`
- Concurrency control with sleep between batches
- Full audit logging

### .gitignore updates
- `data/raw-drive-exports/`, `data/staging-knowledge/`, `data/ingestion-logs/`
- `docs/project-governance/DATA_INGESTION_POLICY.md`
- `scripts/bulk_knowledge_ingestion/upload_manifest.json`
- `scripts/bulk_knowledge_ingestion/upload_manifest_curated.json`

---


## 2026-03-10 — Sprint 4: UX Avancada e Fecho de Alocacoes

### Scope
Global Tribe Selector dropdown for admins and Allocation Notification system.

### Epic 1: Global Tribe Selector (Cross-Navigation)
- **Before**: Tier 4+ admins without a tribe saw a static "Explorar Tribos" link
  pointing to `/#tribes`. No way to jump directly to a specific tribe dashboard.
- **After**: Interactive dropdown in both desktop nav and mobile drawer:
  - Desktop: Click "Explorar Tribos ▾" to reveal a positioned dropdown listing all
    active tribes with direct `/tribe/{id}` links. Click outside or press Escape to close.
  - Mobile nav: Same dropdown behavior adapted for mobile layout.
  - Profile Drawer: Expandable tribe list with chevron toggle and lazy-loaded tribe data.
  - Regular members (Tier 1-3) continue seeing their personal "Minha Tribo" link.
  - Tribes are fetched once and cached (`_tribesCache`) to avoid redundant queries.
- **Files**: `src/components/nav/Nav.astro`

### Epic 2: Allocation Notification Module
- **Edge Function**: `send-allocation-notify` created with:
  - Dry-run mode: Returns preview of all allocated members grouped by tribe
  - Send mode: Groups members by tribe, sends personalized emails per tribe with:
    - Tribe name and direct portal link (`/tribe/{id}`)
    - WhatsApp group button (green CTA) if tribe has `whatsapp_url`
    - Dynamic GP signature (name, phone, LinkedIn from caller's member record)
  - Sandbox mode: Forces recipient to `vitor.rodovalho@outlook.com` when using test domain
  - All sends logged to `broadcast_log` table
  - Security: Restricted to superadmin/manager/deputy_manager
- **Admin UI** (`/admin/index.astro`):
  - "Notificar Alocacoes" card in Tribes tab (visible when allocated members > 0)
  - Shows member count and tribe count summary
  - "Pre-visualizar" button: Opens confirmation modal with dry-run preview
  - "Notificar Membros" button: Same flow via modal
  - Confirmation modal: Lists all members grouped by tribe with warning banner
  - "Confirmar e Enviar" button with loading state and error handling
- **Files**: `supabase/functions/send-allocation-notify/index.ts`, `src/pages/admin/index.astro`


## 2026-03-10 — Sprint 2+3: Knowledge Hub Tags + Leader Tools Validation

### Scope
Artifact tag filtering (Sprint 2 completion) and validation of existing
deliverable/My Week features (Sprint 3).

### S-KNW3: Artifact Tag Filtering (/artifacts.astro)
- **Before**: No filtering on the artifacts catalog. No tag display. Type filter
  buttons did not exist.
- **After**: Full filtering system with:
  - Text search (debounced 250ms) across title, author name, and tags
  - Type filter chips (article, ebook, framework, presentation, video, toolkit, other)
  - Tribe dropdown filter
  - Taxonomy tag chips (loaded from `list_taxonomy_tags` RPC, color-coded by category)
  - Results counter
  - Tags displayed as colored pills on each artifact card
- **Files**: `src/pages/artifacts.astro`, `src/i18n/pt-BR.ts`, `en-US.ts`, `es-LATAM.ts`

### Sprint 3 Validation: Deliverables Progress Bar
- **Status**: Already implemented in `tribe/[id].astro` (`progressBarHtml()`)
- Green bar (completed %) + blue bar (in_progress %) with counters
- CRUD via `upsert_tribe_deliverable` RPC with proper RLS (superadmin or tribe_leader)
- Status transitions: planned -> in_progress -> completed (with cancel/revert)

### Sprint 3 Validation: My Week (profile.astro)
- **Status**: Already implemented with 4 cards:
  1. Next Meeting (from `tribe_meeting_slots` + `tribes.meeting_link`)
  2. Trail Progress (X/8 courses from `course_progress`)
  3. Pending Deliverables (from `list_tribe_deliverables` filtered by assignee)
  4. Weekly XP (from `gamification_points` last 7 days)
- Full i18n support in PT/EN/ES

### Gate validation
- `npx astro build` passed with 0 errors.
- No new SQL migrations required (tags column already exists on artifacts).

---

## 2026-03-10 — Sprint 1: Trilha de Inteligencia e Gamificacao (Wave 3)

### Scope
Cycle-aware gamification, per-course trail status, and profile XP lifecycle differentiation.

### Backend: Cycle-Aware Leaderboard (Migration 20260310010000)

**Problem**: The `gamification_leaderboard` VIEW aggregated all-time points as `total_points`. Both "Cycle" and "Lifetime" leaderboard modes effectively showed the same data, making the ranking unfair for newcomers in Cycle 3.

**Solution**: Recreated the VIEW with dual aggregation:
- `total_points`: Sum of ALL `gamification_points` rows (lifetime)
- `cycle_points`: Sum filtered by `created_at >= cycles.cycle_start WHERE is_current = true`
- Added per-category cycle breakdowns: `cycle_attendance_points`, `cycle_course_points`, `cycle_artifact_points`, `cycle_bonus_points`

**New RPC `get_member_cycle_xp(p_member_id uuid)`**:
- Returns JSON with `lifetime_points`, `cycle_points`, and per-category cycle breakdown
- Uses `SECURITY DEFINER` with cycle date from `cycles` table
- Consumed by `profile.astro` Dashboard section

### Frontend: Gamification Page

**Leaderboard**:
- Cycle mode now uses `m.cycle_points` (from rebuilt VIEW) instead of `m.total_points`
- Lifetime mode uses `m.total_points` (true lifetime)
- Tribe ranking also uses `cycle_points` for cycle mode

**My Points Tab**:
- Current cycle XP card now reads `cycle_points` from the VIEW
- Category breakdown grid shows per-category totals above transaction list

**Trail Clarity Card (S-UX1)**:
- Replaced paragraph-style course listing with individual course rows
- Each of the 8 PMI AI courses rendered with status icon: checkmark (completed), clock (in-progress), empty circle (pending)
- Direct "Acessar curso" link to PMI e-learning portal per course
- Responsive layout with truncated course names

### Frontend: Profile Page

**Dashboard "Current Cycle" Section**:
- Points card now calls `get_member_cycle_xp` RPC to show cycle-scoped XP
- Lifetime total displayed as secondary label below cycle XP
- Falls back to lifetime total if RPC unavailable

**Timeline with Per-Cycle XP**:
- Each cycle card in the timeline shows XP earned during that period (from previous session)

### Files changed
- `supabase/migrations/20260310010000_cycle_aware_leaderboard.sql` (NEW)
- `src/pages/gamification.astro` (leaderboard, trail, my points, escapeHtml)
- `src/pages/profile.astro` (cycle XP RPC, dashboard display)
- `src/i18n/pt-BR.ts`, `en-US.ts`, `es-LATAM.ts` (trail status + lifetime keys)

### Gate validation
- Migration pushed to production via `supabase db push`
- `npx astro build` passed with 0 errors
- RLS: VIEW reads from `members` + `gamification_points` (existing policies apply)
- RPC uses `SECURITY DEFINER` (safe, no RLS recursion)

---

## 2026-03-09 — Bugfix: LGPD Contact Integration (tribe/[id].astro)

### Scope
QA identified that the LGPD contact data feature in the tribe dashboard
was not reliably displaying member contact information for privileged users.

### Root cause (3 issues)
1. **JSON parse fragility**: The RPC `get_tribe_member_contacts` returns `json` type. Depending on the Supabase JS client version and transport, the `.data` field may arrive as a raw JSON string rather than a parsed object. The original check `typeof cd === 'object'` silently failed for string payloads, leaving `contactData` empty.
2. **Async member resolution race**: When the user session resolves after the initial `boot()` member check (via the `nav:member` CustomEvent), the handler updated `currentMember` but never loaded `contactData` or re-rendered member cards. Superadmins whose session resolved late saw LGPD masks instead of real data.
3. **No re-render path**: Even if `contactData` was eventually populated, there was no mechanism to re-render the member list with the newly available contact information.

### Fix applied
- **Robust JSON parsing**: Added `typeof cd === 'string' ? JSON.parse(cd) : cd` before the object type check.
- **Late-bind contacts in `nav:member` handler**: The event listener now checks whether the newly resolved member has contact privileges. If so, it calls the RPC, populates `contactData`, and re-renders the member list with real email/phone data.
- **Unchanged visual behavior for regular members**: Non-privileged users still see the `***-*** LGPD` mask with the explanatory tooltip.

### Files changed
- `src/pages/tribe/[id].astro` (boot sequence + nav:member handler)

### Backlog addition
- Added "Epico: Seletor Global de Tribos (Cross-Navigation)" to `backlog-wave-planning-updated.md` as a Wave 4 UX item, specifying the Dropdown/Modal pattern for Tier 4+ users navigating between multiple tribes.

---

## 2026-03-09 — Sprint 1: Trilha de Inteligencia e Gamificacao (Wave 3)

### Scope
Enhanced gamification trail visibility, XP lifecycle differentiation,
and profile timeline enrichment with per-cycle XP data.

### S-UX1: Trail Status Consolidated View
- **Before**: Trail clarity card in `/gamification` showed a progress bar and paragraph listing missing/in-progress course names.
- **After**: Each of the 8 PMI AI courses is now rendered individually with status icons (checkmark for completed, clock for in-progress, empty circle for pending), a direct "Acessar curso" link to the PMI e-learning portal, and truncated course names.
- **Files**: `src/pages/gamification.astro`, `src/i18n/pt-BR.ts`, `en-US.ts`, `es-LATAM.ts`

### S-RM3: Lifetime vs Current Cycle XP Differentiation
- **Before**: My Points tab showed lifetime total and current cycle total as text.
- **After**: Added a visual category breakdown grid (attendance, course, artifact, bonus, credly) showing points per category before the individual transaction list.
- **Files**: `src/pages/gamification.astro`

### S-RM2: Profile Timeline with Per-Cycle XP
- **Before**: Profile timeline showed cycle history cards (role, tribe, chapter) but no quantitative data.
- **After**: Each cycle card now displays the XP earned during that cycle period, calculated by date-range filtering gamification_points against cycle boundaries.
- **Files**: `src/pages/profile.astro`

### Gate validation
- `npx astro build` passed with 0 errors.
- No new SQL migrations required.
- All queries use existing authenticated RLS paths.

---

## 2026-03-09 — P3: Knowledge Ingestion Sprint

### Scope
Admin UI for knowledge ingestion (Trello import, Calendar import, PDF upload),
webinar artifact pipeline, and Supabase Storage provisioning.

### P3.1: Trello Board Import
- **Feature**: Added Trello JSON import section to admin Knowledge tab.
- **UI**: File upload for exported Trello board JSON, source selector (C1/C2/C3/Social),
  target table selector (artifacts/hub_resources), Dry Run and Import buttons.
- **Backend**: Uses deployed `import-trello-legacy` Edge Function with admin auth,
  status mapping, cycle inference, and tag defaults.

### P3.2: Google Calendar Import
- **Feature**: Added Calendar event import section to admin Knowledge tab.
- **UI**: JSON textarea for Google Calendar API events, Dry Run and Import buttons.
- **Backend**: Uses deployed `import-calendar-legacy` Edge Function with superadmin auth,
  project keyword filtering, event type inference, and duration calculation.

### P3.3: PDF Upload to Supabase Storage
- **Feature**: Added PDF upload section to admin Knowledge tab.
- **UI**: Title input, type selector (reference/minutes/governance/other), file picker.
- **Backend**: Uploads to Supabase Storage `documents` bucket (`knowledge-pdfs/` folder),
  creates `hub_resources` record with public URL link.
- **Migration**: `20260309220000_storage_documents_bucket.sql` creates `documents` bucket
  with public read, authenticated upload, and admin delete policies.

### P3.4: Webinar Artifact Pipeline
- **Feature**: Added "Artefatos vinculados a Webinars" section to `/admin/webinars`.
- **Logic**: Queries `artifacts` and `hub_resources` with `tags @> ["webinar"]`,
  merges and sorts by date, displays with icons and tag badges.
- **Impact**: Any artifact or resource tagged "webinar" (from Trello import or manual creation)
  now automatically appears in the webinar management dashboard.

---


## 2026-03-09 — Critical Bugfix Sprint + Legacy Asset Ingestion + Presentation Module

### Scope
Production P0 bugfixes, Presentation Module with democratic ACL, legacy asset organization,
and file-system onboarding of governance documents from Cycles 1-3.

### P0 Bugfixes (CRITICAL_BUG_FIX.md)

#### Bug 1: Tribe Counter showing 0/6 for all tribes
- **Root cause**: `count_tribe_slots()` RPC returns JSON with **string** keys (e.g. `"1": 5`)
  but `TRIBE_IDS` array contains **numbers** (`[1,2,3...]`). JavaScript strict-equality lookup
  `tribeCounts[1]` on key `"1"` yields `undefined`, rendering as 0.
- **Fix**: Added `Object.entries(data).forEach()` with `Number(pair[0])` coercion in
  `TribesSection.astro` so numeric `TRIBE_IDS` correctly match the parsed counts.

#### Bug 2: /admin/curatorship forced logout
- **Root cause**: Boot function checked `navGetMember()` synchronously; if Nav.astro hadn't
  fired yet, it fell through to `getSession()` which could fail, showing denied state prematurely.
  No `nav:member` event listener existed (unlike comms.astro pattern).
- **Fix**: Refactored boot to mirror comms.astro: registers `nav:member` listener first,
  then checks cached member, then falls back to session. Denied state now shows the "back to admin"
  link instead of a dead-end.

#### Bug 3: Comms Dashboard "CARREGANDO" infinite
- **Root cause**: When `PUBLIC_LOOKER_COMMS_DASHBOARD_URL` is set (iframe mode), `showPanel()`
  skipped `loadNativeTable()` but never hid the `comms-table-loading` spinner, leaving it spinning forever.
- **Fix**: In `showPanel()`, when mode is iframe, explicitly hide native table loader and show empty state.

### S-PRES1: Presentation Module (Democracy + Data Layers)

#### Governance (ACL)
- Home (/): Toggle visible to admin+ only (Tier 4/5)
- Tribe (/tribe/[id]): Toggle visible to admin+ OR tribe_leader of that specific tribe
- Implemented in shared `PresentationLayer.astro` component

#### Data Layers
- `PresentationLayer.astro`: shared component with ACL-gated toggle, end-session modal
  (recording link, deliberations, publish checkbox), and tribe-context KPI overlays
  (sprint presence + pending deliverables)
- `save_presentation_snapshot` RPC: leader-scoped with `p_tribe_id` guard,
  `deliberations` column, `p_is_published` flag
- `list_meeting_artifacts` RPC: optional `p_tribe_id` filter
- `count_tribe_slots()` RPC: SECURITY DEFINER, bypasses RLS, grants to anon+authenticated

#### UX
- End-presentation modal: recording link, key deliberations (one per line), publish checkbox
- /presentations page: filterable history (All / General / By Tribe)
- i18n: 22 `pres.*` keys in PT/EN/ES

### ACAO ZERO: Legacy Asset Organization
Organized 106 files from ~/Downloads into project structure:
- `public/legacy-assets/governance/` — 6 files (Acordos PMI, Manual, LATAM Award)
- `public/legacy-assets/presentations/` — 3 files (Kickoff PDF/PPTX, Template)
- `public/legacy-assets/infographics/` — 7 files (roadmap/KPI PNGs)
- `public/legacy-assets/logos/` — 10 files (PMI chapter logos)
- `public/legacy-assets/photos/` — 66 files (member photos)
- `public/legacy-assets/roadmap-planning/` — 8 files (product vision docs)
- `data/legacy-imports/calendar/` — 1 file (iCal export)
- `data/legacy-imports/docs/` — 2 files (consolidated analysis, project list)
- `docs/sprints/` — 3 files (CRITICAL_BUG_FIX, UX_GOVERNANCE_REFACTOR, SPRINT_KNOWLEDGE_INGESTION)

### DB Migration Applied
- `20260309200000_presentation_refinements.sql`: count_tribe_slots RPC, deliberations column,
  leader-scoped save_presentation_snapshot, list_meeting_artifacts with tribe filter

### Validation
- `npx astro build` passed
- `supabase db push` confirmed all migrations applied
- All files copied and verified

### Pending (Next Sprint — P2/P3)
- P2: UX Governance Refactor (Minha Tribo for Superadmin, LGPD mask, native analytics charts)
- P3: Knowledge Ingestion (Trello/Calendar import execution, PDF upload, Webinar pipeline)

---

## 2026-03-09 — Wave 4: Governance, Lifecycle & Global Onboarding (Major Release)

### Scope
Complete operational governance toolkit: member lifecycle management, global onboarding broadcast,
legacy data ingestion infrastructure, LGPD hardening, and navigation consolidation.

### S-COM7: Global Onboarding Broadcast Engine
- New Edge Function `send-global-onboarding`: groups active members by tribe, sends BCC onboarding emails
  with Credly tutorial (public URL instructions), login guidance, profile completion steps, and TMO/PMO
  (Tribo 3) alternative for schedule conflicts
- GP signature embedded: Vitor Maia Rodovalho (+1 267-874-8329 / LinkedIn)
- Dry-run mode for pre-send simulation; sandbox mode for Resend test domain
- Management (Tier 3/4) copied on every tribe dispatch

### S-ADM3: Member Lifecycle Management
- 4 SECURITY DEFINER RPCs:
  - `admin_move_member_tribe` — transfer with member_cycle_history log
  - `admin_deactivate_member` — soft-delete with draft email generation
  - `admin_change_tribe_leader` — demote old + promote new + dual history log
  - `admin_deactivate_tribe` — bulk inactivation of all tribe members + draft email
- All mutations require `is_superadmin = true` (Tier 5)
- Every action auto-logs to `member_cycle_history` with: reason, timestamp, actor name
- Admin UI: lifecycle controls in Reports panel (select-based, Superadmin gated)

### S-COM1: Communications Team Integration
- SQL backfill: Mayanna Duarte -> comms_leader; Leticia/Andressa -> comms_member
- TeamSection.astro: recognizes comms_leader/comms_member (backward compat with comms_team)
- Profile.astro: comms designation labels and colors
- RPC hardening: sync-attendance-points and sync-credly-all gated to Tier 4+

### Wave 4 Expansion: Product & UX (Agent 1)
- `/admin/comms`: expanded with Tribe Impact Ranking (RPC), Broadcast History (RPC), native metrics
- `/admin/webinars`: full CRUD for PMI chapter webinar calendar (table + RLS + UI)
- Navigation.config.ts fully integrated into Nav.astro (dynamic rendering by tier/designation)

### Wave 4 Expansion: Data Ingestion (Agent 2)
- Edge Function `import-trello-legacy`: Trello JSON -> artifacts/hub_resources with dedup
- Edge Function `import-calendar-legacy`: Google Calendar -> events with keyword filtering
- `trello_import_log` audit table; extended artifacts/hub_resources with source/tags/trello_card_id
- `docs/WAVE5_KNOWLEDGE_HUB_PLAN.md`: taxonomy, tag system, KPI alignment

### Wave 4 Expansion: Admin Governance (Agent 3)
- `admin_links` table with Tier 4+ RLS; seeded with Pasta Administrativa
- `list_admin_links` RPC; UI in admin Reports panel
- Git hygiene: removed migrations.skip/, .bak files; added patterns to .gitignore

### LGPD & Security (Wave 1-3 Foundation)
- RLS on `members` table with SECURITY DEFINER helpers (get_my_member_record, has_min_tier)
- `public_members` VIEW (no email/phone) used in all non-admin pages
- WhatsApp opt-in (share_whatsapp boolean), peer-to-peer wa.me via RPC
- Email broadcast via Edge Function with BCC (no frontend email exposure)

### Edge Functions Deployed (11 total, all --no-verify-jwt)
| Function | Status | Purpose |
|---|---|---|
| send-tribe-broadcast | ACTIVE | Per-tribe email broadcast |
| send-global-onboarding | ACTIVE | Global onboarding email |
| sync-attendance-points | ACTIVE | Attendance XP sync |
| sync-credly-all | ACTIVE | Bulk Credly badge sync |
| verify-credly | ACTIVE | Individual Credly verification |
| sync-comms-metrics | ACTIVE | Communications KPI ingestion |
| sync-knowledge-insights | ACTIVE | Knowledge hub insights |
| import-trello-legacy | ACTIVE | Trello board data import |
| import-calendar-legacy | ACTIVE | Google Calendar event import |
| get-comms-metrics | ACTIVE | Comms metrics reader |
| sync-knowledge-youtube | ACTIVE | YouTube knowledge sync |

### DB Migrations Applied (this wave)
- `20260309070000` — Admin global access + timelock bypass
- `20260309080000` — Members RLS + public_members VIEW
- `20260309090000` — share_whatsapp column + RPCs
- `20260309100000` — broadcast_log table + RLS
- `20260309110000` — RLS recursion fix (SECURITY DEFINER helpers)
- `20260309120000` — comms_metrics RLS stabilization
- `20260309130000` — Comms designations backfill
- `20260309140000` — Webinars schema + RPC security hardening
- `20260309150000` — Legacy ingestion + admin_links
- `20260309160000` — Member lifecycle RPCs

### Navigation Config (all routes covered)
- Home anchors: agenda, quadrants, tribes, kpis, networking, rules, trail, team, vision, resources
- Tools: workspace, onboarding, artifacts, gamification
- Authenticated: attendance (member+), my-tribe (member+, dynamic)
- Profile: profile (member+, drawer)
- Admin: admin (observer+), analytics (admin+), comms (admin+ or comms designation),
  webinars (admin+), help (leader+)
- Redirect stubs: /rank -> /gamification, /ranks -> /gamification, /teams -> /#team

### Git Hygiene
- Removed `supabase/migrations.skip/` (3 legacy files)
- Added `.bak`, `.skip`, `migrations.skip/` to .gitignore
- No PII in client-facing code; sandbox emails only in server-side Edge Functions

### Validation
- `npm run build` passed
- `supabase db push` confirmed all migrations applied
- All 11 Edge Functions confirmed ACTIVE via `supabase functions list`
- `navigation.config.ts` covers all 17 page routes + 5 admin sub-routes

---


## 2026-03-09 — Tribe Kickoff Readiness (Major Release)

### Scope
Complete platform preparation for tribe operations starting 2026-03-10.

### Features delivered
- **Tribe Dashboard** `/tribe/[id]` — per-tribe view with members, deliverables, resources tabs (PT/EN/ES)
- **Deliverables Tracker** — CRUD modal, status toggle, progress bar in tribe dashboard
- **Researcher Weekly View** — "My Week" summary cards on profile (next meeting, trail progress, pending deliverables, weekly XP)
- **Onboarding Page** `/onboarding` — 8-step checklist for new researchers (PT/EN/ES)
- **Knowledge Hub** `/workspace` — public resource browser from hub_resources DB
- **KPI Section** — live data from kpi_summary() RPC (replaces static values)
- **ResourcesSection** — loads from hub_resources with static fallback
- **Guest UX** — meaningful messages for authenticated non-members across all pages
- **Open-source** — CONTRIBUTING.md, issue templates (bug_report, feature_request)
- **Public artifacts catalog** — accessible to unauthenticated visitors

### Bug fixes
- **TribesSection SSR crash** — variable `t` shadowed i18n function in .map() template; renamed to `tr`; all 12 sections now render
- **Login detection** — `INITIAL_SESSION` event handled in Nav.astro onAuthStateChange
- **Deadline** — formatted from DB `home_schedule.selection_deadline_at` instead of hardcoded i18n string
- **select_tribe** — server-side deadline enforcement, capacity check, tribe_leader block
- **admin_update_member** — PostgREST ambiguity resolved (5-param overload dropped)
- **artifacts** — `author_id` → `member_id` (column didn't exist)
- **attendance i18n** — literal `{t(...)}` strings replaced with define:vars injection

### DB migrations (15 total, 8 new this session)
- `restore_legacy_role_columns` — role/roles + trigger sync
- `admin_update_member_v2` + `_full` + `_ambiguity_fix`
- `cycles_table` — cycles config with seed + RPCs
- `kpi_summary_rpc` — live KPI aggregation
- `select_tribe_deadline_check` — server-side enforcement + deadline extension to 2026-03-14
- `tribe_meeting_slots_complete` — slots for tribes 3,4,6
- `tribe_deliverables` — per-tribe deliverable tracking + RLS
- `deliverable_crud_rpcs` — upsert RPC with auth
- `announcements_tribe_filter` — tribe_id column for targeted announcements

### Code quality
- 42 inline onclick handlers removed (event delegation across all pages)
- ~400+ i18n keys added (PT/EN/ES) — gamification, artifacts, profile, attendance, all sections
- Error handling with try/catch + user feedback on 6 pages
- Dynamic tribe iteration (no hardcoded `for 1..8` loops)
- Zero raw PT strings remaining in client scripts

### New routes
- `/onboarding` (+en, +es)
- `/workspace` (+en, +es)
- `/tribe/[id]` (+en, +es)

### Docs
- `docs/project-governance/PROJECT_ON_TRACK.md`
- `docs/wireframes/WIREFRAME_SPECS.md`
- `AGENTS.md` with agent team structure
- `CONTRIBUTING.md` with dev setup and PR workflow
- `.github/ISSUE_TEMPLATE/` bug_report + feature_request

---

## 2026-03-08 — Fix critical: restore role/roles columns + admin_update_member v2

### Problema
Coluna `role` foi dropada da tabela `members` mas RPCs (`admin_force_tribe_selection`, `admin_update_member`, views) ainda a referenciavam. Resultado: "column role does not exist" ao alocar membro em tribo e ao editar membros.

### Causa raiz
Migração anterior removeu `role`/`roles` sem atualizar todos os RPCs e views que dependiam delas.

### Solução (3 migrations)
1. **20260308222431_restore_legacy_role_columns.sql**: Re-adiciona `role` e `roles` como colunas regulares; backfill via `compute_legacy_role()`/`compute_legacy_roles()`; trigger `trg_sync_legacy_role` mantém em sync com `operational_role`+`designations`.
2. **20260308223000_admin_update_member_v2.sql**: Drop do overload legado `(p_role, p_roles)`; recria `admin_update_member` com params `(p_operational_role, p_designations)`.
3. **20260308223500_admin_update_member_full.sql**: Overload completo para `admin/member/[id]` com `(p_name, p_email, p_operational_role, p_designations, p_chapter, p_tribe_id, p_pmi_id, p_phone, p_linkedin_url, p_current_cycle_active)`.

### Frontend
- Removido `computeLegacyFields` e fallback legado de `admin/index.astro`
- Removido `buildLegacyRolePayload` e fallback legado de `admin/member/[id].astro`

### Validação
- RPC `admin_force_tribe_selection`: retorna "Acesso negado" (auth check) em vez de crash
- RPC `admin_update_member` v2: retorna "Not authenticated" (auth check) em vez de "function not found"
- `npm test` + `npm run build` passando
- Migrations aplicadas via `supabase db push --linked`

---

## 2026-03-08 — Cleanup .gitignore + PROJECT_ON_TRACK doc

### Escopo
- `.gitignore`: ignorar `.astro/data-store.json`, `.cursor/`, scripts ad hoc
- `docs/project-governance/PROJECT_ON_TRACK.md`: auditoria completa DB↔Frontend↔API
- S-HF9 criado no backlog: edge functions ausentes no repo
- Gate de integração adicionado a SPRINT_IMPLEMENTATION_PRACTICES

---

## 2026-03-08 — CI workflow (validação automática de qualidade)

### Problema
Não havia workflow GitHub Actions executando `npm test && npm run build && npm run smoke:routes` em push/PR. A validação era manual, com risco de regressões em main.

### Solução
- `.github/workflows/ci.yml`: roda em `push` e `pull_request` para `main`
- Passos: install → test → build → smoke:routes
- Env placeholder para build (PUBLIC_SUPABASE_*); smoke usa dev server
- `docs/QA_RELEASE_VALIDATION.md` e `SPRINT_IMPLEMENTATION_PRACTICES.md` atualizados

### Recomendação
Configurar branch protection em `main` para exigir que CI passe antes de merge.

---

## 2026-03-08 — S-AUD1 + S-CFG1 (sprints continuidade)

### S-AUD1: TribesSection i18n
- Toast e labels: "Seleção encerrada!", "Tribo lotada!", "LOTADA", "Escolher esta Tribo", etc. → `tribes.*` PT/EN/ES
- TRIBES_MSG injetado via define:vars (sem import no script)
- Entregáveis, Encontros, trailsUnavailable, loading → i18n

### S-CFG1: MAX_SLOTS single source of truth
- `data/tribes.ts` continua como fonte única de MAX_SLOTS (6) e MIN_SLOTS (3)
- `admin/constants.ts` re-exporta MAX_SLOTS de data/tribes
- TribesSection recebe MAX_SLOTS/MIN_SLOTS via define:vars (remove duplicata no script)

---

## 2026-03-08 — Fix: Deadline tribo hardcoded → home_schedule

### Problema
Pesquisador recebeu "Seleção encerrada!" ao tentar escolher tribo. Deadline estava fixa em `2026-03-08T15:00:00Z`, ignorando `home_schedule.selection_deadline_at`.

### Correção
- `src/lib/schedule.ts`: `getSelectionDeadlineIso()` lê `home_schedule.selection_deadline_at`
- Index pages (pt-BR, en, es): fetch deadline no SSR e passam para HeroSection e TribesSection
- TribesSection e HeroSection: usam prop em vez de hardcode; fallback 2030-12-31 se DB vazio
- `docs/HARDCODED_DATA_AUDIT.md`: auditoria de outros pontos de risco (ciclos, MAX_SLOTS, labels)

### Admin
Atualizar `home_schedule.selection_deadline_at` via SQL quando necessário. Se tabela vazia, fallback permite seleção.

---

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
