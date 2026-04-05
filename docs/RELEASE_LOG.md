# Release Log

## 2026-04-02 — v2.9.0: Sprint 12 — 4 Waves, i18n Audit, Volunteer Term, Diversity

### Scope
Addressed all 11 pending CRs across 4 strategic waves, comprehensive i18n audit (63% reduction in hardcoded PT), volunteer term rewrite matching DocuSign template, diversity dashboard, campaign webhook fix.

### Delivered (15 commits)
- **11 CRs addressed** in 4 waves: Governance Engine, Member Lifecycle, Operational Clarity, Strategic Positioning
- **Volunteer term rewrite**: 5 simplified → 12 full DocuSign clauses + LGPD + Lei 9.608 (3 languages)
- **Admin-editable template**: governance_documents.content jsonb (23 keys), DB-first with i18n fallback
- **BoardMembersPanel**: New admin component for per-board member permissions (CR-028)
- **DiversityDashboard**: Mounted as 4th tab in /admin/selection (5 chart dimensions, LGPD-compliant)
- **i18n audit**: 222 new keys (3463→3685), 27 components translated, BoardEngine auto-translate (22 keys → all sub-components)
- **R3 Manual enriched**: §1 research-to-impact chain, §5 attendance rules, §7.2 MCP 15→52, Apêndice B
- **P0 #28 fix**: process_email_webhook counter sync + backfill (50/50 delivered)
- **TMO cleanup**: 10 ghost events deleted, 268 events total
- **Notifications**: 7 tribe leaders (attendance) + 5 sponsors (CR votes)

### Validation
- Health: v2.9.0, 54 tools, native-streamable-http, sdk 1.28.0
- 779 unit tests pass, 0 fail
- Smoke: 11/11
- All 16 demo pages: 200 OK
- EN governance content verified (renders in English)
- Hardcoded PT: 87 → 32 (63% reduction)
- DB: 46 CRs, 33+12 manual sections, 6 gov docs, 449 board items, 955 attendance, 51 members

---

## 2026-03-31 — v2.8.0: MCP Expansion + Knowledge Layer + i18n Audit + Blog SSR

### Scope
Major MCP expansion (29→52 tools), server-side auto-refresh, knowledge layer, 6 AI hosts verified, comprehensive i18n audit, blog SSR for SEO.

### Delivered (30 commits)
- **MCP tools 29 → 52** (+23 tools): full persona coverage (sponsors, comms, GP, liaisons)
- **Auto-refresh**: Server-side JWT renewal via KV-stored refresh_token (30-day TTL). Validated on Manus AI.
- **Knowledge layer**: Dynamic prompt `nucleo-guide` (role-adaptive) + static resource `nucleo://tools/reference`
- **6 AI hosts verified**: Claude.ai, Claude Code, ChatGPT, Perplexity, Cursor, Manus AI
- **i18n audit**: 6 waves, 74 keys added (3428 total), 0 hardcoded PT-BR remaining
- **Blog SSR**: Posts rendered server-side with OG meta tags for SEO/social sharing
- **Data cleanup**: 155 resources reclassified, 83 junk archived, asset_type constraint expanded
- **XP rank**: get_member_cycle_xp returns rank_position + total_ranked
- **Governance**: get_governance_docs + get_manual_section (trilingual)
- **Write tools**: create_board_card accepts board_id, manage_partner (new), first write validated in production
- **Blog post**: full rewrite (3 langs, 52 tools, 6 hosts, auto-refresh, knowledge layer)
- **Fixes**: get_public_impact_data nested aggregate, blog lang keys, admin blog editor, notifications actor_name, announcements ends_at

### Validation
- Health: v2.8.0, 52 tools, native-streamable-http, sdk 1.28.0
- 779 unit tests pass, 0 fail
- Auto-refresh validated >1h on Manus AI
- First write tool (create_board_card) successful in production
- Blog SSR verified via WebFetch (content visible to crawlers)

---

## 2026-03-31 — Sprint 9: Tier 2 MCP Tools + Tooling Upgrades + Docs Sync

### Scope
Add 3 Tier-2 MCP tools, upgrade Supabase CLI and Wrangler, sync all docs.

### Delivered
- **MCP tools 26 → 29** (3 new Tier-2 read tools):
  - `get_operational_alerts` — inactivity, overdue, taxonomy drift alerts (admin/GP)
  - `get_cycle_report` — full cycle report via `exec_cycle_report` (admin/GP)
  - `get_annual_kpis` — annual KPIs targets vs actuals (admin/sponsor)
- **Supabase CLI** 2.75.0 → 2.84.2 (+9 versions)
- **Wrangler** 4.77.0 → 4.78.0
- **MessageChannel polyfill** confirmed no-op (React 19.2.4 + Astro 6.1.1 fix)
- **Docs synced**: all 3 READMEs, CLAUDE.md, AGENTS.md, MCP rules, MCP guide
- **Plugin tracking**: @typescript-eslint/parser stable still `<6.0.0`, eslint-plugin-react still `^9.7`

### Validation
- Health: v2.6.0, 29 tools, native-streamable-http, sdk 1.28.0
- All 3 new tools: HTTP 200, Zod pass, "Not authenticated" (correct)
- `npm test` — 779 pass, 0 fail

---

## 2026-03-30 — Sprint 8b: MCP SDK 1.28.0 Native Transport + Historical Debt Audit

### Scope
Re-evaluate MCP SDK 1.28.0 after full dep upgrade. Audit historical workarounds.

### Delivered

- **1. MCP SDK 1.27.1 → 1.28.0 (native Streamable HTTP)**
  - `WebStandardStreamableHTTPServerTransport` now works on Deno — original failure was caused by old deps + non-Zod schemas, not Deno incompatibility
  - Removed 85 lines of manual SSE wrapping (InMemoryTransport, batch handling, timeout, SSE formatting)
  - Replaced with 15-line native transport handler
  - Supabase officially documents this pattern for Edge Functions
  - Zod pinned to `^3.25` (SDK requires `^3.25 || ^4.0`)

- **2. Historical Workaround Audit**
  - MessageChannel polyfill (`patch-worker-polyfill.mjs`): React 19.2.4 + Astro 6.1.1 no longer produce MessageChannel refs in server chunks — polyfill is now a no-op (kept as safety net)
  - CSRF middleware manual check: Still required — Astro's `checkOrigin` runs before middleware, blocks OAuth/MCP cross-origin POSTs
  - Cross-tribe attendance bug: Already fixed in GC-113b (denominator fix)
  - MCP SDK pin justification: REMOVED — 1.28.0 now works, no more pin needed

### Validation
- Health: v2.5.0, 26 tools, transport: native-streamable-http, sdk: 1.28.0
- Initialize: 200 SSE, protocolVersion 2025-03-26
- tools/list: 26 tools with correct inputSchema
- tool/call: 200, Zod validation passes
- Notification: 202
- GET: 406 (native transport behavior, correct per MCP spec)
- Proxy: 200 SSE through nucleoia.vitormr.dev

---

## 2026-03-30 — Sprint 8: TypeScript 6 + ESLint 10 — Zero Legacy Deps

### Scope
Upgrade the last 2 remaining major dependencies. Platform now runs on latest stable of everything.

### Delivered

- **1. TypeScript 5.9.3 → 6.0.2 (major)**
  - Last JS-based release (TS 7 will be Go-native)
  - ES module interop always enabled, strict mode unconditional
  - `@typescript-eslint/parser` upgraded to 8.57.3-alpha.3 (adds TS6 support: `<6.1.0`)
  - Zero build errors, 779 tests pass

- **2. ESLint 9.39.4 → 10.1.0 (major)**
  - Node.js >= 20.19 required (we run Node 24)
  - eslintrc completely removed (we already use flat config)
  - Config lookup per-file (from CWD before)
  - `@eslint/js` upgraded to 10.0.1
  - `eslint-plugin-react` 7.37.5 via --legacy-peer-deps (awaiting official ESLint 10 peerDep update)
  - `npm run lint:i18n` works, 1 pre-existing `no-empty` (not from upgrade)

### Platform Dependency State
Zero packages outdated. All dependencies on latest stable (or latest alpha where stable blocks).

### Validation
- `npx astro build` — success
- `npm test` — 779 pass, 0 fail
- `npm run lint:i18n` — works (1 pre-existing warning)
- `npm outdated` — clean

---

## 2026-03-30 — Sprint 7: Major Dep Upgrades + 3 New MCP Tools

### Scope
Upgrade 3 major dependencies (lucide-react, recharts, tiptap) and add 3 Tier-1 MCP tools.

### Delivered

- **1. lucide-react 0.577.0 → 1.7.0 (major)**
  - Brand icons removed (not used in project)
  - UMD build removed (already ESM)
  - `aria-hidden` default on icons (accessibility improvement)
  - 14 files import lucide-react — all icons present in v1, zero breakage

- **2. recharts 2.15.4 → 3.8.1 (major)**
  - Internal state management rewrite
  - Dependencies internalized (recharts-scale, react-smooth)
  - 5 files use recharts — all with standard patterns, zero breakage

- **3. @tiptap/* 2.27.2 → 3.21.0 (major)**
  - StarterKit now bundles Link by default — added `link: false` to avoid conflict
  - 1 file affected: `RichTextEditor.tsx`
  - No BubbleMenu/FloatingMenu used — most breaking changes don't apply

- **4. MCP Tools 23 → 26 (3 new Tier-1 read tools)**
  - `get_tribe_dashboard` — full tribe dashboard via `exec_tribe_dashboard` RPC
  - `get_attendance_ranking` — attendance ranking via `get_attendance_panel` RPC
  - `get_portfolio_overview` — executive portfolio via `get_portfolio_dashboard` RPC (admin only)

### Validation
- `npx astro build` — success
- `npm test` — 779 pass, 0 fail
- Health: v2.5.0, 26 tools
- All 3 new tools: HTTP 200, Zod pass
- Workers deployed, EF v31 deployed

---

## 2026-03-29 — Sprint 5: MCP Claude.ai Connector Fix + Dependency Upgrade

### Scope
Fix Claude.ai showing "0 tools" despite OAuth working. Root cause: three transport/schema bugs. Also: safe npm dependency upgrades.

### Delivered

- **1. MCP Tool Schema Fix (root cause #1)**
  - SDK 1.27.1 misidentified plain JSON Schema params as `ToolAnnotations`, leaving `inputSchema.properties` empty
  - Converted all 13 parameterized tools to Zod schemas (`z.string()`, `z.number()`, `z.boolean()`)
  - Added `import { z } from "npm:zod@3"` to Edge Function

- **2. Streamable HTTP GET Handler (root cause #2)**
  - `GET /mcp` was crashing with 500 (tried to JSON.parse a GET request body)
  - Claude.ai sends GET for SSE stream after initialize — the 500 caused it to abort
  - Now returns clean 405 (stateless mode, per MCP spec)

- **3. Workers Proxy SSE Streaming (root cause #3)**
  - Proxy was buffering SSE responses with `await res.text()`, breaking streaming
  - SSE responses (`text/event-stream`) now stream through unbuffered
  - Added `Access-Control-Expose-Headers: Mcp-Session-Id` for CORS

- **4. Safe npm Dependency Upgrades**
  - `@astrojs/cloudflare` 13.1.3 → 13.1.4
  - `@astrojs/react` 5.0.1 → 5.0.2
  - `@sentry/browser` 10.43.0 → 10.46.0
  - `@tailwindcss/vite` + `tailwindcss` 4.2.1 → 4.2.2
  - `@typescript-eslint/parser` 8.57.0 → 8.57.2
  - `astro-eslint-parser` 1.3.0 → 1.4.0

- **5. SDK Upgrade Investigation (documented, not applied)**
  - SDK 1.28.0: `mcp.tool()` API changed to require Zod natively — breaks all 23 tools
  - SDK 1.28.0: `WebStandardStreamableHTTPServerTransport` crashes on Deno runtime
  - Decision: stay on 1.27.1 with manual Streamable HTTP SSE wrapping

### Architecture Decision
- MCP transport: SDK 1.27.1 McpServer + InMemoryTransport + manual SSE wrapping
- Rationale: SDK 1.28.0's native WebStandard transport crashes on Deno; 1.27.1 with Zod schemas + manual SSE is stable
- Protocol version: `2025-03-26` (Streamable HTTP) — negotiated correctly by SDK 1.27.1

### Validation
- `npx astro build` — success
- `npm test` — 779 pass, 0 fail
- Health: `curl .../health` → 200
- Initialize: `curl -X POST .../mcp` → 200 SSE, protocolVersion 2025-03-26
- tools/list: 23 tools with correct `inputSchema.properties`
- GET /mcp: 405 (clean, not 500)
- Claude.ai: 23 tools visible, 5 read tools tested successfully

---

## 2026-03-12 — Sprint N7: data sanitation, branch protection, comms readiness, dark mode completion

### Scope
End-to-end stabilization sprint: data quality, CI hardening, ops documentation, and final dark mode cleanup.

### Delivered

- **1. Data Sanitation** (12 fixes across 4 blocks)
  - Synced `members.tribe_id` from `tribe_selections` — 32 NULL rows backfilled
  - Created `trg_sync_tribe_id` trigger to prevent future drift
  - Fixed Andressa Martins tribe_id (8→2, stale value)
  - Set operational_role for 2 chapter_liaisons + 4 sponsors (was `none`)
  - Deactivated 2 departed members (`current_cycle_active→false`)
  - Reactivated 3 founders (Ivan=sponsor, Roberto=liaison, Sarah=active)
  - Post-sanitation: 0 inconsistencies, 43/67 with tribe_id, 2 active with role=none

- **2. Branch Protection** (GitHub API)
  - Required status checks: `validate` + `browser_guards`
  - Force push to main blocked, branch deletion blocked
  - No PR requirement (bus factor=1), admin bypass enabled
  - Documented in `docs/GITHUB_SETTINGS.md`

- **3. RPC Registry Cleanup**
  - `kpi_summary`: wired to home page KpiSection (live progress indicators)
  - `publish_board_item_from_curation`: reclassified as Internal (called by `submit_curation_review`)
  - 3 RPCs marked Deprecated: `get_curation_cross_board`, `list_webinars`, `platform_activity_summary`

- **4. Comms Migration Readiness**
  - Verified 54 imported items across 5 columns (28 backlog, 2 todo, 3 in_progress, 1 review, 20 done)
  - Team permissions verified: Mayanna (comms_leader), Leticia (comms_member), Andressa (comms_member)
  - Created `board-attachments` storage bucket (5MB, pdf/png/jpg/docx/xlsx/pptx) with RLS policies
  - Documented in `docs/COMMS_MIGRATION_CHECKLIST.md`

- **5. Dark Mode Completion**
  - Migrated final 7 `text-slate-*` / `bg-slate-*` occurrences across 4 files
  - **Zero slate classes remaining** in src/ (.astro + .tsx)
  - Files: selection.astro, KpiBar.astro (4), TeamSection.astro, PresentationLayer.astro

- **6. CI & PostHog Stabilization** (carried from earlier today)
  - Fixed browser_guards CI test (useMemberContext nav:member fallback)
  - Fixed PostHog console errors (safePH wrapper, __SV guard, env var gating)
  - Fixed board columns crash on /tribe/6 (normalize null/string/array)
  - Fixed get_board_members 400 error (photo_url not avatar_url)
  - Fixed CardDetail/CardCreate resilient RPC calls

- **7. KPI Summary Wiring**
  - Home page KpiSection now calls `kpi_summary` RPC
  - Shows live progress below static targets (chapters, articles, webinars, impact hours, cert %)

### Validation
- `npm run build` — success
- `npm test` — 109/109 pass
- `npm run smoke:routes` — all routes 200
- Zero `text-slate-*` remaining
- `npm run lint:i18n` — clean

---

## 2026-03-12 — Sprint N4: dark mode tokens, WCAG contrast, i18n fixes, prod hotfix

### Scope
Sprint N4 focusing on dark mode completeness, accessibility compliance, and production stability.

### Delivered
- **1. Production Hotfix** (`src/lib/supabase.ts`)
  - Restored Supabase anon key fallbacks to unbreak Cloudflare Workers deployment.
  - Audit item #2 had removed hardcoded keys, but CF Pages lacked env vars. Anon keys are public by design (RLS enforces security).
- **2. WCAG Contrast Fix** (`src/styles/theme.css`)
  - Dark mode `--text-muted`: #64748B → #8B9BB5 (~4.6:1 contrast ratio on `--surface-base`), meeting WCAG AA.
- **3. i18n Hardcoded Strings** (3 locale files + 2 components)
  - Added `common.untitled`, `common.confirmAction`, `common.areYouSure` to pt-BR, en-US, es-LATAM.
  - `PublicationsBoardIsland.tsx`: extracted "Sem título" → `UI.untitled`.
  - `ConfirmDialog.astro`: migrated slate colors to CSS vars for dark mode support.
- **4. Dark Mode Token Migration** (3 admin pages, ~132 classes)
  - `admin/comms.astro` (57 slate → 0), `admin/selection.astro` (39 → 1 intentional), `admin/webinars.astro` (36 → 0).
  - Removed redundant `dark:` Tailwind overrides from webinars.astro.
  - Pattern: `text-slate-*` → `text-[var(--text-primary/secondary/muted)]`, `bg-white` → `bg-[var(--surface-card)]`, etc.

### Remaining (incremental)
- ~188 `text-slate-*` across 20 other files (non-critical, can migrate incrementally).
- Mobile responsiveness validation for /workspace, /tribe/[id], drawer at 375px/768px.

### Validation
- `npm run build` — success
- `npm run smoke:routes` — all routes 200, including /workspace, /en/workspace, /es/workspace
- Cloudflare Workers autodeploy triggered via push

---

## 2026-03-15 — feat: implement tribe cockpit and peer-to-peer curation workflow (CXO Fase 2)

### Scope
CXO Task Force Fase 2: Cockpit da Tribo, Motor de Curadoria no Kanban e Super-Kanban de Curadoria.

### Delivered
- **1. Cockpit da Tribo** (`src/pages/tribe/[id].astro`)
  - Abas reduzidas a: Geral, Kanban, Membros.
  - Aba Geral com seção "🌐 Radar Global": próximos webinars e últimas publicações globais (RPC `list_radar_global`).
- **2. Motor de Curadoria no Kanban** (`TribeKanbanIsland.tsx`)
  - Status de curadoria: draft → peer_review → leader_review → curation_pending → published.
  - Autor: botão "Solicitar Revisão" com Popover Radix para selecionar revisor.
  - Peer: botão "Aprovar (Peer)" quando é o revisor designado.
  - Líder: botão "Aprovar para Curadoria" para enviar a `curation_pending`.
  - Drag-and-drop entre lanes para transições permitidas; reordenação dentro da lane.
- **3. Super-Kanban de Curadoria** (`/admin/curatorship`)
  - Novo componente `CuratorshipBoardIsland.tsx` (dnd-kit).
  - Lista exclusivamente itens `curation_pending` de todas as tribos via RPC `list_curation_pending_board_items`.
  - Coluna "Publicado": drag-and-drop dispara `publish_board_item_from_curation` → item aparece em `/publications`.
- **4. Migration e RPCs**
  - `20260315000007_curation_workflow_board_items.sql`: `reviewer_id`, `curation_status` em `board_items`; RPCs `advance_board_item_curation`, `list_curation_pending_board_items`, `publish_board_item_from_curation`, `list_radar_global`.
- **5. Dependência**
  - `@radix-ui/react-popover` instalada para o seletor de revisor.

### Validation
- `supabase db push`
- `npm run build`
- `npm test`

---

## 2026-03-15 — fix: aggressive rename to bypass cloudflare fs cache issues

### Scope
Build Cloudflare continuou falhando com ENOENT em `board-governance.astro` mesmo após fix de case-sensitivity. Purga completa: ficheiro removido, nova página `governance-v2.astro` criada com nome totalmente novo para evitar conflitos de cache do sistema de ficheiros no Linux.

### Delivered
- **board-governance.astro**: eliminado fisicamente.
- **governance-v2.astro**: nova página com a mesma funcionalidade em `/admin/governance-v2`.
- **navigation.config.ts**: item `admin-governance-v2` com href `/admin/governance-v2`.
- **Nav.astro, scripts, testes, PERMISSIONS_MATRIX.md**: todas as referências atualizadas.

### Validation
- `npm run build` — sucesso local
- `npm test` — sucesso

---

## 2026-03-15 — fix: resolve board-governance ENOENT blocking Cloudflare build

### Scope
Incidente crítico: build falhando no Cloudflare com ENOENT em `board-governance.astro`. Correção de pathing e verificação pré-build.

### Delivered
- **board-governance.astro**: arquivo verificado no Git (lowercase), comentário de rota adicionado.
- **scripts/verify-build-pages.mjs**: verificação pré-build para garantir presença de páginas críticas antes do Astro.
- **package.json**: hook `prebuild` para falhar cedo com mensagem clara se arquivos faltando.
- **Auditoria**: Migrations 20260315000003, 20260315000004, 20260315000005 confirmadas aplicadas no Supabase remoto.
- **Pauta**: index.astro não renderiza AgendaSection; apenas i18n e componente órfão restam (não usados na home).

### Validation captured
- `supabase migration list --linked` — todas aplicadas
- `npm run build` — sucesso local

---

## 2026-03-15 — Wire up modern UI, merge legacy data, meeting schedule editor

### Scope
Task Force: conectar TribeKanbanIsland (dnd-kit) como UI única, refatorar Nav com seções Operações/Governança, merge de dados (T4, T6, T8) e editor de horário de reunião.

### Delivered
- **1. Front-end wire-up**
  - Removido todo código Vanilla do Kanban em `tribe/[id].astro`; único board é `TribeKanbanIsland` (React dnd-kit).
  - Tab "Quadro" com i18n (`tribe.boardTab`).
- **2. Nav refatorado**
  - Tribos de Pesquisa: dropdown mostra apenas tribos com `workstream_type = 'research'`.
  - Seção "⚙️ Operações": Hub de Comunicação (`/admin/comms-ops`).
  - Seção "🌍 Governança": Publicações (`/publications`), Portfólio Executivo (`/admin/portfolio`).
  - Links ocultos se usuário não tiver permissão.
- **3. Migration data merge healing**
  - `20260315000005_data_merge_healing.sql`: T4 (Débora) quadro Cultura/Ciclo 2 atrelado; T6 (Fabrício) cards consolidados em um quadro; T8 (Ana) quadro oficial de entregas criado.
- **4. Edição de horário de reunião**
  - Botão lápis ao lado do horário (quando canEdit); modal para editar texto (ex: "Quintas, 19h"); `supabase.from('tribes').update({ meeting_schedule })`.

### Validation captured
- `supabase db push`
- `npm test`
- `npm run build`

---

## 2026-03-15 — Clean-up & God Mode (UX + Data Sanity + Super Admin)

### Scope
Auditoria pós-entrega: limpeza de UX (PAUTA removida, menus sem duplicidade), correção Tribo 8 vs Comms operacional, God Mode para Super Admin (override RLS e UI).

### Delivered
- **1. UX Clean-up**
  - PAUTA removida completamente: item `agenda` excluído de `navigation.config.ts`, `AgendaSection` removido de `index.astro` (pt-BR, en, es).
  - Teste `ui-stabilization` atualizado para não assertar AgendaSection.
- **2. Data Sanity (Tribo 8)**
  - Migration `20260315000003_fix_tribe8_and_comms.sql`: Tribo 8 volta a `workstream_type = 'research'` e nome `Inclusão & Colaboração & Comunicação`; boards de Comms (domain_key = 'communication') desvinculados da tribo 8, passando a `board_scope = 'global'` (operational exige tribe_id por constraint).
- **3. God Mode (Super Admin)**
  - `TribeKanbanIsland`: early return `canEditBoard() → true` quando `member.is_superadmin`.
  - `tribe/[id].astro`: early return em `checkEditPermission()` quando `currentMember.is_superadmin`.
  - Migration `20260315000004_superadmin_god_mode_rls.sql`: políticas RLS em `project_boards` e `board_items` com bypass total para `auth.uid() IN (SELECT auth_id FROM members WHERE is_superadmin = true)`.

### Validation captured
- `supabase db push`
- `npm test`
- `npm run build`

---

## 2026-03-15 — W85-W89 (Operações, Legado, Qualidade)

### Scope
Trilhas paralelas: Track A (Dashboard Comms), Track B (Data Sanity), Track C (E2E + Docs).

### Delivered
- **W85 Dashboard Comms (Track A):**
  - RPC `get_comms_dashboard_metrics()` — filtra `project_boards` com `domain_key = 'communication'`, cruza `board_items` e `tags`;
  - Componente `CommsDashboard.tsx` (Recharts): macro cards, bar chart por status, pie chart por formato;
  - Página `/admin/comms-ops` atualizada para usar o novo dashboard.
- **W86 Data Sanity (Track B):**
  - Migration `20260315000000_legacy_data_sanity.sql`: orfãos em `member_cycle_history`, padronização de `cycle_code`, `legacy_board_url` em `tribes`;
  - Migration `20260315000001_get_comms_dashboard_metrics.sql`.
- **W87 E2E Lifecycle (Track C):**
  - Spec `tests/e2e/user-lifecycle.spec.ts` — fluxo líder: /tribe/1, board tab, card pre-seeded, drag para Done, logout;
  - Script `npm run test:e2e:lifecycle`.
- **W88 Docs:**
  - Atualizado `MIGRATION.md`, `RELEASE_LOG.md`, `PERMISSIONS_MATRIX.md` (Comms Dashboard W85).

### Validation captured
- `supabase db push`
- `npm test`
- `npm run build`
- `npm run test:e2e:lifecycle`

---

## 2026-03-11 — W80-W84 tooling hardening (Radix + Playwright + ESLint i18n gate)

### Scope
Executar a fundação de governança/UX da onda W80-W84 com ferramentas padrão de mercado e bloqueios fail-closed no CI.

### Delivered
- **Fase 1 (infra):**
  - Playwright Test configurado (`@playwright/test`, `playwright.config.ts`);
  - Radix UI adicionado (`@radix-ui/react-dialog`, `@radix-ui/react-dropdown-menu`);
  - ESLint com gate de hardcoded JSX em superfícies críticas (`eslint.config.mjs`, `npm run lint:i18n`).
- **Fase 2 (caminho crítico):**
  - Modal do `TribeKanbanIsland` migrado para Radix Dialog (focus trap + `Esc` nativo);
  - `PublicationsBoardIsland` passou a usar Radix Dropdown para outcome e limpeza de literals em JSX;
  - Spec visual dark mode criada em `tests/visual/dark-mode.spec.ts` com snapshots para `/`, `/tribe/1`, `/admin/portfolio`.
- **Fase 3 (CI/CD):**
  - `ci.yml` atualizado com gate de lint i18n e job `visual_dark_mode`;
  - quality gate passa a depender de `validate + browser_guards + visual_dark_mode`.
- **Hardening adicional de fail-closed:**
  - `/admin/portfolio` ajustado para negar acesso quando contexto auth não resolve no tempo esperado (evita hangs em browser tests anônimos).

### Validation captured
- `npm run lint:i18n`
- `npm run test:visual:dark`
- `npm test`
- `npm run build`

---

## 2026-03-11 — Gap closure W77-W79 (UI executive impact + permissions regression lock)

### Scope
Fechamento de gaps da rodada W77-W79 para aderência 100% ao briefing original de UX gerencial e blindagem de permissões.

### Delivered
- **W79 UI executiva (`/admin/portfolio`)**
  - macro cards de topo: membros ativos, tribos ativas, boards operando, cards atrasados;
  - agrupamento visual em 3 blocos: Pesquisa, Operações e Global;
  - alertas visuais: atrasos em vermelho (`text-red-600 font-bold`) e badge `⚠️` para boards sem cards ativos.
- **W78 publicações**
  - modal de submissão inclui `external_link` e `published_at`;
  - cards na coluna `done` exibem ícone/link externo quando houver publicação efetiva.
- **Persistência backend (event-sourcing mantido)**
  - migration `20260314201000_publications_external_link_and_effective_publish.sql`;
  - `publication_submission_events` recebe colunas `external_link` e `published_at`;
  - RPC `upsert_publication_submission_event` expandida para os novos campos.
- **W77 regressão dedicada**
  - novo teste `tests/permissions-matrix.test.mjs` com perfis simulados (`guest`, `researcher`, `admin/comms/curator`) contra regras do `navigation.config.ts`;
  - `npm test` atualizado para incluir o novo lock.

### Validation captured
- `supabase db push`
- `npm test`
- `npm run build`

---

## 2026-03-11 — W77-W89: Admin governance expansion + portfolio operations

### Scope
Executar o backlog restante (W77-W89) com foco em governança operacional de boards, superfícies executivas/admin e automações de QA.

### Delivered
- **Permissões e navegação (W77):**
  - novas rotas admin: `/admin/comms-ops`, `/admin/portfolio`, `/admin/board-governance`;
  - `navigation.config.ts` + `Nav.astro` + i18n alinhados;
  - auditoria automática: `scripts/audit_permissions_matrix_sync.sh` (`npm run audit:permissions`).
- **Publicações metadata (W78):**
  - `PublicationsBoardIsland` com modal de metadados de submissão PMI;
  - integração RPC: `upsert_publication_submission_event`.
- **Portfólio executivo (W79):**
  - página `src/pages/admin/portfolio.astro` consumindo `exec_portfolio_board_summary`.
- **Taxonomy drift e sanity (W80/W86):**
  - migrations:
    - `20260314195000_board_taxonomy_alerts.sql`
    - `20260314197000_portfolio_data_sanity_v2.sql`
  - RPCs operacionais para detecção de drift e execução de data sanity.
- **Boards arquivados governados (W81):**
  - página `src/pages/admin/board-governance.astro`;
  - migration `20260314196000_archived_board_items_admin_views.sql`;
  - restore via `admin_restore_board_item`.
- **Acessibilidade e QA (W82/W83/W87):**
  - atalhos de teclado no `TribeKanbanIsland` (`Shift + ArrowLeft/ArrowRight`);
  - `scripts/audit_dark_mode_contrast_snapshots.sh` (`npm run audit:dark:contrast`);
  - browser guards cobrindo deny + restore em governança de board.
- **i18n + docs + checkpoint (W84/W88/W89):**
  - chaves i18n novas em PT/EN/ES para nav/admin/publicações;
  - documentação de governança e backlog atualizada para fechamento do checkpoint.

### Validation captured
- `supabase db push`
- `npm run audit:permissions`
- `npm test`
- `npm run build`

---

## 2026-03-11 — W75-W76: Tribe Kanban migrado para Astro Island (React)

### Scope
Substituir o Kanban vanilla em `src/pages/tribe/[id].astro` por uma island React com DnD moderno, modal rico e UX de edição com menor fricção operacional.

### Delivered
- Novo componente: `src/components/boards/TribeKanbanIsland.tsx`
  - Drag-and-drop com `@dnd-kit` (pointer + keyboard sensors).
  - UI otimista na movimentação de status com rollback local em caso de erro RPC.
  - Modal de card com edição de título, descrição, status, responsável, prazo e checklist.
  - Ação de arquivamento integrada via `admin_archive_board_item`.
- Página da tribo:
  - `panel-board` agora monta `<TribeKanbanIsland client:load ... />`.
  - chamada legacy de `loadProjectBoard()` removida do fluxo principal.
- Dependências:
  - adicionado `lucide-react` para ícones do board/modal.
- Testes atualizados para o novo contrato da island.

### Validation captured
- `npm test`
- `npm run build`

---

## 2026-03-11 — W60-W74: Kanban + Governança de Portfólio (execução contínua)

### Scope
Executar a sequência de 15 sprints com foco em UX operacional de Kanban, governança de taxonomy de boards, segurança de movimentação entre quadros e fechamento do roadmap Dark + Kanban.

### Delivered
- Navegação:
  - hyperlink `Pauta` mantido visível e inativo por decisão temporária de hierarquia.
- Tribo Kanban:
  - persistência de checklist com `[x]/[ ]`;
  - validação/deduplicação de anexos com preview de domínio;
  - restauração de cards arquivados na própria UI;
  - indicadores SLA de atraso/orfandade no toolbar.
- Publications Island:
  - movimentação de cards por teclado (`Shift + ArrowLeft/ArrowRight`).
- QA/UX:
  - novo script `scripts/audit_dark_mode_visual_baseline.sh`;
  - novo comando `npm run audit:dark:baseline`;
  - `smoke-routes` agora cobre `/publications`.
- Backend/migrations aplicadas:
  - `20260314191000_cross_board_move_policy.sql`
  - `20260314192000_portfolio_executive_dashboard_rpc.sql`
  - `20260314193000_board_taxonomy_data_quality_guards.sql`
  - `20260314194000_publications_submission_workflow_enrichment.sql`

### Validation captured
- `supabase db push` (todas as migrations acima aplicadas)
- `./scripts/audit_dark_mode_visual_baseline.sh`
- `npm test`
- `npm run build`

---

## 2026-03-11 — Sprint 38 (Dev): Admin Modularization Phase 4

### Scope
Reduzir acoplamento do `admin/index.astro` extraindo helpers de UI do catálogo de tribos para módulo dedicado, sem alterar ACL ou fluxo operacional.

### Delivered
- Novo módulo: `src/lib/admin/tribe-catalog-ui.ts`
  - `getTribeCatalogSummary(...)`
  - `buildAdminTribeFilterHtml(...)`
- `src/pages/admin/index.astro`:
  - passa a importar os helpers extraídos;
  - mantém comportamento atual de resumo e filtro dinâmico do catálogo.
- `tests/ui-stabilization.test.mjs`:
  - lock de regressão para garantir extração e uso do módulo.

### Audit Results
- `npm test`
- `npm run build`

---

## 2026-03-11 — Sprint 37 (Dev): ADR Baseline Extraction

### Scope
Separar decisões técnicas duráveis em ADRs curtos, evitando mistura de arquitetura com log operacional de governança.

### Delivered
- Novo pacote `docs/adr/`:
  - `docs/adr/README.md` (índice e processo)
  - `docs/adr/ADR-0001-source-of-truth-and-cycle-history.md`
  - `docs/adr/ADR-0002-role-model-v3-operational-role-and-designations.md`
  - `docs/adr/ADR-0003-admin-analytics-internal-readonly-surface.md`
- Novo script `scripts/audit_adr_index.sh` para validar integridade do índice ADR.
- `docs/INDEX.md` atualizado com rota de ADR e comando de auditoria.
- `README.md` atualizado no mapa documental.
- `tests/ui-stabilization.test.mjs` com lock de regressão para baseline ADR.

### Audit Results
- `./scripts/audit_adr_index.sh`
- `./scripts/audit_docs_index_links.sh`
- `npm test`
- `npm run build`

---

## 2026-03-11 — Sprint 36 (Dev): Docs Index Execution Pass

### Scope
Consolidar o índice por persona com uma validação técnica automatizada, evitando drift de links quebrados na documentação de governança.

### Delivered
- Novo script: `scripts/audit_docs_index_links.sh`
  - extrai referências em `docs/INDEX.md`;
  - valida arquivos/diretórios e globs (`*`);
  - falha quando houver referência inválida.
- `docs/INDEX.md`:
  - seção de verificação rápida com comando de auditoria.
- `tests/ui-stabilization.test.mjs`:
  - novo lock garantindo a presença do índice por persona e do script de auditoria.

### Audit Results
- `./scripts/audit_docs_index_links.sh`
- `npm test`
- `npm run build`

---

## 2026-03-11 — Sprint 35 (Dev): Auth Route Smoke Expansion

### Scope
Expandir a cobertura de smoke para validar não apenas disponibilidade (`2xx`), mas também comportamento fail-closed em rotas protegidas quando o usuário está anônimo.

### Delivered
- `scripts/smoke-routes.mjs`:
  - adicionada asserção de conteúdo (`assertContains`) para marcadores de deny em rotas críticas:
    - `/admin/selection` -> `#sel-denied`
    - `/admin/analytics` -> `#analytics-denied`
    - `/admin/curatorship` -> `#cur-denied`
    - `/admin/comms` -> `#comms-denied`
    - `/webinars` -> `#webinars-denied`
    - `/tribe/1` -> `#tribe-denied`
  - mantidos checks de disponibilidade e redirects legados `/rank` e `/ranks`.
- `tests/ui-stabilization.test.mjs`:
  - novo lock de regressão para garantir presença desses checks no smoke script.

### Audit Results
- `npm run smoke:routes`
- `npm test`
- `npm run build`

---

## 2026-03-11 — Sprint 34 (Dev): Cloudflare Env Parity Audit

### Scope
Reduzir risco de regressão em bootstrap Supabase por divergência de variáveis públicas entre Production/Preview no Cloudflare Workers.

### Delivered
- Novo script: `scripts/audit_cloudflare_public_env_parity.sh`
  - valida contrato de `PUBLIC_SUPABASE_URL` e `PUBLIC_SUPABASE_ANON_KEY` em `.env.example`;
  - valida safeguards em `src/lib/supabase.ts` (runtime hooks + fallback);
  - verifica presença/ausência de `[vars]` em `wrangler.toml` (informativo);
  - imprime checklist manual de paridade para Production e Preview.
- `docs/project-governance/CLOUDFLARE_ENV_INJECTION_VALIDATION.md`:
  - seção de auditoria local rápida;
  - checklist separado para Preview;
  - fluxo consolidado de validação pré e pós deploy.
- `tests/ui-stabilization.test.mjs`:
  - lock de regressão garantindo script + runbook de paridade.

### Audit Results
- `./scripts/audit_cloudflare_public_env_parity.sh`
- `npm test`
- `npm run build`

---

## 2026-03-11 — Sprint 33 (Dev): Actions Runtime Future-Proof (Node 24)

### Scope
Blindar a esteira de GitHub Actions contra a depreciação de Node 20 em actions JavaScript, reduzindo risco de quebra silenciosa futura no CI.

### Delivered
- Workflows atualizados com `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: 'true'`:
  - `.github/workflows/ci.yml`
  - `.github/workflows/ci-heartbeat-monitor.yml`
  - `.github/workflows/codeql-analysis.yml`
  - `.github/workflows/issue-reference-gate.yml`
  - `.github/workflows/project-governance-sync.yml`
  - `.github/workflows/credly-auto-sync.yml`
  - `.github/workflows/comms-metrics-sync.yml`
  - `.github/workflows/knowledge-insights-auto-sync.yml`
  - `.github/workflows/release-tag.yml`
- `tests/ui-stabilization.test.mjs`:
  - novo lock de regressão garantindo presença da flag em workflows-chave.

### Audit Results
- `npm test`
- `npm run build`

---

## 2026-03-11 — Sprint 32 (Dev): CI Heartbeat Monitor + Browser Guard Flake Hardening

### Scope
Fechar regressões do quality gate e institucionalizar monitoramento contínuo do CI para evitar acúmulo de falhas silenciosas em `main`.

### Delivered
- `tests/browser-guards.test.mjs`:
  - asserção de `/admin/selection` endurecida para aguardar render real da tabela (`#sel-tbody tr`) em vez de depender de timing de texto em `#sel-count`.
- `.github/workflows/ci-heartbeat-monitor.yml` (novo):
  - execução agendada a cada 30 minutos + `workflow_dispatch`;
  - consulta o último run concluído de `CI Validate` em `main`;
  - abre issue de alerta quando houver falha;
  - comenta/fecha automaticamente o alerta quando houver recuperação.
- `tests/ui-stabilization.test.mjs`:
  - lock de regressão garantindo presença e contrato básico do heartbeat monitor.
- `backlog-wave-planning-updated.md`:
  - fila atualizada para **próximas 15 sprints (W44-W58)**.

### Audit Results
- `npm test`
- `git push origin main`
- Monitoramento GitHub Actions habilitado por workflow dedicado

---


> For historical releases prior to 2026-03-11 Sprint 32, see docs/archive/RELEASE_LOG_HISTORICAL.md
