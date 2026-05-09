# Decision: Freeze AI triage parameters para Cycle 3 batch 2; deploy enriched model from Cycle 4

**Date:** 2026-05-09
**Decided by:** Vitor Rodovalho (PM)
**Status:** Accepted
**Reversibility:** High (governance memo dated; cycle 4 reverte naturalmente)
**Path impact:** preserva A/B/C (process consistency = audit defensibility, beneficia todos paths)

## Context

6 evaluators ativos em Cycle 3 batch 2 já scoraram subset de 40 apps. Enriquecer triage prompt mid-cycle com novos campos (serviceHistoryCount, profileIndustry, profileDesignation, etc.) cria unequal treatment auditável: candidatos avaliados pré-enrichment processados sob diferente information set vs pós-enrichment.

## Options considered

- A) **Freeze AI triage parameters para Cycle 3 batch 2; deploy enriched model from Cycle 4 onward**
- B) Re-run AI triage retroativo para todos batch 2 antes de qualquer offer (equalizar pool)
- C) Document gap, proceed enriching para un-evaluated remaining; disclose post-mortem

## Decision

**A**. Freeze Cycle 3 batch 2. Enriched model deploys Cycle 4.

## Rationale

- Process consistency = audit defensibility (peer-review architecture com 2-evaluator minimum + trigger-blocked self-eval foi designed para process consistency)
- Re-run retroativo (B) cria audibility própria ("model V1 vs V2 comparison?") — adicional vector para appeal challenge
- C cria appeal vector aberto (rejected candidate compares pre/post outcome)
- accountability-advisor: "We discovered enriched data during Cycle 3. We froze evaluation parameters to preserve consistency. We will apply enriched model from Cycle 4." = cleanest audit trail
- Custo zero: candidatos rejeitados podem se candidatar Cycle 4 com enriched model

## Council inputs

- accountability-advisor: explicit recommendation A
- product-leader: convergência implícita ("Cycle 3 in-flight risk")
- legal-counsel: convergência via Art. 20 LGPD revisão humana — process consistency = pre-condition

## Implementation owner

- **PM (Vitor)**: this decision document é o governance memo dated.
- E2 Wave 1: worker mapper popula novos campos no DB (storage), MAS E3 AI triage prompt em selection_applications.cycle_id='cycle3-2026-b2' usa V1 prompt schema
- E3 Wave 1: `pmi-ai-triage` EF adiciona check `IF cycle_id IN (cycle3-2026, cycle3-2026-b2) THEN use V1 prompt template ELSE use V2 enriched`

## Acceptance criteria

- Decision documented em `docs/council/decisions/` antes de qualquer Wave de E3
- pmi-ai-triage EF logic: cycle-based prompt template selection
- Logs em `ai_processing_log` registram qual prompt_version foi usado
- Cycle 4 launch memo documenta enriched model deploy

## Linked artifacts

- ADR-0076 (section "AI triage scope: cycle freeze")
- `supabase/functions/pmi-ai-triage/index.ts`
- LGPD Art. 20 §1
