# Phase 5 C4 — `members.tribe_id` DROP COLUMN Blast Radius

- Data: 2026-04-21
- Autor: Claude (debug session 9908f3, item #81 #2 de follow-up) — aguardando review PM
- Status: **Pre-planning** — documenta o que precisa ser auditado/refatorado ANTES de executar o drop. Não é ordem de execução.
- Escopo: Inventário factual das dependências de `members.tribe_id` em todas as camadas (Postgres + edge functions + frontend) para informar o planejamento de Phase 5 C4 do ADR-0015.

## Por que este doc existe

ADR-0015 definiu `members` como **Deferred — Frontend V3 ainda lê; cutover separado**. As Phases 3a-3e executaram drops em 14 outras tabelas. Phase 5 C4 é o drop final e o mais arriscado — `members` é o pivot de auth, scope, tribe context e UX.

As experiências das Phases 3d e 3e (documentadas em ADR-0017 e issues #79 #80) mostraram que auditorias incompletas causam regressões silenciosas de 3-6 dias em produção. Com `members.tribe_id`, o blast radius é ~10× maior — **não há margem para auditoria incompleta**.

Este doc coleta a evidência runtime (via pg_proc / pg_policy / grep) para que o refactor seja planejado com dados reais, não estimativas.

## Metodologia

Todas as contagens abaixo foram coletadas em 2026-04-21 via Supabase MCP (`pg_proc`, `pg_policy`, `information_schema.columns`) e `grep` estruturado sobre o workspace. Consultas SQL disponíveis no apêndice.

## Resumo executivo

| Camada | Referências a remover/refatorar | Severidade | Complexity |
|---|---:|---|---|
| `pg_proc` functions | **55 funções** | 🔴 P0 | Alta — alguns são writers críticos (auth path) |
| `pg_policy` RLS | ~34 policies tocam `tribe_id` (não todas em members) | 🔴 P0 | Crítica — mudar RLS = mudar surface de privilégio |
| `pg_trigger` | 3 triggers sobre `members.tribe_id` | 🟡 P1 | Média — precisam deletar ou refatorar |
| `pg_views` | 0 refs diretas | ✅ — | — |
| Edge function `nucleo-mcp/index.ts` | **17 ocorrências** de `member.tribe_id` | 🔴 P0 | Alta — core do MCP UX |
| Frontend `src/**` | ~18 ocorrências em 15 arquivos | 🔴 P0 | Alta — afeta 5 rotas principais |
| Scripts + cron | 1 script legacy-seed referencia | 🟢 P2 | Baixa — fix mecânico |

**Total estimado:** ~90-110 pontos de mudança distribuídos em ~45 arquivos.

## Camada 1 — Postgres functions (55)

Funções que referenciam `members.tribe_id` ou alias `m.tribe_id`, classificadas por tipo de uso. Lista completa extraída de `pg_proc.prosrc`.

### Grupo A — Admin/management tooling (15)

```
admin_deactivate_tribe, admin_detect_data_anomalies, admin_get_anomaly_report,
admin_get_member_details, admin_get_tribe_allocations, admin_list_members,
admin_list_members_with_pii, admin_list_tribes, admin_preview_campaign,
admin_update_member_audited, analytics_member_scope, broadcast_history,
bulk_issue_certificates, count_tribe_slots, update_onboarding_step
```

Impacto: UI admin quebra, cron detractors quebra. Todos writers/readers precisam ser refatorados para derivar tribe via `engagements + initiatives.legacy_tribe_id` (padrão ADR-0015).

### Grupo B — Attendance + gamification (9)

```
calc_attendance_pct, detect_and_notify_detractors (+cron), detect_operational_alerts,
get_attendance_grid, get_attendance_panel, get_attendance_summary,
get_dropout_risk_members, send_attendance_reminders (+cron)
```

Impacto: Sistema de presença quebra completamente. Críticos — rodam em cron diário.

### Grupo C — Executive / analytics (13)

```
exec_all_tribes_summary, exec_chapter_dashboard, exec_cycle_report,
exec_role_transitions, exec_skills_radar, get_adoption_dashboard,
get_cross_tribe_comparison, get_cycle_report, get_executive_kpis,
get_portfolio_planned_vs_actual, get_portfolio_timeline, get_public_impact_data,
get_public_trail_ranking
```

Impacto: Todos os dashboards executivos quebram. Não-críticos para operação diária mas visíveis a sponsors/GP.

### Grupo D — Tribe-scoped readers (10)

```
get_board_members, get_my_attendance_history, get_near_events, get_org_chart,
get_publication_submissions, get_tribe_event_roster, get_tribe_events_timeline,
get_tribe_gamification, get_tribe_member_contacts, get_tribe_stats
```

Impacto: Dashboard da tribo (página mais visitada da plataforma) quebra.

### Grupo E — Write/auth-path (8)

```
enforce_board_item_source_tribe_integrity (trigger), get_member_by_auth,
get_member_detail, get_pending_countersign, get_volunteer_agreement_status,
mark_member_excused, mark_member_present, notify_leader_on_review,
notify_webinar_status_change, list_legacy_board_items_for_tribe
```

Impacto: **AUTH PATH** — `get_member_by_auth` é chamado no bootstrap de toda sessão. Regressão aqui = plataforma inteira fora do ar.

## Camada 2 — RLS policies

34 policies pg_policy referenciando `tribe_id` em qualquer tabela. Destas, **investigação adicional necessária** para filtrar só as que tocam `members.tribe_id` especificamente (muitas referenciam `<outra_tbl>.tribe_id` que ainda existe para `members` somente).

Decisão metodológica: antes de Phase 5 C4 executar, rodar query:

```sql
SELECT polname, tbl.relname AS on_table, pg_get_expr(polqual, polrelid) AS qual
FROM pg_policy pol
JOIN pg_class tbl ON tbl.oid = pol.polrelid
WHERE pg_get_expr(polqual, polrelid) ~* 'members\.tribe_id|\Wm\.tribe_id\W'
   OR pg_get_expr(polwithcheck, polrelid) ~* 'members\.tribe_id|\Wm\.tribe_id\W';
```

Qualquer match precisa ser refatorado ANTES do DROP (caso contrário RLS silenciosamente deixa de filtrar).

## Camada 3 — Triggers

3 triggers tocam `NEW.tribe_id` em tabelas relevantes:

| Trigger | Tabela | Function | Ação |
|---|---|---|---|
| `trg_a_sync_initiative_members` | `members` | `sync_initiative_from_tribe` | Preserva sync legacy → initiative_id. Após drop, **remover trigger** (não faz mais sentido). |
| `trg_b_sync_tribe_members` | `members` | `sync_tribe_from_initiative` | Preserva sync initiative_id → legacy. Após drop, **remover trigger**. |
| `trg_sync_tribe_id` | `tribe_selections` | `sync_tribe_id_from_selection` | Escreve em `members.tribe_id`. Após drop, **remover trigger** e substituir por escrita em `engagements`. |

Ordem de execução mandatória:
1. Refatorar Grupo E (auth path) primeiro
2. Drop triggers dual-write
3. Drop column
4. Remove triggers bridge

## Camada 4 — Edge function `nucleo-mcp/index.ts` (17 ocorrências)

| Linha | Context | Tipo |
|---|---|---|
| 97, 105 | `nucleo-guide` prompt (display personalizado) | UX output |
| 420 | `get_my_board_status` default tribe | Filter fallback |
| 441 | `get_my_tribe_attendance` default tribe | Filter fallback |
| 456 | `get_my_tribe_members` default tribe | Filter fallback |
| 493 | `get_meeting_notes` default tribe | Filter fallback |
| 533 | `search_board_cards` default tribe | Filter fallback |
| 564 | `create_board_card` required check | Precondition |
| 565 | `create_board_card` resolve initiative | Translation |
| 645, 647 | `send_notification_to_tribe` scope | Query filter |
| 679, 692 | `create_tribe_event` pass-through | RPC param |
| 768 | `get_tribe_dashboard` default tribe | Filter fallback |
| 917 | outra tool (investigar) | — |

**Padrão de fix sugerido:** introduzir helper `getMemberTribeId(member)` que lê via `engagements` + `initiatives.legacy_tribe_id`, cacheando durante a sessão. Fica 1 ponto de mudança em vez de 17.

## Camada 5 — Frontend `src/**` (15 arquivos, ~18 ocorrências)

```
src/components/admin/… (AdminNav.astro)
src/components/nav/Nav.astro (×3)
src/components/onboarding/OnboardingChecklist.tsx
src/components/sections/HomepageHero.astro (×4)
src/components/ui/PresentationLayer.astro
src/components/workspace/AttendanceDashboard.tsx (×3)
src/components/workspace/AttendanceForm.tsx (×2)
src/components/workspace/DropoutRiskBanner.tsx
src/components/boards/TribeKanbanIsland.tsx
src/hooks/useBoardPermissions.ts
src/lib/permissions.ts
src/pages/help.astro
src/pages/publications.astro
src/pages/workspace.astro (×14)
```

Destaque — `src/pages/workspace.astro` tem 14 refs → provavelmente o arquivo de maior complexity a refatorar.

**Padrão de fix sugerido:** criar hook `useMemberTribeId()` que resolve via RPC `get_member_by_auth` (que já retorna `initiative_id` v4). Todos os 18 pontos passam a usar o hook.

## Camada 6 — Scripts (1 arquivo)

`scripts/seed_legacy_member_links.ts` — script de seed legacy. Pode ser deletado ou comentado para o refactor; não roda em prod.

## Ordem sugerida de execução

Baseada no que aprendi com Phases 3d/3e (ADR-0017):

1. **Week -2:** Refatorar Grupo E (auth path — 8 funções) + triggers. Deploy. Smoke test em staging.
2. **Week -1:** Refatorar Grupos A-D (47 funções restantes). Deploy progressivo. Monitor `mcp_usage_log` por 7 dias.
3. **Week -1:** Refatorar edge function (17 pontos). Deploy. `supabase/config.toml` garante verify_jwt preservado.
4. **Week 0 Day 1:** Refatorar frontend (15 arquivos). PR review detalhado pelo time.
5. **Week 0 Day 3:** Aplicar `DROP COLUMN members.tribe_id` com gate D3 do ADR-0017.
6. **Week 0 Day 4:** Remover 3 triggers bridge. Final invariant check.
7. **Week +1:** Observability watch — `mcp_usage_log` + Sentry para regressões latentes.

**Estimativa total:** 3 semanas de trabalho concentrado ou 6 semanas em paralelo com outros projetos. **Não executar sem janela de foco dedicada.**

## Apêndice — SQL queries usadas

```sql
-- A. Functions tocando members.tribe_id
SELECT p.proname, pg_get_function_identity_arguments(p.oid)
FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
WHERE n.nspname='public'
  AND p.prosrc ~* 'members\.tribe_id|\Wm\.tribe_id\W|FROM (public\.)?members[^;]{0,200}tribe_id|JOIN (public\.)?members[^;]{0,200}tribe_id';
-- → 55 rows

-- B. Policies tocando tribe_id em qualquer tabela (filter member-specific após)
SELECT count(*) FROM pg_policy
WHERE pg_get_expr(polqual, polrelid) ~* 'tribe_id'
   OR pg_get_expr(polwithcheck, polrelid) ~* 'tribe_id';
-- → 34 rows (não todas sobre members)

-- C. Triggers acessando NEW.tribe_id / OLD.tribe_id
SELECT c.relname, t.tgname, p.proname
FROM pg_trigger t JOIN pg_proc p ON t.tgfoid=p.oid
JOIN pg_class c ON t.tgrelid=c.oid
WHERE NOT t.tgisinternal
  AND (p.prosrc ~* '\WNEW\.tribe_id\W' OR p.prosrc ~* '\WOLD\.tribe_id\W');
-- → 3 rows

-- D. Frontend grep (CLI)
rg 'member\.tribe_id|members\.tribe_id|m\.tribe_id' src/ -l | wc -l
-- → 15 arquivos, ~18 ocorrências

-- E. Edge function grep (CLI)
rg 'member\.tribe_id|members\.tribe_id|m\.tribe_id' supabase/functions/
-- → 17 ocorrências em nucleo-mcp/index.ts
```

## Referências

- [ADR-0015](../adr/ADR-0015-tribes-bridge-consolidation.md) — Tribes Bridge Consolidation
- [ADR-0017](../adr/ADR-0017-schema-code-contract-audit-methodology.md) — Audit methodology pre-DROP COLUMN (proposed)
- Issues #79, #80, #81 — contexto das regressões de Phase 3d/3e
- Commit `c5b1447`, `b91db51`, `a77d995` — fixes + preventivo
