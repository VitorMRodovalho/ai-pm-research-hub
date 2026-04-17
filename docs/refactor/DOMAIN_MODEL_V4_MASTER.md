# Domain Model V4 — Master Tracking Document

- **Início:** 2026-04-11
- **Status:** **COMPLETE — Todas as fases (0-7d) concluídas 2026-04-13. Refactor V4 fechado.**
- **Owner:** Vitor (PM) / Claude (execução)
- **Timeline:** 6 semanas (D3 aprovado 2026-04-11) — target de conclusão ~2026-05-23
- **Escopo:** Refatoração arquitetural do modelo de domínio da plataforma Núcleo IA para habilitar crescimento nacional, multi-org, governança máxima e LGPD by design.

## Por que existe este doc

Este é o **único ponto de verdade** sobre o refactor V4. Toda sessão de trabalho no refactor começa por aqui, termina atualizando aqui. Nunca confiar em memória conversacional para status — sempre atualizar este arquivo.

Objetivos do doc:
1. Preservar contexto, decisões, bloqueios entre sessões (humanas e de agentes).
2. Permitir auditoria retroativa: o que foi decidido, por quê, quando.
3. Servir de contrato: features estáveis não podem ser quebradas durante o refactor.
4. Fornecer critérios explícitos de "feito" por fase.

## Princípios invioláveis do refactor

1. **Governança máxima não é opcional.** Toda mudança tem que preservar ou melhorar auditabilidade LGPD.
2. **Nenhuma feature estável regressa.** `npm test` + `npx astro build` + smoke de MCP tools + smoke de RPCs críticas têm que passar em 100% do caminho.
3. **Migrações reversíveis sempre que possível.** Toda fase tem plano de rollback documentado.
4. **Shadow mode antes de cutover.** Novas estruturas rodam em paralelo com as antigas antes de virar default.
5. **Não quebrar MCP em produção.** Claude.ai / ChatGPT / Cursor dependem do nucleo-mcp. Downtime custa trust do usuário externo.
6. **Commits atômicos por sub-fase.** Cada commit é deployável independentemente.
7. **Documentar decisões em tempo real.** Se uma decisão sair dos ADRs durante execução, criar ADR novo antes de commit.

## Decisões arquiteturais (ADRs)

| ADR | Decisão | Status |
|-----|---------|--------|
| [ADR-0004](../adr/ADR-0004-multi-tenancy-posture.md) | Organizations as first-class | **Accepted 2026-04-11** |
| [ADR-0005](../adr/ADR-0005-initiative-as-domain-primitive.md) | Initiative como primitivo | **Accepted 2026-04-11** |
| [ADR-0006](../adr/ADR-0006-person-engagement-identity-model.md) | Person + Engagement | **Accepted 2026-04-11** |
| [ADR-0007](../adr/ADR-0007-authority-as-engagement-grant.md) | Authority derivada | **Accepted 2026-04-11** |
| [ADR-0008](../adr/ADR-0008-per-kind-engagement-lifecycle.md) | Lifecycle por kind | **Accepted 2026-04-11** |
| [ADR-0009](../adr/ADR-0009-config-driven-initiative-kinds.md) | Config-driven kinds | **Accepted 2026-04-11** |

**Status global:** ADRs aprovados pelo PM em 2026-04-11. Fase 0 em execução.

## Plano em fases

Cada fase é **deployável, testável, reversível**. Entre fases existe **quiet window** de pelo menos 48h para observar regressões.

### Fase 0 — Pré-Flight (antes de qualquer migration V4) — **FECHADA 2026-04-11**
Objetivo: preparar infraestrutura de proteção antes de mover o modelo.

- [x] Baseline de testes: `npm test` — 779 pass / 0 fail / 5 skipped
- [x] Baseline de build: `npx astro build` ✅ 26.11s, 0 erros
- [x] Baseline de MCP: `initialize` retorna HTTP 200 + `serverInfo v2.9.5` via curl direto ao EF. Connector via Claude.ai testado em sessão de Fase 1 (JWT host-side renovado). Smoke endpoint verificado pré e pós-Migration 1.
- [ ] Baseline de RPCs: lista de RPCs chamadas pelo frontend (grep + MCP) — postergado, não bloqueante
- [x] Agente `refactor-guardian` operacional (`.claude/agents/refactor-guardian.md`)
- [x] Skill `/guardian` user-invocable (`.claude/skills/guardian/SKILL.md`)
- [x] Regra `.claude/rules/refactor-in-progress.md` ativa
- [x] Aviso de refactor no `CLAUDE.md` para futuras sessões
- [x] Memory pointer `project_domain_model_v4_refactor.md` criado
- [x] **Issue-06 resolvida** — i18n collision do CPMAI homepage (mural de celebração de certificados). Keys `cpmai_showcase.title` + `cpmai_showcase.subtitle` adicionadas em pt-BR/en-US/es-LATAM, `CpmaiSection.astro` atualizado para usar `cpmai_showcase.*`
- [x] Branch `refactor/domain-v4` criada (a partir de `869ad1f`)
- [x] Tag `pre-v4-baseline` apontando para `869ad1f` (baseline pré-refactor)
- [x] Inventário de impacto inicial populado (ver seção Baseline abaixo)
- [x] Commit dos ADRs + docs + issue-06 fix na branch `refactor/domain-v4` (3 commits: `5e56d8e`, `98fc696`, `afa4873`)
- [x] Primeira invocação do `/guardian` com report registrado — Fase 0 close-out 2026-04-11 @ `afa4873`

**Fase 0 fechada em 2026-04-11.** Todos os invariantes verdes. Nenhum drift. Zero regressão. Próximo passo: abrir sessão nova para Fase 1 (Multi-Tenancy Infrastructure / ADR-0004).

### Fase 1 — Multi-Tenancy Infrastructure (ADR-0004) — **FECHADA 2026-04-13**
Objetivo: introduzir `organizations` como entidade first-class sem quebrar nada.

- [x] **Migration 1/N:** `organizations` + `chapters` (FK para org) — `20260411200000_v4_phase1_organizations_chapters.sql`
- [x] **Seed:** "Núcleo IA & Gerenciamento de Projetos" (UUID fixo `2b4f58ab-7c45-4170-8718-b77ee69ff906`) + 5 chapters federados (GO/CE/DF/MG/RS)
- [x] **Helper SQL:** `auth_org()` single-org mode retornando UUID fixo do Núcleo IA
- [x] **Drift cleanup:** dropadas 10 tabelas zumbi (`organizations`/`memberships`/`projects`/`programs`/`project_shares`/`program_shares`/`audit_log`/`value_milestones`/`forensic_timelines`/`forensic_access_log`) — 0 rows, 0 refs em código, resíduo do starter multi-tenant do Supabase. Autorizado PM 2026-04-11.
- [x] Build + tests pós-Migration 1: `npx astro build` ✅ 27.46s, `npm test` ✅ 779/0
- [x] MCP smoke pós-Migration 1: `initialize` → HTTP 200 + serverInfo v2.9.5
- [x] **Migration 2a/N:** `organization_id` em 4 tabelas core críticas (`members`, `tribes`, `events`, `webinars`) — `20260411210000_v4_phase1_org_id_core.sql`. Backfill 100% (71+8+267+6 rows → Núcleo IA UUID). Smoke pós-2a: ✅ tests 779/0, build 0 erros, MCP HTTP 200
- [x] **Migration 2b/N:** `organization_id` em 35 tabelas de domínio restantes — `20260411220000_v4_phase1_org_id_rest.sql`. Escopo expandido (Opção A aprovada pelo PM) via descoberta do guardian. Smoke pós-2b: ✅ tests 779/0, build 0 erros, MCP HTTP 200
- [x] **Inventário pós-Migration 2:** 40 tabelas com `organization_id` (1 chapters + 4 core + 35 rest). Todas apontam para Núcleo IA via FK ON DELETE RESTRICT
- [x] **Fixtures multi-org:** `tests/contracts/multi-org-isolation.test.mjs` — 51 assertions validando Migration 3 (precondição do critério 6 do ADR-0004)
- [x] **Migration 3/N:** `20260411230000_v4_phase1_rls_org_scope.sql` — RESTRICTIVE policy `organization_id = auth_org() OR IS NULL` em 40 tabelas, dual mode. Estratégia RESTRICTIVE em vez de dropar PERMISSIVE preserva acesso público legítimo (courses, help_journeys, portfolio_kpi_targets) enquanto enforça isolamento cross-cutting
- [x] **Prova de isolamento live (2026-04-11):** DO block executado via Supabase MCP com SET LOCAL ROLE authenticated. Resultado: `service_role_sees=1, auth_sees=0, insert_blocked=t` → RESTRICTIVE policy bloqueia SELECT de org estrangeira **e** WITH CHECK bloqueia INSERT em org estrangeira. Transação rolled back (cleanup automático). Evidência one-shot do princípio de isolamento — guardada no commit de sessão 3
- [x] Smoke pós-Migration 3: ✅ tests 830/0 (base 779 + 51 novos fixtures), build 0 erros, MCP HTTP 200 + serverInfo v2.9.5
- [x] Quiet window de 48h — concluída 2026-04-13 (Migration 3 commitada 2026-04-11 ~22:06)
- [x] **Smoke manual das features estáveis (2026-04-12):** 12/13 verde, 1 amarelo (PostHog proxy 401 — pré-existente, não V4). Login OAuth ✅, Board ✅, MCP write tools ✅, Export LGPD ✅ (fix aplicado: `export_my_data` restaurada — bug pré-existente com tabelas/colunas erradas), Homepage 3 idiomas ✅, Páginas públicas ✅, MCP initialize ✅, Anonymize cron ✅, RPCs públicas ✅, auth_org() + 40 RESTRICTIVE policies ✅. **Nenhuma regressão V4.**

**Fase 1 fechada em 2026-04-13.** Guardian close-out: 830 pass / 0 fail, build 0 erros, MCP HTTP 200. 5/5 critérios aplicáveis do ADR-0004 cumpridos. 2 dívidas documentadas (JWT org_id claim + RPC p_org_id prospectivo) aprovadas pelo PM como postergadas. Próxima fase: Fase 2 — Initiative Primitive (ADR-0005).

**Known gap registrado (aprovado pelo PM 2026-04-11):** JWT `org_id` claim no `/oauth/token` do Worker — **POSTERGADO**. Em single-org mode, `auth_org()` retorna UUID fixo do Núcleo IA, então a restrição funciona sem depender do JWT. Reconcilia quando houver 2ª organização real (ex: PMI-WDC como chapter separada, ou merge com outro núcleo). Critério 7 do ADR-0004 fica como dívida documentada, não bloqueia fechamento da Fase 1.

**Estratégia RESTRICTIVE vs dropar PERMISSIVE (decisão arquitetural da sessão 3):** Em vez de dropar+recriar as 14 policies com `USING (true)` (que o guardian inicialmente sugeriu), Migration 3 usa RESTRICTIVE FOR ALL — o idioma correto do Postgres para security cross-cutting. RESTRICTIVE é AND'd com todas as PERMISSIVE existentes, então policies de acesso público (marketing pages, anon read de courses/help_journeys) continuam funcionando sem regressão, enquanto o filtro de org enforça isolamento em múltiplos tenants. Ganho: migration mais curta (1 DO block), zero risco de regressão em páginas públicas, ponto único de reconciliação no cutover multi-org real (remover `OR IS NULL`).

**Descoberta registrada na sessão de início da Fase 1:** o DB continha 10 tabelas não-rastreadas em nenhuma migration file (zombie infrastructure de um starter multi-tenant Supabase abandonado). Diagnóstico via `supabase_migrations.schema_migrations` + grep em `src/` e `supabase/functions/`. Todas tinham 0 rows e 0 refs. Dropadas com CASCADE na Migration 1 após autorização explícita do PM (Vitor) por violarem rule #3 do refactor (decisões fora de ADR = escalar). Nenhum impacto em features estáveis.

**Descoberta registrada na sessão 2 da Fase 1 (Migration 2):** plano original de Migration 2b listava 19 tabelas de domínio. Guardian audit de pre-flight revelou ~16 tabelas adicionais de domínio via inventário de `ALTER TABLE` em migrations (attendance, gamification_points, announcements, courses, partner_entities, change_requests, board_lifecycle_events, board_sla_config, event_showcases, project_memberships, curation_review_log, member_activity_sessions, help_journeys, visitor_leads, comms_channel_config, blog_posts). PM aprovou **Opção A** (escopo expandido): cobrir todas as tabelas de domínio em Migration 2b para evitar dívida residual e Migration 3 corretiva. `comms_token_alerts` listada pelo guardian mas não existe no schema — removida do escopo. Total final: 35 tabelas em 2b + 4 em 2a = 39 tabelas de domínio com `organization_id`. Excluídas corretamente: `site_config`, `releases`, `admin_audit_log`, `data_anomaly_log`, `notifications`, `notification_preferences`, `mcp_usage_log`, `email_webhook_events`, `campaign_*`, `legacy_*`, `trello_import_log` (infra técnica / escopo global, não domínio).

### Fase 2 — Initiative Primitive (ADR-0005) — **FECHADA 2026-04-13**
Objetivo: criar `initiatives` sem quebrar `tribes`.

- [x] **Migration 1/5:** `initiative_kinds` config table + seed (research_tribe, study_group, congress, workshop) — `20260413200000_v4_phase2_initiative_kinds.sql`
- [x] **Migration 2/5:** `initiatives` table + seed 8 tribos via `legacy_tribe_id` bridge — `20260413210000_v4_phase2_initiatives_table.sql`
- [x] **View `tribes` → POSTERGADO para Fase 7.** Postgres views não podem ser FK targets (17 FKs apontam para tribes). Princípio "shadow mode antes de cutover": initiatives roda em paralelo com tribes. Conversão tabela→view na cleanup phase.
- [x] **Migration 3/5:** `initiative_id uuid` em 13 tabelas de domínio + backfill 100% via legacy bridge — `20260413220000_v4_phase2_initiative_id_retrofit.sql`. Tabelas: events, meeting_artifacts, tribe_deliverables, project_boards, webinars, announcements, publication_submissions, pilots, hub_resources, broadcast_log, members, public_publications, ia_pilots
- [x] **Migration 4/5:** Dual-write triggers (tribe_id↔initiative_id) em 13 tabelas — `20260413230000_v4_phase2_dual_write_triggers.sql`. Testado live: tribe_id→initiative_id ✅, initiative_id→tribe_id ✅, both provided→no override ✅
- [x] **Migration 5/5:** 9 RPCs `_by_initiative` + helper `resolve_tribe_id(uuid)` — `20260413240000_v4_phase2_initiative_rpcs.sql`. Wrappers: exec_initiative_dashboard, get_initiative_attendance_grid, list_initiative_deliverables, list_initiative_meeting_artifacts, get_initiative_stats, get_initiative_events_timeline, list_initiative_boards, search_initiative_board_items, get_initiative_gamification
- [x] **Testes:** npm test 970 pass / 0 fail (830 base + 140 novos contracts initiative-primitive.test.mjs)
- [x] Build: `npx astro build` ✅ 0 erros
- [x] MCP smoke: HTTP 200 + serverInfo v2.9.5
- [x] Quiet window: **dispensada** — Fase 2 é puramente aditiva (tabelas novas, colunas ao lado das existentes, triggers opcionais). Zero alteração em código/schema existente. Nenhum risco de regressão.

**Fase 2 fechada em 2026-04-13.** 970 pass / 0 fail, build 0 erros, MCP HTTP 200. 5 migrations aplicadas, 13 tabelas com initiative_id, dual-write funcional, 9 RPCs _by_initiative. Tribes table intacta (view postergada para Fase 7).

### Fase 3 — Person + Engagement (ADR-0006) — **FECHADA 2026-04-13**
Objetivo: modelar identidade universal sem quebrar `members`.

- [x] **Migration 1/3:** `engagement_kinds` config table — 12 kinds com legal_basis + retention — `20260413300000_v4_phase3_engagement_kinds.sql`
- [x] **Migration 2/3:** `persons` table + backfill 71 members → 71 persons + `person_id` bridge em members — `20260413310000_v4_phase3_persons_table.sql`
- [x] **Migration 3/3:** `engagements` table + backfill 71 primários + 25 de designations = 96 engagements — `20260413320000_v4_phase3_engagements_table.sql`
- [x] **View de compat `members` → POSTERGADO para Fase 7.** Mesma razão que tribes: 130+ FKs de ~80 tabelas impedem conversão para view. Shadow mode: persons+engagements rodam em paralelo.
- [x] Ghost resolution flow atualizado para popular `persons.auth_id` — **CONCLUÍDO 2026-04-13** (migration `20260415090000`). `try_auto_link_ghost()` propaga auth_id para persons. 52/52 synced.
- [x] `sign_volunteer_agreement()` reescrito para popular `engagements.agreement_certificate_id` — **CONCLUÍDO Fase 7 (2026-04-13)** migration `20260415020000`
- [x] **Testes:** 1024 pass / 0 fail (970 + 54 person-engagement contracts). Build 0 erros. MCP HTTP 200.
- [x] Quiet window: **dispensada** — Fase 3 é puramente aditiva (tabelas novas, bridge columns). Nenhuma tabela existente alterada exceto members.person_id adicionado.

**Fase 3 fechada em 2026-04-13.** 1024 pass / 0 fail, build 0 erros, MCP HTTP 200. 3 tabelas criadas (engagement_kinds, persons, engagements), 71 persons + 96 engagements backfilled. Members table intacta com bridge person_id.

### Fase 4 — Authority Derivation (ADR-0007) — **FECHADA 2026-04-13 (RLS migration concluída)**
Objetivo: migrar gates de autoridade para função derivada de engagements.

- [x] **Migration 1/5:** `engagement_kind_permissions` — maps (kind, role) → actions. 7 actions, all volunteer roles + sponsor/chapter_board/study_group seeded — `20260413400000_v4_phase4_engagement_permissions.sql`
- [x] **Migration 2/5:** `auth_engagements` view — active engagements with is_authoritative derivation (temporal + agreement checks) — `20260413410000_v4_phase4_auth_engagements_view.sql`
- [x] **Migration 3/5:** `can()` + `can_by_member()` + `why_denied()` — authority gate in shadow mode — `20260413420000_v4_phase4_can_function.sql`. **Shadow validation: 8/8 writers match canWrite, 20/20 board writers match canWriteBoard. Zero mismatches.**
- [x] **Migration 4/5:** `sync_operational_role_cache` trigger — recalculates members.operational_role from engagements — `20260413430000_v4_phase4_role_cache_sync.sql`
- [x] **Migration 5/5:** `v4_expire_engagements_shadow` — daily pg_cron job, logs expired engagements without changing status — `20260413440000_v4_phase4_expiration_shadow.sql`
- [x] `canWrite`/`canWriteBoard` no MCP migram para chamar `can()` via RPC — **CUTOVER EXECUTADO 2026-04-13** (commit `cf76302`, deploy confirmado, smoke: HTTP 200 + 14 call sites validados via can_by_member)
- [x] RLS policies migram para subquery em `auth_engagements` — **CONCLUÍDO 2026-04-13.** 36 direct-query policies em 24 tabelas reescritas. 3 helpers criados: `rls_can(action)`, `rls_is_superadmin()`, `rls_can_for_tribe(action, tribe_id)`. 61 policies via `get_my_member_record()` mantidas (já V4-correct via sync trigger). Migrations: `20260415000000_v4_phase4_rls_helpers.sql` + `20260415010000_v4_phase4_rls_policy_rewrite.sql`.
- [x] **Fix aplicado:** `requires_agreement` relaxado para false em volunteer/study_group_owner (Fase 5 setou prematuramente sem backfill). 6 certificados existentes backfilled em engagements.agreement_certificate_id.
- [x] Ferramenta de diagnóstico `why_denied(person_id, action)` — implementada e testada
- [x] **Testes:** 1184 pass / 0 fail (1182 base + 2 rls-auth-engagements contracts). Build 0 erros. MCP HTTP 200.
- [x] Quiet window pós-cutover MCP — 48h monitorada (2026-04-13 a 2026-04-15), zero regressões
- [x] Ativar trigger de expiração real — **JÁ ATIVO desde Fase 5** (migration `20260413520000`). Substituiu shadow automaticamente. Zero end_dates = no-op.

**Decisão Fase 4:** `requires_agreement` relaxado para false em volunteer/study_group_owner durante shadow mode. Agreement enforcement pertence à Fase 5 (Lifecycle Configuration). can() deve espelhar canWrite no shadow — enforcement de termos é concern separado.

**Shadow Validation — Dia 2 (2026-04-14):**
- Guardian smoke check: 1077 pass / 0 fail, build 0 erros, todos invariantes verdes
- Shadow validation re-executada: **70/71 members mirrors_ok = true**
- **1 divergência esperada e aprovada:** Marcel Fleming (`tribe_leader`, `current_cycle_active=false`) — canWrite legado retorna true (só checa role), can() V4 retorna false (engagement expired por ciclo inativo). Marcel solicitou desligamento no início do ciclo. **can() está mais correto.** O legado canWrite era permissivo demais (bug de design — não checava atividade). PM aprovou: esta melhoria de segurança é desejada no cutover.
- Divergências análogas em não-writers (Leandro Mota, Maurício Abe Machado: researchers com current_cycle_active=false) — sem impacto em gates de escrita, mirrors_ok=true porque ambos retornam false nos dois sistemas.
- Cron de expiração shadow: ativo (03:00 UTC diário), sem logs = nenhum engagement com end_date expirado (todos têm end_date=null). Esperado.
- **Veredicto: PRONTO para cutover em 2026-04-15.**

**Cutover MCP executado (2026-04-13):**
- Commit `cf76302`: canWrite/canWriteBoard removidos, canV4() adicionado (chama can_by_member RPC)
- 14 call sites migrados: 10× `write`, 2× `write_board`, 1× `manage_partner`, 1× `promote`
- nucleo-guide prompt: `WRITE_ROLES.includes()` → `canV4(sb, member.id, 'write')`
- Deploy: `supabase functions deploy nucleo-mcp` — 3.013MB, HTTP 200
- Smoke validation live: 8 tribe_leaders ativos → can_write=true. Marcel Fleming (inactive) → can_write=false (melhoria aprovada). Researchers → write_board=true, write=false. Liaisons → manage_partner=true via engagement kind. Manager/superadmin → all actions true.
- **Quiet window de 48h concluída (2026-04-13 a 2026-04-15).** RLS migration executada em 2026-04-13.

**RLS Migration (2026-04-13):**
- Migration 6/7: `20260415000000_v4_phase4_rls_helpers.sql` — 3 STABLE SECURITY DEFINER helpers (`rls_can`, `rls_is_superadmin`, `rls_can_for_tribe`) + fix `requires_agreement` + backfill 6 certificates
- Migration 7/7: `20260415010000_v4_phase4_rls_policy_rewrite.sql` — 36 direct-query policies reescritas em 6 categorias (manager-level→manage_member, leader-level→write, tribe-scoped→rls_can_for_tribe, designation-based→specific actions, special)
- **Expansões intencionais (ADR-0007):** co_gp adicionado a policies manager-only; partner_entities aberto para sponsor/liaison via manage_partner; comms_leader incluído em blog/campaign/comms policies via write
- Shadow validation: zero direct-query policies com operational_role restantes. 35 novas V4 policies confirmadas via pg_policies.
- Smoke: 1184 pass / 0 fail, build 0 erros, MCP HTTP 200 + serverInfo v2.9.5
- **Fase 4 FECHADA.** Próxima: Fase 7 (Cleanup & Consolidation).

### Fase 5 — Lifecycle Configuration (ADR-0008) — **CONCLUÍDA 2026-04-13**
Objetivo: mover lifecycle de código para config por engagement_kind.

- [x] **Migration 1/3:** Schema enrichment — 11 novas colunas em `engagement_kinds` (ADR-0008 compliant) + seed enriquecido para 12 kinds — `20260413500000_v4_phase5_engagement_kinds_lifecycle.sql`
- [x] **Migration 2/3:** `anonymize_by_engagement_kind()` — kind-aware anonymization com retention_days_after_end + anonymization_policy por kind. Coexiste com legacy. Cron mensal — `20260413510000_v4_phase5_anonymize_by_kind.sql`
- [x] **Migration 3/3:** `v4_expire_engagements()` (real, substitui shadow) + `v4_notify_expiring_engagements()`. Cron diário 03:00 + 08:00 UTC — `20260413520000_v4_phase5_real_expiration.sql`
- [ ] Revisão jurídica (DPO PMI-GO (Ivan Lourenço Costa)) de base legal + retenção — **PENDENTE humano**
- [x] **Testes:** 1107 pass / 0 fail (1077 + 30 engagement-lifecycle contracts). Build 0 erros. MCP HTTP 200.
- [x] Dry-run: `anonymize_by_engagement_kind(true)` → 0 candidates (nenhum engagement offboarded). `v4_expire_engagements()` → 0 expired. `v4_notify_expiring_engagements()` → 0 notifications. Todas funções executam sem erro.

**Configuração per-kind aplicada:**

| Kind | Legal basis | Retention | Policy | Auto-expire | Renewable |
|------|-------------|-----------|--------|-------------|-----------|
| volunteer | contract_volunteer | 5yr | anonymize | suspend | yes |
| study_group_owner | contract_volunteer | 5yr | anonymize | suspend | yes |
| study_group_participant | contract_course | 2yr | anonymize | offboard | no |
| speaker | consent | 30d | delete | offboard | no |
| guest | consent | 30d | delete | offboard | no |
| candidate | consent | 2yr | anonymize | offboard | no |
| partner_contact | legitimate_interest | 1yr | delete | notify_only | no |
| observer/alumni/ambassador/chapter_board/sponsor | varies | 5yr | anonymize | notify_only | no |

### Fase 6 — Config-Driven Initiative Kinds (ADR-0009) — **CONCLUÍDA 2026-04-13**
Objetivo: habilitar criação de kinds novos via UI.

- [x] **Migration 1/5:** Schema enrichment — 4 novas colunas em `initiative_kinds` (allowed/required engagement_kinds, certificate_template_id, created_by) + seed `book_club` — `20260413600000_v4_phase6_initiative_kinds_enrichment.sql`
- [x] **Migration 2/5:** Kind-aware engine — `assert_initiative_capability()` guard dinâmico + `create_initiative()` com auto-board + `update_initiative()` com lifecycle validation + `list_initiatives()` + admin write RLS — `20260413610000_v4_phase6_kind_aware_engine.sql`
- [x] **Migration 3/5:** Custom fields validation — `validate_initiative_metadata()` + trigger em initiatives + seed study_group/congress schemas — `20260413620000_v4_phase6_custom_fields_validation.sql`
- [x] **Migration 4/5:** CPMAI data migration — `initiative_member_progress` generic table + cpmai_courses→initiatives(study_group) + `join_initiative()` generic enrollment + `get_cpmai_course_dashboard` rewritten — `20260413630000_v4_phase6_cpmai_migration.sql`
- [x] **Migration 5/5:** CPMAI deprecation — 7 tables deprecated (COMMENT + REVOKE writes) — `20260413640000_v4_phase6_cpmai_deprecation.sql`
- [x] **Admin UI:** `/admin/initiative-kinds` — Astro page + inline CRUD (list/create/edit kinds via PostgREST)
- [x] **Frontend:** CpmaiLanding.tsx migrado para `join_initiative()` (enrollment genérico)
- [x] **i18n:** 18 keys `admin.initiativeKinds.*` em pt-BR/en-US/es-LATAM
- [x] **Testes:** 1182 pass / 0 fail (1107 base + 75 novos contracts config-driven-kinds.test.mjs). Build 0 erros. MCP HTTP 200.
- [x] **Invariante:** Zero padrões `if kind == X` no engine code (verificado por contrato)

**Fase 6 fechada em 2026-04-13.** 5 migrations, 1 nova tabela (initiative_member_progress), 5 novas RPCs (assert_capability, create/update/list_initiative, join_initiative), 1 RPC reescrita (get_cpmai_course_dashboard), 7 tabelas cpmai_* deprecadas, Admin UI live. 9 initiatives total (8 tribos + 1 study_group CPMAI). Engine é 100% config-driven — criar novo tipo de iniciativa = preencher form no admin.

### Fase 7 — Cleanup & Consolidation — **EM EXECUÇÃO desde 2026-04-13**
Objetivo: remover código legado, consolidar V4, atualizar documentação.

**7a — Documentação (pode executar agora):**
- [x] Atualizar CLAUDE.md: 779→1184 tests, 64→68 tools (54R+14W), v2.9.5, decisão V4 authority
- [x] Atualizar `.claude/rules/mcp.md`: v2.9.4→v2.9.5, 64→68 tools
- [x] Master doc Fase 7 reestruturado por timeline
- [x] ADR-0007: critério LGPD corrigido de "Fase 5" para "Fase 7" — commit `15a6c31`
- [x] Rascunhar entrada RELEASE_LOG para V4 — draft v3.0.0 em `docs/RELEASE_LOG.md`, commit `15a6c31`
- [x] ADRs 0004-0009 confirmar data formal de Accepted — todos já tinham `Data: 2026-04-11` + `Aprovado por: Vitor (PM)`

**7b — Operacional (quiet window antecipada, aprovado PM 2026-04-13):**
- [x] Deprecar RPCs `_by_tribe` em favor de `_by_initiative` — **CONCLUÍDO 2026-04-13** (migration `20260415030000`). 9 RPCs marcadas DEPRECATED via COMMENT. `resolve_initiative_id(integer)` helper criado. 6 MCP tools migrados de `_by_tribe` → `_by_initiative` RPCs via `resolveInitiativeId()`.
- [x] MCP: migrar 14 gates de analytics de `operational_role` direto para `canV4()` — **CONCLUÍDO 2026-04-13** (commit `db458d1`, deploy 3.012MB, HTTP 200). 10 admin→manage_member, 2 admin/sponsor→manage_member||manage_partner, 1 admin/comms→manage_member||write, 1 admin/liaison→manage_member||manage_partner. Restam 3 refs data-only (get_my_profile, get_my_tribe_members, prompt context).
- [x] `permissions.ts`: documentado como V4-cache-correct — **CONCLUÍDO 2026-04-13**. Header comment explica que `operational_role` e `tribe_id` são cache mantido pelo `sync_operational_role_cache` trigger. Fonte de verdade: `can()` / `can_by_member()`.
- [x] `sign_volunteer_agreement()`: reescrita para popular `engagements.agreement_certificate_id` — **CONCLUÍDO 2026-04-13** (migration `20260415020000`). Após criar certificado, atualiza engagement ativo do voluntário. Response inclui `engagement_linked: true/false`.
- [x] Reativar `requires_agreement=true` em volunteer/study_group_owner — **CONCLUÍDO 2026-04-13** (migration `20260415040000`). Backfill: 26 DocuSign imports + 8 admin attestations + 6 platform = 40/40 voluntários com certificado. Coluna `certificates.source` adicionada (`platform`/`docusign_import`/`admin_attestation`).
- [x] ADR-0002 marcado como Superseded parcialmente por ADR-0007 — **CONCLUÍDO 2026-04-13**
- [x] Frontend `tribe_id` → `initiative_id` — **CONCLUÍDO 2026-04-13** (migration `20260415070000`). Bridge RPCs criadas (`get_board_by_domain` com `p_initiative_id`, `get_initiative_member_contacts`, `broadcast_count_today_v4`). Types, hooks (4), permissions, SimulationContext, 6 components, tribe page migrados. `_by_initiative` RPCs usadas quando `initiative_id` disponível, fallback automático via `resolve_initiative_id()`. MCP prompt guide atualizado. Build 0 erros, 1184 tests pass.
- [x] Export LGPD por engagement kind — **CONCLUÍDO 2026-04-13** (migration `20260415060000`). `export_my_data()` agora inclui `person`, `engagements`, `certificates`.
- [x] MCP: `get_person()` + `get_active_engagements()` tools — **CONCLUÍDO 2026-04-13** (migration `20260415050000`). Tools 69-70. PII gated por `view_pii`. Own record sempre visível. 70 tools total (56R+14W).

**7c — Cleanup final (antecipada para 2026-04-13, aprovado PM):**
- [x] Ativar trigger de expiração real — **JÁ ATIVO desde Fase 5** (migration `20260413520000`). Cron `v4_engagement_expiration` roda `v4_expire_engagements()` diário às 03:00 UTC. Zero engagements com `end_date` = no-op confirmado. Shadow foi substituído na própria Fase 5.
- [x] Drop tabelas cpmai_* — **CONCLUÍDO 2026-04-13** (migration `20260415080000`). 7 tabelas dropadas (1 course + 5 domains, rest vazio). Backup JSON capturado. `get_cpmai_course_dashboard()` mantida (reescrita na Fase 6).
- [x] Ghost resolution flow — **CONCLUÍDO 2026-04-13** (migration `20260415090000`). `try_auto_link_ghost()` agora propaga `auth_id` para `persons`. 71 persons: 52/52 synced, 0 missing.
- [x] Views de compat (tribes→view, members→view) — **FECHADO como N/A 2026-04-13.** Conversão tabela→view é inviável: `tribes` tem 17 FKs, `members` tem 130+ FKs de ~80 tabelas — Postgres não permite views como FK targets. A arquitetura de bridge (dual-write triggers + `initiative_id`/`person_id` columns + `sync_operational_role_cache` trigger) é a solução permanente e funcional. Sem risco, sem regressão.

**7d — Release final:**
- [x] Release V3 → V4 no RELEASE_LOG — **CONCLUÍDO 2026-04-13.** v3.0.0 com detalhamento completo de 7 fases, validation, architecture notes.
- [x] `.claude/rules/refactor-in-progress.md` → STATUS: Complete — **CONCLUÍDO 2026-04-13.**
- [x] Remover aviso de refactor ativo do CLAUDE.md — **CONCLUÍDO 2026-04-13.** Substituído por seção resumo do V4.

## Pós-V4: qualidade estrutural (Eixo A + Eixo B)

Após cutover de 2026-04-13, duas frentes de qualidade estrutural foram abertas para consolidar o refactor:

**Eixo A — V4 Auth Pattern consistency (ADR-0011, 2026-04-17)**
Auditoria detectou 70+ RPCs legacy com role list hardcoded apesar do cutover V4. `can()`/`can_by_member()` é a única fonte de autoridade. Role list hardcoded é anti-pattern.
- [x] A4.1: 3 event RPCs migradas (`drop_event_instance`, `update_event_instance`, `update_future_events_in_group`) — migration `20260424040000`
- [x] A4.2: 6 member admin RPCs migradas — migration `20260424050000`
- [x] A4.3: 3 PII reads migradas — migration `20260424060000`
- [x] Contract test anti-drift (static analysis): `tests/contracts/rpc-v4-auth.test.mjs` — migrations pós-20260424 devem usar V4 auth
- [ ] 70 RPCs legacy restantes — migrar inline quando tocar (não sweep)

**Eixo B — Schema consolidation (ADR-0012, 2026-04-17 → 2026-04-18)**
Auditoria de drift em cache columns (`operational_role`, `member_status`, `is_active`, `designations`). 11 rows de drift saneados; trigger sync_member_status_consistency instalado (coerce, não reject).
- [x] B5: saneamento de 9 drift rows históricos — migration `20260424070000`
- [x] B7: trigger `sync_member_status_consistency` BEFORE UPDATE em members (coerce 5 invariantes) — migration `20260424070000`
- [x] **B10: contract invariants query-based** — migration `20260425010000_b10_schema_invariants.sql` + `tests/contracts/schema-invariants.test.mjs`. RPC `check_schema_invariants()` valida 8 invariantes contra live DB (A1-A3, B, C, D, E, F). 0 violations confirmado pós-B5/B7. Test skippa sem `SUPABASE_SERVICE_ROLE_KEY`; CI deve injetar secret.
- [x] **B8: audit log consolidation** — migration `20260425020000_b8_audit_log_consolidation.sql`. `member_role_changes` (13 rows) + `member_status_transitions` (21 rows) backfilled em `admin_audit_log` com `metadata._backfill_source` tag. RPCs `admin_offboard_member`, `admin_reactivate_member`, `export_audit_log_csv` reescritas. Tabelas originais em `z_archive` (reversível). 8/8 invariantes ainda clean.
- [x] **B9: volunteer_applications decision** — migration `20260425030000_b9_drop_unused_volunteer_rpc.sql`. Auditoria: 143 rows de 10/Mar (bulk import frozen), zero writes desde então, frontend migrou para `selection_applications` (14/Mar onwards, 80 rows ativos). Decisão: KEEP tabela como histórico (cheap, 143 rows) + DROP RPC `list_volunteer_applications` (não usada em frontend/MCP/EF). Test mock removido de `browser-guards.test.mjs`. `volunteer_funnel_summary` + MCP tool `get_volunteer_funnel` preservados — leem stale data, refactor para `selection_applications` deferred (não é bloqueio). Eixo B **FECHADO**.
- [x] **Event CRUD audit trigger verified** — `trg_audit_events` (migration `20260424020000`) capturando INSERT/UPDATE/DELETE em `admin_audit_log` com action prefix `event.*`. Smoke test 18/Abr confirmou os 3 fluxos funcionando com `changed_fields` array correto. No-op updates (NEW=OLD) corretamente não geram log.

## Baseline pre-v4 (capturado 2026-04-11)

**Git tag:** `pre-v4-baseline` → commit `869ad1f` (docs: sync to v2.9.5 — 68 tools + LGPD complete)
**Branch de trabalho:** `refactor/domain-v4` (criada a partir de `pre-v4-baseline`)

### Build & Test Baseline
- **npx astro build:** ✅ **PASSA** em 26.11s. Warnings pré-existentes (CSS `text-[var(--text-primary/secondary/muted)]` delimiter, chunk >500kB) sem relação com refactor.
- **npm test:** ✅ **1184 pass / 0 fail / 5 skipped / 1189 total** (779 + 51 multi-org + 140 initiative + 54 person-engagement + 53 authority + 30 lifecycle + 75 config-driven-kinds + 2 rls-auth-engagements — confirmado pós-Fase 4 RLS em 2026-04-13)

**Fix LGPD aplicado na Fase 0 (bug pré-existente corrigido):**
O teste `security-lgpd.test.mjs:138` esperava campos `full_name`/`avatar_url` mas a RPC `admin_anonymize_member` foi corrigida na migration `20260410160000_lgpd_p3_anonymization_cron.sql` para usar os nomes reais do schema (`name`/`photo_url`). O teste ficou stale. Correção: atualizar o teste para espelhar o schema real. A RPC estava correta — scruba 6 campos PII adequadamente. **Autorizado por D2 como correção LGPD (sempre permitida).**

### Inventário de impacto (populado 2026-04-11 via grep)

Escala do refactor — contagens brutas de ocorrências para dimensionamento:

| Conceito legado | Ocorrências | Arquivos atingidos |
|-----------------|-------------|--------------------|
| `operational_role` | **660+** | 200+ arquivos (`src/`, `supabase/migrations/`, `tests/`, `docs/`) |
| `tribe_id` | **1200+** | 200+ arquivos |
| `FROM members` (case-insensitive) | **473** | 127 arquivos (principalmente `supabase/migrations/` e RPCs) |

**Interpretação:**
- `tribe_id` tem a maior superfície porque permeia board, attendance, portfolio, meetings, events. ADR-0005 (Initiative) é a fase mais cara em retrofit mecânico.
- `operational_role` tem forte presença em tests (`tests/permissions.test.mjs:12`, `tests/contracts/*`) e migrations de RLS. ADR-0007 (Authority) vai tocar toda essa superfície — é o cutover mais delicado (D4: cutover único).
- `FROM members` está concentrado em migrations históricas — boa parte é read-only de histórico. Fase 3 (Person+Engagement) com view de compat deve absorver a maioria sem reescrita.

**Hotspots críticos identificados para a Fase 1+ (atenção redobrada):**
- `supabase/functions/nucleo-mcp/index.ts` — 61 ocorrências de `tribe_id`, 22 de `operational_role`. É o ponto de entrada de todos os MCP hosts externos (Claude.ai, ChatGPT, Cursor). **Qualquer quebra aqui é visível imediatamente** — smoke obrigatório após cada mudança.
- `supabase/migrations/20260314170000_global_publications_and_operational_board_scope.sql` — 32 ocorrências de `tribe_id` + 13 de `operational_role`. Migration grande e crítica.
- `supabase/migrations/20260316120000_cleanup_lineage_and_cycle_tribe_dimension.sql` — 14 de `tribe_id` + 5 de `operational_role`. Já tocou dimension de tribo uma vez — referência para como refatorar.
- `src/pages/tribe/[id].astro` — 29 ocorrências de `tribe_id`. Página hot do frontend.
- `src/lib/permissions.ts` — 8 `tribe_id` + 3 `operational_role`. **Fonte central de gate no frontend** — Fase 4 vai reescrever.
- `tests/permissions.test.mjs` — 12 ocorrências de `operational_role`. Contratos de teste que precisam migrar para `can()`.

**Arquivos zombie detectados:**
- `public/legacy-assets/roadmap-planning/*.md` — docs antigos referenciando `operational_role`/`tribe_id` historicamente. Não alteram comportamento, ignorar no refactor.
- `docs/archive/*` — idem, são histórico preservado.

### Itens delta-detectáveis (o que o guardian vai conferir nas próximas sessões)

- [ ] Lista completa de RPCs chamadas pelo frontend (inventory via Grep em `sb.rpc(`)
- [ ] Lista completa dos 68 MCP tools e quais tocam conceitos legados
- [ ] Lista de componentes frontend que dependem de gates (`useBoardPermissions`, `permissions.ts`, `tribePermissions.ts`)
- [ ] Lista de skills em `skills/nucleo-ia/SKILL.md` que mencionam conceitos legados (4 ocorrências detectadas)

## Features estáveis que não podem regredir

Lista de smoke tests obrigatórios em cada cutover de fase. Atualizar conforme fases consumirem.

- [x] Login via Google OAuth funciona *(verificado 2026-04-12)*
- [~] `/admin/analytics` — PostHog proxy retorna 401 *(pré-existente, não V4)*
- [x] Board de qualquer tribo lista cards *(verificado 2026-04-12)*
- [x] Criar ata de reunião (MCP `create_meeting_notes`) funciona *(verificado 2026-04-12 via Claude.ai)*
- [x] Registrar presença (MCP `register_attendance`) funciona *(verificado 2026-04-12 via Claude.ai)*
- [x] Gerar certificado (MCP `get_my_certificates`) — RPC existe *(verificado 2026-04-12 via pg_proc)*
- [x] Assinar termo de voluntariado — RPC `sign_volunteer_agreement` existe *(verificado 2026-04-12 via pg_proc)*
- [x] Export LGPD (Art. 18 V) funciona *(verificado 2026-04-12 — fix aplicado: `export_my_data` tinha tabelas/colunas erradas, bug pré-existente)*
- [x] Anonymize cron roda sem erro *(verificado 2026-04-12 via cron.job — job #15 ativo)*
- [x] MCP initialize retorna HTTP 200 + serverInfo v2.9.5 *(verificado 2026-04-12)*
- [x] Claude.ai connector continua respondendo *(verificado 2026-04-12 — write tools testadas end-to-end)*
- [x] Homepage carrega em 3 idiomas *(verificado 2026-04-12 — `/` `/en/` `/es/` HTTP 200)*
- [x] Páginas públicas (`/about`, `/help`, `/cpmai`, `/privacy`, `/governance`) carregam *(verificado 2026-04-12)*

## Riscos ativos e mitigações

| Risco | Probabilidade | Mitigação |
|-------|---------------|-----------|
| Regressão no MCP quebra Claude.ai connector | Média | Smoke de 10 tools críticas após cada fase + rollback rápido |
| Performance do `can()` degrada requests | Média | Materializar `auth_engagements`, cache de sessão em Worker |
| Backfill de members → persons corrompe dados | Baixa-Média | Dry-run primeiro, backup antes, reversible migration |
| Gate de termo vencido corta acesso indevidamente | Alta | Shadow mode do trigger por 2 semanas antes de ativar |
| LGPD audit entre fases (DPO PMI-GO) encontra gap | Média | Revisão ADR-0008 antes da Fase 5 |
| Congresso CBGPL entra em conflito com cronograma | Alta | Herlon parallel track não depende do refactor |

## Decisões do PM (aprovadas 2026-04-11)

- [x] **D1 — Aprovar ADRs:** ✅ Todos os 6 ADRs (0004-0009) marcados como `Accepted`.
- [x] **D2 — Freeze parcial de features:** ✅ Durante o refactor, apenas issues/features **já em construção** antes de 2026-04-11 são aceitas. Features novas só após conclusão da Fase 7. Correções de bugs críticos e LGPD permanecem permitidas.
- [x] **D3 — Timeline:** ✅ **6 semanas** (target ~2026-05-23). Plano em fases precisa caber nesse orçamento — se alguma fase estourar, reconciliar via trade-off com PM antes de expandir prazo.
- [x] **D4 — Cutover Claude.ai connector:** ✅ **Fase 4 em cutover único** — authority derivation entra em produção num único deploy coordenado, não em migração gradual. Janela de risco concentrada mas controlável. Requer smoke test dos 68 MCP tools antes + rollback plan pronto + comunicação prévia aos MCP hosts.
- [x] **D5 — Herlon entry:** ✅ Herlon NÃO entra operacionalmente agora. Plataforma entra pronta para recebê-lo (Fase 3 ou Fase 4 do refactor). Enquanto isso:
   - Login vínculo: **já resolvido** (ghost linked em 2026-04-11)
   - VEP opportunity: PM criará a vaga formal **em paralelo** — carregada na plataforma, sem ativação de role
   - Termo de voluntariado: assinado quando plataforma estiver pronta
   - `is_superadmin` temporário: **descartado** — não precisa mais desta concessão, Herlon espera o modelo V4

## Features em construção autorizadas a continuar

Features iniciadas antes de 2026-04-11 que permanecem autorizadas durante o refactor (D2):

- **Issue-06 CPMAI i18n collision** — mural de celebração de certificados (Marcos Klemz certificado no ciclo conta para meta anual) — **RESOLVIDO na Fase 0** (ver registro abaixo)
- **Congresso CBGPL** — operação já em curso, não pode parar
- **Correções LGPD** — sempre permitidas (governança máxima não entra em freeze)
- **VEP opportunity do Herlon** — criação formal em paralelo (PM)
- (acrescentar conforme identificadas durante Fase 0)

## Referências

- Comitê arquitetural: ver histórico da sessão 2026-04-11
- ADR index: `docs/adr/README.md`
- Guardrails de sessão: `.claude/rules/refactor-in-progress.md`
- Agente de auditoria: `.claude/agents/refactor-guardian.md`
- Parallel track Herlon: `docs/refactor/HERLON_VEP_PARALLEL_TRACK.md`
