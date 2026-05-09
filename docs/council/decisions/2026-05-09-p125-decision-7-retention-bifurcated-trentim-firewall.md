# Decision: Retenção bifurcada + Trentim Path B firewall ADR clause

**Date:** 2026-05-09
**Decided by:** Vitor Rodovalho (PM)
**Status:** Accepted
**Reversibility:** Medium (cron logic reversível; mas dados anonimizados antes de 5y são unrecoverable)
**Path impact:** preserva A/B/C; Path B (consulting) explicitly firewall'd

## Context

Council convergence (legal-counsel + security-engineer) que retenção 5y para todos viola Art. 6 §III LGPD (minimização) para candidatos não-selecionados. profileAboutMe (texto livre) tem maior risco latente de conteúdo sensível Art. 11 — merece retenção mais curta. Adicionalmente, accountability-advisor flagged Trentim Path B (consulting) risk: persistir 171 historical PMI roles + diversity aggregates pode posicionar dataset como "asset comercial" sem authorization dos 5 chapter presidents que ratificaram IP Policy.

## Options considered

- A) Anonymize cron 5y para todos (status quo)
- B) **Bifurcado: 5y para active members; 12 months para non-selected applicants; 90 days para profileAboutMe + bio fields independent of selection** + ADR clause Trentim firewall
- C) 5y for all, com profileAboutMe explicit short retention (90d)

## Decision

**B**. Retenção bifurcada + ADR clause Trentim firewall obrigatória.

## Rationale

- 5y (status quo) é desproporcional para candidato sem engajamento pós-seleção — viola Art. 6 §III
- 12 meses para applicant-rejected = compatível com prazo eventual contestação + Cycle seguinte de candidatura
- 90 dias para profileAboutMe = priorização anti Art. 11 (dado sensível latente em texto livre)
- ADR clause Trentim firewall: "data persisted under este modelo é para selection + operational governance only; commercial use requires new CR approved by all 5 ratifying chapters"
- Sem clause Trentim, dataset pode ser invocado externalmente (pitch consultoria, LIM keynote) sem governance — accountability-advisor risk

## Council inputs

- legal-counsel: "Recomendação B. 5 anos é desproporcional para candidato sem engajamento pós-seleção"
- security-engineer: "Option B. Service history detail rows movidos para anonymized summary após cycle close"
- accountability-advisor: "Option B + Trentim Path B firewall ADR clause"

## Wave 3 synth update (2026-05-09 — Decision S2 locked by PM)

**IP Policy v3 commitment** para tornar Trentim firewall legalmente vinculante (não apenas cultural):

- **Owners**: Vitor (PM Núcleo) + Ivan (DPO PMI-GO) co-drivers
- **Deadline**: Q3 2026 — até 30/Set/2026
- **Cláusula penal mínima**: 3 meses budget do programa Núcleo IA pagos pelo capítulo violador para os 4 capítulos não-violadores
- **Definição precisa de "commercial use"**: lista explícita (consulting engagement com terceiro pago / white-label da methodology / sale of dataset access / sharing com 3rd party não-PMI / monetização direta ou indireta de aggregate insights)
- **Veículo**: approval_chains workflow existente (5 presidents ratificam — mesmo padrão IP Policy v2)
- **Trigger pré-CR**: any external mention by Núcleo team em pitch/keynote/whitepaper de dataset como "talent intelligence", "diversity benchmark", ou "consulting asset" OBRIGA pause + CR antes de prosseguir
- **Tracking**: GitHub issue T-2 + agendamento governance review meeting com 5 presidents ANTES de Path B materializar

## Implementation owner

- E1 Wave 1 ADR-0076: explicit retention table per concept (active member / applicant rejected / free-text bio)
- E1 Wave 1 ADR-0076: clause "Trentim Path B firewall" — exact wording em ADR Princípio 7 + IP Policy v3 path forward (Decision S2 acima)
- E1 Wave 1 cron extension migration: bifurcate `anonymize_cron_5y` logic
  - Active members (status='active'): 5y retention
  - Applicants rejected (selection_applications.status IN ('declined','withdrawn','removed')): 12 months
  - Free-text bio fields (profile_about_me, non_pmi_experience): 90 days regardless of status
- E1 Wave 2 (data-architect): verify CASCADE coverage — Risk 2 do pre-mortem

## Acceptance criteria

- ADR-0013 contains retention table + Trentim firewall clause
- Migration extends `anonymize_cron_5y` (or creates `anonymize_cron_bifurcated`) com 3 tracks
- Test: applicant rejected 12+ months ago → fields anonymized
- Test: profile_about_me 90+ days old → field cleared (cycle agnostic)
- 5 chapter presidents ratification trail: Trentim firewall clause visible to them at next governance review

## Linked artifacts

- ADR-0013 (section "Retention bifurcated + Trentim firewall")
- LGPD Art. 6 §III (minimização), Art. 11 (dados sensíveis), Art. 18 §VI (eliminação)
- IP Policy v2 (5 chapter presidents ratified Apr 2026)
