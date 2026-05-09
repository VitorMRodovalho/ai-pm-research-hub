# Decision: pmi_memberships híbrido (snapshot + canonical 1:N)

**Date:** 2026-05-09
**Decided by:** Vitor Rodovalho (PM)
**Status:** Accepted
**Reversibility:** Low (1:N table com FK CASCADE = breaking change rollback). Lock; mudança futura via migration v0.2.
**Path impact:** preserva A/B/C (multi-chapter modeling neutral para todos paths)

## Context

PMI candidates may have multi-chapter membership (49/97 candidates; 5 chapters extreme case Fernando Maquiaveli). E1 schema needs to capture (a) submission-time snapshot (committee evaluates), (b) canonical live registry (E3 cron compliance queries expiry).

## Options considered

- A) JSONB only on selection_applications (snapshot only)
- B) JSONB only on persons (canonical, no snapshot)
- C) **HÍBRIDO**: JSONB on selection_applications (snapshot, immutable per submission) + new 1:N table `pmi_chapter_memberships(id, person_id, chapter_name, expiry_date, source, captured_at)` (canonical, queryable)
- D) JSONB on persons + new tabela `pmi_chapter_memberships`

## Decision

**C**. Híbrido snapshot + canonical 1:N.

## Rationale

- Snapshot (selection_applications.pmi_memberships JSONB): committee evaluates state at submission per ADR-0067 D5 audit principle. Imutável.
- Canonical (pmi_chapter_memberships table): E3 cron query `WHERE expiry_date < now() + interval '60 days'` precisa B-tree index em (person_id, expiry_date). JSONB GIN não escala vs table.
- ADR-0006 invariante: identity facts em persons (via FK 1:N), não em selection_applications.
- legal-counsel minimização: `chapter_name` armazenado, expiry_date armazenado — both necessary para finalidade compliance reminders.

## Council inputs

- data-architect (autor da síntese): "C with snapshot + canonical separation; ADR-0007 invariant (engagements ≠ pmi_memberships) preserved"
- legal-counsel: "armazenar chapter_name sem normalização para chapter_registry — Fernando Maquiaveli's Silicon Valley não existe ali"
- security-engineer: RLS at-creation default-deny obrigatório; `view_pii` action gate

## Implementation owner

- E1 Wave 1 (PM drafting): tabela DDL + RLS policies + ADR explanation
- E2 Wave 1: worker mapper popula ambos (snapshot during ingest + UPSERT canonical com `source='pmi_community'`)

## Acceptance criteria

- `selection_applications.pmi_memberships JSONB` adicionada (NULL-allowed, snapshot)
- `pmi_chapter_memberships` table criada com FK ON DELETE CASCADE para persons
- Index B-tree em `(person_id, expiry_date)`
- RLS habilitado at-creation com `view_pii` gate via rls_can('view_pii')
- COMMENT ON COLUMN `selection_applications.pmi_memberships`: "point-in-time submission snapshot, NOT canonical live registry (see pmi_chapter_memberships)"

## Linked artifacts

- ADR-0013 (PMI 3-dimensional volunteer model)
- ADR-0006 (Person + engagement identity model)
- ADR-0012 (Schema consolidation principles)
