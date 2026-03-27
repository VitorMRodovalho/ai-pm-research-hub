# Release Log

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
