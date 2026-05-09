# Decision: Issue E — 10 candidates cycle3-2026-b2 com interview_status='scheduled' SEM objective_score_avg → let proceed

**Date:** 2026-05-09
**Decided by:** Vitor Rodovalho (PM)
**Status:** Accepted
**Reversibility:** Low (decisão sobre 10 indivíduos em ciclo ativo; reverter pós-comunicação aos candidatos = friction alta)
**Path impact (Trentim A/B/C):** preserva (process integrity preservada via gate forward-only; "Núcleo absorve falha processual" é institutional consistent)

## Context

Step 0.5 pre-mortem p125 + Wave 2 council E2 surfaced 10 cycle3-2026-b2 candidates com `interview_status='scheduled'` mas `objective_score_avg=NULL`. Originalmente framed como Issue E ("legacy bypass") + Issue B ("schedule_interview gate bypass").

**Live recon p126 revelou (`docs/strategy/p126_issue_e_diagnostic.md`)**:
- Os 10 são em ciclo ATIVO (cycle3-2026-b2, phase=evaluating)
- score é NULL, não 0
- Status original 'submitted', não advanced
- 5/10 têm `final_score` populated (suggests partial scoring path)

**Recon adicional p126 (revisão de schedule_interview RPC + ADR-0073)**:
- `schedule_interview` JÁ tem 3 gates rígidos (Gate 1 AI, Gate 2 peer review, Gate 3 score) desde p87 (migration 20260516380000)
- Path alternativo `sync_calendar_booking_to_interview` (ADR-0073) **bypassa intencionalmente** os gates — design rationale: "booking via Calendar é informational, não significa decisão"
- 10 candidatos provavelmente entraram via esse path (manual call OR admin UPDATE — webhook_url=NULL impede Apps Script automatic flow)

## Options considered

- A) **Let proceed — todos os 10 continuam pipeline normal** (current scoring, interview, decision based on cycle's standard criteria)
- B) Re-schedule — cancelar bookings + restart objective scoring path
- C) Document gap, proceed enriching for un-evaluated remaining; disclose post-mortem

## Decision

**A — Let proceed.** PM principle: "process failure não pode refletir em perda de experiência/fricção a candidatos a não ser que realmente necessário; neste caso é mitigável."

## Rationale

- **Process failure is internal**: candidatos fizeram tudo certo (submitted candidatura, agendaram entrevista). Falha foi interna (alguém bypass gate ou UI exposed booking sem objective_eval done).
- **Cancelling now = high friction**: candidatos já marcaram horários, criaram expectativa. Cancelar = fricção institucional desproporcional ao gain de "process purity".
- **Mitigable forward-only**: gate enforcement via `schedule_interview` já existe; futura instâncias bloqueadas. Issue B não é nova falha — é manifestação ADR-0073 design intencional.
- **LGPD Art. 20 risk if cancel**: rolling back a decision arbitrarily creates appeal vector. Letting proceed maintains process consistency com objective_eval rolling out paralelo.
- **Audit trail**: esta decisão registrada formalmente; selection committee notes documentam exception explicitly.

## Implementation

### Forward-only gate (already exists)
- `schedule_interview` RPC has 3 gates since p87 — no patch needed
- `sync_calendar_booking_to_interview` continues bypassing gates per ADR-0073 design
- New bookings via this path will continue creating interview_status='scheduled' rows pré-scoring (intentional)

### Communication to selection committee
- PM notify selection committee that 10 candidates have non-standard sequence
- Document in selection committee notes: "esses 10 candidatos foram a entrevista antes do objective_eval avg estar computado; análise será feita post-interview"

### Communication to affected candidates: NONE
- Candidatos não viram a falha; comunicar = revelar gap institucional desnecessariamente
- Process flows naturalmente; objective_score será computado eventualmente; final decisions based on full data

### Audit cleanup
- Update `docs/strategy/p126_issue_e_diagnostic.md` with this decision reference
- Issue E closes as resolved (let-proceed); Issue B closes as not-a-bug (ADR-0073 design)

## Council inputs

- security-engineer Wave 2 (E2 review): identified booking-without-score as integrity gap; concurred com PM judgment "process consistency post-fix forward only"
- product-leader implicit: "candidate journey > process integrity" alignment with PM principle
- ADR-0073 (2026-05-06): explicitly designed sync bypass + score-submission gate

## Implementation owner

- **PM (Vitor)**: this decision document is the governance memo
- **Selection committee**: PM notifies + documents in committee notes
- **Future-state**: Issue A Apps Script deployment will populate webhook_url so future Calendar bookings auto-sync (vs current ad-hoc manual)

## Acceptance criteria

- Decision dated + archived em `docs/council/decisions/`
- 10 affected candidatos identified em Issue E diagnostic doc + cross-referenced
- Selection committee notes updated to reference this decision
- Issue B + Issue E status: CLOSED (not-a-bug + let-proceed respectively)

## Linked artifacts

- ADR-0073 (Issue 116 Calendar booking sync via Apps Script — design rationale for gate bypass)
- ADR-0076 Princípio 4 (Cycle 3 freeze — V1 prompt; doesn't conflict with let-proceed)
- `docs/strategy/p126_issue_e_diagnostic.md` (live data + remediation steps)
- p87 schedule_interview workflow gates (migration 20260516380000)
- LGPD Art. 20 §1 (decision review; cancellation cria appeal vector — preserved)
