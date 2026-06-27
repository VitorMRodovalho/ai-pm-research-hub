# SPEC #902 sub-gap 2 — VEP-expired re-application (policy + authority + comms)

- **Status:** **Fase 1 RATIFIED + BUILT** (PM 2026-06-27: scope = comms + runbook, Expired/OfferExpired only, re-anchor; Withdrawn excluded, OfferNotExtended manual GP review). Fase 1 shipped dormant on branch `feat/902-subgap2-phase1-comms-runbook` (migration `20260805000255`, applied additive/dormant; awaiting PR merge). **Fase 2 (auto-approve RPC) remains DEFERRED** pending cycle5 + cohort justification + a new ADR. Original deferral: PM 2026-06-26 ("spec + legal review BEFORE any code").
- **Ratified decisions:** D1 = Expired/OfferExpired only · D2 = GP human-click, no cron bypass, no seed expansion · D3 = **re-anchor** (resume pipeline; prior score = GP context, never inherited approval) · D5/D7 = membership gate out of scope v1, phased.
- **Issue:** #902 sub-gap 2 (sub-gap 1 = visibility, shipped in PR #903, merged + live).
- **Author:** PM main-loop synthesis over a 13-agent grounding+review+adversarial-verify workflow (`wf_cc1ab601-977`, 2026-06-26). All counts/RPC bodies grounded against live prod (`ldrfrvwhxsmgaabwmaik`) this session.
- **Governing precedent:** ADR-0067 D1 (every admission/refusal/advancement decision is made **exclusively by the human committee**) + LGPD Art. 18 (member-lifecycle = GP-only) + `.claude/rules/database.md` "V4 Authority audit" (no seed-expansion of `engagement_kind_permissions` for destructive actions).
- **Council verdict:** all four lenses (legal-counsel, security-engineer, data-architect, product-leader) returned **CONDITIONAL**. Two of three load-bearing design claims came back **partial**; one came back **refuted**. The refutation is the centre of this spec.

---

## 0. TL;DR (PT-BR, para decisão do PM)

A direção proposta no #902 — *"comunicar que a oferta VEP não pôde ser estendida, mas uma re-aplicação seria **auto-aprovada com o score anterior transferido**, com início condicionado a filiação PMI corrente"* — **não pode ser ratificada como está**. O aterramento ao vivo derruba a sua premissa central e expõe três bloqueadores convergentes nas quatro lentes do conselho:

1. **Não existe "aprovação anterior" para fazer grandfather.** `cutoff_approved_email_sent_at` é o **passe na triagem objetiva + convite de entrevista**, não uma admissão. **Só 1 dos 7** candidatos da coorte chegou a entrevistar; os 2 casos "limpos" (Expired) **nunca entrevistaram**. Logo "transferir score e auto-aprovar" superestima o que esses candidatos conquistaram — eles passaram só a 1ª etapa.
2. **"Auto-aprovar" sem clique humano de GP viola o invariante de ciclo de vida (ADR-0067 D1 + LGPD Art. 18).** `approve_selection_application` é `manage_platform` (GP-only) e cria membro/engajamento. O "auto" só pode ser **pré-preenchimento de UX para um clique de GP**, nunca automação cega nem expansão de seed.
3. **Os 3 buckets têm naturezas jurídicas diferentes** e não podem ser tratados igual: Expired/OfferExpired (2, lapso de prazo puro) ≠ OfferNotExtended (4, decisão ATIVA do PMI/VEP de não estender) ≠ Withdrawn (1, o próprio candidato desistiu).

**Recomendação (faseada):**
- **Fase 1 (barata, ~1 sessão, mergeável já):** template de comms trilíngue "prazo VEP expirou — não foi rejeição por mérito — você pode se recandidatar" (bucket **Expired/OfferExpired apenas**), coluna de idempotência single-fire, e um **runbook manual de GP**. Sem auto-aprovar, sem transferência de score, sem gate de filiação. **Não ativar o cron até existir um próximo ciclo (cycle5).**
- **Fase 2 (3–5 sessões, só se a coorte do cycle5 justificar):** RPC `reapprove_from_prior_cycle` GP-gated (clique humano), **re-ancoragem** (retomar o pipeline na entrevista no novo ciclo, reavaliando contra o cutoff do novo ciclo) — **não** grandfather. Requer ratificação explícita do PM da regra de re-ancoragem e do escopo de buckets.

Nada disso cabe no `cycle4-2026` (fecha **2026-06-30**, ~4 dias); o alvo real é o próximo ciclo. Os 7 da coorte atual ficam elegíveis para o ciclo seguinte.

---

## 1. Grounded current state (load-bearing facts, live prod this session)

> Every number below came from a live `execute_sql` / `pg_get_functiondef` result in the 2026-06-26 grounding workflow. Re-ground at each PR boundary (CLAUDE.md grounding mandate).

### 1.1 The cohort (aggregate, no PII)

| `vep_status_raw` → `status` | n | interview eval **completed** | passed objective cutoff | has `final_score` |
|---|---|---|---|---|
| `OfferNotExtended` → `rejected` | 4 | **1** | 1 | 4 |
| `Expired` → `rejected` | 2 | **0** | 2 | 2 |
| `Withdrawn` → `withdrawn` | 1 | **0** | 1 | 1 |
| **Total** | **7** | **1** | 4 | 7 |

- All 7 are in **`cycle4-2026`** (open, phase `evaluating`, closes **2026-06-30**). Prior cycles have **0** cutoff-approval emails sent at all.
- **All 7 are pre-member** (0 match a `members` row by `lower(email)`). This is decisive for the membership-currency policy (§5.5).
- `final_score` is non-null on all 7, but **only 1/7 has a completed interview** — so for 6/7 the score reflects only the objective screening stage, not a completed evaluation pipeline. **`final_score` present ≠ merit admission earned.**

### 1.2 What `cutoff_approved_email_sent_at` actually means

The cutoff-approval email is fired by cron `selection-cutoff-pending-daily` (`_selection_cutoff_pending_cron` → `notify_selection_cutoff_approved`) gated `status IN ('screening','interview_pending') AND objective_score_avg >= pert_target_score AND cutoff_approved_email_sent_at IS NULL`. **It is the objective-pass + interview INVITATION, not an admission decision.** This is why "the candidate already cleared an approval cutoff" is false for this cohort.

### 1.3 Re-application is net-new; no score-transfer exists

- A re-application is **always a net-new `selection_applications` row** (via `import_vep_applications` or `promote_lead_to_application`); scores start NULL and derive from `selection_evaluations` per `application_id`.
- **No cross-cycle score-transfer mechanism exists.** The only score-copy idioms (`mirror_sibling_interview`, `admin_decide_dual_track`) are **same-cycle dual-track only** and work *because both rows share one cohort*.
- `import_vep_applications` **skips terminal VEP rows** (`OfferNotExtended/Declined/Withdrawn → CONTINUE`); dedup is on `(vep_application_id, vep_opportunity_id)`. A new cycle = new opportunity = new `vep_application_id` ⇒ net-new row.
- Candidate identity across cycles is matched **by `lower(email)` only** (no `person_id`/`member_id` FK on `selection_applications`). A re-application under a different email defeats `previous_cycles`/`is_returning_member` and any prior-row lookup.
- `linked_application_id` (self-FK) exists but is **dual-track-only today** (16/17 same-cycle); `admin_decide_dual_track` and `mirror_sibling_interview` branch on `promotion_path='dual_track'`. Reusing it cross-cycle is safe **only with a distinct `promotion_path` set at INSERT time** (autolink trigger `20260805000172` guards on `linked_application_id IS NULL`).

### 1.4 Scoring + PERT cutoff is distributional and per-cycle

- The PERT cutoff is **relative**: `target = (2*min + 4*avg + 2*max)/8` over **that cycle's own** applicant pool by role (`cohort_scope='current_cycle_applications_by_role'`), bands `lower=target*0.75`. The **same raw score is above-cutoff in one cycle and below in another** (live: cycle3-b2 `final_score` target 220.71 vs cycle4 221.84; cohort min/avg/max differ materially).
- `weighted_subtotal` is computed **at submit time against the source cycle's rubric** (`objective_criteria`/`interview_criteria`/`leader_extra_criteria`); rubrics drift across cycles (`leader_extra` 5→6 criteria cycle3→cycle3-b2/cycle4). **A copied score is a silent cross-rubric artifact.**
- `compute_pert_cutoff` UPDATEs `pert_*` on **all** cycle rows and runs **weekly** (cron jobid 47) — any "frozen snapshot" stored in `pert_*`/`final_score` is **clobbered** on the next Monday.
- ⚠️ `selection_cycles.objective_cutoff_formula` text column is **drifted/advisory** (stores `…/6*0.75`, live body hardcodes `/8`). **Cite the live `prosrc`, never the cycle text column.**

### 1.5 Authority model

- `approve_selection_application`: SECDEF, single gate `can_by_member(caller,'manage_platform')` (GP-only), **no cron/service bypass**, requires source `status IN ('approved','converted')`. It is a **member-lifecycle mutation** (INSERTs `members`/`persons`/`engagements`/`onboarding_progress`, flips `is_active`, promotes `operational_role`).
- `manage_platform` is seeded **only** for `volunteer × {manager, co_gp, deputy_manager}` at org scope. There is **no** designation/initiative path to it.
- **Precedents that matter:**
  - `admin_decide_dual_track` — GP-gated (`manage_platform`) **score-copy** between linked apps, then delegates to the single-app approval. The correct "auto = pre-fill under the same authority" idiom.
  - `auto_promote_eligible_leads_for_cycle` — "auto" = iteration over pre-qualified rows; REST callers gated `manage_member`, cron context via `_request_is_rest_caller()`. **Auto ≠ new authority grant.**
  - `anonymize_inactive_members` (cron, service_role-only EXECUTE grant ladder) — a system actor *can* do member-lifecycle, but **only to discharge an LGPD retention/deletion DUTY**, never to *grant* membership.
- **Anti-pattern (documented, do not commit):** seeding `engagement_kind_permissions` to give a non-GP actor `approve_selection_application`/`manage_platform` = privilege escalation breaking member-lifecycle=GP-only (LGPD Art. 18).

### 1.6 Membership currency

- `member_affiliation_verifications` has **0 rows** (F1 loop never exercised live); `members.pmi_id_verified` (44 true / 61 false) is **import-seeded, not live**. **Do not gate on it.**
- For pre-members the only live currency signal is `selection_applications.vep_status_raw='Active'` — **but the worker has already overwritten it to terminal for all 7.** A clean `Active` can only come from a **fresh VEP re-application** (= the re-application itself).
- `method='vep_sync'` leaves `membership_expires_on` NULL by design (VEP exposes no expiry). No existing gate blocks onboarding/start on currency (`sign_volunteer_agreement` *records* `affiliation_unverified` but never raises).

### 1.7 Comms substrate

- `campaign_send_one_off(slug, to_email, variables, metadata)` (service_role-only) → `send-campaign` EF (Resend, 100/day throttle) → renders `campaign_templates` jsonb `{pt,en,es}`. **Reaches pre-member candidates** (`external_email`, no member row needed).
- **Email i18n is NOT the frontend 3-dict** — it lives as a `campaign_templates` row (slug). A new message = one new template row.
- Idempotency convention = a per-application `*_sent_at timestamptz` stamp (`cutoff_approved_email_sent_at`, `vep_offer_reminder_sent_at`). **No `reapply` stamp column exists** — must be added.
- The **D7 VEP-offer-reminder** (`process_pending_vep_offer_reminders` + `trg_stamp_vep_offer_extended` + `sla_policies` grace + trilingual template with LGPD Art.7 footer) is the **exact structural analog** for the re-apply comms.
- No candidate `language` column → all selection emails currently render **pt** regardless of locale.

---

## 2. The central correction (why the original direction must change)

The #902 direction reads "an **approved** candidate … re-application would be **auto-approved with the prior score transferred**." Grounding refutes the two premises:

1. **"Approved" overstates it.** The cohort cleared the **objective gate + interview invite**, not admission. 6/7 never interviewed. There is no completed merit verdict to "transfer" or "grandfather."
2. **"Auto-approve" has no lawful, structurally-safe automation path.** The approval RPC is GP-only with no bypass; any automation route is either a seed-expansion escalation (forbidden) or a system *grant* of membership (legally distinct from the anonymize crons, which discharge a *duty*). ADR-0067 D1 already settles this: admission decisions are **exclusively** the human committee's.

**Consequence:** the defensible model is **re-anchor / resume the pipeline**, not grandfather. The re-applicant re-enters a future cycle, their prior objective score + interview-invite status is **surfaced to the GP as context**, and they **continue evaluation (interview) in the new cycle**, re-anchored against that cycle's own cutoff. The GP makes a fresh decision. This is more defensible *and* simpler than building a score-transfer + cohort-exclusion machine.

---

## 3. Decisions the PM must ratify (before any code)

Each decision lists the council-convergent recommendation. **Code is blocked until D1–D3 are ratified.**

### D1 — Bucket split (MANDATORY, all four lenses) 
Treat the three buckets distinctly; **never homogeneously**:
- **Expired / OfferExpired** (2) — pure deadline lapse by inaction → eligible for the re-apply invite + GP fast-track context. *The only clean "administrative, not merit" bucket.*
- **OfferNotExtended** (4) — PMI/VEP **actively** chose not to extend; may encode an eligibility judgment → **requires per-case GP review**, no fast-track by default. Inclusion needs explicit PM + legal ratification (→ ADR).
- **Withdrawn** (1) — candidate's own opt-out → **excluded** from re-apply invite + fast-track; if they re-apply it is a brand-new candidacy with no carried benefit.
> **Recommendation:** ratify Expired/OfferExpired as the v1 eligible bucket; exclude Withdrawn; route OfferNotExtended to manual GP review.

### D2 — Authority model (MANDATORY, NON-NEGOTIABLE)
- **No human-less auto-approve.** Approval stays `can_by_member(caller,'manage_platform')` with a **human GP click** (ADR-0067 D1; LGPD Art. 18). "Auto" = pre-fill + surface prior context, under the same gate.
- **No seed expansion** of `engagement_kind_permissions`. **No cron/service bypass added to `approve_selection_application`.**
- If a Phase-2 RPC is built, it is SECDEF gated **strictly** `manage_platform` (not the committee-lead/`manage_member` entry style), reuses `approve_selection_application` internally, and writes its own `admin_audit_log` + preserves `data_anomaly_log 'selection_approval_canonical'`.
> **Structural note (adversarial finding):** a *service_role-only* entrypoint behind the EXECUTE grant ladder would not violate the *structural* seed/escalation invariant (the anonymize crons prove a system actor can do lifecycle). The reason to keep a human in the loop here is **legal/fairness (grant vs duty)**, ratified by ADR-0067 D1 — not the structural invariant. Keep the human click.

### D3 — Re-anchor vs grandfather (MANDATORY)
> **Recommendation: RE-ANCHOR (resume the pipeline).** Because 6/7 never completed evaluation, there is no admission to grandfather. The re-applicant resumes in the new cycle (at the interview stage for those already invited), is re-evaluated against the **new cycle's** `compute_pert_cutoff`, and the GP decides. The prior objective score + interview-invite status are **provenance/context only**, never a cohort-eligible score.
- Grandfathering is reserved **narrowly** for a candidate with a **complete** prior evaluation (interview done **and** `final_score ≥ prior pert_target`) — and even then only as a **GP-surfaced recommendation**, not auto. (Today: at most the 1 interviewed case could qualify, and it is OfferNotExtended → manual review anyway.)
- If grandfathering is ever chosen, it requires a net-new "carried, excluded-from-cohort-statistics" mechanism (does not exist) + a patch to `_compute_pert_cutoff_core` to exclude the row from cohort stats and from the weekly clobber. This is real Phase-2 work and an ADR.

### D4 — Legal basis for cross-cycle data reuse (MANDATORY before code; PT-BR parecer in §6)
Selection scores are personal data (LGPD Art. 5, I) collected under the "Ciclo 4-2026 selection" purpose. Reusing them in a new cycle is a new processing operation needing a documented basis. **Recommended basis for Expired:** Art. 7, II (continuidade de procedimento pré-contratual interrompido por causa administrativa) + Art. 6, I (finalidade compatível), with candidate transparency per Art. 9 in the comms. OfferNotExtended would need Art. 7, IX (legítimo interesse) + documented LIA + opt-out.

### D5 — Membership currency gate (policy "c") — DEFER to v2 / out of scope v1
All 7 are pre-member; `member_affiliation_verifications` is empty; `pmi_id_verified` is stale. The only clean signal is **a fresh VEP application with `vep_status_raw='Active'`** — which the re-application itself produces. So **policy (c) is vacuously satisfied** by a genuine VEP re-application and needs **no separate gate in v1**. Any future currency check must be **notify/alert only** (F3 radar pattern), never auto-block/auto-deactivate (that would be a GP-only lifecycle mutation).

### D6 — Comms (policy "a")
- New `campaign_templates` slug (e.g. `selection_vep_expired_reapply_invite`), trilingual `{pt,en,es}`, **conditional copy that never promises approval**: *"sua candidatura não avançou por motivo administrativo de prazo VEP — não foi rejeição por mérito — você pode se recandidatar; caso aceita pela GP, seus resultados anteriores poderão ser considerados."* Include the D7 LGPD Art. 7 controller/finalidade footer + opt-out line, and the Art. 9 note that prior evaluation data may be reused + an Art. 18 rights channel.
- **New single-fire stamp column** `selection_applications.vep_expired_reapply_email_sent_at timestamptz` (D7 pattern) **before** any sender. Filter `… AND vep_expired_reapply_email_sent_at IS NULL`.
- Dispatch via a **cron RPC** (ADR-0028 bypass, like D7), not worker-side, for auditability + grace-windowing. **Do not activate the cron until a live next-cycle VEP opportunity exists.**
- Copy differs per bucket (Withdrawn gets an informational-only variant, if anything).

### D7 — Scope / phasing
> **Recommendation:** Phase 1 = comms template + stamp column + **GP runbook**, Expired/OfferExpired only, no auto-approve/score-transfer/currency-gate. Phase 2 = the `reapprove_from_prior_cycle` RPC + re-anchor mechanism + admin UI, **only after cycle5 exists and the cohort size justifies it** (today: 2 clean cases — product-leader flags bespoke automation as negative ROI vs a runbook).

---

## 4. Proposed design — Phase 1 (shippable, low-risk)

> Phase 1 deliberately contains **no approval automation and no score transfer.** It makes the cohort actionable and prevents the *next* silent expiry from being a dead end.

1. **Migration (additive, dormant):**
   - `selection_applications.vep_expired_reapply_email_sent_at timestamptz NULL` + COMMENT referencing #902.
   - `campaign_templates` upsert: slug `selection_vep_expired_reapply_invite`, jsonb `subject/body_html/body_text` for `{pt,en,es}`, `variables` declaring `{first_name, reapply_url}` (the `reapply_url` stays a placeholder until cycle5 exists).
2. **Dispatch RPC (cron, dormant until activated):** mirror `process_pending_vep_offer_reminders` — scan `cutoff_approved_email_sent_at IS NOT NULL AND vep_status_raw IN ('Expired','OfferExpired') AND status='rejected' AND vep_expired_reapply_email_sent_at IS NULL`, single-fire stamp after send, ADR-0028 cron/service gate, `admin_audit_log` entry, `sla_policies`-driven grace window. **Cron schedule left unscheduled** until cycle5.
3. **GP runbook** (`docs/runbooks/` or memory): the manual path for the current 7 — `admin_move_application_to_cycle` into cycle5 once it exists, GP reviews the prior objective score + interview-invite status on the selection dashboard, candidate resumes evaluation, GP clicks approve under `manage_platform`. Withdrawn excluded; OfferNotExtended reviewed case-by-case.

## 4b. Proposed design — Phase 2 (only if ratified + cohort justifies)

`reapprove_from_prior_cycle(p_source_application_id, p_target_cycle_id)` — SECDEF, gated **strictly** `can_by_member(caller,'manage_platform')`, **human GP click**, **no cron bypass**:
- **Eligibility:** source `cutoff_approved_email_sent_at IS NOT NULL AND vep_status_raw IN ('Expired','OfferExpired') AND status='rejected'`.
- **Idempotency:** `NOT EXISTS (linked_application_id = source AND promotion_path='vep_reapply')` → else return `already_processed`.
- **Row creation:** INSERT new row with `linked_application_id = source.id` and `promotion_path='vep_reapply'` **in the same statement** (autolink-trigger safety); copy email/name; **leave `final_score`/`objective_score_avg`/`interview_score`/`pert_*` NULL** so the row is auto-excluded from cohort stats; carry the prior score only in a **dedicated provenance field** (e.g. `carried_prior_final_score`, `carried_from_application_id`), never in `pert_*`/`final_score`.
- **Re-anchor (D3):** the row **resumes evaluation** (interview) in the target cycle; approval is a fresh GP decision against the new cutoff. No auto status flip to `approved`.
- **Guards required (DDL via `apply_migration`, Track Q-C ritual):**
  - Patch `_compute_pert_cutoff_core` to exclude `promotion_path='vep_reapply'` rows from the cohort CTE **and** all UPDATE branches (base the patch on the **live `prosrc`**, not the drifted migration file).
  - Guard `compute_application_scores` to early-return on `promotion_path='vep_reapply'` (else it wipes the carried provenance to NULL silently).
  - New invariant `AG_vep_reapply_integrity` in `check_schema_invariants()` (counter 33→34): every `vep_reapply` row has `linked_application_id IS NOT NULL AND carried_from_application_id IS NOT NULL`.
- **Audit:** `admin_audit_log action='vep_reapplication_approved'` with `{source_application_id, source_cycle, prior_objective_score, prior_pert_target, vep_status_raw, gp_actor}` — closing the chain after the silent worker flip.

---

## 5. Risks & edge cases (must be addressed if Phase 2 proceeds)

- **5.1 PERT cohort contamination** — a carried score materialized into `final_score` shifts the new cycle's min/avg/max for *every* applicant. Mitigation: leave cohort columns NULL; carry only in provenance columns.
- **5.2 Weekly recompute clobber** — `pert_*` snapshots are overwritten Mondays. Mitigation: never store provenance in `pert_*`.
- **5.3 `compute_application_scores` silent wipe** — zero-eval `vep_reapply` row → `final_score=NULL`. Mitigation: the early-return guard.
- **5.4 `linked_application_id` collision** — `admin_decide_dual_track`/`mirror_sibling_interview` branch on `promotion_path='dual_track'`. Mitigation: distinct `promotion_path='vep_reapply'`, set at INSERT.
- **5.5 Membership currency is a mirage for pre-members** — `pmi_id_verified` stale; old `vep_status_raw` terminal. Only a fresh VEP `Active` counts. Notify, never auto-block.
- **5.6 Comms over-promise** — copy must not imply automatic approval (LGPD Art. 9 + expectativa legítima).
- **5.7 No target cycle** — cycle5 doesn't exist; `reapply_url` is undefined; cron must stay dormant.
- **5.8 Duplicate rows** — no `(cycle_id, email)` uniqueness; the RPC idempotency check + a careful runbook are the only guards.

---

## 6. Parecer jurídico (legal-counsel, PT-BR) — síntese

**Veredicto:** CONDICIONAL. Viável apenas para o bucket **Expired** (2 casos), com ajustes. Dois bloqueadores centrais:

1. **Conflação dos três buckets.** OfferNotExtended reflete decisão ativa de inelegibilidade do PMI/VEP (não lapso administrativo); Withdrawn reflete vontade do próprio titular. Tratar os três igual para auto-aprovação é juridicamente insustentável e indefensável frente a contestação de outro candidato do novo ciclo.
2. **Auto-aprovação sem decisão humana de GP viola Art. 18 (ciclo de vida = GP-only).** Distinção material: os crons de anonimização **descarregam um DEVER legal de retenção/deleção** (sistema executa o que a lei impõe); re-aprovação **CONCEDE** membro/engajamento (ato discricionário que exige ator humano responsabilizável — Art. 6, X). A assimetria dever-vs-concessão é o fundamento; não basta o invariante estrutural.

**Base legal do reuso de score:** declarar finalidade compatível (Art. 6, I) + base jurídica (Art. 7, II para Expired — procedimento pré-contratual interrompido por causa administrativa). Informar o candidato na comms (Art. 9) que dados de avaliação anteriores poderão ser reutilizados; indicar canal de direitos (Art. 18). Para OfferNotExtended, exigiria Art. 7, IX + LIA documentado + opt-out.

**Withdrawn:** excluir do fluxo de auto/fast-track; re-aplicação = candidatura nova com novo consentimento.

**PERT re-anchoring:** escolher e documentar UMA abordagem; a recomendação técnica reforçada por este parecer é **re-ancorar** (reavaliar no novo ciclo), por equidade frente aos demais candidatos.

**Timing:** mesmo ratificado hoje, a implementação não cabe antes do fechamento do cycle4 (30/06) sem bypass de CI; o alvo realista é o próximo ciclo. Tornar explícito que os 7 ficam elegíveis ao ciclo seguinte.

*Parecer para revisão inicial; confirmação com advogado licenciado recomendada antes de ratificação.*

**Governance note:** the human-in-the-loop invariant for this re-approval is **already covered by ADR-0067 D1** — no new ADR is needed for *that* principle. A **new ADR (or an ADR-0067 amendment) IS required** if the PM ever ratifies (a) including OfferNotExtended in a fast-track, or (b) grandfathering without re-evaluation — both depart from the conservative model and need a documented legal basis + rationale.

---

## 7. Migration hygiene (when code is authorized)

All DDL via `apply_migration` (never `execute_sql`), then the Track Q-C + apply-row-dedup ritual:
1. `apply_migration` (applies to remote).
2. `Write` local file `supabase/migrations/<next-ts>_<name>.sql` (ts > current head).
3. `supabase migration repair --status applied <next-ts>`.
4. `DELETE FROM supabase_migrations.schema_migrations WHERE version='<apply-time-auto>' AND name='<name>'` — because `apply_migration` **already inserts** an apply-time row (per `feedback_apply_migration_creates_tracking_row`); leaving it = a second row = `rpc-migration-coverage` drift failure.
5. `NOTIFY pgrst, 'reload schema'` for any RPC/policy/view change.
6. Base any `_compute_pert_cutoff_core` patch on the **live `prosrc`**, not the drifted migration file.

---

## 8. Derived issues to file (orthogonal to #902, surfaced by grounding)

- **Pre-member retention/anonymization gap** — `anonymize_inactive_members` is member-anchored; the 7 pre-member rejected/withdrawn rows have **no anonymization path** (LGPD minimization gap, latent). Needs its own remediation.
- **`finalize_decisions` silent-fail** — a committee-lead-without-`manage_platform` can submit "approved" decisions that roll back silently inside `approve_selection_application`, returning `success:true, approved:0`. Pre-existing; becomes relevant if the re-approve UI routes through `finalize_decisions`.
- **Candidate locale not stored** — selection emails render `pt` for everyone; consider `selection_applications.language text DEFAULT 'pt'`.
- **`selection_cycles.*_cutoff_formula` text drift** — advisory text columns disagree with the live PERT body; either sync or annotate as non-authoritative.

---

## 9. References

- Issue #902 · PR #903 (sub-gap 1) · ADR-0067 (Art. 20 human-in-the-loop) · ADR-0007 (`can()`) · ADR-0006 (persons/engagements) · ADR-0028 (cron-aware comms gate) · ADR-0012 (schema invariants) · ADR-0097 (RPC migration coverage).
- `docs/reference/V4_AUTHORITY_MODEL.md` · `.claude/rules/database.md` (V4 Authority audit; Track Q-C) · `feedback_apply_migration_creates_tracking_row`.
- `docs/specs/SPEC_D7_VEP_OFFER_REMINDER.md` (comms structural analog) · `memory/reference_vep_sync_terminal_flip_and_deadline_902.md` · `memory/selection_interview_invite_resend_runbook.md`.
- Grounding+review+verify workflow `wf_cc1ab601-977` (13 agents, 2026-06-26); live prod `ldrfrvwhxsmgaabwmaik`.
