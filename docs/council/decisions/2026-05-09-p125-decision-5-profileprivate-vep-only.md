# Decision: profilePrivate (19/97) → VEP-only com policy documentada

**Date:** 2026-05-09
**Decided by:** Vitor Rodovalho (PM)
**Status:** Accepted
**Reversibility:** High (mapper logic reversível; column drop additive)
**Path impact:** preserva A/B/C

## Context

19/97 candidatos têm `profilePrivate=true` — desabilitaram explicitamente perfil público em community.pmi.org. Phase B enrichment retornou HTTP 400 para esses 19. Council convergência (legal-counsel + security-engineer + accountability-advisor) que ingerir Phase B fields para esses 19 viola Art. 18 LGPD (boa-fé + opt-out reconhecimento).

## Options considered

- A) **VEP-only para os 19; flag `community_profile_private=true`; policy doc'd "scored on VEP data only, not penalty"**
- B) Re-consent específico via email
- C) Excluir os 19 do triage entirely

## Decision

**A**. VEP-only com policy pré-comprometida.

## Rationale

- Art. 7 VI LGPD ("dados manifestamente públicos") **não se aplica** — user disabled public profile = ato volitivo de restrição equiparável a Art. 18 §I (acesso restrito)
- Art. 7 IX (legítimo interesse) requer balanceamento — user com profile private tem expectativa de privacidade forte que defeats balance
- B (re-consent) gera atrito + delay E2; complicação não-proporcional para 19/97
- C (excluir) = penalidade implícita por exercer privacy right; viola fairness
- A pre-commits scoring policy ANTES de qualquer triage: "candidates with profilePrivate scored on VEP data only; this is not a disadvantage relative to stated selection criteria, which are based on PMI volunteer experience, not public profile richness"

## Council inputs

- legal-counsel: "Posição A. Opt-out explícito do titular no PMI Community é sinal inequívoco. Contornar viola Art. 18 (boa-fé) e princípio da finalidade (Art. 6 I)"
- security-engineer: "Option A. Write-time refusal é V4 fail-closed pattern (ADR-0011 principle aplicado a data ingestion)"
- accountability-advisor: "Option C [na sua taxonomia, equivalent A na nossa]: Score with available data, document explicitly"

## Implementation owner

- E1 Wave 1: column `community_profile_private boolean DEFAULT false` em selection_applications
- E2 Wave 1: mapper PMI Community client detecta HTTP 400 → set `community_profile_private=true` + leave all `profile_*` fields NULL
- E3 Wave 1: AI triage prompt checks `community_profile_private` flag — se true, document explicitly que sinal "VEP-data-only" não é penalidade

## Acceptance criteria

- selection_applications.community_profile_private populated correctly para os 19 candidates after E2 deploy
- AI triage logs registram quando candidate foi avaliado com VEP-only data + flag explícito
- Selection criteria UI display política para evaluators ("scored on VEP data only — equivalent confidence")
- Decision policy markdown criado ANTES de qualquer Wave de E3

## Linked artifacts

- ADR-0013 (section "profilePrivate posture")
- LGPD Art. 6 I, Art. 7 VI, Art. 7 IX, Art. 18 §I
- ADR-0011 (V4 auth fail-closed pattern)
