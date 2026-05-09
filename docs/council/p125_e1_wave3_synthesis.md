# p125 E1 Wave 3 Synthesis — PM as Product Lead

**Date:** 2026-05-09
**Sessão:** p125
**Predecessor:** Step 0 (`p125_spec_strategic_review.md`) + Step 0.5 (`p125_premortem.md`) + Wave 1 PM drafts (ADR-0076 + 8 migrations) + Wave 2 council parallel review (5 agents)
**Successor:** Wave 4 = ADR-0076 sign-off (Vitor + Ivan DPO ratification — async); E2 worker drafting (next session) precedes E1 migration apply to prod

## Wave 2 council verdicts (5 agents paralelos)

| Agent | Verdict | Convergências fortes flagadas |
|---|---|---|
| data-architect | YELLOW | 6 missing NULLs em anonymize functions + service_history_count cache violation + hardcoded date '2026-05-18' |
| security-engineer | YELLOW | Risk 2 fechado com 1 ghost-member edge case + EXCEPTION silent skips em anonymize_rejected_applicants |
| legal-counsel | APROVADO COM RESSALVAS | LIA Art. 7 IX defensável + Trentim firewall não-vinculante hoje + PMI Global DPA gap + retention anchor errado em anonymize_free_text_bios |
| platform-guardian | YELLOW | service_history_count denormalized survives purge + ADR table stale + invariants count mismatch |
| accountability-advisor | YELLOW | ADR-0013/0076 numbering broken + audit gaps gender/age unanchored + 5 chapter VP contacts unnamed |

## Wave 3 fixes aplicados — Categorias

### A. SAFE fixes auto-aplicados pela Wave 3 synth (12 items)
1. ✅ anonymize_rejected_applicants + anonymize_inactive_members: 6 missing NULL clears (`service_history_count`, `service_first_start_date`, `service_latest_end_date`, `is_open_to_volunteer`, `pmi_data_fetched_at`, `consent_version`) — fechava gap LGPD Art. 18 §VI
2. ✅ anonymize_rejected_applicants EXCEPTION block: data_anomaly_log INSERT — não silenciar skipped rows
3. ✅ anonymize_free_text_bios retention anchor: `COALESCE(pmi_data_fetched_at, imported_at, created_at)` — Art. 6 §III correto
4. ✅ anonymize_free_text_bios appeal window check: `NOT EXISTS sc.close_date > now() - interval '60 days'` — preserva motivation_letter durante appeal window per ADR-0067 D4
5. ✅ I_VEP_IMPORT_COLUMNS_COMPLETE: removido hardcoded date, usa `pmi_data_fetched_at IS NOT NULL` — date-agnostic
6. ✅ import_vep_applications v_applicant_city fallback: removido `v_row->>'state'` (state era US-style code)
7. ✅ Migration 4 header: "3 invariants" → "5 invariants"
8. ✅ ADR-0013 → ADR-0076: corrigido em 4 decisions docs
9. ✅ ADR Implementation table: atualizada para 8 migrations (incluindo Hotfix Wave 0 + 5b + nova Migration 6)
10. ✅ COMMENT ON COLUMN para 7 Phase B fields sem COMMENT (legal-counsel E3 + data-architect D3)
11. ✅ COMMENT ON COLUMN service_history_count + 3 derived: SNAPSHOT-ONLY documentado (Decision S5 — ADR-0012 Principle 2 não aplica)
12. ✅ Migration 3 header: contradição com Migration 1 resolvida via SNAPSHOT semantics

### B. PM-locked Wave 3 decisions (Decisions S1-S12)

**Decision S1 — gender out-of-scope; age_band CHECK constraint voluntário**
- ✅ ADR-0076 Princípio 8 atualizado: gender REMOVED de E4 dimensions; age_band gated by mini-audit Ivan 30/Jun/2026
- ✅ Nova Migration 6 (20260518060000): CHECK constraint `age_band IN ('18-25','26-35','36-50','50+','prefer_not_to_say')` + COMMENT documentando out-of-scope para gender
- ✅ Cycle 4+ termo voluntariado v3 NÃO pede gender; age_band voluntário
- E4a CSV ships com 5 dimensões pós-Wave 4 (geo + industry + certs + senioridade + multi-chapter); age_band entra como 6ª pós Ivan sign-off

**Decision S2 — IP Policy v3 commitment Q3 2026 + cláusula penal**
- ✅ ADR-0076 Princípio 7 atualizado com path forward concreto
- ✅ Decision 7 markdown atualizado com Wave 3 synth section
- Owners: Vitor (PM) + Ivan (DPO PMI-GO) co-drivers
- Deadline: 30/Set/2026
- Cláusula penal: 3 meses budget capítulo violador → 4 não-violadores
- Tracking: GitHub issue T-2 (a abrir)

**Decision S3 — PMI Global authorization stance**
- ✅ Aceito A: LIA only no ADR-0076 + B na próxima VEP partnership renewal
- Não bloqueia E1; reduz exposure progressivamente

**Decision S4 — PMI Code §3.3.4 cross-reference**
- ✅ ADR-0076 Princípio 10 (NEW) adiciona assessment formal contra Code §3.3.4 + §2.2.6
- Public-by-default Community ≠ proprietary no sentido do Code

**Decision S5 — service_history_count snapshot semantic**
- ✅ COMMENT ON COLUMN documenta SNAPSHOT-ONLY (não cache; ADR-0012 Principle 2 não aplica)
- ✅ Migration 3 header contradiction resolvida

**Decision S6 — selection_application_service_history RLS**
- ✅ Mantém atual: `view_pii OR promote` — committee evaluators precisam ver service history
- Sign-off Ivan DPO ratifica explicit

**Decision S7 — anonymize_pmi_cascade semantic**
- ✅ Mantém atual (helper deleta explicitly) — defense-in-depth para ghost member edge case

**Decision S8 — anonymize_free_text_bios appeal window**
- ✅ Aplicado: `NOT EXISTS sc.close_date > now() - interval '60 days'` clause
- 60-day buffer post cycle close (30 day appeal + 30 day buffer)

**Decision S9 — Cycle 5+ profileAboutMe Precondition 4 (DPIA/RIPD)**
- ✅ Memory file `project_p125_cycle5_profileaboutme_track.md` atualizado com Precondition 4
- ✅ Action item: Vitor verifica com Ivan se RIPD interno PMI-GO existe; se não, Vitor drafta como anchor (oportunidade liderança LGPD Latam)
- PMI-GO public site (https://pmigo.org.br/politicas/) tem só Política Privacidade (atualizada 11/12/2025); RIPD/DPIA não público

**Decision S10 — is_open_to_volunteer view-level redaction**
- ✅ Process risk aceito (atual)
- COMMENT explícito + DPO sign-off ratifica
- View-level redaction adiada para Cycle 4 backlog (invasive change)

**Decision S11 — Severity taxonomy migration**
- ✅ Manter standalone Wave 4
- Separate migration post-Wave 4 alinha taxonomy (high/medium/low) + integra em base check_schema_invariants

**Decision S12 — Cycle 4 launch memo**
- ✅ Owner: Vitor (PM) + deadline 15/Ago/2026 OR 30 dias antes Cycle 4 open

### C. Items deferred to E2/E3/E4 Wave 2 (não Wave 3)
- security-engineer S2 (RLS service_history selectivity): RLS atual mantém via Decision S6
- security-engineer S4 (check_schema_invariants_p125 weak auth gate): defer pra separate migration post-Wave 4 (Decision S11 path)
- security-engineer Q3 (mapper E2 profilePrivate enforcement): E2 Wave 2 audita
- accountability-advisor S-3 (5 chapter VP contacts): Vitor solicita a Ivan; pre E3 Wave 1
- accountability-advisor T-2 (gender/age audit owner): Decision S1 + S9 fecha — owners Vitor + Ivan, deadline 30/Jun/2026

## Pendências Wave 4 (sign-off async)

### Vitor + Ivan DPO ratification
- ADR-0076 status: `Proposed` → `Accepted` após Ivan DPO sign-off
- Ressalvas Ivan a ratificar:
  1. Trentim firewall IP Policy v3 commitment Q3 2026 + cláusula penal
  2. age_band mini-audit deadline 30/Jun/2026
  3. PMI Global authorization status (A: LIA-only) + ação para B (próxima VEP renewal)
  4. service_history RLS `view_pii OR promote` para committee
  5. is_open_to_volunteer process risk acceptance
  6. RIPD interno verification (Decision S9)

### Tracking items para criar (GitHub issues)
- **T-1** (LOW): Calendar reminder profileAboutMe 2026-08-15 review
- **T-2** (HIGH): IP Policy v3 revision Q3 2026 — owners Vitor + Ivan
- **T-3** (HIGH): E3 cron 5 chapter VP coordination + named contacts (pre E3 Wave 1)
- **T-4** (MEDIUM): DPA Anthropic request (Cycle 5+ Precondition 1)
- **T-5** (HIGH): age_band mini-audit by Ivan deadline 30/Jun/2026 — go/no-go gate para E4a 6ª dimension
- **T-6** (MEDIUM): Cycle 4 launch memo deadline 15/Ago/2026 — Vitor (PM)
- **T-7** (LOW): RIPD interno PMI-GO verification with Ivan (informa Decision S9 path)

### Apply gate (production deploy preconditions)

ANTES de aplicar E1 migrations 1-6 em prod:
1. ADR-0076 status `Accepted` (Ivan DPO sign-off completed)
2. E2 worker mapper code drafted + deployed (atomicity Princípio 11)
3. Hotfix Wave 0 (Migration 0 = 20260517235500) pode aplicar standalone — independente
4. Smoke test em staging Supabase branch antes de prod

## Implementation table — final post-Wave 3

| # | Migration file | Timestamp | Status |
|---|---|---|---|
| 0 | `_p125_hotfix_wave0_engagements_end_date_source.sql` | 20260517235500 | ✅ Wave 1 + Wave 3 fixes |
| 1 | `_p125_e1_selection_applications_pmi_3d_columns.sql` | 20260518000000 | ✅ Wave 1 + Wave 3 fixes (RPC + COMMENTs + fallback fix) |
| 2 | `_p125_e1_pmi_chapter_memberships.sql` | 20260518010000 | ✅ Wave 1 (sem fixes Wave 3) |
| 3 | `_p125_e1_service_history_table.sql` | 20260518020000 | ✅ Wave 1 + Wave 3 (header contradição resolvida) |
| 4 | `_p125_e1_invariants_extension.sql` | 20260518030000 | ✅ Wave 1 + Wave 3 (date hardcode fix + count fix) |
| 5 | `_p125_e1_anonymize_bifurcated_cron.sql` | 20260518040000 | ✅ Wave 1 + Wave 3 fixes (NULLs + EXCEPTION + retention anchor + appeal window) |
| 5b | `_p125_e1_anonymize_inactive_members_cascade.sql` | 20260518050000 | ✅ Wave 1 + Wave 3 fixes (NULLs) |
| 6 | `_p125_e1_age_band_constraint_gender_freeze.sql` | 20260518060000 | ✅ Wave 3 NEW (Decision S1) |

8 migrations total. Hotfix Wave 0 (#0) é standalone-deployable. Migrations 1-6 wait for E2 worker deploy.

## Outputs canônicos sessão p125

| Artefato | Path | Status |
|---|---|---|
| Step 0 strategic review | `docs/council/p125_spec_strategic_review.md` | ✅ Final |
| Step 0.5 pre-mortem | `docs/council/p125_premortem.md` | ✅ Final |
| 9 PM decisions (Step 0/0.5) | `docs/council/decisions/2026-05-09-p125-decision-{1..9}-*.md` | ✅ Final |
| ADR-0076 master | `docs/adr/ADR-0076-pmi-3d-volunteer-model-and-phase-b-base-legal.md` | Proposed → pending Ivan DPO Wave 4 |
| 8 E1 migrations | `supabase/migrations/2026051723*.sql` + `2026051800*.sql` | Wave 1+3 drafts; pending E2 + Ivan |
| Wave 3 synthesis | `docs/council/p125_e1_wave3_synthesis.md` | ✅ Final (este doc) |
| Cycle 5+ profileAboutMe track | `memory/project_p125_cycle5_profileaboutme_track.md` | ✅ Updated com Precondition 4 |

## Próximas sessões — sequência recomendada

1. **Async**: Vitor envia ADR-0076 + 9 decisions docs para Ivan DPO ratification (próxima reunião biweekly Vitor↔Ivan)
2. **Próxima sessão p126**: E2 worker draft (mapper + types) — depende de ADR-0076 ratificada OU pode prosseguir Wave 1 paralelo com signoff async
3. **p127+**: E2 Wave 2 council + Wave 3 synth + Wave 4 sign-off
4. **p128+**: E3 + E4a sequencial (cada com 4 waves)
5. **Q3 2026**: IP Policy v3 revision + 5 presidents ratification meeting
6. **30/Jun/2026**: age_band mini-audit Ivan completion deadline
7. **15/Ago/2026**: Cycle 4 launch memo Vitor draft
8. **2026-09-01 → 2026-12-15**: Cycle 4 V2 enriched prompt deploy

## Lessons learned p125 (durables)

- **Step 0 strategic upfront é alto-ROI**: catched 4 cross-deliverable contradictions ANTES de drafting (gender base legal, multi-chapter authorization, profileAboutMe LLM, Trentim firewall). Saving = ≥1 day of rework.
- **Live DB queries beat handoff text**: 3 premissas do handoff foram invalidadas (state/country já existem; chapter rename é breaking; persons.chapter NÃO existe). Sempre verificar live antes de draftar DDL.
- **Council 5 agents Wave 2 = 4 YELLOW + 1 conditional**: nenhum aprovou as-is. Mas TODOS achavam que o spec era "structurally sound" — divergências eram em detalhes (NULLs, hardcodes, severity taxonomy). High convergência on big picture, divergência on details = healthy review structure.
- **Decision logs são audit primary defense**: 9 decisions × estrutura fixa (Context/Options/Decision/Rationale/Owner/Reversibility) = artifact chain robusto para qualquer audit PMI Latam.
- **Wave 3 fixes auto-aplicáveis vs PM-locked**: clear rule — typos/safe-NULLs/COMMENTs claude aplica; semantic decisions PM lock.
