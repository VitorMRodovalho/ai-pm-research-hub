# Release Log

## 2026-03-11 — Sprint 21 (Dev): Comms Integration Roadmap

### Scope
Definir roadmap oficial para integração do time de comunicação no Hub e substituição orientada de Trello em fases com mitigação de risco operacional.

### Delivered
- `docs/project-governance/COMMS_INTEGRATION_ROADMAP.md`:
  - fases de execução (baseline, híbrido, cutover, estabilização);
  - milestones por fase;
  - matriz de riscos/dependências e critérios de aceite.
- `README.md`:
  - roadmap adicionado à seção de governança do projeto.

### Audit Results
- Validado com `npm run build`.

---

## 2026-03-11 — Sprint 20 (Dev): Knowledge Hub Design Spec

### Scope
Publicar especificação consolidada para implementação incremental do Knowledge Hub, com escopo, fases, riscos, dependências e critérios de aceite.

### Delivered
- `docs/project-governance/KNOWLEDGE_HUB_DESIGN_SPEC.md`:
  - objetivo, princípios, escopo MVP, direção de dados, ACL, fluxos e fases A/B/C;
  - dependências, riscos e DoD operacional.
- `README.md`:
  - referência ao design spec adicionada ao mapa oficial de documentação.

### Audit Results
- Validado com `npm run build`.

---

## 2026-03-11 — Sprint 19 (Dev): Bus Factor Drill Evidence Pack

### Scope
Fortalecer o controle de continuidade operacional com template padronizado de evidências para drill de operador secundário.

### Delivered
- `docs/project-governance/BUS_FACTOR_DRILL_EVIDENCE_TEMPLATE.md`:
  - metadados, checklist, anexos de evidência, matriz de gaps e plano de ação.
- `docs/DISASTER_RECOVERY.md`:
  - seção de drill atualizada com referência explícita ao template e critérios mínimos de aprovação.

### Audit Results
- Validado com `npm run build`.

---

## 2026-03-11 — Sprint 18 (Dev): Documentation Index by Persona

### Scope
Reduzir fricção de onboarding e navegação documental com um índice orientado por persona e integração no mapa oficial do repositório.

### Delivered
- `docs/INDEX.md`:
  - trilhas de leitura por persona (GP/PM, liderança operacional, contributor, sponsor/chapter liaison);
  - atalhos por tema e regra operacional de atualização documental.
- `README.md`:
  - `docs/INDEX.md` adicionado ao `Repository Documentation Map`.

### Audit Results
- Validado com `npm run build`.

---

## 2026-03-11 — Sprint 17 (Dev): CI/Branch Hardening Operational Gate

### Scope
Endurecer o pipeline operacional em `main`/`dev` e consolidar orientação de branch protection com checks obrigatórios.

### Delivered
- `.github/workflows/ci.yml`:
  - gatilho em `push`/`pull_request` para `main` e `dev`;
  - `concurrency` por branch para evitar execução concorrente desnecessária;
  - novo job agregador `quality_gate` (depende de `validate` + `browser_guards`).
- `docs/project-governance/BRANCH_ENFORCEMENT.md`:
  - guia prático de checks obrigatórios e aplicação de protection rules.
- `docs/DEPLOY_CHECKLIST.md`:
  - visão de workflows atualizada com `CI Validate` e `Issue Reference Gate`.

### Audit Results
- Validado com `npm test` e `npm run build`.

---

## 2026-03-11 — Sprint 16 (Dev): Browser Guard Expansion for Critical Flows

### Scope
Expandir cobertura de regressão para fluxos críticos operacionais (Credly/profile, alocação admin e curadoria) com foco em estabilidade de interface e ACL.

### Delivered
- `tests/ui-stabilization.test.mjs`:
  - novo teste para contrato do botão `verify-credly` (event delegation + toggle seguro de estado do botão);
  - novo teste de proteção null-safe no pending allocation (`safeName` + `normalizeDigits`).
- `tests/browser-guards.test.mjs`:
  - cenário positivo para `/admin/curatorship` com manager simulado;
  - validação de board visível, editor de aprovação (`visibilidade/audiência`) e busca operacional.

### Audit Results
- Validado com `npm test`, `npm run test:browser:guards` e `npm run build`.

---

## 2026-03-11 — Sprint 15 (Dev): Governance Automation Gate + Short Guide

### Scope
Fechar a tranche de automação de governança (`#5`) com um gate de rastreabilidade para trilha crítica e um guia operacional curto para gestão de waves/sprints.

### Delivered
- `.github/workflows/issue-reference-gate.yml`:
  - gate em `push`/`pull_request` para `main` e `dev`.
- `scripts/require_issue_reference.sh`:
  - valida referência de issue (`#123`, `GH-123` ou URL) quando há mudança em trilha crítica.
- `docs/project-governance/PROJECT_AUTOMATION_SHORT_GUIDE.md`:
  - campos mínimos do Project, fluxo operacional e regra do gate.

### Audit Results
- Validado com `npm run build` e lint shell básico do script de gate (`bash -n`).

---

## 2026-03-11 — Sprint 14 (Dev): Executive Admin Panel Bind Closure (V2 Contracts)

### Scope
Concluir a tranche de bind executivo do admin (`#6`) com validação de contrato atual, alinhando escopo legado com os RPCs V2 efetivamente utilizados no painel.

### Delivered
- `docs/project-governance/ANALYTICS_V2_PARTNER_VALIDATION.md`:
  - seção de mapeamento legado -> V2;
  - explicitação dos contratos oficiais (`exec_funnel_v2`, `exec_impact_hours_v2`, `exec_certification_delta`, `exec_chapter_roi`, `exec_role_transitions`, `exec_analytics_v2_quality`).

### Audit Results
- Validado com `npm run test:browser:guards` (inclui `/admin/analytics` para perfil sem permissão) e `npm run build`.

---

## 2026-03-11 — Sprint 13 (Dev): Home Schedule SOT Closure + Legacy Hotfix Validation Review

### Scope
Encerrar formalmente a trilha de fonte única de agenda/prazo da home (Issue #3) e revisar a validação legada do hotfix de homepage (Issue #2), consolidando evidências e runbook operacional.

### Delivered
- `docs/migrations/HOME_SCHEDULE_SOT_RUNBOOK.md`:
  - checklist de auditoria, SQL de verificação, SQL de atualização e estratégia de rollback sem hardcode frontend.
- Revisão de aderência:
  - home pública (PT/EN/ES) já consome `home_schedule` via `src/lib/schedule.ts`;
  - superfícies de hero/agenda/tribos/recursos alinhadas ao runtime da agenda.

### Audit Results
- Validado com `npm run smoke:routes`, `npm run test:browser:guards` e `npm run build`.

---

## 2026-03-11 — Sprint 12 (Dev): Artifacts 400 Harden + Tribes Resilience Guard

### Scope
Fechar a tranche de estabilidade para `artifacts` e `tribes` com foco em prevenção de regressão: evitar chamadas inválidas para RPC de curadoria e ampliar cobertura browser para interação mínima de cards de tribos.

### Delivered
- `src/pages/artifacts.astro`:
  - guarda explícita para `artifactId` ausente antes de chamar `curate_item`;
  - tratamento amigável para erro de UUID inválido (classe de falha que tende a gerar 400).
- `tests/browser-guards.test.mjs`:
  - cobertura adicional da home para garantir que um card de tribo expande corretamente ao clique no header.
- `DEBUG_HOLISTIC_PLAYBOOK.md`:
  - lição aprendida adicionada para classe de bug `artifacts 400`.

### Audit Results
- Validado com `npm test`, `npm run test:browser:guards` e `npm run build`.

---

## 2026-03-11 — Sprint 11 (Dev): CI Path-Portability + Browser Guard Regex Fix

### Scope
Corrigir quebra de CI em ambiente GitHub Actions causada por paths absolutos hardcoded nos testes e por regex case-sensitive no browser guard da home.

### Delivered
- `tests/ui-stabilization.test.mjs`: root de leitura alterado para `process.cwd()` (portável entre local e runner CI).
- `tests/attendance-ui.test.mjs`: root de leitura alterado para `process.cwd()`.
- `tests/browser-guards.test.mjs`: regex do `#hero-event-area` ajustada para case-insensitive (`/i`) evitando falso negativo com variação de caixa em `kick-off`.

### Audit Results
- Validado localmente com `npm test`, `npm run test:browser:guards` e `npm run build`.

---

## 2026-03-11 — Sprint 10 (Dev): CI/Governance Closure Pass (`#14`)

### Scope
Concluir formalmente a trilha de hardening de pipeline/governanca com encerramento da issue S-CI1 baseada nas entregas de CI gate e policy operacional já publicadas.

### Delivered
- Issue `#14` encerrada com referência direta às evidências:
  - atualização de workflows e policy trunk-based com gate mínimo
  - job browser guard incorporado ao CI
  - locks de regressão de superfícies operador/admin

### Audit Results
- Tranche de governança/issue management sem SQL novo.

---

## 2026-03-11 — Sprint 9 (Dev): Reliability Closure Pass (`#12`, `#13`)

### Scope
Encerrar formalmente a trilha de confiabilidade associada ao SSR safety audit e ao data patch follow-through com rastreabilidade de evidências.

### Delivered
- Issue `#12` encerrada com evidência de hardening SSR/name-safe em componentes e páginas críticas.
- Issue `#13` encerrada com evidência de aplicação da migration de sanidade de dados (`20260314110000_member_data_sanity_patch.sql`) e confirmação de alinhamento local/remoto no Supabase.

### Audit Results
- Tranche de governança/issue management sem SQL novo adicional (migration já aplicada em sprint anterior).

---

## 2026-03-11 — Sprint 8 (Dev): P0 Closure Pass (`#19`, `#11`, `#1`)

### Scope
Formalizar encerramento dos P0 de estabilizacao com rastreabilidade em issue tracker, vinculando evidencias de commits e gates de validacao ja executados nas sprints anteriores.

### Delivered
- Issues criticas encerradas com comentario de evidencia:
  - `#19` (admin allocation crash)
  - `#11` (rank/credly alignment)
  - `#1` (credly recurring regression)
- Comentarios incluem referencia aos commits de correção, locks de regressao e resultados de audit (`test/build/smoke`).

### Audit Results
- Tranche de governanca/issue management sem SQL novo.

---

## 2026-03-11 — Sprint 7 (Dev): W44.3 Partner Validation Pack for Analytics V2

### Scope
Preparar fechamento operacional de W44.3 com trilha auditavel de validacao partner-facing em dados reais para Analytics V2, sem alterar ACL de producao.

### Delivered
- `docs/project-governance/ANALYTICS_V2_PARTNER_VALIDATION.md` criado com:
  - escopo de ACL
  - matriz de RPCs a validar
  - procedimento de evidencia
  - criterio de fechamento
- `PROJECT_GOVERNANCE_RUNBOOK.md` atualizado para incorporar esse checklist no fluxo de execucao.

### Audit Results
- Tranche documental sem SQL novo.
- Execucao funcional em conta partner real permanece como passo operacional da proxima janela de validacao.

---

## 2026-03-11 — Sprint W44: Milestones + Repo Sync Strategy + Bus-Factor Drill Pack

### Scope
Executar a tranche de readiness de governanca criando marcos operacionais no GitHub, formalizando o fluxo de sincronizacao entre remotes e adicionando checklist de drill para operador secundario.

### Delivered
- **Milestones criadas no GitHub**:
  - `Cycle 2026.1 Stabilization Gate`
  - `Wave 41-44 Reliability and Governance`
- **Issues criticas e de confiabilidade vinculadas aos milestones**:
  - `#19`, `#11`, `#1` no milestone de estabilizacao
  - `#12`, `#13`, `#14` no milestone de reliability/governance
- **Nova estrategia oficial de sync**:
  - `docs/project-governance/REPO_SYNC_STRATEGY.md`
  - links adicionados em `README.md` e `PROJECT_GOVERNANCE_RUNBOOK.md`
- **Bus-factor mitigation drill pack**:
  - `docs/DISASTER_RECOVERY.md` atualizado com checklist para operador secundario.

### Audit Results
- `gh api .../milestones`: repositório passou de `0` para `2` milestones abertas.
- Fluxo de sync e continuidade operacional agora documentado em runbook dedicado.

---

## 2026-03-11 — Sprint W43.1-W43.2: SSR Name Guards + Member Data Sanity Patch

### Scope
Fechar follow-through de confiabilidade com hardening de renderizacao em componentes sensiveis a dados incompletos e aplicar patch SQL de sanidade de `members` no ambiente remoto.

### Delivered
- **SSR/client render hardening**:
  - `src/components/sections/TeamSection.astro`
  - `src/components/sections/CpmaiSection.astro`
  - `src/components/sections/TrailSection.astro`
  - `src/pages/profile.astro`
  Todos os pontos acima passaram a usar fallback seguro de nome antes de `split/map` para evitar quebra quando `name` vier nulo/vazio.
- **Data patch follow-through**:
  - `supabase/migrations/20260314110000_member_data_sanity_patch.sql`
  - Backfill de `members.name` vazio para valor seguro.
  - Backfill de `members.designations` nulo para array vazio.
  - Normalizacao de `members.phone` para digitos (ou `null` quando vazio).

### Audit Results
- `supabase db push`: migration `20260314110000_member_data_sanity_patch.sql` aplicada com sucesso.
- `supabase migration list`: `Local` e `Remote` alinhados apos aplicacao.
- Validacao de app (nesta tranche): `npm test` + `npm run build` + `npm run smoke:routes` no fechamento do sprint.

---

## 2026-03-11 — Sprint W42.3-W43.3: CI Browser Gate + Operator Regression Locks

### Scope
Subir o gate de qualidade para incluir guarda browser no CI e expandir locks de regressao para fluxo operador/admin na curadoria.

### Delivered
- **`.github/workflows/ci.yml`**: novo job `browser_guards` executa Playwright (`npm run test:browser:guards`) com ambiente mock para bloquear regressao de ACL/SSR de rotas criticas.
- **`tests/browser-guards.test.mjs`**: cobertura anonima expandida para `/admin/curatorship`, garantindo deny state e ausencia de board para visitante.
- **`tests/ui-stabilization.test.mjs`**: novo lock de regressao textual para busca/targeting de aprovacao da curadoria (`searchQuery`, `p_tribe_id`, `p_audience_level`).

### Audit Results
- Validacao local desta tranche: `npm test`, `npm run test:browser:guards`, `npm run build`.

---

## 2026-03-11 — Sprint W42.1-W42.2: PR Hygiene + Delivery Gate Policy

### Scope
Reduzir backlog operacional de PRs de dependencias/governanca e formalizar o modelo de entrega adotado pelo projeto para evitar fila parada e regressao por fluxo ambiguo.

### Delivered
- **Dependabot uplift incorporado em `main`**: workflows atualizados para `actions/checkout@v6` e `actions/setup-node@v6` nos pipelines internos.
- **Policy formalizada** em `SPRINT_IMPLEMENTATION_PRACTICES.md` e `PROJECT_GOVERNANCE_RUNBOOK.md`: trunk-based em `main` com gate tecnico obrigatorio (`test`, `build`, `smoke`) e higiene ativa de PRs de dependencia.

### Audit Results
- Validacao local desta tranche: `npm test` + `npm run build` em andamento no fechamento do sprint.

---

## 2026-03-11 — Sprint W41.3-W41.4: Rank/Credly Alignment + Profile Verify Retry

### Scope
Endurecer o eixo critico de gamificacao/Credly com alinhamento de pontuacao lifetime nas superficies de rank e mitigacao de regressao recorrente no verify Credly com retry de sessao quando houver 401 transitorio.

### Delivered
- **`src/pages/gamification.astro`**: ranking individual e de tribos passam a priorizar `lifetimePointsByMember` (agregado real) antes de fallback em `total_points`, reduzindo drift de exibicao entre backend e UI.
- **`src/pages/gamification.astro`**: render de nomes iniciais no leaderboard/tribes agora usa fallback seguro para evitar quebra com dados incompletos.
- **`src/pages/profile.astro`**: `verifyCredly()` ganhou retry unico em resposta `401`, com `refreshSession()` e nova tentativa autenticada antes de falhar.
- **`tests/ui-stabilization.test.mjs`**: novos locks textuais para garantir retry de credly e uso da fonte lifetime agregada no ranking.

### Audit Results
- Validacao local prevista nesta tranche: `npm test`, `npm run build`, `npm run smoke:routes`.

---

## 2026-03-11 — Sprint W41.1-W41.2: Secrets Hygiene + Admin Allocation Crash Guard

### Scope
Executar o gate inicial de estabilizacao P0 removendo `.env` do versionamento e eliminando a causa recorrente de crash no pool de pendentes da alocacao de tribos quando `phone` vem fora do formato esperado.

### Delivered
- **Secrets hygiene**: `.env` removido do tracking git (mantido apenas local), com reforco explicito no `CONTRIBUTING.md` para nunca commitar env files.
- **Admin allocation hardening**: `src/pages/admin/index.astro` recebeu normalizacao segura de telefone (`normalizeDigits`) e fallback de primeiro nome via `safeName`, evitando `replace` em valores nao-string no fluxo de pendentes.

### Audit Results
- Build local apos ajuste de frontend: pendente de execucao no fechamento da tranche W41 completa.
- Risco reduzido: dados incompletos/heterogeneos em `members.phone` deixam de quebrar renderizacao da lista de pendentes.

---

## 2026-03-11 — DB Hotfix: Curadoria com Segmentacao por Tribo e Audiencia

### Scope
Aplicar no banco remoto a correcao da funcao `public.curate_item` para suportar curadoria de `knowledge_assets` com segmentacao por tribo e para permitir atualizacao de `audience_level` em `events` no mesmo fluxo de moderacao.

### Delivered
- **`supabase/migrations/20260314060000_curate_item_knowledge_and_visibility_fix.sql`** aplicada em producao via `supabase db push`.
- A assinatura da funcao passa a aceitar `p_tribe_id` e `p_audience_level`, mantendo controle de acesso administrativo (`superadmin`, `manager`, `deputy_manager`).
- O fluxo cobre `knowledge_assets`, `artifacts`, `hub_resources` e `events`, com validacao de acao e erro explicito quando item nao e encontrado.

### Audit Results
- `supabase migration list`: `20260314060000` estava pendente no remoto antes da aplicacao.
- `supabase db push`: migration aplicada sem erro.
- `supabase migration list` (pos-push): `Local` e `Remote` alinhados para `20260314060000`.

---

## 2026-03-12 — v0.34.0 Waves 36-40: Analytics V2 Read-Only Rollout

### Scope
This tranche turns `/admin/analytics` into the staged Analytics V2 surface: a global filter bar, internal read-only ACL for partner-facing observers, and explicit SQL contracts for engagement funnel, innovation hours, certification delta, chapter ROI, and leadership journey.

### Analytics V2 Upgrade
- **`supabase/migrations/20260312110000_analytics_v2_internal_readonly_and_metrics.sql`**: Adds `can_read_internal_analytics`, cycle-aware member scoping, and the RPCs `exec_funnel_v2`, `exec_impact_hours_v2`, `exec_certification_delta`, `exec_chapter_roi`, and `exec_role_transitions`.
- **`src/pages/admin/analytics.astro`** and **`src/components/analytics/ChartCard.astro`**: Rebuild the route around Chart.js-native V2 sections, global filters, KPI cards, and a transition matrix, while keeping the route aligned with the existing admin shell.
- **`src/lib/admin/constants.ts`**, **`src/lib/navigation.config.ts`**, **`src/components/nav/AdminNav.astro`**, and **`src/pages/admin/index.astro`**: Split analytics read access from admin write access so observers with the approved designations can read the dashboard without inheriting management powers.

### Governance / Regression
- **`src/lib/database.gen.ts`** regenerated from the linked Supabase project after applying the migration.
- **`tests/ui-stabilization.test.mjs`**, **`tests/browser-guards.test.mjs`**, and **`scripts/smoke-routes.mjs`** now lock the new analytics ACL path, V2 RPC wiring, and route availability.
- **Backlog / governance / permissions / migration notes / README** updated to reflect the Analytics V2 rollout and the new read-only audience.

### Files Changed
- `src/components/analytics/ChartCard.astro`
- `src/lib/admin/constants.ts`
- `src/lib/navigation.config.ts`
- `src/components/nav/AdminNav.astro`
- `src/pages/admin/analytics.astro`
- `src/pages/admin/index.astro`
- `src/i18n/pt-BR.ts`
- `src/i18n/en-US.ts`
- `src/i18n/es-LATAM.ts`
- `src/lib/database.gen.ts`
- `supabase/migrations/20260312110000_analytics_v2_internal_readonly_and_metrics.sql`
- `tests/ui-stabilization.test.mjs`
- `tests/browser-guards.test.mjs`
- `scripts/smoke-routes.mjs`
- `backlog-wave-planning-updated.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `docs/RELEASE_LOG.md`, `docs/MIGRATION.md`, `README.md`

### Audit Results
- Build: clean
- Tests: 32/32
- Browser guard: OK
- Smoke: routes OK

---

## 2026-03-12 — v0.33.0 Wave 35: Dynamic Tribe Catalog Foundation

### Scope
Wave 35 removes the most brittle `01..08` tribe assumptions from the internal platform, introduces an explicit active/inactive flag in the tribe catalog, and opens admin controls to create and manage runtime tribes without reopening the ACL issues fixed in Wave 34.

### Dynamic Tribe Upgrade
- **`supabase/migrations/20260312050000_dynamic_tribe_catalog_and_status.sql`**: Adds `tribes.is_active`, introduces `admin_list_tribes`, `admin_upsert_tribe`, and `admin_set_tribe_active`, and updates `admin_deactivate_tribe` so closing a tribe also marks the catalog entry inactive.
- **`src/pages/admin/index.astro`**: The tribes panel now loads a runtime catalog, populates filters dynamically, shows active/inactive badges, allows project management to create a new tribe, and lets the catalog mark tribes active/inactive without returning to hardcoded options.
- **`src/pages/tribe/[id].astro`**, **`src/pages/en/tribe/[id].astro`**, **`src/pages/es/tribe/[id].astro`**, and **`src/components/nav/Nav.astro`**: Tribe routes and navigation stop blocking ids above `8`, use runtime tribe metadata when available, and keep inactive-tribe visibility reserved to superadmin.
- **`src/pages/workspace.astro`**, **`src/pages/artifacts.astro`**, **`src/pages/gamification.astro`**, and **`src/components/sections/HeroSection.astro`**: Runtime tribe names/status now feed more of the internal surfaces so new tribes do not immediately fall back to broken labels or stale counts.

### Governance / Regression
- **`tests/ui-stabilization.test.mjs`**: Regression coverage now locks the removal of the `> 8` route bound, the new tribe catalog helpers, the runtime admin catalog flow, and the explicit `is_active` migration contract.
- **Backlog / governance / permissions / migration notes / README** updated to reflect that the structural tribe-catalog tranche is now in progress and already applied on the linked database.

### Files Changed
- `src/lib/tribes/catalog.ts`
- `src/components/nav/Nav.astro`
- `src/pages/tribe/[id].astro`
- `src/pages/en/tribe/[id].astro`
- `src/pages/es/tribe/[id].astro`
- `src/pages/admin/index.astro`
- `src/pages/workspace.astro`
- `src/pages/artifacts.astro`
- `src/pages/gamification.astro`
- `src/components/sections/HeroSection.astro`
- `supabase/migrations/20260312050000_dynamic_tribe_catalog_and_status.sql`
- `tests/ui-stabilization.test.mjs`
- `backlog-wave-planning-updated.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `docs/RELEASE_LOG.md`, `docs/MIGRATION.md`, `README.md`

### Audit Results
- Build: clean
- Tests: 31/31
- Browser guard: OK
- Smoke: not run in this slice

---

## 2026-03-11 — v0.32.0 Wave 34: Tribe Exploration Access And Lifecycle Expansion

### Scope
Wave 34 fixes the broken `Explorar Tribos` experience for active members, closes the implicit public gap on `/tribe/[id]`, and expands the existing tribe lifecycle operations from superadmin-only to the project-management layer.

### Access / Lifecycle Upgrade
- **`src/components/nav/Nav.astro`**: The tribe directory no longer depends on a non-existent `tribes.is_active` flag. It now derives visible tribes from the active member roster and exposes `Explorar Tribos` to active members and above even when they are not allocated to a tribe.
- **`src/pages/tribe/[id].astro`** and **`src/lib/tribes/access.ts`**: Tribe pages now fail closed for visitors/inactive accounts, allow active members to explore other active tribes in read-only mode, and keep editing/broadcast controls restricted to local leadership or project management.
- **`src/pages/admin/index.astro`** and **`supabase/migrations/20260311123000_expand_tribe_lifecycle_management_access.sql`**: The existing move-member, change-leader, deactivate-member, and deactivate-tribe flows now open to GP / Deputy Manager / `co_gp` in addition to superadmin, while the admin UI avoids duplicate lifecycle event binding on refresh.

### Governance / Regression
- **`tests/ui-stabilization.test.mjs`**: Regression coverage now locks the active-member tribe exploration path, the tribe page guard, and the widened lifecycle-management path.
- **`tests/browser-guards.test.mjs`**: Browser coverage now asserts that `/tribe/1` fails closed for anonymous visitors, alongside the existing admin/webinars ACL checks.
- **Backlog / governance / permissions** updated to reflect the hierarchy and ACL shift. Dynamic tribe creation remains intentionally deferred because the current route/catalog layer is still bounded to `1..8`.

### Files Changed
- `src/lib/tribes/access.ts`
- `src/components/nav/Nav.astro`
- `src/pages/tribe/[id].astro`
- `src/pages/admin/index.astro`
- `supabase/migrations/20260311123000_expand_tribe_lifecycle_management_access.sql`
- `tests/ui-stabilization.test.mjs`
- `tests/browser-guards.test.mjs`
- `backlog-wave-planning-updated.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `docs/RELEASE_LOG.md`

### Audit Results
- Build: clean
- Tests: 30/30
- Browser guard: OK
- Smoke: routes OK

---

## 2026-03-11 — v0.31.0 Wave 33: Webinars In-Module Authoring Aids

### Scope
Wave 33 deepens the webinars reuse flow again, this time by adding lightweight authoring and QA assistance inside `Attendance` and `Admin Comms` instead of only improving landing-state routing.

### In-Module Assistance Upgrade
- **`src/pages/attendance.astro`** and **`src/components/attendance/EditEventModal.astro`**: The focused webinar edit flow now includes contextual guidance, quick follow-through actions, and field targeting for the specific operator task such as filling the meeting link or replay URL.
- **`src/pages/admin/comms.astro`**: The webinar handoff now renders a small contextual playbook with reusable subject/body suggestions and copy actions, while preserving the page as an analytics/history surface rather than a parallel comms editor.
- **`src/pages/admin/webinars.astro`**: Webinar comms links now include the event id needed to keep the focused round-trip between webinars, comms, and attendance coherent.

### Governance / Regression
- **`tests/ui-stabilization.test.mjs`**: Regression coverage now locks the presence of the webinar-specific authoring aids in `Attendance` and `Admin Comms`.
- **`tests/browser-guards.test.mjs`**: Browser coverage keeps the contextual-link chain protected as the webinar flow emits richer route state.
- **Backlog / governance / permissions / README / discovery note** updated to reflect this next layer of operator assistance.

### Files Changed
- `src/components/attendance/EditEventModal.astro`
- `src/pages/attendance.astro`
- `src/pages/admin/comms.astro`
- `src/pages/admin/webinars.astro`
- `tests/ui-stabilization.test.mjs`
- `tests/browser-guards.test.mjs`
- `README.md`
- `docs/WEBINARS_MODULE_DISCOVERY.md`
- `backlog-wave-planning-updated.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `docs/RELEASE_LOG.md`

### Audit Results
- Build: clean
- Tests: 29/29
- Browser guard: OK
- Smoke: routes OK

---

## 2026-03-11 — v0.30.0 Wave 32: Webinars Attendance And Comms Handoffs

### Scope
Wave 32 extends the webinars contextual-handoff line into `Attendance` and `Admin Comms`, so operators no longer land on generic destination pages for the most operational next steps.

### Contextual Handoff Upgrade
- **`src/pages/admin/webinars.astro`**: Attendance and comms quick actions now generate webinar-aware URLs, including focused event, stage, and edit intent where relevant.
- **`src/pages/attendance.astro`**: Added URL-driven webinar context (`tab`, `type`, `q`, `eventId`, `action`, `edit`), local filtering, focus highlighting, and optional edit-modal opening for the targeted event.
- **`src/pages/admin/comms.astro`**: Added URL-driven webinar context (`focus`, `context`, `stage`, `q`, `title`, `date`), a contextual banner, and filtered broadcast-history search so webinar promotion follow-through starts in a narrower state.

### Governance / Regression
- **`tests/ui-stabilization.test.mjs`**: Regression coverage now locks the new route-state pattern across `admin/webinars`, `attendance`, and `admin/comms`.
- **`tests/browser-guards.test.mjs`**: Browser coverage now also verifies that `/admin/webinars` emits contextual attendance/comms links instead of generic destinations.
- **Backlog / governance / permissions / README / discovery note** updated to reflect this deeper reuse-surface interoperability.

### Files Changed
- `src/pages/admin/webinars.astro`
- `src/pages/attendance.astro`
- `src/pages/admin/comms.astro`
- `tests/ui-stabilization.test.mjs`
- `tests/browser-guards.test.mjs`
- `README.md`
- `docs/WEBINARS_MODULE_DISCOVERY.md`
- `backlog-wave-planning-updated.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `docs/RELEASE_LOG.md`

### Audit Results
- Build: clean
- Tests: 29/29
- Browser guard: OK
- Smoke: routes OK

---

## 2026-03-11 — v0.29.0 Wave 31: Webinars Contextual Handoffs

### Scope
Wave 31 reduces webinar follow-through friction by turning the `Presentations` and `Workspace` destinations into pre-filtered handoffs from `/admin/webinars`, still without adding webinar-specific schema.

### Contextual Handoff Upgrade
- **`src/pages/admin/webinars.astro`**: Quick actions and publication links now deep-link into filtered `Presentations` and `Workspace` views tailored to the current webinar title and tribe context.
- **`src/pages/presentations.astro`**: Added URL-driven `q`, `filter`, and `tribe` initialization plus local search so webinar replay follow-through can open directly in a narrowed result set.
- **`src/pages/workspace.astro`**: Added URL-driven `type`, `q`, `tribe`, and `tag` initialization so operators can land in the webinar slice of the knowledge library instead of the full workspace list.

### Governance / Regression
- **`tests/ui-stabilization.test.mjs`**: Regression coverage now locks the query-param handoff pattern on `admin/webinars`, `presentations`, and `workspace`.
- **Backlog / governance / permissions / README / discovery note** updated to reflect this interoperability-focused follow-through.

### Files Changed
- `src/pages/admin/webinars.astro`
- `src/pages/presentations.astro`
- `src/pages/workspace.astro`
- `tests/ui-stabilization.test.mjs`
- `README.md`
- `docs/WEBINARS_MODULE_DISCOVERY.md`
- `backlog-wave-planning-updated.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `docs/RELEASE_LOG.md`

### Audit Results
- Build: clean
- Tests: 28/28
- Browser guard: OK
- Smoke: routes OK

---

## 2026-03-11 — v0.28.0 Wave 30: Webinars Operator Actions

### Scope
Wave 30 adds a new operator-guidance layer to `/admin/webinars`, turning status signals into direct next actions while keeping the page anchored to the current events-first stack.

### Operator Guidance Upgrade
- **`src/pages/admin/webinars.astro`**: The panel now computes a recommended next action per webinar, renders a prioritized quick-actions section, and adds per-card “Proxima acao” guidance based on meeting link, replay, and publication status.
- **No new schema or write path**: The implementation continues to orchestrate the existing `Attendance`, `Admin Comms`, `Presentations`, and `Workspace` surfaces instead of introducing webinar-local CRUD.

### Governance / Regression
- **`tests/ui-stabilization.test.mjs`**: Regression coverage now locks the new operator-action layer so the webinars panel keeps deriving next-step guidance from the current events-first model.
- **Backlog / governance / README / discovery note** updated to reflect this operator-flow follow-through.

### Files Changed
- `src/pages/admin/webinars.astro`
- `tests/ui-stabilization.test.mjs`
- `docs/WEBINARS_MODULE_DISCOVERY.md`
- `README.md`
- `backlog-wave-planning-updated.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/RELEASE_LOG.md`

### Audit Results
- Build: clean
- Tests: 27/27
- Smoke: routes OK

---

## 2026-03-11 — v0.27.0 Wave 29: Webinars Browser Coverage

### Scope
Wave 29 extends browser coverage to the new `/admin/webinars` surface, validating both admin ACL denial for anonymous visitors and the operational publication-state UI under a mocked admin context.

### Browser Coverage Expansion
- **`tests/browser-guards.test.mjs`**: The browser suite now picks a truly free local port, validates anonymous denial on `/admin/webinars`, and injects a controlled admin/webinar dataset to assert publication-state signals across `Presentations` and `Workspace`.
- **`src/pages/admin/webinars.astro`**: The page now fails closed for anonymous visitors instead of remaining stuck in loading while still listening for a later `nav:member` handoff.

### Governance / Regression
- **`tests/ui-stabilization.test.mjs`**: Keeps the file-level lock on the events-first webinars direction and the anonymous-session guard path.
- **Backlog / governance / permissions / README** updated to reflect the new browser validation for the webinars admin workflow.

### Files Changed
- `tests/browser-guards.test.mjs`
- `src/pages/admin/webinars.astro`
- `tests/ui-stabilization.test.mjs`
- `README.md`
- `backlog-wave-planning-updated.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `docs/RELEASE_LOG.md`

### Audit Results
- Build: clean
- Tests: 27/27
- Browser guard: OK
- Smoke: routes OK

---

## 2026-03-11 — v0.26.0 Wave 28: Webinars Replay Publication Follow-Through

### Scope
Wave 28 deepens the new admin webinars MVP by making replay publication status visible across `Presentations` and `Workspace`, still without adding new webinar schema.

### Replay Publication Visibility
- **`src/pages/admin/webinars.astro`**: The panel now loads `list_meeting_artifacts` and webinar entries from `hub_resources`, correlates them to webinar events, and shows whether each replay has reached `Presentations`, `Workspace`, both, or neither.
- **Operator guidance improved**: Admin users can now identify replay publication gaps from the webinar surface itself instead of checking multiple modules manually.

### Governance / Regression
- **`tests/ui-stabilization.test.mjs`**: Regression coverage now locks the replay-publication wiring so `/admin/webinars` continues to read both `list_meeting_artifacts` and `hub_resources` instead of drifting back to a placeholder or isolated webinar path.
- **Backlog / governance / README / discovery note** updated to reflect this follow-through on the events-first webinars line.

### Files Changed
- `src/pages/admin/webinars.astro`
- `tests/ui-stabilization.test.mjs`
- `docs/WEBINARS_MODULE_DISCOVERY.md`
- `README.md`
- `backlog-wave-planning-updated.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/RELEASE_LOG.md`, `docs/PERMISSIONS_MATRIX.md`

### Audit Results
- Build: clean
- Tests: 27/27
- Smoke: routes OK

---

## 2026-03-11 — v0.25.0 Wave 27: Admin Webinars Events-First MVP

### Scope
Wave 27 replaces the `/admin/webinars` placeholder with a thin operational surface that reuses the current event, attendance, comms, and replay stack instead of opening a new webinar-specific CRUD or schema path.

### Admin Webinars Surface
- **`src/pages/admin/webinars.astro`**: The page now loads webinar sessions through `get_events_with_attendance`, filters `events.type='webinar'`, renders KPI cards, highlights upcoming sessions, surfaces replay follow-up, and links operators to `Attendance`, `Admin Comms`, `Presentations`, and `Workspace`.
- **No new SQL or RLS changes**: The implementation stays on the approved events-first path documented in the discovery and migration notes.

### Governance / Regression
- **`tests/ui-stabilization.test.mjs`**: Added a regression check ensuring the admin webinars page no longer stays in placeholder mode and continues to use the existing events stack instead of `list_webinars`.
- **Backlog / governance / permissions / README** updated to reflect that the webinars MVP now has a real admin orchestration surface while remaining admin-only and member-first.

### Files Changed
- `src/pages/admin/webinars.astro`
- `tests/ui-stabilization.test.mjs`
- `docs/WEBINARS_MODULE_DISCOVERY.md`
- `README.md`
- `backlog-wave-planning-updated.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `docs/RELEASE_LOG.md`

### Audit Results
- Build: clean
- Tests: 27/27
- Smoke: routes OK

---

## 2026-03-11 — v0.24.0 Wave 26: Webinars Module Discovery

### Scope
Wave 26 closes the deferred webinars discovery item by defining the MVP source of truth, scope boundaries, and rollout path before any new schema is added.

### Discovery Outcome
- **`docs/WEBINARS_MODULE_DISCOVERY.md`**: New decision note defining the recommended webinars MVP as `events`-first, member-first, and heavily based on reuse of the current attendance, content, communications, and analytics stack.
- **`docs/MIGRATION.md`**: Added an explicit transition rule so the repo does not drift into a dual-source webinar model between `events` and the standalone `webinars` table.

### Governance / ACL Alignment
- **`docs/PERMISSIONS_MATRIX.md`**: Revalidated that `/admin/webinars` remains admin-only and documented that external registration or speaker CRM are still out of scope.
- **`README.md` and `AGENTS.md`**: Updated the doc map and immediate priorities so the next implementation slice follows the approved webinars direction.

### Files Changed
- `docs/WEBINARS_MODULE_DISCOVERY.md`
- `docs/MIGRATION.md`
- `README.md`, `AGENTS.md`
- `backlog-wave-planning-updated.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `docs/RELEASE_LOG.md`

### Audit Results
- Build: clean
- Tests: 26/26
- Smoke: routes OK

---

## 2026-03-11 — v0.23.0 Wave 25: Public Home Browser Coverage Expansion

### Scope
Wave 25 expands browser validation for the public home so the new runtime-driven `Hero` and `Tribes` states are covered by real-page assertions instead of relying only on textual regression checks.

### Browser Coverage Expansion
- **`tests/browser-guards.test.mjs`**: The home browser scenario now validates runtime hero content plus `TribesSection` state badge, deadline badge, notice visibility, and anonymous login prompt behavior.
- **`src/components/sections/TribesSection.astro`**: Added stable DOM ids for the public runtime summary elements so browser assertions can target the selection state without depending on brittle text layout selectors.

### Governance / Regression
- **Backlog / governance / permissions / README** updated to reflect this browser-focused follow-through with no ACL or site-hierarchy impact.

### Files Changed
- `tests/browser-guards.test.mjs`
- `src/components/sections/TribesSection.astro`
- `backlog-wave-planning-updated.md`, `docs/RELEASE_LOG.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `README.md`

### Audit Results
- Build: clean | Tests: 26/26 | Browser guard: OK | Smoke: routes OK

---

## 2026-03-11 — v0.22.0 Wave 24: Tribes Deadline Formatting Cleanup

### Scope
Wave 24 closes another small public-home schedule gap by aligning `TribesSection` deadline formatting with the same locale-aware runtime pattern already used in other home sections and by removing stale fixed fallback date strings.

### Tribes Runtime Follow-Through
- **`src/components/sections/TribesSection.astro`**: The selection deadline badge now formats through `Intl.DateTimeFormat(..., { timeZone: 'America/Sao_Paulo' })` instead of using manual UTC subtraction and a hardcoded Portuguese month array.
- **i18n**: The dormant `tribes.deadline` fallback strings in PT/EN/ES now use generic current-schedule wording instead of the old March deadline.

### Governance / Regression
- **`tests/ui-stabilization.test.mjs`**: Added regression coverage to ensure the manual UTC math is gone and the old fixed `tribes.deadline` strings do not return.
- **Backlog / governance / permissions / README** updated to reflect this smaller public runtime cleanup with no ACL or site-hierarchy impact.

### Files Changed
- `src/components/sections/TribesSection.astro`
- `src/i18n/pt-BR.ts`, `src/i18n/en-US.ts`, `src/i18n/es-LATAM.ts`
- `tests/ui-stabilization.test.mjs`
- `backlog-wave-planning-updated.md`, `docs/RELEASE_LOG.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `README.md`

### Audit Results
- Build: clean | Tests: 26/26 | Browser guard: OK | Smoke: routes OK

---

## 2026-03-11 — v0.21.0 Wave 23: Hero Kickoff Runtime Truth

### Scope
Wave 23 reduces another public-home legacy dependency by making `home_schedule.kickoffAt` the primary truth for the post-kickoff hero state, while keeping `events` only as optional enrichment for recording and meeting links.

### Hero Runtime Hardening
- **`src/components/sections/HeroSection.astro`**: The hero client payload now receives `kickoffAt` and `platformLabel` from the server-side `home_schedule` read. Post-kickoff fallback state is rendered from that runtime contract before any client-side `events` query completes.
- **Legacy event reads reduced**: The `events` lookup no longer decides whether kickoff already happened; it now only upgrades the UI with replay CTA and meeting-link enrichment when those records exist.

### Governance / Regression
- **`tests/ui-stabilization.test.mjs`**: Added a regression check ensuring the hero injects kickoff runtime metadata and no longer derives post-kickoff state from `ev.date + 'T22:30:00Z'`.
- **Backlog / governance / permissions / README** updated to reflect this public runtime follow-through with no ACL or site-hierarchy impact.

### Files Changed
- `src/components/sections/HeroSection.astro`
- `tests/ui-stabilization.test.mjs`
- `backlog-wave-planning-updated.md`, `docs/RELEASE_LOG.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `README.md`

### Audit Results
- Build: clean | Tests: 25/25 | Browser guard: OK | Smoke: routes OK

---

## 2026-03-11 — v0.20.0 Wave 22: Public Cycle Copy Cleanup

### Scope
Wave 22 closes another small public-home drift point by removing the last fixed `Cycle 3` labels from visible home copy where runtime cycle metadata is not yet available.

### Public Home Copy Cleanup
- **`src/i18n/pt-BR.ts`**, **`src/i18n/en-US.ts`**, **`src/i18n/es-LATAM.ts`**: The hero badge, CPMAI empty-state message, and Team section subtitles now refer generically to the current cycle instead of hardcoding `Cycle 3`.

### Governance / Regression
- **`tests/ui-stabilization.test.mjs`**: Added a regression check ensuring the old public `Cycle/Ciclo 3` strings removed in this wave do not return.
- **Backlog / governance / permissions / README** updated to reflect that this wave changes public copy only, with no ACL or site-hierarchy impact.

### Files Changed
- `src/i18n/pt-BR.ts`, `src/i18n/en-US.ts`, `src/i18n/es-LATAM.ts`
- `tests/ui-stabilization.test.mjs`
- `backlog-wave-planning-updated.md`, `docs/RELEASE_LOG.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `README.md`

### Audit Results
- Build: clean | Tests: 24/24 | Browser guard: OK | Smoke: routes OK

---

## 2026-03-11 — v0.19.0 Wave 21: Resources Runtime Fallback Alignment

### Scope
Wave 21 closes the next public-home runtime gap by aligning `ResourcesSection` fallback content with the same selection deadline already passed through the landing page and by removing Portuguese-only fallback copy from the shared component.

### Resources Runtime Follow-Through
- **`src/components/sections/ResourcesSection.astro`**: The YouTube playlist fallback card now formats the runtime selection deadline instead of embedding the old `Sáb 12h` text, and the rest of the fallback resource cards now resolve their titles/descriptions through locale keys.
- **`src/pages/index.astro`**, **`src/pages/en/index.astro`**, **`src/pages/es/index.astro`**: The existing `deadlineIso` flow is now also passed into `ResourcesSection`, keeping another public home surface aligned with `home_schedule`.
- **i18n**: Added localized fallback keys for the resources cards so the shared component no longer defaults to Portuguese copy on English or Spanish pages.

### Governance / Regression
- **`tests/ui-stabilization.test.mjs`**: Regression coverage expanded to ensure the home pages wire `deadlineIso` into `ResourcesSection` and that the old playlist fallback string does not return.
- **Backlog / governance / permissions / README** updated to reflect this smaller Wave 21 follow-through on the public runtime track.

### Files Changed
- `src/components/sections/ResourcesSection.astro`
- `src/pages/index.astro`, `src/pages/en/index.astro`, `src/pages/es/index.astro`
- `src/i18n/pt-BR.ts`, `src/i18n/en-US.ts`, `src/i18n/es-LATAM.ts`
- `tests/ui-stabilization.test.mjs`
- `backlog-wave-planning-updated.md`, `docs/RELEASE_LOG.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `README.md`

### Audit Results
- Build: clean | Tests: 23/23 | Browser guard: OK | Smoke: routes OK

---

## 2026-03-11 — v0.18.0 Wave 20: Generic Home Fallback Cleanup

### Scope
Wave 20 closes another small public-home reliability gap by removing the last fixed kickoff and recurring-meeting fallback copy that could resurface outdated March dates when runtime schedule data is missing or partial.

### Home Fallback Hardening
- **`src/i18n/pt-BR.ts`**, **`src/i18n/en-US.ts`**, **`src/i18n/es-LATAM.ts`**: Hero and agenda fallback strings now point generically to the current cycle agenda/schedule instead of embedding fixed kickoff dates or recurring meeting times.
- **`src/components/sections/HeroSection.astro`**: The remaining inline client-side defaults for meeting labels now fall back to generic cycle wording rather than `Thursdays 19:30 BRT` style literals.

### Governance / Regression
- **`tests/ui-stabilization.test.mjs`**: Added a regression check ensuring the old hardcoded kickoff dates and recurring time strings do not reappear in locale bundles or in the hero fallback shell.
- **Backlog / governance / permissions / README** updated to reflect that this wave changes public fallback copy only, with no ACL or site-hierarchy impact.

### Files Changed
- `src/components/sections/HeroSection.astro`
- `src/i18n/pt-BR.ts`, `src/i18n/en-US.ts`, `src/i18n/es-LATAM.ts`
- `tests/ui-stabilization.test.mjs`
- `backlog-wave-planning-updated.md`, `docs/RELEASE_LOG.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `README.md`

### Audit Results
- Build: clean | Tests: 22/22 | Browser guard: OK | Smoke: routes OK

---

## 2026-03-11 — v0.17.0 Wave 19: Agenda Runtime Deadline Sync

### Scope
Wave 19 closes the next small home-runtime gap by replacing the fixed tribe-selection date inside `AgendaSection` with the same runtime deadline already used by the landing hero and tribes surfaces.

### Home Runtime Follow-Through
- **`src/components/sections/AgendaSection.astro`**: The "Research Streams / Dinâmica das Tribos" agenda item now formats the runtime selection deadline instead of embedding a fixed March date in localized copy.
- **`src/pages/index.astro`**, **`src/pages/en/index.astro`**, **`src/pages/es/index.astro`**: The existing `deadlineIso` flow is now passed into `AgendaSection`, keeping the public home timeline surfaces consistent.
- **i18n**: Added lightweight `agenda.item3.descPrefix` keys so the runtime deadline can remain localized without hardcoding a specific date into copy.

### Governance / Regression
- **`tests/ui-stabilization.test.mjs`**: Regression test expanded to ensure all home pages wire `deadlineIso` into `AgendaSection`.
- **Backlog / governance / README** updated to reflect this smaller Wave 19 follow-through on the home-runtime track.

### Files Changed
- `src/components/sections/AgendaSection.astro`
- `src/pages/index.astro`, `src/pages/en/index.astro`, `src/pages/es/index.astro`
- `src/i18n/pt-BR.ts`, `src/i18n/en-US.ts`, `src/i18n/es-LATAM.ts`
- `tests/ui-stabilization.test.mjs`
- `backlog-wave-planning-updated.md`, `docs/RELEASE_LOG.md`, `docs/GOVERNANCE_CHANGELOG.md`, `README.md`

### Audit Results
- Build: clean | Tests: 21/21 | Browser guard: OK | Smoke: routes OK

---

## 2026-03-11 — v0.16.0 Wave 18: Home Runtime Messaging & Browser Coverage Expansion

### Scope
Wave 18 extends the home schedule hardening work by replacing more static kickoff/meeting copy with runtime `home_schedule` data and by widening browser validation to cover both the public home state and the LGPD-sensitive selection guard.

### Home Runtime Messaging
- **`src/lib/schedule.ts`**: Added shared `getHomeSchedule()` so landing pages can read the full schedule contract once instead of resolving only the selection deadline.
- **`src/pages/index.astro`**, **`src/pages/en/index.astro`**, **`src/pages/es/index.astro`**: Home pages now pass the shared runtime schedule object into `HeroSection`.
- **`src/components/sections/HeroSection.astro`**: The initial event badge and recurring meeting labels now derive from `kickoff_at`, `platform_label`, `recurring_weekday`, `recurring_start_brt`, and `recurring_end_brt`. The cycle-status shell also becomes visible immediately after the deadline state flips, even before Supabase counts load.

### Browser Coverage Expansion
- **`tests/browser-guards.test.mjs`**: Browser smoke now checks two critical behaviors in one run: anonymous denial on `/admin/selection` and public home runtime behavior after the configured deadline.
- **`tests/ui-stabilization.test.mjs`**: Added a regression check that all localized home pages use the shared `getHomeSchedule()` flow.

### Governance / Docs
- **Backlog / governance / permissions / README** updated to reflect Wave 18 scope and the new home-runtime direction.
- **i18n**: Added lightweight prefix keys so runtime meeting labels stay localized while using DB-backed schedule values.

### Files Changed
- `src/lib/schedule.ts`
- `src/pages/index.astro`, `src/pages/en/index.astro`, `src/pages/es/index.astro`
- `src/components/sections/HeroSection.astro`
- `src/i18n/pt-BR.ts`, `src/i18n/en-US.ts`, `src/i18n/es-LATAM.ts`
- `tests/ui-stabilization.test.mjs`, `tests/browser-guards.test.mjs`
- `backlog-wave-planning-updated.md`, `docs/RELEASE_LOG.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `README.md`

### Audit Results
- Build: clean | Tests: 21/21 | Browser guard: OK | Smoke: routes OK

---

## 2026-03-11 — v0.15.0 Wave 17: Home Schedule Hardening & Browser Guard Base

### Scope
Wave 17 removes the artificial far-future deadline fallback from the home selection flow, restores the live Supabase migration audit path on this workstation, and adds the first browser-based ACL regression check.

### Home Schedule Hardening
- **`src/lib/schedule.ts`**: Selection deadline now resolves to a real value or `null`; the landing flow no longer treats a fake `2030-12-31` timestamp as operational truth.
- **`src/components/sections/HeroSection.astro`**: Countdown only renders when a valid schedule deadline exists; cycle status takes over cleanly when the deadline is absent or already closed.
- **`src/components/sections/TribesSection.astro`**: Selection status now reflects runtime schedule state (`open`, `closed`, `pending`), and regular members are no longer kept artificially in an always-open path when `home_schedule` is missing.

### Browser Guard Base
- **`tests/browser-guards.test.mjs`**: New Playwright-backed browser smoke verifies that `/admin/selection` still denies anonymous visitors.
- **`package.json`**: Added `npm run test:browser:guards` as the first dedicated browser validation entrypoint.

### Operational / Governance
- **Supabase CLI**: `supabase migration list` now succeeds again without the earlier auth/debug workaround, confirming `44/44 local == remote`.
- **Docs**: Backlog, governance, README, permissions, and DB access notes updated for the new schedule behavior and restored live audit path.

### Files Changed
- `src/lib/schedule.ts`
- `src/components/sections/HeroSection.astro`, `src/components/sections/TribesSection.astro`
- `src/i18n/pt-BR.ts`, `src/i18n/en-US.ts`, `src/i18n/es-LATAM.ts`
- `tests/ui-stabilization.test.mjs`, `tests/browser-guards.test.mjs`, `package.json`
- `backlog-wave-planning-updated.md`, `docs/RELEASE_LOG.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `docs/AI_DB_ACCESS_SETUP.md`, `README.md`

### Audit Results
- Build: clean | Tests: 20/20 | Browser guard: OK | Smoke: routes OK

---

## 2026-03-11 — v0.14.0 Wave 16: Supabase Audit, Attendance/Profile/Selection Stabilization

### Scope
Wave 16 closes the next stabilization tranche after v0.13.0: it carries forward the attendance ACL/modal cleanup already merged on `main`, refreshes linked Supabase schema types, corrects migration-count drift, and reduces fragile UI wiring in `profile` and `admin/selection`.

### Supabase Audit / Drift Fix
- **Repo + linked schema**: `supabase/migrations/` now documented as `44` tracked migrations; `npm run db:types` refreshed `src/lib/database.gen.ts` from the linked project and re-synced generated types with the current remote schema.
- **Operational note**: This wave ships **no new migration**. `supabase migration list` on this workstation currently requires DB credential refresh, so the live schema proof for this sprint comes from linked type generation plus the tracked migration set.

### Stabilization
- **`src/pages/attendance.astro` + attendance modals**: Management actions remain `leader+`, modal interactions stay on delegated handlers, and regression coverage protects against inline-handler reintroduction.
- **`src/pages/profile.astro`**: Credly normalization now uses delegated listeners (`focusout`, `paste`, `input`) instead of re-binding handlers after each `renderProfile(...)`.
- **`src/pages/admin/selection.astro`**: Cycle tabs and snapshot title now resolve from runtime cycle metadata via `loadCycles()` / `getCurrentCycle()`, preserving the existing `admin_selection` and LGPD gate while removing fixed cycle copy.
- **`src/components/ui/ConfirmDialog.astro`**: Confirm actions now use a static button listener plus stored callback state, eliminating mutable `btn.onclick` rewiring.

### Governance / Docs
- **Docs drift corrected**: `AGENTS.md`, `backlog-wave-planning-updated.md`, `README.md`, `docs/PERMISSIONS_MATRIX.md`, and `docs/GOVERNANCE_CHANGELOG.md` updated for Wave 16, current priorities, and the real migration count.
- **Regression tests**: Added textual stabilization checks for profile delegation, selection cycle hardcodes, and confirm dialog callback wiring.

### Files Changed
- `src/pages/profile.astro`, `src/pages/admin/selection.astro`
- `src/components/ui/ConfirmDialog.astro`
- `src/lib/database.gen.ts`
- `tests/ui-stabilization.test.mjs`, `package.json`
- `AGENTS.md`, `README.md`, `backlog-wave-planning-updated.md`
- `docs/RELEASE_LOG.md`, `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`

### Audit Results
- Build: clean | Tests: 18/18 | Smoke: routes OK

---

## 2026-03-11 — v0.13.0 Wave 15: Cycle-Config Hardening

### Scope
Wave 15 removes the highest-impact cycle/date hardcodes from active operational surfaces, moving admin, profile, and tribe flows to the DB-backed `list_cycles` model before the next stabilization tranche.

### Cycle-Config Hardening
- **`src/pages/profile.astro`**: My Week and cycle timeline now resolve the active cycle from `loadCycles()` / `getCurrentCycle()` instead of hardcoding `cycle_3`; dashboard fallback title is generic per locale.
- **`src/pages/tribe/[id].astro`**: Deliverable reads and writes now use the active cycle resolved at runtime, eliminating direct `cycle_3` coupling in the tribe workspace flow.
- **`src/pages/admin/index.astro`**: Cycle history, add-record actions, and default date filters now derive from `list_cycles` maps instead of deprecated local cycle constants or `'2026-01-01'`.

### Compatibility Cleanup
- **`src/lib/admin/constants.ts`**: Legacy `CYCLE_META` / `CYCLE_ORDER` exports removed from the active admin path.
- **`src/lib/cycles.ts`**: Helper now uses the correct Supabase client type, removing the previous build warning.
- **`src/lib/cycle-history.js`**: Keeps a bounded label fallback for sparse legacy records/tests while operational reads prefer DB-backed cycle data.

### Governance / Docs
- **Backlog**: Wave 15 marked complete with audit notes in `backlog-wave-planning-updated.md`.
- **Governance**: `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, and `docs/project-governance/PROJECT_ON_TRACK.md` now reflect the current cycle-config status and remaining residual debt.
- **README**: Immediate priorities updated after moving the main cycle-aware surfaces to `list_cycles`.

### Files Changed
- `src/pages/profile.astro`, `src/pages/tribe/[id].astro`, `src/pages/admin/index.astro`
- `src/lib/cycles.ts`, `src/lib/cycle-history.js`, `src/lib/admin/constants.ts`
- `src/i18n/pt-BR.ts`, `src/i18n/en-US.ts`, `src/i18n/es-LATAM.ts`
- `README.md`, `backlog-wave-planning-updated.md`
- `docs/GOVERNANCE_CHANGELOG.md`, `docs/PERMISSIONS_MATRIX.md`, `docs/project-governance/PROJECT_ON_TRACK.md`

### Audit Results
- Build: clean | Tests: 13/13 | Smoke: routes OK (`SMOKE_PORT=4335`)

---

## 2026-03-11 — v0.12.0 Wave 14: Divergence Cleanup, Gap Audit & Deferred Structuring

### Scope
Wave 14 removes documentation drift, cleans residual PostHog/Looker references from the admin surface, starts a focused event delegation cleanup, and turns deferred items into actionable backlog lanes.

### Doc Divergence Cleanup
- **README.md**: Analytics stack and priorities updated to match native Chart.js + Supabase RPC dashboards, current engineering priorities, and local workflow with tests and smoke routes.
- **docs/MIGRATION.md**: Role drop, smoke routes, site hierarchy audit, and native analytics migration now reflect the current production state.
- **CONTRIBUTING.md**: Repository path fixed (`ai-pm-research-hub`), local workflow updated, PR checklist aligned with site hierarchy and 5-phase sprint closure.

### Admin Hygiene
- **`src/pages/admin/index.astro`**: Removed stale PostHog/Looker env refs and replaced the main batch of inline handlers with delegated `data-action` dispatch.
- **`src/pages/admin/comms.astro`**: Removed legacy Looker mode toggle from the current UI path.
- **Shared UI**: `LangSwitcher`, `AuthModal`, and `ConfirmDialog` no longer use inline `onclick` attributes.
- **i18n**: Comms/admin labels now describe native platform dashboards instead of Looker/PostHog embeds.

### Deferred Structuring
- **Backlog**: `S23`, `S24`, `S-KNW7`, and webinar discovery now have lane ownership, dependencies, and clear exit criteria from deferred.
- **Benchmark notes**: Added lightweight references for RBAC/admin, knowledge hub, and webinars/event ops to support future requirement discovery.

### Site Hierarchy / Access Audit
- Verified current routes in `navigation.config.ts` still map to existing pages.
- Aligned `admin_webinars` in `AdminRouteKey` / route tier constants so navigation, route metadata, and permissions stay consistent.
- `PERMISSIONS_MATRIX.md` changelog updated after the Wave 14 audit.

### Files Changed
- `README.md`, `docs/MIGRATION.md`, `CONTRIBUTING.md`
- `src/pages/admin/index.astro`, `src/pages/admin/comms.astro`
- `src/components/nav/LangSwitcher.astro`, `src/components/ui/AuthModal.astro`, `src/components/ui/ConfirmDialog.astro`
- `src/i18n/pt-BR.ts`, `src/i18n/en-US.ts`, `src/i18n/es-LATAM.ts`
- `src/lib/admin/constants.ts`
- `backlog-wave-planning-updated.md`, `docs/PERMISSIONS_MATRIX.md`, `docs/GOVERNANCE_CHANGELOG.md`

### Audit Results
- Build: clean | Tests: 13/13 | Smoke: routes OK

---

## 2026-03-11 — v0.11.0 Wave 13: Doc Hygiene (Edge Functions)

### Scope
Wave 13 corrects obsolete documentation: AGENTS.md and PROJECT_ON_TRACK now reflect that sync-credly-all and sync-attendance-points exist in the repo.

### Doc Hygiene
- **AGENTS.md**: "Where key things live" — Edge functions list updated; sync-credly-all and sync-attendance-points marked as present (13 functions total).
- **PROJECT_ON_TRACK**: Section 3 (Edge Functions) — all 5 functions marked present; F1 (Batch 1) marked Concluído; Frontend sem API table updated (gamification.astro OK); última verificação 2026-03-11.

### ResourcesSection Verification
- **W13.2**: ResourcesSection.astro already fetches from `hub_resources` client-side; static array is SSR fallback. Documented as Partial; SSR improvement deferred.

### Files Changed
- `AGENTS.md`, `docs/project-governance/PROJECT_ON_TRACK.md`
- `backlog-wave-planning-updated.md` (Wave 13, LATEST UPDATE)

### Audit Results
- Build: clean | Tests: 13/13

---

## 2026-03-11 — v0.10.0 Wave 12: Agent Interaction Docs, Release Workflow & Screenshots

### Scope
Wave 12 documents the 5-phase routine for agent interaction, adds Semantic Versioning release workflow, and delivers S-SC1 multilingual screenshot script.

### Agent Interaction Docs
- **AGENTS.md**: New "Interação com agentes" — checklist ao iniciar (backlog, site hierarchy, PERMISSIONS) e ao encerrar (5-phase). Migrations count 42.
- **SPRINT_IMPLEMENTATION_PRACTICES**: Cross-ref to AGENTS.md agent interaction.
- **AGENT_BOARD_SYNC**: Repo corrected from `ai-pm-hub-v2` to `ai-pm-research-hub`.

### Release Workflow (Semantic Versioning)
- **`.github/workflows/release-tag.yml`**: `workflow_dispatch` with version input; creates and pushes tag vX.Y.Z. Tech debt Semantic Versioning → Addressed.

### S-SC1 Multilingual Screenshots
- **`scripts/screenshots-multilang.mjs`**: Playwright script captures /, /en, /es (index, workspace, artifacts, gamification). Saves to `docs/screenshots/`.
- **`npm run screenshots:multilang`**, **`npm run screenshots:setup`** (playwright install chromium).

### Files Changed
- `AGENTS.md`, `docs/AGENT_BOARD_SYNC.md`, `docs/project-governance/SPRINT_IMPLEMENTATION_PRACTICES.md`
- `.github/workflows/release-tag.yml` (new)
- `scripts/screenshots-multilang.mjs` (new)
- `package.json` (playwright devDep, screenshots scripts)
- `backlog-wave-planning-updated.md`, `docs/PERMISSIONS_MATRIX.md`, `docs/GOVERNANCE_CHANGELOG.md`

### Audit Results
- Build: clean | Tests: 13/13 | Site hierarchy: OK

---

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
