# Decision Pass — 2026-06-08 (G1/G2/G3, G15, G19 ratifications · G12 clock-start · #569-574 triage)

- **Date:** 2026-06-08
- **Forum:** PM async decision pass (opened post-#597 per the handoff directive to stop the polish-loop)
- **PM:** Vitor Maia Rodovalho · **PL/CTO synthesis:** Claude (main loop)
- **Grounding:** Workflow `wf_1b9774e5-9df` (10 grounded readers, all options carry live facts) + base re-ground (main `4c2d304c`, **61** open, invariants **0**, `/mcp` 308 + `/semantic` 4, platform 200).
- **Working agreement:** `working-agreement-decision-process-2026-06-07` (PL/CTO brings recommendation + embasamento; PM decides; record durably).

## Headline
Grounding showed **3 of the 4 nominal gates were already decided/shipped** — they needed **ratification (doc hygiene), not a decision**. One genuinely-live decision (**G12**) was approved. The new legal-ops cohort **#569-574** was triaged. PM chose **all PL/CTO recommendations**.

## G1 / G2 / G3 — Selection reliability → RATIFIED (shipped + live-verified)
- **Evidence:** #292 / #260 / #411 CLOSED; crons `selection-cutoff-pending-daily` + `selection-stuck-scheduled-rescue-daily` `last_status=succeeded` 2026-06-08 (live); ADR-0022 delivery-mode parity guarded by `adr-0022-delivery-mode.test.mjs`. G2 intent recorded (#347 body) + committee reseed live (#357, both evaluators `can_interview=true`).
- **Decision:** ratify all three as shipped. Residual = per-evaluator booking-URL routing, carried as **build** under #347→#348 (**not a gate**).

## G15 — Role model → RESOLVED = Option A
- Single-valued `operational_role` + lateral `designations[]`. Roberto Macêdo lives with `['chapter_liaison','ambassador','curador']`; `can_by_member(Roberto,'curate_content')=true` vs `write_board=false` (designation path grants curator authority). #245/#161/#192 CLOSED. Option B (multi-valued operational_role) **declined** — fights ADR-0007.
- **Decision:** ratify Option A. Canonical: `docs/reference/V4_AUTHORITY_MODEL.md` + ADR-0007.

## G19 — Connector strategy → RESOLVED = Option C
- **Options:** A = private/custom only; B = official store listing now; **C = private/custom + member self-add canonical, defer official listing behind an explicit trigger** (org→Team/Enterprise, measured consulting/community discovery need, or a client rejecting custom-for-lack-of-listing); `SPEC_280A` = pre-built submission checklist.
- **Rec + Decision:** **C**. Rationale: only Claude/OpenAI have store paths (Perplexity/xAI/Manus = custom-only → listing buys partial discovery, never removes the custom channel); PM on individual plan (org connectors need Team/Enterprise); member self-add works at $0; preserves all 3 strategic paths. **Unblocks the #280 `mcp`→`mcp/full` rename** (was G19-blocked only for lack of a stamped strategy). #234 stays open for 7-day continuity only.

## G12 — Angeline legal-ops clock → START APPROVED (execution = QA/QC FIRST)
- #334 has **0 comments** = external clock not started. #332 CLOSED → the interim Art.18 §IV notification was **already sent** to the affected candidate (o candidato afetado (#332), 2026-05-24) → Angeline's template is **retroactive/canonical, no time pressure**.
- **Decision:** approved to start the clock this pass.
- **PM refinement (2026-06-08, same session):** before sending to Angeline/Aaron, **QA/QC the team's first-layer governance revision** (`~/Downloads/nucleo-juridico-revisado/`) **against Parecer 01/2026** — *"não acreditar na versão final"*. The clock starts on the **validated** send (timestamp → #334).
- **⚠️ Correction recorded:** the platform-grounded G12 draft from `wf_1b9774e5-9df` got the **DPO framing wrong** (it asked to "designate a DPO"). PMI-GO **already has a DPO**: Ivan Lourenço (titular) + **Angeline (substituta)**, `dpo@pmigo.org.br`. Use the team's Gmail draft (id `19ea496bea8d47fc`) as the base, reconciled by the QA/QC. Do **not** send the platform draft as-is.

## Legal-ops cohort #569-574 → TRIAGED (ready-leaves first; self-contained eng in parallel)
| Issue | Self-contained build (no Angeline) | Gated on G12 | Effort |
|---|---|---|---|
| #569 OpenTimestamps (rec k) | full (pgcrypto+pg_cron+pg_net+R2 exist) | — | L |
| #570 image/voice consent (rec e) | mechanism (ALTER consent_records + RPCs) | go-live = clause text | M |
| #571 Material-change/version-pin backbone | full (legal text already ratified; chain exists) | — (notice copy only) | XL → 4 PRs |
| #572 portability/retention/LGPD self-service (rec g) | blocks A/B/C (Block C already live) | cross-processor (DPA/SCC) | XL → 3 |
| #573 EEA/UK conditional clauses | plumbing (`is_eu_resident`→`is_eea_or_uk` + variant log + metric) | clause text (GDPR/SCC/IDTA) | M |
| #574 DPO fiscalization + audit-log integrity (rec h) | Slice A (hash-chain — closes a real gap) | Slice B (DPO role) | L |
- **Decision:** ready-leaves first (#246→#247, #231, #403, #196, #375), then legal-ops **self-contained eng in parallel** with the Angeline async clock; G12-gated slices park behind G12. Do **not** hold the whole cohort to Wave 5.

## Execution refs
- Roadmap `docs/project-governance/BACKLOG_ROADMAP_2026-06.md`: gate rows G1/G2/G3/G12/G15/G19 annotated + §7 "first moves" callout updated.
- This decision doc.
- Issue comments: #334 (G12), #280 + #234 (G19). #569-574 per-issue triage comments → posted alongside the legal QA/QC session.
- Handoff: memory `handoff-2026-06-08-decision-pass-and-legal-qaqc`.
