# Decision: E4 reduzido para E4a CSV-only no p125; E4b dashboard deferido

**Date:** 2026-05-09
**Decided by:** Vitor Rodovalho (PM)
**Status:** Accepted
**Reversibility:** High (E4a CSV é additive RPC + admin-only; E4b dashboard é separate work, easy to add later)
**Path impact:** preserva A/B/C; E4b restored em Cycle 4 pode beneficiar Path B (consulting showcase)

## Context

Council 3-lens convergence (product-leader + accountability-advisor + security-engineer) que /admin/diversity dashboard durante Cycle 3 ativo é alto-ROI-risk e baixo-immediate-value. E4 também depende de R2 audit (gender/age base legal).

## Options considered

- A) Full E4: SECDEF RPCs + k-anonymity + /admin/diversity UI + 6 dimensões + cross-tab
- B) **E4a only: single SECDEF RPC retornando aggregate CSV-friendly, admin-only, no UI. Defer E4b post-cycle 3**
- C) Drop E4 entirely from p125; backlog Cycle 4

## Decision

**B**. E4a CSV-only com PRECONDIÇÃO: gender/age base legal mini-audit completado. Se inadequado → fallback to C.

## Rationale

- product-leader: dashboard ROI baixo durante Cycle 3 (ninguém esperando hoje); CSV em 2h vs dashboard 6-8h
- accountability-advisor: dashboard em ciclo ATIVO = munição para appeal/political risk; super-restricted access policy difícil de garantir em Astro UI
- security-engineer: cross-tab limits explícitos no SQL antes de UI; k≥5 não sobrevive 3+ dimensões em 97 apps
- Custo-benefício: 80% analytical value em 10% engineering cost. Preserva 6-8h engineering para E3 fixes que afetam quality direto

## Council inputs

- product-leader: "Recommend B with kill trigger to C if E1+E2 exceed 2h"
- accountability-advisor: access tier policy A (PM+DPO only durante active cycle); B for retrospective post-cycle
- security-engineer: cross-tab inhibition rules + generalization hierarchies obrigatórios in ADR

## Implementation owner

- **PRECONDIÇÃO**: gender/age base legal mini-audit (próxima sessão pre-Wave 1 E4a)
  - Query `selection_applications WHERE gender IS NOT NULL AND consent_record_id IS NULL` 
  - Se base = consentimento genérico do Termo Voluntariado v2 → avaliar se escopo cobria analytics agregada
  - Se inadequado → defer E4 inteiro Cycle 4 com novo consent
- E4a Wave 1 (PM drafting): single SECDEF RPC `get_diversity_aggregate_csv(p_cycle_id, p_dimensions text[])` 
- E4a access: `view_pii` + `manage_platform` actions; admin-only
- ADR-0013 declares: generalization hierarchies (state→region; cert→has_pmp/has_advanced/has_none; senioridade→junior/mid/senior; multi-chapter→bool); k≥5 enforced server-side; cross-tab limit 2 dimensions

## Acceptance criteria

- gender/age base legal audit decision documented + signed off (Vitor + Ivan DPO)
- Se proceed: E4a RPC implementa k≥5 server-side com RAISE EXCEPTION para cells <5
- pii_access_log entry per RPC call: target_member_id=NULL, context='diversity_aggregate', reason=cycle_id, fields_accessed=dimensions[]
- E4b dashboard NOT in p125 scope — register in backlog Cycle 4

## Linked artifacts

- ADR-0013 (section "Diversity analytics scope + k-anonymity rules")
- LGPD Art. 11 (dados sensíveis), Art. 18
- pii_access_log table (existing)
