# Decision: Cron deploy gate (E3) — dry-run staging 2 semanas + 3 pilot consenting

**Date:** 2026-05-09
**Decided by:** Vitor Rodovalho (PM)
**Status:** Accepted
**Reversibility:** Medium (kill switch cron possível; mensagens enviadas unrecoverable)
**Path impact:** preserva A/B/C; brand protection beneficia todos paths

## Context

Pre-mortem Risk 4: cron compliance D-60/D-30/D-7 sobre TWO timelines (engagements.end_date + pmi_chapter_memberships.expiry_date) tem alta chance de candidate UX disaster. Sem chapter VP secretarial coordination, mensagens podem chegar mesma semana, plataforma idêntica, parecendo conflito ou redundância.

## Options considered

- A) **Dry-run staging 2 semanas + 3 pilot candidates consenting + chapter VP briefed**
- B) Direct deploy com kill switch + monitoring 48h
- C) Phased rollout por chapter (Goiás first, expand)

## Decision

**A**. Dry-run staging + pilot validação antes de go-live full.

## Rationale

- TWO timelines coordinating = alta probabilidade de overlap message indesejado
- Chapter VP secretarial coordination = sem isso, PMI-GO renewal notice + Núcleo termo notice na mesma semana = candidate confusion
- 3 pilot candidates = small sample real-world validation; não é apenas Vitor email
- 2 semanas = cobre full D-60/D-30/D-7 cycle (60d max gap)
- Kill switch (B) é mitigation, não prevention
- Phased por chapter (C) prolonga go-live timeline desnecessariamente

## Council inputs

- pre-mortem (this session): Risk 4 mitigation explícita — chapter VP secretarial briefing como gate
- ux-leader Watch-out (E3 Wave 2): "if interviewers have already adapted workflows to the broken state, a sudden webhook activation may create double-booking"

## Implementation owner

- E3 Wave 1 PM drafting: ADR-0013 declara dry-run protocol explicitamente
- E3 Wave 2 council review: ux-leader + product-leader sign-off no template + dry-run plan
- Dry-run window: 2 weeks pre go-live
- Pilot list: Vitor + 2 chapter leads consenting (provavelmente Fabricio + 1 outro)
- Chapter VP secretarial briefing: meeting 1 week pre go-live, present templates + timing logic

## Acceptance criteria

- Dry-run staging environment recebe cron output (sem real email send) por 2 semanas
- 3 pilot candidates receive real emails durante semana 1 do dry-run, give feedback
- Chapter VP secretarial 5 chapters briefed em meeting before deploy
- Cron logs durante dry-run analysed: false positives count, timing collisions count
- Go/no-go decision pós-dry-run: se >5% false positives ou ANY collision com PMI renewal, defer + redesign
- Templates distintos com nomenclatura explícita ("termo de voluntariado Núcleo" vs "filiação PMI [Chapter]")
- Quiet window enforced: mensagens não disparam entre 18h sextas e 8h segundas

## Linked artifacts

- ADR-0013 (section "Cron deploy protocol")
- `docs/council/p125_premortem.md` (Risk 4)
- E3 Wave 1 spec (a ser draftado)
