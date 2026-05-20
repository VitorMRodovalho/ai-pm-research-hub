# ADR-0093: Canonical RPC as facade — approval orchestration concentrates in a single source

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-05-20 (sessão p204) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | `20260726000000` (canonical + delegating wrappers) · `20260726000001` (council fix: RAISE EXCEPTION + dedup) |
| Invariants | R + S (added p204 via Issue #180, ADR-0093 partner) |
| Cross-ref | [ADR-0007](./ADR-0007-authority-as-engagement-grant.md) (can() V4 authority) · [ADR-0011](./ADR-0011-v4-auth-pattern-rpcs-mcp.md) (V4 auth pattern, RPCs/MCP) · [ADR-0028](./ADR-0028-service-role-bypass-adapter-pattern.md) (service_role bypass adapter — related pattern for cron/EF) · [ADR-0080](./ADR-0080-v4-engagement-canonical-deprecate-members-initiative-id.md) (V4 engagement canonical) |
| Closes | GAP-204.A (filed p204 close per council Tier 1 platform-guardian report) |
| Pairs with | PR #198 (Issue #179 canonical approval RPC) + PR #199 (Issue #180 invariants R + S — the watchdog) |

## Context

P201/P202 lifecycle audit revelou **drift silenciosa entre dois caminhos de aprovação de candidato voluntário**:

- `admin_update_application(uuid, jsonb)` — chamado pelo `/admin/selection` UI (4 call sites, todos em `src/pages/admin/selection.astro`). Pré-p204: atualizava `selection_applications.status='approved'`, promovia `operational_role` de members EXISTENTES, mas **não criava member novo** se não existia (gap real: 1 caso em produção — Adalberto Neris).
- `finalize_decisions(uuid, jsonb)` — chamado pelo comitê em bulk no fim do ciclo. Pré-p204: criava member novo, seedava onboarding canônico, mas **não populava `members.person_id` nem `engagements.selection_application_id`** (não tocava grafo V4).

Os dois RPCs divergiram organicamente: cada vez que um caminho ganhou um side-effect novo (notification, audit log, partner-chapter flag), o outro não foi atualizado em paralelo. Symptom acumulado:

- 38 applications `approved`/`converted`, 1 sem `members` row (Adalberto Neris, conversion docs como deliberate non-active).
- 0 approved members com `person_id IS NULL` na baseline, mas **futura aprovação via `admin_update_application` criaria** essa drift porque o RPC nunca tocou `persons`.
- 16 engagements ativos com `requires_agreement=true` AND `agreement_certificate_id IS NULL` — operational queue legítima (Herlon-class invariant: counter-signature pendente). Nenhum dos 2 RPCs cobria criação inicial de engagement; populated por caminhos paralelos (VEP sync, manual admin inserts, etc.).

**O risco vai além dos 2 RPCs existentes.** Adicionar uma 3ª entrada de aprovação no futuro (MCP tool em Issue #183, batch cron de reprocessamento, REST endpoint para integração com VEP, conversion API para sponsor track) replicaria a divergência. A próxima entrada quase certamente esquece pelo menos um dos 8 side-effects mandatórios (validação V4, member upsert, person upsert, members.person_id link, engagement insert, onboarding seed, notification, audit). E o caller pode estar fora do mundo PostgREST onde os tests contratuais existentes detectariam drift.

Sem um ADR explícito codificando "approval orchestration deve concentrar em uma RPC canonical; novas entradas DELEGAM", o padrão é descobrível apenas lendo PR #198 — vulnerável a future contributors recriarem divergência.

## Decision

### §1. Padrão "canonical RPC as facade"

Para subsistemas com **lifecycle transitions críticas** (volunteer approval, futuramente: offboarding, role-change, governance-doc activation), define-se:

1. **Existe exatamente uma RPC canonical** que orquestra todos os side-effects da transition. Ela é a fonte única de verdade para a sequência de mutations.
2. **Todas as entradas (UI, MCP, bulk, cron, REST) chamam a canonical** em vez de replicar a lógica.
3. **Side-effects são side-effects da canonical**, não dos callers. Wrapper code só:
   - Valida shape de input específico do canal (parâmetros do RPC vs corpo de payload)
   - Aplica auth se diferente do que a canonical aplica (geralmente nada — canonical já valida)
   - Adapta return shape para backward-compat com callers existentes
4. **Falhas da canonical propagam por exceção**, não por return JSON, para que transactions rolled back (vide ADR-0011 §1 sobre RAISE EXCEPTION patterns).

Para volunteer approval (PR #198), a canonical é `approve_selection_application(uuid, jsonb)`. As 2 facades atuais (`admin_update_application` + `finalize_decisions`) DELEGAM:

- `admin_update_application` chama canonical em approve transition (new=approved AND old≠approved); falha → `RAISE EXCEPTION` (rollback).
- `finalize_decisions` chama canonical por decision quando `decision='approved'`; falha → `RAISE EXCEPTION` dentro de `BEGIN/EXCEPTION` sub-block (per-decision rollback, batch continues).

### §2. Critérios para "lifecycle transition" qualificar para canonical-facade

Nem todo RPC precisa ser canonical. Critérios para escalar um RPC ao status de "canonical":

1. **A transition tem ≥4 side-effects mandatórios** (member/person/engagement/onboarding/notification/audit — qualquer combinação)
2. **≥2 entry points** podem disparar a transition (UI + bulk, ou UI + MCP, ou UI + cron, etc.)
3. **Drift entre paths cria invariant violation** (e.g., approved app sem member → invariant R; approved member sem person_id → invariant S)
4. **Side-effects são acopladas** (não dá pra criar member sem person sem engagement sem onboarding — todos juntos ou nada)

Quando ≥3 dos 4 critérios verdade, candidate to canonical-facade pattern.

### §3. Critérios "não-targets"

Pattern **NÃO** se aplica a:

- **CRUD simples** (1 INSERT/UPDATE, sem side-effects além de audit log). Examples: `update_card_status`, `register_attendance`. Esses ficam standalone — não precisam canonical.
- **Read-only queries** (get_*, list_*, exec_*). Canonical pattern é sobre mutations.
- **Pure helpers** (calculate_score, format_date). Sem state change.
- **RPCs com 1 caller único** (e.g., MCP-only tool sem UI). Não há drift risk se só há 1 path.

### §4. Forward-defense via invariants

Padrão **deve ser pareado com schema invariants** que detectam bypass:

- Para volunteer approval: invariants R + S em `check_schema_invariants()` (PR #199, Issue #180)
- Para futuros canonical RPCs: o ADR introducing each canonical deve listar **quais invariants** detectam bypass. Sem invariant correspondente, canonical-facade vira aspiracional.

Esquema mental: **a canonical orquestra; os invariants vigiam**. Os 2 juntos formam o contrato.

### §5. Documentation rule

Quando um novo canonical RPC é introduzido:

1. Migration header descreve a canonical signature + 8-ish side-effects
2. Wrapper RPCs ganham `COMMENT ON FUNCTION` referenciando a canonical
3. ADR novo (ou Amendment a este ADR-0093) lista a tripla: **canonical RPC + facade callers + watchdog invariants**

Catalog (a ser estendido conforme novos canonicals chegam):

| Domain | Canonical RPC | Facade callers | Watchdog invariants |
|---|---|---|---|
| Volunteer approval | `approve_selection_application(uuid, jsonb)` | `admin_update_application`, `finalize_decisions` | R, S |

### §6. Rollback

Por se tratar de um padrão arquitetural (não código), rollback é "revert PR #198 + PR #199 → padrão deixa de existir". Sem rollback da ADR por si só.

Caso o padrão precise ser revisto (e.g., descobre-se que canonical-facade tem custo de manutenção alto), o caminho é:

1. Novo ADR substituindo este (ADR-00XX supersedes ADR-0093) articulando a nova decisão
2. Audit dos canonical RPCs ativos via grep `COMMENT ON FUNCTION ... 'Canonical orchestration'`
3. Migration por canonical para inverter o padrão (re-distribute side-effects entre callers)

Este ADR não é Accepted aspirationally — o padrão JÁ está implementado e live em produção via PR #198 / #199.

## Validation

Pós-merge de PR #198 + PR #199:

1. ✅ `approve_selection_application(uuid, jsonb)` definido (DEFINER, search_path locked, GRANT EXECUTE TO authenticated)
2. ✅ `admin_update_application` body contains `RAISE EXCEPTION` quando canonical fails
3. ✅ `finalize_decisions` body contains `BEGIN ... EXCEPTION WHEN OTHERS ... END` sub-block
4. ✅ `check_schema_invariants()` retorna 18 rows (16 + R + S)
5. ✅ R = 0 violations + S = 0 violations
6. ✅ 14 + 10 = 24 contract tests estáticos covering canonical + invariants
7. ⏳ DB-aware behavioural tests (GAP-204.B) — futuro: idempotency + partial-commit guard + historical-cycle + R/S forward-defense

## Consequences

### Positive

- Single source of truth para volunteer approval orchestration; impossível esquecer side-effect quando todos os callers DELEGAM
- Drift entre paths é detectada em < 1 minuto via R + S invariants (vs. semanas de drift silenciosa pré-p204)
- Forward-defense: PR #183 (MCP lifecycle tools) ganha pattern claro — wrappa `approve_selection_application`, não recria orquestração
- Wrappers ficam ~30% menores (lógica concentrada na canonical); facilita future maintenance
- Pareamento canonical-RPC + watchdog-invariants codifica "build the safety net, then the trampoline" — invariant existe antes do canonical poder bypassar

### Negative

- Padrão tem custo cognitivo extra para contributors que estão acostumados com RPCs standalone — precisam aprender o catalog + decision criteria do §2
- Canonical RPC pode se tornar "god function" se 8 side-effects crescerem para 15. Mitigação: split internamente em helper RPCs privadas (signature stays canonical), não em outros canonicals
- `RAISE EXCEPTION` em wrappers muda contract de error handling: callers que reading `data?.error` precisam re-handle HTTP 4xx. Frontend `if (error) throw error;` já cobre — confirmado p204
- ADR adds documentation surface (catalog do §5) que precisa update toda vez que canonical novo é introduzido. Risk: cataloque rotar. Mitigação: PR template lembra de atualizar este ADR ao adicionar canonical

### Neutral

- Pattern **opt-in por subsistema**. Sistemas existentes (board lifecycle, governance review, certificate signing, partner management) não precisam ser refactored para o pattern só por consistência — só quando o quarteto de critérios do §2 for satisfeito
- Não impede subsystem internal helpers privados (e.g., canonical pode chamar `_ensure_member`, `_ensure_person`, `_seed_onboarding` internamente — internal split é orthogonal à decisão público-vs-canonical)
