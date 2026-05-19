# Release Log

## 2026-05-19 — p201 hotfix: Attendance grid + curatorship access

### Scope
Hotfixes para `/attendance` e `/admin/curatorship`: `get_attendance_grid` retornava HTTP 400 no PostgREST; `get_tribe_attendance_grid` mostrava N/A para reunião de tribo sem linhas de presença; a ilha de curadoria ignorava capacidades V4 `curate_content`.

### Delivered
- Migration `20260722010000_p201_fix_attendance_grid_status_ambiguity.sql` qualifica `status` como `cs2.status` / `cs3.status` em `detractor_calc`, sem mudar assinatura da RPC.
- Migration `20260722020000_p201_fix_tribe_attendance_empty_event_absent.sql` remove a branch `row_count=0 -> na` em `get_tribe_attendance_grid`, para que evento elegível de hoje/passado sem marcação apareça como `absent`.
- `src/components/boards/CuratorshipBoardIsland.tsx` e `src/components/nav/AdminNav.astro` passam a aceitar `canFor('curate_content')` e `canFor('participate_in_governance_review')` além do gate legado `admin.curation`.
- SQL aplicado diretamente via Supabase MCP porque `supabase db push` está bloqueado por drift antigo de migration history; migration marcada como aplicada com `supabase migration repair --status applied 20260722010000`.
- Segunda migration marcada como aplicada com `supabase migration repair --status applied 20260722020000`.

### Validation
- API log confirmou o 400 em `POST /rest/v1/rpc/get_attendance_grid`; Postgres log no mesmo timestamp confirmou `column reference "status" is ambiguous`.
- `pg_get_functiondef` confirmou a função live com `cs2.status` e `cs3.status`.
- Chamada SQL simulando usuário autenticado retornou JSON com `summary`, `events` e `tribes`.
- Simulação de Marcos Klemz na Tribo 7 para o evento `4b31e97d-2b63-4548-91af-65adbec6fb46` retorna `today_status='absent'`.
- DB confirma Roberto Macêdo e Sarah Faria com `curate_content=true` e `participate_in_governance_review=true`.
- `check_schema_invariants()` permaneceu 16/16 em 0 violações.

### Rollback
Restaurar o corpo anterior de `get_attendance_grid(integer, text)` a partir de `20260722000000_p201_bug_201_a_cancelled_event_attendance_display.sql`. Para `get_tribe_attendance_grid`, reinserir a branch `WHEN COALESCE(erc.row_count, 0) = 0 THEN 'na'` antes do `ELSE CASE`. Para curadoria, reverter `CuratorshipBoardIsland` e `AdminNav` ao gate legado `hasPermission(..., 'admin.curation')`. Usar somente para bisect emergencial, pois os rollbacks reintroduzem os bugs reportados.

## 2026-05-19 — p40-p201 release backfill: structural milestones

### Scope
Backfill resumido das principais entregas entre o baseline pós-V4 (`2026-04-17`) e os hotfixes p201. Este bloco não substitui o histórico detalhado em ADRs/migrations/git log; serve como ponte auditável para release governance.

### Milestones
- **p40-p64 — V4 RPC/RLS hardening + subsystem retirement:** Phase B'' conversions, service-role adapter pattern, ingestion/release-readiness/governance-bundle retirement. ADRs 0025-0040 e GC-141.
- **p65-p106 — MCP expansion + threat model + meeting traceability:** ADR-0018 mitigations, confirmation gates, rate limits/anomaly detection, meeting-board traceability closure. ADRs 0045-0049 e 0053-0058.
- **p116-p126 — PMI Journey + CV extraction + LGPD substrate:** portal/token substrate, CV text extraction, consent/legal-basis work and retention/anonymization extensions. ADRs 0075-0076 and related migrations.
- **p150-p159 — Selection AI/video + dual-track onboarding:** subjective/video scoring, interview automation, dual-track application/onboarding data and dashboard metadata.
- **p160-p166 — Gamification config + Champions + capability cache:** ADR-0081, ADR-0083, XP pillar/rules refactors, Champion ledger, V4 UI gates.
- **p168-p173 — Attendance/selection sync + VEP linkage + multi-leader digest:** ATT-1/2/3, canonical impact hours, VEP→engagement FK, invariant Q, leader digest expansion.
- **p176-p181 — RPC drift capture and tier cleanup:** broad RPC body drift sweeps, LGPD gates, `has_min_tier` V4 replacement and removal.
- **p190-p195 — Cross-initiative metrics and selection storage:** ADR-0085 metric scoping, governance-review carve-outs, selection resume/profile storage improvements.
- **p196-p198 — Curation FSM and committee workspace:** ADR-0086, peer/leader review flow, Curadoria workspace seed and live Débora case.
- **p200-p201 — Curator V4 action and p201 hardening:** ADR-0087 `curate_content` sweep, document_* RLS carry identified, MCP/docs audit, Cloudflare 1010 diagnosis, attendance/curatorship hotfixes.

### Validation
- p201 audit confirmed MCP runtime `tools/list=293`, `nucleo-mcp /health=293`, and `check_schema_invariants()` 16/16 with 0 violations.
- Hotfix-specific validation lives in the p201 hotfix entry above.

### Follow-up
- Full per-session release reconstruction remains open as governance debt; see `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` item #31 and `docs/audit/P201_MCP_ARCHITECTURE_AUDIT.md`.

## 2026-04-17 — v3.2.1: Post-V4 Structural Quality — ADR-0011/0012/0013 + Governance Baseline + Advisor CI

### Scope
Sessão de qualidade estrutural pós-cutover V4. 24 commits em um dia cobrindo três eixos: autoridade (can_by_member em todas as camadas), consolidação de schema (invariantes, drift trigger, audit log unification), e governance tooling (SECURITY/GOVERNANCE docs, pre-commit, advisor drift CI). Sem features user-facing — puro hardening.

### Delivered

#### Eixo A — ADR-0011 V4 Auth Pattern
- **ADR-0011** criado (`acbe431`) — `can()`/`can_by_member()` é única fonte de autoridade em RPC, MCP, RLS. Role list hardcoded é anti-pattern.
- **A4.1** (`d120272`, mig `20260424040000`) — 3 event RPCs (`create_event`, `update_event`, `drop_event_instance`) usam `can_by_member('manage_event')`.
- **A4.2** (`297e1f5`, mig `20260424050000`) — 6 member admin RPCs usam `can_by_member('manage_member'/'promote')`.
- **A4.3** (`3fc78c9`, mig `20260424060000`) — 3 PII read RPCs usam `can_by_member('view_pii')`.
- **Anti-drift test** (`7afbec0`) — `rpc-v4-auth.test.mjs` parseia novas migrations pós-cutover e exige `can_by_member` em RPCs com auth gate. Baseline: 17/94 RPCs V4-compliant (70 restantes são legacy, migração inline).

#### Eixo B — ADR-0012 Schema Consolidation
- **ADR-0012** criado (`5c82e42`) — 6 princípios para evitar drift entre colunas que representam o mesmo conceito (fact × dim × cache). Cache columns exigem trigger de sync (coerce, not reject).
- **B5+B7** (`101916f`, mig `20260424070000`) — saneamento de 9 rows de drift de membro + `trg_sync_member_status_consistency` (BEFORE UPDATE coerce trigger).
- **B8** (`2e0fe45`, mig `20260425020000`) — audit log consolidation: 34 rows backfilled de `member_role_changes` + `member_status_transitions` → `admin_audit_log`; 3 RPCs reescritas (`export_audit_log_csv`, `admin_offboard_member`, promote paths); 2 tabelas movidas para `z_archive`.
- **B9** (`b727bda`, mig `20260425030000`) — drop `list_volunteer_applications` (não usada); `volunteer_applications` mantida como histórica frozen. `trg_audit_events` verificado em INSERT/UPDATE/DELETE.
- **B10** (`ef84ba3`, mig `20260425010000`) — `check_schema_invariants()` RPC valida 8 invariantes (A1 alumni, A2 observer, A3 active role, B is_active↔member_status, C designations terminal, D persons.auth_id, E engagement.active, F initiatives.legacy_tribe_id). `tests/contracts/schema-invariants.test.mjs`. Live baseline: 0 violations em todos 8.
- **Static contract** (`b19964a`) — `tests/contracts/schema-cache-columns.test.mjs`: 2 testes detectam ALTER TABLE ADD COLUMN em `members`/`engagements`/`initiatives` sem trigger de sync (cutover `20260426020000`) + reference map de 4 cache columns canônicas.
- **P2 fix** (`8032d57`, mig `20260426010000`) — `volunteer_funnel_summary` refactor: lê `selection_applications` + `selection_cycles` (80 rows ativas) em vez de `volunteer_applications` (143 frozen 10/Mar). Auth via ADR-0011, MCP tool #62 signature `cycle: number` → `cycle_code: string`.

#### ADR-0013 — Log Table Taxonomy
- **ADR-0013** criado (`8380bd6`) — 5 categorias para classificar log tables: (A) Admin Audit → consolidar em `admin_audit_log`; (B) Domain Lifecycle Events → separada; (C) High-Volume → separada IO; (D) Distinct Retention → separada compliance; (E) External Ingestion → separada payload bruto. Default para novas tabelas: Categoria A.

#### Governance Baseline
- **`SECURITY.md`** — vuln reporting, lista de não-committar (JWTs, PII, service_role, real emails).
- **`GOVERNANCE.md`** — decision authority matrix, ADR lifecycle, trifold de conteúdo (repo público / wiki privado / frameworks públicos / SQL operacional), archive criteria.
- **`CONTRIBUTING.md`** atualizado — instruções de pre-commit + gitleaks.
- **`.githooks/pre-commit`** — secret scanner (JWT/sk_/ghp_/AWS/service_role + real emails) + warnings para TODO/FIXME + large files.
- **`.github/workflows/invariants-check.yml`** — roda `check_schema_invariants()` em push/PR/daily 07:00 UTC (requer secret `SUPABASE_SERVICE_ROLE_KEY`, já configurado).
- **`.github/workflows/advisors-check.yml`** + `scripts/check_advisors.mjs` + `scripts/advisor_baseline.json` (commit `8c7e284`) — advisor drift CI: 17 accepted findings documentados com rationale, PR paths + weekly Monday 08:00 UTC. Requer secret `SUPABASE_ACCESS_TOKEN` (PAT).
- **Skills/agents overhaul** (`269e30a`) — `platform-guardian` agent novo (pós-V4); skills `invariants` + `session-log` novas; `guardian` + `code-reviewer` + `audit` enhanced; `refactor-guardian` marcado legacy.

#### Bug fixes entregues
- **`drop_event_instance` two-step flow** (`86dec30`, mig `20260424010000`) — force attendance com confirm dialog + count.
- **`trg_audit_events` em events** (`5db043d`, mig `20260424020000`) — INSERT/UPDATE/DELETE capturados em `admin_audit_log` com `changed_fields` + `source` (user/system/orphan_auth).
- **`admin_offboard_member` consolidado** (`dee6407`, mig `20260424030000`) — fecha ghost data gap: 7 campos V4 + engagements em único pipeline atomico (Wellington case foi o sintoma).

#### Docs + housekeeping
- **CBGPL S3 materials** (`e68571c`) — `CBGPL_VIDEO_FALLBACK_3MIN.md` (teleprompter + CUEs) + `CBGPL_DRY_RUN_PLAN.md` (60min rehearsal) + `CBGPL_BLOG_POST.md`.
- **Wiki sync flow corrigido** (`5697b9e`) — docs atualizadas: webhook (não cron) + Obsidian Git plugin.
- **CLAUDE.md drift fix** (`ba03fae`) — test baseline 1184 → 1188 (pós rpc-v4-auth + schema-cache-columns + advisor tests).
- **Gitignore housekeeping** (`efa5374`, `3067ed2`) — `*.deb`/`*.rpm`/`*.AppImage` + `.claude/scheduled_tasks.lock`.

### Validation
- `npm test` ✅ 1195 total / 1188 pass / 7 skipped / 0 fail
- `npx astro build` ✅ 0 errors
- MCP smoke ✅ HTTP 200 + serverInfo
- `check_schema_invariants()` ✅ 8/8 em 0 violations (live DB)
- CI 5/5 green (Schema Invariants, Deploy Workers, CodeQL, Issue Gate, CI Validate)
- Advisor baseline ✅ 17 findings documentados (12 security_definer_view + 5 WARN, todos com rationale)

### Open tech debt (não-bloqueante)
- 70 RPCs legacy com role hardcoded — migrar inline quando tocar (não sweep)
- MEMBER_CHECK policies (~30) ainda dependem de `get_my_member_record()` legacy — Fase 4.2 opcional
- `comms_member` designation (2 users) preservada inline em 2 policies — mapear para engagement role em Fase 4.2

### Addendum (17/Abr p4 — entregues na mesma data):
- ✅ **B8.1 `platform_settings_log` consolidation** — migration `20260427020000` + fix P0 `get_audit_log` quebrada pós-B8. Ver commit `138639d`.
- ✅ **Retention policy ADR-0014** — `docs/adr/ADR-0014-log-retention-policy.md` + migration `20260427010000` (purge_expired_logs RPC + pg_cron mensal). Ver commits `4fc574e` + `1b4e6a0`.
- ✅ **Tribes deprecation ADR-0015** — `docs/adr/ADR-0015-tribes-bridge-consolidation.md` + Fase 0 reader audit. Fases 1-5 plan pendente. Ver commits `fe2f205` + `f96a3a9` + `5d68e4d`.
- ✅ **KV free-tier fix** — kvLog debug writes neutered em 5 routes + `/oauth/debug-logs` removido. Deploy `0db6fee8`. Conta upgraded para Cloudflare Paid Plan $5/mo. Ver commit `7740abf`.

### Addendum (17/Abr p5 — Fase 4.1 RLS sweep):
- ✅ **RLS V4 Fase 4.1** — migration `20260427030000` reescreve 42 policies role-gating (muito além do "5" inicialmente flagged). Cobertura: admin_links (4), members (5), ingestion_* (6), release_readiness_* (2), data_quality_audit_snapshots (2), tribe_continuity_overrides, tribe_lineage, project_memberships_write, pilots, vep_opportunities_insert_admin, trello_import_log, board_item_* (3 write), event_* (3 manage), board_lifecycle_events (2), communication_templates (2), broadcast_log tribe_leader, meeting_artifacts (2), cr_approvals, curation_review_log, selection_* (2), comms_* (4, comms_member preservado inline), webinars (3), taxonomy_tags. Mapping: `rls_is_superadmin()`, `rls_can('manage_member'|'write'|'write_board'|'manage_partner')`, `rls_can_for_tribe(...)`. `rls-auth-engagements.test.mjs` habilitado + novo test `rls-v4-phase4-1.test.mjs` (52 assertions). Tests baseline: 1188 → 1290 pass.

### Addendum (17/Abr p6 — Fase 4.2 RLS decoupling):
- ✅ **RLS V4 Fase 4.2** — migration `20260427040000` decoupla 23 SELECT policies do legacy `get_my_member_record()`. Novo helper `rls_is_member()` (STABLE SECURITY DEFINER, EXISTS on members.auth_id). Cobertura: 20 MEMBER_CHECK (EXISTS pattern → rls_is_member), 2 GHOST_CHECK (NOT EXISTS → NOT rls_is_member para events/webinars public view), 1 ROLE_GATE miss de Fase 4.1 (broadcast_log_read_admin → rls_is_superadmin + rls_can('manage_member')). **RLS layer agora 100% V4-native**: 0 policies referenciam operational_role, 0 referenciam get_my_member_record. Function `get_my_member_record()` mantida (70 RPC callers — out of scope). Novo contract test `rls-v4-phase4-2.test.mjs`. Tests: 1290 → 1330 pass.

### Addendum (17/Abr p7 — ADR-0015 Phase 1 webinars reader cutover):
- ✅ **ADR-0015 Phase 1 (webinars)** — migration `20260427050000` refactors 2 reader RPCs (`list_webinars_v2`, `webinars_pending_comms`) to JOIN `initiatives i` instead of `tribes t`. `tribe_name` now derived from `i.title` (initiatives column). Filter `p_tribe_id` now matches `i.legacy_tribe_id` instead of `w.tribe_id`. Output shape preserved identically (25 keys list_webinars_v2, all present). Smoke: 6/6 webinars return with `tribe_name` + `tribe_id` populated; filter by tribe_id=6 returns 2 rows correctly. Writer RPCs (`upsert_webinar`, `link_webinar_event`) unchanged — dual-write triggers still active until Phase 2. First C3 table out of 11. `tribes` table permanent; `webinars.tribe_id` column kept until Phase 3.

### Addendum (17/Abr p8 — ADR-0015 Phase 1 publication_submissions reader cutover):
- ✅ **ADR-0015 Phase 1 (publication_submissions)** — migration `20260427060000` refactors 3 reader RPCs (`get_publication_submissions`, `get_publication_submission_detail`, `get_publication_pipeline_summary`). LEFT JOIN tribes → initiatives; tribe_name derivado de `i.title`; filter via `i.legacy_tribe_id`; aggregation `GROUP BY initiative_id`. Dual-write integrity: 8/8 both. Smoke: `get_publication_submissions()` 8/8 rows com tribe_name; `by_tribe` summary retorna 4 tribos agregadas corretamente (3+3+1+1=8); detail retorna tribe_name "ROI & Portfólio". Writer `create_publication_submission` unchanged. 2ª C3 table done de 11.

### Addendum (17/Abr p16 — Trigger audit + Phase 2 blocker identification):
- ✅ **Phase 2 trigger drop — BLOCKED** (safety check). Inventário: 22 triggers ativos (trg_a + trg_b × 11 C3 tables) + 2 sync functions. Writers RPCs ainda escrevem só `tribe_id` em: `upsert_webinar`, `link_webinar_event`, `create_publication_submission`, `admin_manage_publication`, `auto_publish_approved_article`, `create_pilot`, `update_pilot`, `save_presentation_snapshot`. Frontend direct queries ainda usam `tribe_id` em 5 lugares: `tribe/[id].astro:1459,1651`, `HeroSection.astro:249`, `KnowledgeIsland.tsx`, `BoardMembersPanel.tsx`. **Writer refactor is the correct pre-requisite** — droppar triggers sem refactor = regressão silenciosa. Scope documentado em `project_adr0015_writer_refactor_plan.md` (memory). Phase 2 adiada para próxima sessão. Phase 1 (leitura) permanece 100% completa.

### Addendum (17/Abr p22 — ADR-0015 Phase 2 COMPLETE — Dual-write triggers dropped):
- ✅ **ADR-0015 Phase 2 COMPLETA** — migration `20260427160000` dropa 24 triggers (`trg_a_sync_initiative_*` + `trg_b_sync_tribe_*`) em 12 tabelas: 11 C3 (webinars, broadcast_log, meeting_artifacts, publication_submissions, public_publications, events, pilots, ia_pilots, hub_resources, announcements, project_boards) + tribe_deliverables. Writers agora são 100% responsáveis pelo dual-write (feito em Commits 1-2), frontend também (Commit 3), e contract test impede regressões (Commit 5).
- ✅ **Preserved for Phase 5**: `members` ainda tem `trg_a` + `trg_b` (total 2 triggers). Cutover de `members.tribe_id` está deferido para pós-CBGPL (workstream separado). Funções `sync_initiative_from_tribe()` + `sync_tribe_from_initiative()` seguem vivas — triggers de members dependem delas.
- ✅ **Pre-drop validation**: live check confirmou 0 rows `tribe_only` em todas as 12 tabelas (trigger job cumprido em 100% dos rows existentes). F_initiative_legacy_tribe_orphan invariant: 0 violations.
- ✅ **Post-drop smoke**: INSERT em `webinars` com só `initiative_id` (sem tribe_id) pós-drop confirma trigger foi removido — `tribe_id` fica NULL em vez de ser backfilled. Transação rolled back. Comportamento esperado — writers em produção sempre setam ambos.
- ✅ **Validação**: tests 1332 pass / 0 fail (contract test ADR-0015 anti-regress continua green), `npx astro build` 0 errors (built in 4.64s), invariants 8/8 em 0 violations pós-drop.
- 🎉 **ADR-0015 Phase 2 FECHADA** — 6/6 commits da writer refactor workstream completos em 1 sessão. Próximo: **Phase 3** (DROP COLUMN tribe_id por tabela, irreversível, quarentena pós-CBGPL + quiet window). Phase 4 (views rewrite) e Phase 5 (members.tribe_id cutover) seguem deferidos.

### Addendum (17/Abr p21 — ADR-0015 writer refactor Commit 5 — Anti-regress test):
- ✅ **Contract test anti-regress** — novo arquivo `tests/contracts/adr-0015-dual-write.test.mjs` (+2 testes). Scan estático das migrations pós-cutover `20260427140000` (Commit 1): qualquer `INSERT INTO <C3>` cujo column list inclua `tribe_id` DEVE incluir `initiative_id`; qualquer `UPDATE <C3> SET ... tribe_id = ...` DEVE incluir `initiative_id = ...` no mesmo SET block. Allowlist `DUAL_WRITE_EXEMPT` disponível para backfills intencionais com rationale.
- ✅ **Self-check incluído**: segundo teste verifica que a migration de cutover (Commit 1) passa suas próprias regras — garante que o gate sempre começa green e qualquer regressão futura pega antes de virar commit em main.
- ✅ **12 C3 tables cobertas**: webinars, broadcast_log, meeting_artifacts, publication_submissions, public_publications, pilots, ia_pilots, hub_resources, announcements, project_boards, events, tribe_deliverables. Após Phase 3 (column drop), entradas serão removidas table-by-table dessa lista.
- ✅ **Registrado em package.json** scripts `test` + `test:contracts`. Tests totais 1330 → 1332 (+2 novos, 0 fail).
- **Progress**: 5/6 commits feitos. **Writer path + frontend + contract guardrail completos.** Commit 6 (Phase 2 trigger drop) agora é SAFE porque qualquer regressor de escrita seria pego pelo contract test antes de merge.

### Addendum (17/Abr p20 — ADR-0015 writer refactor Commit 4 — Frontend reads):
- ✅ **Frontend reads refactor**: 2 queries diretas em tabelas C3 migradas para preferir `initiative_id` sobre `tribe_id`, deixando a camada cliente Phase 3-ready (sobrevive ao drop da coluna `tribe_id`).
  - `src/pages/tribe/[id].astro` (loadBroadcastHistory): `.eq('tribe_id', TRIBE_ID)` → ternário que usa `INITIATIVE_ID` quando resolvido, com fallback tribe_id apenas enquanto a coluna legacy existir. Pattern espelha o `hub_resources` do mesmo arquivo.
  - `src/components/sections/HeroSection.astro` (loadHeroEvent): `.is('tribe_id', null)` → `.is('initiative_id', null)`. Semanticamente mais estrito — exclui 2 eventos `init_only` (tribe NULL + init NOT NULL), que são ligados a iniciativas específicas não-tribo (AIPM Ambassadors etc.). Correto para o intent do componente: "chapter-wide kickoff" deve excluir eventos de iniciativa específica.
- ℹ️ **Scope preserved**: `tribe/[id].astro:1651` (hub_resources) já tinha ternário initiative_id preferred — nada a mudar. `BoardMembersPanel.tsx` select `project_boards.tribe_id` é read de dropdown — será limpo em Phase 3 (column drop); não bloqueia Phase 2.
- ✅ **Validação**: tests 1330 pass / 0 fail, `npx astro build` 0 errors (built in 4.80s).
- **Progress**: 4/6 commits feitos. **Frontend read+write paths 100% trigger-independent.** Resta: Commit 5 (contract test anti-regress), Commit 6 (Phase 2 trigger drop — agora SAFE).

### Addendum (17/Abr p19 — ADR-0015 writer refactor Commit 3 — Frontend writes):
- ✅ **Frontend writes refactor**: as 2 páginas que fazem INSERT/UPDATE direto em tabelas C3 agora gravam `initiative_id` junto com `tribe_id`, removendo a última dependência dos dual-write triggers na camada cliente.
  - `src/components/admin/KnowledgeIsland.tsx`: antes do INSERT/UPDATE em `hub_resources`, o handler consulta `initiatives.id` via `legacy_tribe_id = tribe_id` e inclui `initiative_id` no payload. Custo adicional: 1 SELECT por save (aceitável — fluxo de admin raro).
  - `src/pages/attendance.astro` (2 ocorrências, `handleEventSave` com scope 'future' e 'this'): antes do `sb.from('events').update(updateFields)`, deriva `initiative_id` do `tribeId` selecionado e inclui no `updateFields`.
- ℹ️ **Confirmed scope minimal**: grep exaustivo sobre `.insert/.update/.upsert` em C3 tables retornou só estes 2 arquivos — todos os demais writes passam por RPC (já refatorados em Commits 1 e 2). `BoardMembersPanel.tsx` não é writer de C3 (só SELECT project_boards para dropdown); será tocado em Commit 4 (reads).
- ✅ **Validação**: tests 1330 pass / 0 fail, `npx astro build` 0 errors (built in 4.68s).
- **Progress**: 3/6 commits feitos. Next: Commit 4 (frontend reads em `tribe/[id].astro` + `HeroSection.astro` + `KnowledgeIsland.tsx` select), Commit 5 (contract anti-regress), Commit 6 (Phase 2 trigger drop — SAFE após 1-4 todos merged).

### Addendum (17/Abr p18 — ADR-0015 writer refactor Commit 2 — Writers Batch B):
- ✅ **ADR-0015 Writer Refactor Commit 2** — migration `20260427150000` refatora os 2 writers remanescentes identificados no audit prosrc pós-Batch A: `create_event` (events) e `upsert_tribe_deliverable` (tribe_deliverables). Ambos migrados para V4 auth (`can_by_member`) + dual-write `initiative_id`. Combined refactor motivado pelo contract test ADR-0011: strings `'Unauthorized'` em `RAISE EXCEPTION` (upsert_tribe_deliverable) e em `json_build_object` retornos (create_event) teriam sido flagradas.
- ✅ **create_event V4**: gate principal `can_by_member('manage_event')`; scope não-admin via `can_by_member('manage_member')` (admin-class ignora restrição; demais ficam limitados a type='tribo' na própria tribe + sem externals/invitees). Comportamento preservado — V4 apenas substitui role list hardcoded pelo permissões engagement-derived. INSERT events agora escreve `initiative_id` junto com `tribe_id` (derivado de `legacy_tribe_id`).
- ✅ **upsert_tribe_deliverable V4**: gate `can_by_member('write')` + tribe scope preservado para não-admins. INSERT path escreve ambas colunas; UPDATE path não toca `tribe_id` (apenas os campos de conteúdo), por isso `initiative_id` nunca drifta.
- ℹ️ **Out of scope confirmed**: `create_initiative_event` já usa V4 + dual-write (nada a mudar); `update_event`, `update_event_instance`, `update_future_events_in_group`, `update_event_duration`, `upsert_event_agenda`, `upsert_event_minutes`, `admin_update_board_columns` — nenhum escreve `tribe_id` em SET clauses, apenas em WHERE/auth checks.
- ✅ **Test contract update**: `tests/contracts/security-lgpd.test.mjs` atualizado — `create_event` shouldCheck passou de `operational_role` (V3) para `can_by_member` (V4). Comentário inline explica motivo e link para ADR-0011. Spirit do teste preservado: a RPC continua tendo check de autoridade baseado em papel.
- ✅ **Smoke trigger-disabled**: INSERT em events + tribe_deliverables com `session_replication_role='replica'` retornou `initiative_id` populado — prova independência de triggers. Rolled back.
- ✅ **Validação**: tests 1330 pass / 0 fail, `npx astro build` 0 errors, invariants 8/8 em 0 violations, F_initiative_legacy_tribe_orphan = 0.
- **Progress**: writer refactor estão nos commits 2/6. Next: Commit 3 (frontend writes em KnowledgeIsland.tsx + BoardMembersPanel.tsx), Commit 4 (frontend reads em tribe/[id].astro + HeroSection.astro), Commit 5 (contract anti-regress), Commit 6 (Phase 2 trigger drop — SAFE).

### Addendum (17/Abr p17 — ADR-0015 writer refactor Commit 1 — Writers Batch A):
- ✅ **ADR-0015 Writer Refactor Commit 1 (8 writers + 1 trigger fn)** — migration `20260427140000` remove a dependência de writer paths nos dual-write triggers, abrindo caminho para Phase 2. 7 RPCs + 1 trigger function derivam `v_initiative_id` de `legacy_tribe_id = p_tribe_id` e gravam **ambas** as colunas explicitamente: `upsert_webinar`, `link_webinar_event` (via `v_webinar.initiative_id` com fallback), `save_presentation_snapshot`, `create_publication_submission`, `admin_manage_publication` (create path), `auto_publish_approved_article` (lê `pb.initiative_id` do `project_boards`), `create_pilot`, `update_pilot`. Signatures (incl. DEFAULTs) preservadas via `CREATE OR REPLACE` — zero identity-argument drift.
- ✅ **Combined ADR-0011 V4 auth** em 2 dos 8 writers (session wrap lesson #6 — migrar V4 quando tocar auth-gated RPC): `save_presentation_snapshot` agora gateia via `can_by_member('manage_event')` com admin exception via `can_by_member('manage_member')` (tribe scope preservado); `create_publication_submission` via `can_by_member('write_board')` (tightening semântico vs "qualquer member ativo" — publicações são board-originated). Os outros 5 writers (`upsert_webinar`, `link_webinar_event`, `admin_manage_publication`, `create_pilot`, `update_pilot`) usam strings de exception (`access_denied`/`auth_required`/`Admin only`) que o contract test pós-cutover não flagra — permanecem tech debt para sweep dedicado.
- ✅ **Smoke test com triggers desabilitados** (`SET session_replication_role='replica'`): INSERT direto em webinars/meeting_artifacts/publication_submissions/public_publications/pilots/events retornou `initiative_id` populado em todas as 6 tabelas — prova que writers são trigger-independent. Transaction rolled back.
- ✅ **Validação**: tests 1330 pass / 0 fail (ADR-0011 contract test agora green após V4 auth nos 2 RPCs), `npx astro build` 0 errors, invariants 8/8 em 0 violations pré e pós-migration, F_initiative_legacy_tribe_orphan = 0.
- 🐞 **Bug latente descoberto (não corrigido)**: `link_webinar_event` passa `audience_level='general'` em INSERT events, mas `events_audience_level_check` só permite `all/leadership/tribe/curators`. Pré-existia desde a criação do RPC. Scope discipline — não corrigido neste commit, flag para backlog.
- **Próximos**: Commit 2 (events writers `create_event`/`update_event` — already V4 auth'd em A4.1), Commit 3 (frontend writes: KnowledgeIsland.tsx, BoardMembersPanel.tsx), Commit 4 (frontend reads: tribe/[id].astro, HeroSection.astro), Commit 5 (contract test anti-regress), Commit 6 (Phase 2 trigger drop — SAFE).

### Addendum (17/Abr p15 — ADR-0015 Phase 1c attendance grid RPCs — **PHASE 1 COMPLETE**):
- ✅ **ADR-0015 Phase 1 COMPLETA (11/11 C3 tables)** — migration `20260427130000` refatora os 2 RPCs complexos restantes: `get_attendance_grid` + `get_tribe_attendance_grid`. Combined ADR-0011 V4 auth + ADR-0015 JOIN swap. Auth gate top-level convertido de `operational_role IN (...)` + `designations &&` para `can_by_member('manage_member')` (admin) + `can_by_member('manage_partner')` (stakeholder) + `members.tribe_id = p_tribe_id` (own tribe member). Eligibility CTEs preservadas (business rule lê cache `operational_role` — não é auth gate, é classificação data-driven). Tests 1330 stable, invariants 8/8 em 0 violations. **ADR-0015 Phase 1 deliverable complete — 11/11 C3 tables fully migrated.**

### Addendum (17/Abr p14 — ADR-0015 Phase 1 events reader cutover part A):
- ✅ **ADR-0015 Phase 1 (events, 4/6 RPCs)** — migration `20260427120000` refactors 4 simpler reader RPCs: `get_meeting_detail`, `get_meeting_notes_compliance` (hybrid pattern simplificado para initiatives only + COALESCE fallback 'Gerais/sem tribo'), `get_recent_events`, `list_meetings_with_notes` (drop redundant tribes JOIN; initiatives JOIN já existia — agora single source). Dual-write: 150 both + 2 init-only + 118 neither (total 270). Smoke: 52 recent events, 5 tribes in notes compliance (68% overall). **11ª e última C3 table done (partial)** — `get_attendance_grid` + `get_tribe_attendance_grid` ficam para Phase 1c (scope grande: deep operational_role/designations logic requer combined ADR-0007/0011/0015 refactor). **Phase 1 core scope: 10/11 C3 tables fully migrated, events partial**.

### Addendum (17/Abr p13 — ADR-0015 Phase 1b project_boards auth-gated RPCs):
- ✅ **ADR-0015 Phase 1b (project_boards, 4/7 auth-gated RPCs)** — migration `20260427110000` combina JOIN swap + ADR-0011 V4 auth. Fecha project_boards Phase 1 (7/7 readers done). RPCs: `get_curation_dashboard` + `list_curation_pending_board_items` (→ `can_by_member('write_board')`), `get_portfolio_timeline` (admin = `manage_member`, stakeholder = `manage_partner`, scope filter preserved via member_id/tribe_id/chapter), `list_legacy_board_items_for_tribe` (access via `v_caller_id = v_leader_id OR can_by_member('manage_member')`). Tests 1330 pass.

### Addendum (17/Abr p12 — ADR-0015 Phase 1 project_boards reader cutover part A):
- ✅ **ADR-0015 Phase 1 (project_boards, 3/7 RPCs)** — migration `20260427100000` refactors 3 clean reader RPCs: `list_project_boards` (canonical), `exec_portfolio_board_summary` (CTE aggregate), `get_portfolio_dashboard` (artifacts + by_tribe aggregates). All JOIN tribes → initiatives, `tribe_name` via `i.title`. Signature `get_portfolio_dashboard(p_cycle integer DEFAULT 3)` preservada (corrigido primeiro apply). Smoke: 10 active boards all with tribe_name; 4 lanes no summary; 50 artifacts + 7 tribes no dashboard. Dual-write: 9 both + 3 init-only + 2 neither (14 total). 10ª C3 table — **Phase 1 partial**: 4 RPCs auth-gated (get_curation_dashboard, get_portfolio_timeline, list_curation_pending_board_items, list_legacy_board_items_for_tribe) ficam para **Phase 1b** (commit separado com V4 auth refactor).

### Addendum (17/Abr p11 — ADR-0015 Phase 1 bundled cutover: hub_resources + pilots + ia_pilots + announcements + public_publications):
- ✅ **ADR-0015 Phase 1 bundled (5 tables)** — migration `20260427090000` refactors 4 RPCs covering 5 C3 tables em 1 commit atômico. RPCs: `list_curation_board` (hub_resources block → JOIN initiatives), `list_pending_curation` (hub_resources block → JOIN initiatives + **bonus ADR-0011 V4 auth fix**: `operational_role IN` → `can_by_member('write')`), `get_pilots_summary` (LEFT JOIN initiatives), `get_public_publications` (filter via `i.legacy_tribe_id`). Data reality: hub_resources 330 rows (157 both + 173 global), ia_pilots/pilots/announcements 1 row each (all global), public_publications 7 rows (all global). Low-risk cutover — muitas rows já eram globais. search_hub_resources + get_publication_detail não precisaram refactor (sem JOIN/filter). get_public_impact_data não usa tribe_id destas tabelas. Tests 1330 pass após ADR-0011 V4 fix. 9ª C3 table done de 11. 6 commits ADR-0015 hoje.

### Addendum (17/Abr p10 — ADR-0015 Phase 1 broadcast_log reader cutover):
- ✅ **ADR-0015 Phase 1 (broadcast_log)** — migration `20260427080000` refactors 2 RPCs. `broadcast_history`: LEFT JOIN tribes → initiatives, `i.title AS tribe_name`, filter via `i.legacy_tribe_id`. `broadcast_count_today`: INNER JOIN initiatives (tribe_id NOT NULL invariant). Return TABLE shape preserved. Gotcha encontrado: parameter order mismatch entre nova migration e signature existente (`p_tribe_id, p_limit`) — fix manteve ordem original pois callers usam named params. Smoke: 25/25 broadcasts, filter por Radar Tecnológico retorna 7 rows. 4ª C3 table done de 11.

### Addendum (17/Abr p9 — ADR-0015 Phase 1 meeting_artifacts reader cutover):
- ✅ **ADR-0015 Phase 1 (meeting_artifacts)** — migration `20260427070000` refactors 2 reader RPCs. `list_meeting_artifacts` agora filtra via `LEFT JOIN initiatives + legacy_tribe_id` em vez de `tribe_id` direto. `list_initiative_meeting_artifacts` elimina dependência de `resolve_tribe_id()` (bridge call) — agora filtra `initiative_id` nativamente. SETOF meeting_artifacts return preservado. Dual-write: 11 both + 1 neither (outlier, handled by LEFT JOIN NULL). Smoke: unfiltered 12 rows, filtered por tribe/initiative ambos retornam 9 (matching + null). Writer `save_presentation_snapshot` unchanged. 3ª C3 table done de 11. Bug bonus corrigido: `list_initiative_meeting_artifacts` para initiatives não-tribo (legacy_tribe_id=NULL) antes retornava TUDO via resolve_tribe_id=NULL + list_meeting_artifacts fallback; agora filtra corretamente pela initiative.

### Known issues
- `apply_migration` MCP não registra em `supabase_migrations.schema_migrations` — workaround `INSERT ON CONFLICT DO NOTHING` manual documentado no `platform-guardian` checklist.

---

## 2026-04-15 → 2026-04-16 — v3.2.0: Initiative Pages + Comms/Instagram + Security Hardening

### Scope
47 commits em dois dias consolidando três frentes: (1) CR-051 Initiative Pages — página própria por iniciativa com board inline, membros, eventos, attendance, gamification nativos; (2) Comms analytics — Instagram Graph API integration, redesign de páginas comms (operational × analytics split), pg_cron daily sync; (3) Security hardening pós-advisor scan — 88 findings → 17 (−81%). Meeting rito migrado para biweekly. Upgrade Claude Opus 4.7.

### Delivered

#### CR-051 — Initiative Pages (MVP → Parity)
- **Data foundation + page MVP** (`d098bed`) — initiative page com tabs Visão/Membros/Eventos/Deliverables/Gamification.
- **MCP tools + nav** (`2cb9458`) — tools CRUD para initiative + nav entry `/initiatives`.
- **/initiatives catalog + version bump** (`00c7840`) — listagem de todas iniciativas + cards + filtros.
- **RPC-based loading + drawer UX** (`37f5c26`) — page carrega tudo via RPCs específicas (não direct queries).
- **Inline board + member management + status actions** (`0f0dccf`) — board Kanban inline, editar/remover membros, change status buttons.
- **Member RPCs + roles** (`b91ad1e`, `ee7efc2`, `bbb86ca`) — search/activate via RPC, edit role/remove, role permissions legend. CPMAI dashboard fix.
- **Events + cross-links + deliverables/attendance tabs** (`5c5be77`, `2dd1d3e`) — eventos da iniciativa + links cruzados `/cpmai`.
- **Gamification tab** (`f5cd599`) — carrega via RPC `get_initiative_gamification` (replaces inline JS with TribeGamificationTab island).
- **Full Parity fix** (`22b54e9`, `6d9fda7`, `5263d3f`) — 3 RPCs corrigidas: `get_initiative_attendance_grid` (CTE native, fixed buggy `SELECT tribe_id FROM tribes`), `get_initiative_stats` (native path), `get_initiative_gamification` (GamificationData shape). Iniciativas não-tribo (CPMAI, Hub Comms, Publicações) agora funcionam nativamente sem delegação a `get_tribe_*(NULL)`.
- **Meetings/attendance initiative-aware** (`c98a2bf`, `8780d1a`, `ba215a8`) — `list_meetings_with_notes` + `get_meeting_notes_compliance` + `get_events_with_attendance` com initiative_id/initiative_name. Attendance agrupa initiative events em seções próprias.
- **Smart roster scoping** (`ba215a8`) — initiative events → só engagement members (53→2 para CPMAI); 1on1/entrevista/parceria com attendance → só attendees (12→2); Liderança → audience_level leadership (53→17).
- **Trail ranking inverted logic** (`12536ca`) — `/7` hardcoded → `TOTAL_COURSES` dinâmico (6). Incluir só membros ativos (tribe_id NOT NULL ou functional role leader/coordinator/manager/participant); exclui 9 governance-only (sponsors, chapter_board, liaisons, observers). Avg 29% → 35%.
- **`update_future_events_in_group` uuid fix** (`a493327`) — `v_rec_group text` → `uuid` (estava causando 404).

#### Comms Analytics + Instagram
- **Instagram Graph API** (`5fb0613`) — permanent Page token, `ig_user_id=17841480236591775`, 212 followers. EF fix: `impressions` → `reach` + `accounts_engaged` + `total_interactions` (deprecated API handled).
- **Comms security** (`e547bae`) — channel config hidden from `comms_member` role (LGPD).
- **Comms pages redesign** (`4281230`) — split em `/admin/comms-ops` (operational: board, webinars, playbook, broadcasts, calendar) + `/admin/comms` (analytics: KPIs with delta, trend chart, per-channel, top content).
- **Analytics enhancements** (`aba36e0`) — CSV export, PDF via `window.print`, period comparison, best time heatmap, publication calendar, top content.
- **pg_cron daily sync** (`7e54443`) — job #21 (06:00 UTC), vault `sync_comms_secret`. `comms_media_items` table + `comms_top_media` + `comms_executive_kpis` RPCs. `comms_token_alerts` table criada.
- **PDF export compat** (`f7f5167`) — `window.print` (oklch-compat fix para browsers novos) + schema reload.
- **MCP workgroup kind** (`43c1f5a`) — tool descriptions atualizadas para workgroup initiative kind.

#### Meeting Rito Change (biweekly)
- General meetings → quinzenal
- Leadership meetings → alternate weeks (começo 16/Abr)
- 7 Liderança events ajustados (audience_level `all` → `leadership`)
- WhatsApp messages enviadas (general + leadership)

#### Navigation UX Overhaul
- **Iniciativas in top bar** (`b954c7e`) — tribe dropdown links to `/initiatives`.
- **Nav UX overhaul + curators separated** (`cb205fc`) — Comms Hub separado de curators list.
- **R1/R3/R4/R7 + workgroup kind** (`74663c1`) — nav clusters por role archetype.
- **Initiative parity + events isolation** (`3198ed2`) — meeting notes + events não vazam entre iniciativas.

#### Security Hardening (post-advisor scan)
- **RLS em audit tables** (`5637df3`, mig `20260423030000`) — `member_role_changes` + `selection_ranking_snapshots`.
- **search_path hardening** (`7c49dcd`, mig `20260423040000`) — 48 funções public (CVE-2018-1058).
- **Drop notif_insert_system** (`a0d407a`, migs `20260423050000`/`60000`) — permissive policy removida; REVOKE anon em `cycle_tribe_dim`.
- **DROP 16 MeridianIQ ghost tables** (`0e2a574`) — cross-contamination cleanup; `database.gen.ts` stripped −622 linhas.
- **Storage buckets hardened** (`e6230cf`, mig `20260423080000`) — `member-photos` (INSERT/UPDATE own, drop anon) + `member-signatures` (cross-user prevented). RLS `selection_membership_snapshots`.
- **Attendance grid future + Wellington observer fix** (`6e9602b`, mig `20260423090000`) — grid futuro tratado como scheduled (não absent); Wellington observer state sincronizado (7 campos V4).
- **Initiative-scoped events excluded from main grids** (`ef9b73e`, mig `20260423110000`) — CPMAI Kickoff não inflava mais Geral (era enrolando 51 membros).

Advisor delta: **88 findings → 17** (14 ERRORS → 12, 58 WARN → 5, 16 INFO → 0).

#### Certificate Integrity Audit
- **gov.br signer backfill + IP instruments** (`099309c`, mig `20260417010000`) — `scripts/extract-govbr-signers.py` extraiu PKCS7/CMS de 92 PDFs. Institutional signer é **LORENA DE SOUZA PAULA** (89/92 docs, dir. voluntários PMI-GO), não Ivan. 26 DSGN certs corrigidos (issued_by + counter_signed_by); 6 TERM counter-signed com gov.br data. 4 variantes `pdf.ts` (gov.br migrated, attestation, platform+gov.br, platform).

#### P1 UX Batch (16/Abr afternoon)
- **Event type/nature via future scope** (`d325cb4`, mig `20260423010000`) — `update_future_events_in_group` aceita p_type/p_nature com CHECK.
- **Past events paginated** (`a08ddbf`) — PAST_LIMIT=10 (Gerais 53 paginado).
- **Ata editor full toolbar** (`580d492`) — tiptap toolbar="full" (H2/H3/blockquote/hr/image/code) + `normalizeContent()` via marked para legacy.
- **Grid nature filter** (`28f8600`, mig `20260423020000`) — recorrente/avulsa/workshop/kickoff dropdown.

#### Upgrades + docs
- **Opus 4.7 upgrade** (`5357b58`) — Claude Opus 4.7 model + 18 npm packages updated.
- **Docs drift sync** (`4dea931`) — i18n dup (3 dicts), ADR README, INDEX.md, CLAUDE.md 22 EFs.
- **Ata Trentim + briefing liderança** (`1cdfbfd`) — ata reunião 15/Abr + briefing 16/Abr.

### Validation
- `npm test` ✅ 1184 pass / 0 fail
- `npx astro build` ✅ 0 errors
- MCP smoke ✅ 76 tools (61R+15W)
- 11 migrations aplicadas (20260423010000 → 110000)
- Supabase advisor 88 → 17 findings (−81%)

### Architecture notes
- Initiative events ficam escopados à página da iniciativa; main grids (/attendance, /meetings) excluem initiative_id. Initiative-awareness = feature, não bug.
- Trail ranking usa lógica invertida: incluir só active (não exclude governance). Mais sustentável a longo prazo.
- Grade future events = scheduled (não absent) — fix estrutural aplicado a `get_attendance_grid` e `get_tribe_attendance_grid`.

---

## 2026-04-14 — v3.1.0: Wiki Knowledge Layer + IP Policy Execution + DocuSign Integrity + Meeting Unification

### Scope
15 commits materializando quatro threads: (1) Wiki Knowledge Layer completo (Phases 2-5 do plano, culminando em ADR-0010); (2) IP Policy execução completa (E1-E5 de CR-050) — chapter_registry, adendo retificativo, cláusula 2.1-2.5, CNPJ dinâmico; (3) DocuSign cert integrity (34 certs hidratados, 26 counter-signed); (4) Meeting notes unification across 6 workstreams. MCP: 70 → 74 tools.

### Delivered

#### Wiki Knowledge Layer (ADR-0010)
- **ADR-0010** (`fe1cd41`) — Wiki Scope: Narrative Knowledge Only. SQL = operational data. Refino arquitetural do plano wiki.
- **Phase 2 — sync EF** (`74ed0e5`) — `sync-wiki` Edge Function (#22) deployed. GitHub push webhook → `wiki_pages` upsert. HMAC-SHA256 signature verification. GitHub PAT `nucleo-wiki-sync` (expires 2027-04-15). `search_wiki` enhanced com `domain` e `tag` filters.
- **Phase 3 — content migration** — 27 → 29 wiki pages com frontmatter estruturado (title, domain, summary, tags, authors, license, ip_track). 3 governance docs (manual, ip-policy, volunteer-term), 7 tribe pages (tribo-{1,2,4,5,6,7,8}.md), partnerships/cooperation-agreements, onboarding/guide.
- **Phase 4 — frameworks repo** — `nucleo-ia-gp/frameworks` (public, MIT + CC-BY-SA). EAA scaffold (Tribo 2: Engenharia de Agentes Autônomos, Track B). CLA eliminada (clause 2.2 do volunteer agreement serve de license direto).
- **Phase 5 — lifecycle automation** (`30e7eff`, mig `20260419030000`) — `wiki_health_report()` RPC: staleness (>90d, >180d), PII scan (email/phone/CPF regex), metadata completeness. MCP tool 74: `get_wiki_health`. First PII finding caught and fixed (emails em cooperation-agreements).

#### LGPD engagement_kinds fix
- 4 kinds `consent` → `legitimate_interest`: guest, observer, speaker, candidate.
- `ambassador` mantido `consent` + `requires_agreement=true`.
- `_audit_engagement_kinds_changes` trigger bugfix (`details` → `changes` + `metadata`, `actor_id` nullable para system ops, `contract` no legal_basis whitelist).

#### IP Policy Execution (CR-050 E1-E5)
- **chapter_registry** (`8871658`, `6c76a6c`) — 5 chapters com CNPJs reais extraídos de privacy policies oficiais (GO, CE, DF, MT, RS). 3-tier fallback em `sign_volunteer_agreement()`.
- **Draft template R3-C3-IP** — cláusula 2 com subclauses 2.1-2.5 (moral rights, license, publication, notification, industrial property). i18n 3 languages. Active template não muda — draft roda paralelo até CR-050 aprovado.
- **IP Addendum** — template 7 artigos para 4 bilateral cooperation agreements + wiki page.
- **4 cooperation agreements** enriquecidos com content + addendum linkado. `DocumentsList` com content expansion + status badges.
- **sync-wiki EF fix** (`bf35b55`) — `ip_track` uppercase + YAML null handling.

#### DocuSign Cert Integrity
- **Hydrate 34 certs** (`bc174f4`) — content_snapshot, template_id, period, status→issued, chapter CNPJ. 41/41 volunteer agreement certs agora `issued` (era 7 completos).
- **Counter-sign 26 DSGN-** (`6dcbd18`) — counter_signed_at/by preenchidos; PDF mostra seal verde (não "pending").
- **Governance lifecycle** — RPC `update_governance_document_status()` + CHECK constraint (draft→under_review→approved→active→superseded). 4 draft docs visíveis para manager/deputy_manager/superadmin.

#### Meeting Notes Unification (6 workstreams)
- **MCP** (`1ecc857`) — `get_meeting_notes` lê `events.minutes_text` (full Markdown, não `meeting_artifacts` summaries). `create_meeting_notes` escreve via `upsert_event_minutes` RPC (audit trail).
- **Frontend** — marked.parse em atas; EventMinutesIsland montado; edit button; /meetings em nav drawer.
- **Permissions** — researchers podem manage own tribe events (72h edit window); leaders/GP unlimited.
- **Edit history** — `minutes_edit_history` jsonb + `minutes_edited_at` em events.
- Migration `20260421020000_unify_meeting_notes.sql`.

#### Other fixes + releases
- **Comms permissions** (`4e01ec5`, `a694737`) — `canEditAny` inclui comms members em global boards. Mayanna/Letícia/Maria Luiza gerenciam cards + status dropdown.
- **#75 closed** (`318c98d`) — announcements filtradas do /blog; releases em /changelog.
- **CBGPL one-pager** (`ecc6c37`) — 52 members, 74 tools, 7 tribes.
- **Blog V4 SQL + IP email draft** (`101e8d0`) — material de apoio CR-050.

### Validation
- `npm test` ✅ 1184 pass / 0 fail
- `npx astro build` ✅ 0 errors
- MCP smoke ✅ 74 tools (60R+14W) — nucleo-mcp v2.10.0
- 4 migrations aplicadas (20260419010000/020000/030000, 20260421010000, 20260421020000)
- Wiki health report ✅ 0 issues em 29 pages
- CR-050 artefatos prontos para ativação quando Ivan aprovar

### Notes
- Activation do draft template depende do CR-050 approval pelos 5 chapter presidents — Ivan validou direção por WhatsApp, aguardando reunião 16/Abr.
- Meeting artifacts table (12 rows legacy) mantida mas bypassed — deprecation em sessão futura.
- Phase 6 (platform transfer para nucleo-ia-gp org) questionada pelo PM e deferred — platform code = engineering artifact (Vitor's infra), wiki = institutional memory.

---

## 2026-04-13 (evening) — v3.0.1: Post-V4 Stabilization — LGPD v2.2 + Wiki Phase 1 + Platform Fixes

### Scope
9 commits pós-cutover v3.0.0 no mesmo dia, consolidando LGPD Art. 7 alignment com o novo engagement_kinds lifecycle, fechando Phase 1 do plano Wiki (foundation), corrigindo campaign bugs descobertos em prod, e resolvendo 2 issues do GitHub.

### Delivered
- **LGPD legal_basis alignment** (`df646d1`) — legal_basis de cada engagement_kind alinhado com LGPD Art. 7. Privacy policy atualizada.
- **Privacy Policy v2.2** (`f5af71e`) — adiciona engagement-type retention rows. Ciclo de retenção por engagement_kind documentado (anonymize_by_engagement_kind cron).
- **admin_send_campaign include_inactive** (`f5ae9a5`/`892adad`) — filter flag respeitado (bug: campanhas vazando para inactive members).
- **Campaign chapter column fix** (`b296c39`) — `m.chapter` em vez de `t.chapter` (column não existe em tribes pós-V4).
- **MCP docs sync** (`e97c477`) — mcp.md connector tools count sincronizado com 70 (v2.9.6).
- **Blog "updated on" banner** (`8c2483d`) — post slug page mostra updated_at para edited posts.
- **Wiki Phase 1 + IP policy + comms_leader fix + MCP v2.10.0** (`faf3e08`) — foundation do plano wiki: 15 seeded pages (9 ADRs + 6 domain READMEs), `wiki_pages` table + FTS portuguese + 3 RPCs (`search_wiki_pages`, `get_wiki_page`, `get_decision_log`), 3 MCP tools novos → 73 total (59R+14W). Migration `20260417000000_wiki_pages_sync.sql`. IP policy base em DB. `comms_leader` role fix.
- **#76 privacy automation + #77 bot filter** (`b7590d6`) — automação notificação privacy policy changes + filtro bot opens em campaign analytics.

### Validation
- `npm test` ✅ 1184 pass / 0 fail (baseline herdado de v3.0.0)
- `npx astro build` ✅ 0 errors
- MCP smoke ✅ 73 tools após Wiki Phase 1

---

## 2026-04-13 — v3.0.0: Domain Model V4 — Multi-Org, Initiative-Driven, Engagement-Based Authority

### Scope
Refatoração arquitetural completa do modelo de domínio. 6 ADRs (0004-0009), 7 fases (0-7d), 30 migrations. Habilita crescimento multi-org, multi-capítulo, com autoridade derivada de engagements e lifecycle config-driven por kind.

### Delivered

#### Fase 1 — Multi-Tenancy (ADR-0004)
- `organizations` + `chapters` como entidades first-class
- `organization_id` em 40 tabelas de domínio com backfill 100%
- RESTRICTIVE RLS policies para isolamento cross-org
- `auth_org()` helper para single-org mode

#### Fase 2 — Initiative Primitive (ADR-0005)
- `initiative_kinds` config table (research_tribe, study_group, congress, workshop, book_club)
- `initiatives` table com bridge `legacy_tribe_id` para 8 tribos existentes
- `initiative_id` em 13 tabelas + dual-write triggers (tribe_id↔initiative_id)
- 9 RPCs `_by_initiative` como wrappers sobre RPCs `_by_tribe`

#### Fase 3 — Person + Engagement (ADR-0006)
- `engagement_kinds` (12 kinds com base legal + retenção LGPD)
- `persons` table — identidade universal desacoplada de auth
- `engagements` table — 96 engagements backfilled (71 primários + 25 designations)
- Bridge `person_id` em members

#### Fase 4 — Authority Derivation (ADR-0007)
- `engagement_kind_permissions` — maps (kind, role) → 7 actions
- `auth_engagements` view — is_authoritative derivation (temporal + agreement)
- `can()` + `can_by_member()` + `why_denied()` — canonical authority gate
- MCP cutover: 14 call sites migrados de canWrite/canWriteBoard → canV4()
- RLS migration: 36 direct-query policies reescritas via `rls_can()` helpers
- `sync_operational_role_cache` trigger — operational_role como cache

#### Fase 5 — Lifecycle Configuration (ADR-0008)
- Per-kind retention, anonymization policy, auto-expire behavior
- `anonymize_by_engagement_kind()` — kind-aware anonymization mensal
- `v4_expire_engagements()` + `v4_notify_expiring_engagements()` — cron diário

#### Fase 6 — Config-Driven Initiative Kinds (ADR-0009)
- Kind-aware engine: `create_initiative()`, `update_initiative()`, `join_initiative()`
- Custom fields validation via JSON Schema per kind
- CPMAI migrado: cpmai_courses → initiatives(study_group), 7 tabelas cpmai_* deprecadas
- Admin UI: `/admin/initiative-kinds` — CRUD de kinds via PostgREST

#### Fase 7 — Cleanup & Consolidation
- **7a (Docs):** CLAUDE.md, rules, ADRs, RELEASE_LOG atualizados
- **7b (Operacional):** RPCs `_by_tribe` deprecated, MCP gates → canV4(), `sign_volunteer_agreement` → engagements, `requires_agreement` re-ativado (40/40 certificados backfilled), frontend tribe_id → initiative_id (types, hooks, components, pages), LGPD export por engagement kind, MCP `get_person()`/`get_active_engagements()` tools (70 total)
- **7c (Cleanup):** 7 tabelas cpmai_* dropadas, ghost resolution flow (persons.auth_id synced em login), expiration trigger confirmado ativo, views de compat fechado como N/A (bridge architecture é permanente)
- **7d (Release):** RELEASE_LOG finalizado, refactor rules fechadas

### Validation
- `npm test` ✅ 1184 pass / 0 fail
- `npx astro build` ✅ 0 errors
- MCP smoke ✅ HTTP 200 + serverInfo v2.9.6 (70 tools)
- Shadow validation: 70/71 members `mirrors_ok=true` (1 divergência aprovada — melhoria de segurança)
- LGPD: Art. 18 cycle complete (consent gate + export + delete + anonymize cron 5y)

### Architecture (permanent)
- `tribes` e `members` permanecem como tabelas (não views) — 147+ FKs impedem conversão
- Bridge architecture: dual-write triggers + `initiative_id`/`person_id` columns + `sync_operational_role_cache`
- `can()` / `can_by_member()` são source of truth para autoridade (não `operational_role`)
- `operational_role` é cache mantido por trigger, lido pelo frontend para UI gating

### Pending (non-blocking, human-dependent)
- Revisão jurídica: DPO PMI-GO (Ivan Lourenço Costa) — validar base legal + retenção por engagement_kind

---

## 2026-04-10 — v2.9.5: LGPD Compliance Complete + Selection Dual Ranking + 68 MCP Tools

### Scope
Fecha o ciclo LGPD Art. 18 end-to-end (P1+P2+P3), entrega CR-047 Dual Ranking para seleção com self-eval block, TCV legal v1 com 2-wave signature, coleta ampliada de dados pessoais via /profile, e resolve 5 GitHub issues (certificates, MCP offline, self-eval, meeting alerts, meetings search).

### Delivered (17+ commits)

#### LGPD — Art. 18 cycle complete (P1 + P2 + P3)
- **P1 consent + revalidation:** `PrivacyGateModal` em `BaseLayout` — bloqueia uso até aceitação da política corrente, modal anual de revalidação dos dados, `check_my_privacy_status` + `accept_privacy_consent` + `mark_my_data_reviewed`
- **P1 share flags:** `share_whatsapp`, `share_address`, `share_birth_date` (default privado)
- **P2 portabilidade:** `export_my_data` — JSON completo (13 seções: personal, membership, privacy, cycle history, role changes, attendance, certificates, selection, board cards, xp events, onboarding, audit, rights notice)
- **P2 audit trail:** `pii_access_log` table + `log_pii_access` helper + `get_my_pii_access_log` (member transparency) + `get_pii_access_log_admin` (admin)
- **P2 instrumentação:** `admin_list_members_with_pii` loga todo acesso administrativo
- **P3 anonimização automática:** `anonymize_inactive_members(dry_run, years, limit)` + `list_anonymization_candidates` + pg_cron `lgpd-anonymize-inactive-monthly` (day 1 03:30 UTC, 5 anos retenção)
- **P3 fix admin_anonymize_member:** função quebrada por colunas legadas (`full_name`, `avatar_url`, `bio`) — reescrita para `name`, `photo_url` + PII completo
- **CR-048** (Governança de Coleta de Dados, Manual §7) — submitted, aguarda 5 chapter presidents
- **CR-049** (Política de Privacidade v1.0) — submitted, aguarda 5 chapter presidents

#### CR-047 Selection Dual Ranking
- Two tracks (researcher + leader) com fórmulas ponderadas (`research_score = obj + int`; `leader_score = research * 0.7 + leader_extra * 0.3`)
- Trigger `_block_self_evaluation` (Issue #66)
- Promotion path badges (👑 Líder, 👑⇡ Triado, 🎓 Pesquisador, 🎓 promovido)
- Rankings snapshot table para auditoria
- 4 novas MCP tools: `get_my_selection_result`, `get_selection_rankings`, `get_application_score_breakdown`, `promote_to_leader_track`

#### TCV (Termo de Voluntariado) end-to-end
- Template legal PDF com 12 cláusulas + anexo (governance_documents)
- Profile completeness gate (7 campos obrigatórios) antes de assinar
- 2-wave signature: voluntário assina → diretor counter-signs (badges ❌/✍️/✓✓)
- Datas derivadas de VEP (quando existe aplicação) ou `member_cycle_history` (legacy)
- Bulk download para admin/certificates

#### Personal data collection (/profile)
- Novos campos: `address`, `city`, `birth_date` (dd/mm sem ano)
- Privacy flags por campo com UI dedicada
- **CEP auto-complete via ViaCEP** — Brasil-only, não sobrescreve, formato live `00000-000`
- LGPD Rights card (export, privacy flags, delete)
- TCV banner com lista de campos faltantes

#### GitHub Issues resolvidas
- **#64** certificates designations + offboard + volunteer_agreement filter
- **#66** selection self-eval block (trigger)
- **#67** meeting notes alert (ALERT 6 em `detect_operational_alerts`)
- **#68** meetings full-text search + `list_meetings_with_notes` + /meetings page
- **MCP offline** hotfix: duplicate tool names crash + stale refresh token in KV auto-deleted

#### Meetings page (nova)
- Full-text search via `tsvector` index
- Compliance widget
- Detail modal com ata + attachments

#### MCP v2.9.5
- 68 tools (54R + 14W), SDK 1.29.0
- Pre-deploy check de duplicate tool names adicionado a `.claude/rules/mcp.md`
- Worker proxy auto-deletes stale KV refresh token em falha

### Validation
- `npx astro build` ✅ 0 errors
- `npm test` ✅ 779 pass
- Dry-run anonimização: 0 candidatos (projeto < 2y, ativa naturalmente)
- CR-047 validado com dados reais (Marcos, Hayala duplicate bug corrigido com DISTINCT ON)

### Known Deferred
- **PDF server-side Puppeteer:** requer Cloudflare Browser Rendering paid (~$5/mo) ou API externa. Fluxo client-side atual (blob URL + instruction banner) funciona.

---

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
- Health: v2.9.0, 56 tools, native-streamable-http, sdk 1.29.0
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
