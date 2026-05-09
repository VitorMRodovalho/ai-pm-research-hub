# Decision: Hotfix Wave 0 paralelo a E1 drafting

**Date:** 2026-05-09
**Decided by:** Vitor Rodovalho (PM)
**Status:** Accepted
**Reversibility:** Medium (calendar deploy reversível; ADR doc + RPC invariant additive)
**Path impact (Trentim A/B/C):** preserva (operational debt cleanup)

## Context

Issue A (Calendar webhook 30 dias zero sync) e Issue D (94/94 active engagements end_date NULL) são P0 produção. Issue D semantic decision precede E1 DDL. Council convergência (product-leader + data-architect + platform-guardian).

## Options considered

- A) Hotfix Wave 0 paralelo a E1 drafting: (a1) Calendar webhook deploy + (a2) NULL end_date semantic doc'd + (a3) `import_vep_applications` invariant adicionado + (a4) `pii_access_log` shape extension review
- B) Block E1 only on Issue D semantic; defer Issue A e pii_access_log
- C) Treat all P0s as E1 prereqs, sequential

## Decision

**A**. Hotfix Wave 0 paralelo. Custo ~6h, risk savings significativos.

## Rationale

- Calendar webhook = schema-independent, ops-crítico, 2-4h fix; deferir significa 60+ dias broken ops total
- Issue D semantic = ADR doc ("NULL = currently active" preservado per ADR-0007) — não toca código
- import_vep_applications invariant = pre-empts Risk 3 do pre-mortem (4ª iteração drift)
- pii_access_log shape review = não muda tabela, decide formato de log entry para E4 aggregate (Decision 6)
- Atomicity preservada: Wave 0 não toca schema novo

## Council inputs

- product-leader: A com kill criteria explícito ("if A+D não shipped em 6h, paralelizar bloqueia E1")
- data-architect: Issue D semantic load-bearing para E1 DDL design (NULL semantics)
- platform-guardian: pii_access_log existe (false-negative no grep inicial), shape adequado para per-member; review entry format para aggregate

## Implementation owner

- (a1) Calendar webhook: spec-executor + senior-software-engineer (Apps Script auth)
- (a2) end_date semantic: registrado neste decision + ADR-0013
- (a3) import_vep invariant: data-architect Wave 2 E1
- (a4) pii_access_log review: documented in ADR-0013

## Acceptance criteria

- Calendar webhook firing eventos para `sync_calendar_booking_to_interview` em <48h pós-decisão
- ADR-0013 explicitamente declara "NULL end_date = active semantics per ADR-0007"
- check_schema_invariants() ganha invariante `I_vep_import_columns_complete` em E1 migration
- pii_access_log entry format documented em ADR-0013 (target_member_id NULL para aggregate)

## Linked artifacts

- `docs/council/p125_spec_strategic_review.md` (C1 + R1)
- `docs/council/p125_premortem.md` (Risk 3 + Risk 4)
- ADR-0076 (drafted Wave 1; pending Wave 4 sign-off)
