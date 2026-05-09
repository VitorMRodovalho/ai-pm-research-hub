# Decision: Issue D fallback strategy — multi-source end_date com origem flagged

**Date:** 2026-05-09
**Decided by:** Vitor Rodovalho (PM)
**Status:** Accepted
**Reversibility:** High (fallback strategy pode evoluir; nenhum dado destruído; cron alertas perdidos durante gap recoverable se fix shipa em N+1)
**Path impact:** preserva A/B/C

## Context

Issue D fix proposto via `agreement_certificate_id` source. Mas live audit revelou: **58/94 active engagements (62%) NÃO têm agreement_certificate_id**. Fallback strategy obrigatória — sem ela, Issue D resolvida apenas para 36/94 (38%) e legacy cohort permanece invisível para cron compliance.

## Options considered

- A) **Backfill multi-source: `agreement_certificate_id` primeiro, fallback `pmi_vep` (serviceEndDateUTC) com `metadata->>'end_date_source'` flag**
- B) Backfill estimated current_date + 6m com flag origem
- C) Manual data entry chapter VP secretarial — labor-intensive
- D) Defer Issue D — reconhecer como P1 não resolvido em p125

## Decision

**A**. Multi-source com origem flagged em metadata.

## Rationale

- 36/94 (38%) podem ser backfilled de agreement_certificate (canonical, accurate)
- 58/94 (62%) precisam fallback — PMI VEP serviceEndDateUTC é fonte secundária disponível imediata
- audit trail via `metadata->>'end_date_source'` = ('agreement', 'pmi_vep', 'estimated', 'manual') permite E3 cron filtrar por confidence level
- Não é "estimated guess" — é dado real do PMI (mesmo que opportunity-window-based vs term agreement)
- João Coelho case: PMI serviceEndDate provavelmente cobrirá mesmo sem agreement_certificate

## Council inputs

- data-architect: "agreement_certificate canonical para term; PMI dates secundário"
- pre-mortem (this session): Risk 5 ranked HIGH probability + MEDIUM-HIGH impact — fallback strategy obrigatória

## Implementation owner

- Hotfix Wave 0 (per Decision 1) ou E1 Wave 1: SQL audit doc + migration adicionando fallback logic
- E2 Wave 1 worker mapper: 
  - First try: `agreement_certificate_id` derived end_date (if exists, source='agreement')
  - Fallback: `serviceEndDateUTC` from PMI VEP (source='pmi_vep')
  - Last resort: `current_date + 6 months` (source='estimated', flagged for manual review)
- E3 Wave 1 cron logic:
  - 'agreement' source: D-60/D-30/D-7 alerts (high confidence)
  - 'pmi_vep' source: D-90/D-60/D-30 alerts (earlier, less confidence; mensagem "estimativa baseada em PMI VEP, confirmar com sua chapter VP")
  - 'estimated' source: alerta apenas como "pendente confirmação" no admin dashboard, NÃO ao candidato

## Acceptance criteria

- engagements.metadata JSONB ganha `end_date_source` key (one of: agreement | pmi_vep | estimated | manual)
- Test: backfill aplicado em 94 active → 36 source='agreement', ~50 source='pmi_vep', remainder source='estimated'
- E3 cron filter `metadata->>'end_date_source'` antes de send
- Audit query: `SELECT metadata->>'end_date_source', COUNT(*) FROM engagements WHERE status='active' GROUP BY 1` deve mostrar distribuição

## Linked artifacts

- ADR-0013 (section "Issue D fallback strategy")
- ADR-0007 (engagements canonical authority — NULL semantics)
- `docs/council/p125_premortem.md` (Risk 5)
