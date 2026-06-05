# Tier 3 Strategic Review — `/council-review topic=212`

**Session:** p207 (2026-05-20)
**Issue:** [#212 — Initiative Collaboration Hub spec](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/212)
**PR under review:** [#214 (Draft)](https://github.com/VitorMRodovalho/ai-pm-research-hub/pull/214) — 6 docs / ~2700 lines on `agent/issue-212-research`
**Inputs:** Phase 1 (5 personas) + Phase 2 (5 Tier-2 specialists: product, security, data, legal, ux) already consolidated in `INITIATIVE_COLLABORATION_HUB_COUNCIL_SYNTHESIS.md`
**This document:** Tier 3 strategic (5 lenses, distinct from Phases 1-2) — c-level · startup · vc-angel · accountability · ai-engineer
**Output target:** PM (consultive — no code modified)

---

## 0. Verdict at a glance — 5/5 GO-WITH-AMENDMENTS

| Councillor | Verdict | Headline amendment |
|------------|---------|--------------------|
| c-level-advisor | GO-WITH-AMENDMENTS | Extract B5 (Whisper) as standalone P0; define M1 trigger criterion; Vassouras MOU letter of intent before 02-Jun |
| startup-advisor | GO-WITH-AMENDMENTS | Vassouras via manual runbook only (M4); B5 = P0 standalone this week; MOU template is highest-leverage asset |
| vc-angel-lens | GO-WITH-AMENDMENTS | Resequence: 20h Whisper + tactical FIRST; CPMAI signal-watch SECOND; #212 v1 only if Vassouras proves funnel |
| accountability-advisor | GO-WITH-AMENDMENTS | B5 remediation gates ADR-0094 ratification; add Termo de Participação + PMI-RJ courtesy notification; codify M1 governance prerequisites |
| ai-engineer | GO-WITH-AMENDMENTS | DROP trigger + `consent_voice_biometric_at` gate; `provider` column on `ai_processing_log`; document MCP secret hygiene |

**Convergence:** All 5 councillors independently identified the same top priority: **Whisper Art. 11 retroactive (B5) must be extracted from #212 and closed as a standalone critical-priority remediation BEFORE #212 ratifies or implements.**

**Empirical reality check (run live at p207 boot, 2026-05-20):**

```
total_screenings:        90    (uploaded/created since p197d)
transcribed:              0    (status='transcribed')
has_transcription_text:   1    (single row with text)
in_flight:                5    (status IN uploaded/transcribing)
distinct_applications:   18    (candidates touched)
video_suggestions:        1    (selection_evaluation_ai_suggestions)
video_completed:          1    (ai_processing_log)
video_failed:             2    (Whisper 429 quota blocks per p199-a smoke)
```

**Material implication:** The Whisper RETROACTIVE violation is real (legal-counsel correct on legal framing), but the **actual biometric data footprint is 1 row, not "months of mass processing"**. OpenAI Whisper quota 429 errors blocked the pipeline organically before scale. This **does not reduce urgency** of the migration block (the *intent* to process without Art. 11 consent is the violation, irrespective of OpenAI's quota), but it **dramatically reduces** the remediation scope: notification population is ~1 candidate, not 18+. Documentation duty applies regardless.

---

## 1. The five strategic lenses — distilled findings

### 1.1 — c-level-advisor (3-path optionality + sustainability)

**Path most advanced by spec:** Path A (Trentim/PMI institutional). Specifically because G4.1 (org-owned service account, no DWD) eliminates the single largest succession-risk of PM-personal-Google-account custody.

**Path most at risk:** Path A — but from B5 Whisper, not from #212 architecture. A live LGPD Art. 11 violation is incompatible with the institutional credibility Path A depends on. Whitepaper + LIM Detroit positioning both reference "responsible AI in PM" — a documented uncorrected violation makes that narrative adversarial to write.

**Capacity vs scope:** Cannot reconcile. 65-90h dev @ 1-2 sessions/wk = 6-9 weeks minimum. Vassouras T-13d. Synthesis M4 (manual runbook) is the only honest answer.

**M1 multi-hub:** Correct posture, but needs a written trigger criterion: "named operator + signed governance document." Without it, M1 defers infinitely or re-litigates every session.

**Sustainability ranking:** (1) Whisper remediation; (2) Vassouras tactical + MOU initiation; (3) #212 spec ratification (ADR rewrite + sub-issue spawn, NOT implementation).

### 1.2 — startup-advisor (GTM + community↔commercial)

**Naming:** "Initiative Collaboration Hub" reads as feature description, not platform-wedge. Real story = "engagement model that onboards any external actor into the same verified authority chain, LGPD-compliant by construction." Rename for external comms; keep internal title.

**CPMAI deferral:** Correct sequencing if and only if stub is active + named owner. Re-prioritize tripwire: (a) Vassouras demonstrates 15+ returning students, OR (b) a 2nd academic partner commits — whichever comes first. If neither by Q3 2026, CPMAI = vision without market.

**Vassouras strategic value:** Positioning (c) "learning lab" with hard caveat — it's an experiment, not a GTM signal yet. Build the runbook, run the event, observe what 30 students + academic coordinator actually do. The observation is the data; the architecture comes after.

**Multi-hub:** 80% distraction at current scale, but `organization_id` everywhere is correct insurance. GTM investment in chapter expansion = wait until PMI-CE/MG sends a named human + commits hours.

**Partnership posture:** Deliberate + limited. Vassouras first, full stop. No second partnership until Vassouras MOU executed AND one full engagement lifecycle completes without SQL workaround. ~September 2026 = potential 2nd academic partner; that's the GTM signal.

### 1.3 — vc-angel-lens (capital efficiency + moat)

**P1 engagement-driven architecture:** Forming, not yet defensible. Architecture is sound; **moat requires longitudinal data across N hubs** — which doesn't exist. MCP server (293 tools, claude.ai-verified) is the more differentiated surface today.

**IRR comparison — #212 v1 vs CPMAI v0:**
- 65-90h on #212 v1 = zero revenue, one event enabled
- 65-90h on CPMAI v0 (payment + cohort schema + enrollment) = first unit potential ARR. At R$1,500-3,000/participant × 20-person cohort = R$30k-60k gross/cycle. LTV/CAC ~3.5x → R$105k-210k LTV per cohort.
- **The IRR comparison is not close.** Only legitimate argument for #212 v1 first: forcing compliance posture NOW that CPMAI would need anyway. But only B1-B6 are truly prerequisite (~20-25h), not the full 65-90h.

**Whisper investor due-diligence impact:** Standard treatment = proactive disclosure + remediation timeline + 10-15% escrow holdback against milestone. **Concealment post-close** = R&W breach + clawback rights + (worst case) personal liability under LGPD Art. 52 §1. Pre-revenue platform ANPD fine cap effectively unbounded by 2% floor; investors price as $200k-500k risk-adjusted liability = 40-100% premium on a $500k pre-seed = material.

**Capital allocation ranking:**
- **B (Whisper + minimal Vassouras tactical, ~20h)** — recommended first, unconditional
- **C (defer #212 v1; 90h into CPMAI revenue infra)** — second, contingent on Vassouras → CPMAI signal
- **A (ship #212 v1 as specced)** — third; with 9 blockers resolved, real effort is 90-120h not 65-90h

### 1.4 — accountability-advisor (PMI governance + audit readiness)

**External-member `write_board_assigned` institutional risk:** MEDIUM-HIGH but mitigable with 2 governance gates:
- **Gate 1** — Termo de Participação individual (one-pager, 2-3h legal) signed at engagement acceptance. Acknowledges: (i) participation under Núcleo IA, not PMI chapter membership; (ii) board content confidential to initiative; (iii) no public attribution without written PM consent. Separate from full MOU.
- **Gate 2** — Courtesy notification to PMI-RJ chapter president BEFORE any of their board members onboarded. One email, archive it, one-week response window. Not approval-seeking — institutional courtesy that prevents future inter-chapter dispute.

**Whisper Art. 18 §IV / Art. 48 protocol:**
- Internal disclosure: complete (this council record). File standalone critical issue TODAY with date precision.
- External notification: per-individual (not generic notice), references Art. 18, includes mechanism to request deletion. Angeline drafts.
- Art. 48 ANPD trigger: **engage Angeline for written determination** — if she concludes notification not required, that opinion becomes the audit defense document; if required, 2-business-day clock starts from her determination.
- Audit trail (5 docs): issue ticket date · SQL affected-row count · Angeline written opinion · notification template + send log · deletion log per subject.

**Service account transition governance gates:**
1. Infrastructure Custody Record (1-page, who holds what, succession)
2. Rotation runbook BEFORE first key (not after)
3. `drive.file` scope + NO DWD confirmed in writing
4. PM decision record on Workspace identity scope (for PMI-GO/chapter governance audit trail)

All 4 = documentation tasks, 2-4h total, no legal review.

**M1 governance maturity stages:**
- Stage 1 (current): Single hub PMI-GO. ADR-0094 design intent doc. ✓
- Stage 2 (2nd hub): data isolation audit + per-org consent docs + MOU + PMI Brasil courtesy notification
- Stage 3 (3rd+): Platform Governance Committee (2-3 chapter presidents + PM, one-page charter)
- Stage 4 (federation 5+): formal PMI Latam governance submission

**Recommendation:** Write Stage 2 gate criteria into ADR-0094 as explicit "Multi-Hub Governance Prerequisites" section. 30 minutes effort.

**Budget/effort/sequencing of 5 LGPD docs for T-13d:**
1. **Termo de Participação Speaker** — MUST SHIP FIRST (Art. 11 biometric gate). Angeline 6-8h, 3-4 business days.
2. **Acordo de Cooperação Vassouras** — Before first student added. 4-6h drafting + back-and-forth with university.
3. **Aviso Privacidade Externos** — Before first external accepts engagement (Art. 9 collection-time requirement). 4-6h.
4. **Adendo Privacidade Principal (Whisper)** — Depends on Art. 48 determination. 2-3h.
5. **Política Retenção** — Parallel with G2 wave. 2-3h.

**Non-negotiable if scope compresses:** Whisper consent capture + Vassouras MOU. Everything else produces risk; these two produce immediate liability.

**Council process audit:** Calibrated correctly for architecture-level specs touching LGPD/multi-chapter. Should NOT be invoked at this depth for routine implementation sub-issues. **Codify in council README: Tier 3 invoked only for (a) LGPD sensitive data, (b) multi-chapter institutional decisions, (c) >50h-effort specs, (d) pre-prod audit-readiness checks.** Otherwise default to Tier 1 (platform-guardian + code-reviewer).

### 1.5 — ai-engineer (Whisper + MCP authorization + AI architecture)

**Whisper remediation — recommend Option B** (BLOCK + RETAIN past + Art. 18 deletion offer). Option A destroys audit evidence; Option C legally fragile (cannot legitimize past with future consent under Art. 11).

**Engineering execution sequence:**
1. `DROP TRIGGER trg_video_ai_analysis_on_upload ON public.pmi_video_screenings` (1-line migration)
2. Add `consent_voice_biometric_at` + `consent_voice_biometric_evidence text` columns on `selection_applications`
3. Update `analyze_application_video_async` gate: skip if `consent_voice_biometric_at IS NULL OR consent_voice_biometric_revoked_at IS NOT NULL`
4. Survey query result (run live at boot): **1 transcription row, 5 in-flight, 18 distinct candidates touched** — affected notification population ≤18, not 90+
5. Migration header inline-comments LGPD Art. 18 §IV basis + exact disable timestamp

**Consent architecture:** Column on `selection_applications` (fast gate, O(1), mirrors existing `consent_ai_analysis_at`) PLUS standalone `application_consent_log(application_id, consent_type, captured_at, evidence_text, revoked_at)` table (audit trail). Candidates are NOT `auth_engagements`, so `engagement_consent_log` (ADR-0094 G1.6) is wrong structural home for candidate-level consent.

**AI vs Google API queue:** Keep separate. Different retry semantics (Google = deterministic backoff; AI = quota + model availability + non-determinism). Add `provider` column to `ai_processing_log` (30-min migration, non-breaking) — separates "what" from "who," unlocks cost/quota attribution + future provider circuit-breakers without schema change.

**`view_pii` INTERSECTION rollout (Phase 2 S3):**
- Migrate `analyze_application_video` MCP tool to `_can_all(view_pii)` at v2.77 (low-volume tool, negligible perf impact)
- Audit other 12 view_pii tools individually — most are list/browse aggregate (UNION acceptable); biometric-derived tools = INTERSECTION
- Update `.claude/rules/mcp.md` with the rule

**Service account hygiene:**
- Vault: `google_service_account_key_<organization_id>` + `service_role_key` only
- AI provider keys (OpenAI, Anthropic, Google AI): **EF Secrets only** (`supabase secrets set`), never Vault. EF self-references Vault for `service_role_key` to dispatch; provider keys live in EF env. Document this in `.claude/rules/mcp.md` under new "Secret hygiene" section.

**Capacity allocation ranking from AI maturity lens:**
1. Whisper remediation (~20h) — closes one open hole + establishes `application_consent_log` primitive that ALL future AI features reuse
2. Antigravity/Gemini integration (~30h, parent #204) — extends proven `ai_processing_log` + `selection_evaluation_ai_suggestions` human-in-loop pattern
3. Drive/external-collab plumbing (65-90h) — zero AI maturity advancement; high operational value but does not move the needle

**North star:** every data-touching action consent-auditable; every AI output human-ratifiable; every provider call traceable to specific consent grant. Whisper remediation closes that hole.

---

## 2. Consolidated amendments — what changes in the spec

### 2.1 — Convergent across all 5 (unconditional)

**A1 — File Whisper Art. 11 standalone critical issue TODAY (this session).**
- File as separate from #212 (cross-cutting LGPD remediation, not collab-hub work).
- Block trigger via 1-line migration BEFORE any other code work this session.
- Survey query result documented in migration header (1 transcription + 5 in-flight + 18 distinct candidates).
- Angeline engaged for: (a) Art. 48 written determination; (b) Termo de Speaker draft; (c) Art. 18 §IV notification template.
- Documentation: timestamp of discovery (2026-05-20), affected row count, Angeline's written opinion, notification template, deletion log. 5-doc audit trail.

**A2 — Vassouras (02-Jun T-13d) executes via manual runbook (M4) ONLY.**
- NO #212 v1 code dependency for the event.
- BUG-212.A (#217) fix shipped this week (30-min migration).
- Vassouras MOU letter of intent initiated BEFORE 02-Jun (signing can follow; trail must exist).
- Termo de Participação one-pager (Gate 1) drafted by Angeline before any external onboarded.
- PMI-RJ chapter president courtesy notification email sent (Gate 2) before PMI-RJ board members onboarded.
- Service account provisioning (PM ops, 2-4h) + rotation runbook (1-page, BEFORE first key).

**A3 — ADR-0094 ratification gated on B5 issue filed + Phase 1 (block) migration applied.**
- Spec ratification cannot move from Draft → Proposed → Accepted while a live LGPD violation exists in production.
- After A1 ships: ADR-0094 rewrite per Phase 2 §9 (6 amendments) + 3 new Tier 3 amendments (below).

### 2.2 — Convergent across ≥3 councillors (high-priority new amendments to ADR-0094)

**B1 — Multi-Hub Governance Prerequisites section (accountability + c-level + startup).**
Add explicit ADR-0094 section codifying Stage 1-4 gates. Trigger for actual multi-hub IMPLEMENTATION investment = "named operator + signed governance document + per-org consent docs + data isolation audit." Without this, M1 is technical promise without institutional guardrails.

**B2 — Consent architecture for sensitive AI (ai-engineer).**
Document in ADR-0094:
- Candidate-level: `selection_applications.consent_voice_biometric_at` column + `application_consent_log` table
- Engagement-level: `engagement_consent_log` per G1.6 (already in spec)
- These are SEPARATE — candidates ≠ auth_engagements. Do not collapse.

**B3 — Service account + AI secret hygiene rule (ai-engineer + accountability).**
Document in `.claude/rules/mcp.md`:
- Vault holds: service-account keys (Google) + `service_role_key` only
- EF Secrets holds: AI provider API keys (OpenAI/Anthropic/Google AI)
- Rotation runbook written BEFORE first key provisioned
- 5-year retention on `google_api_call_log` (LGPD Art. 37)

### 2.3 — Sequencing call (vc-angel + startup convergent on signal-watch)

**C1 — CPMAI re-prioritization tripwire (formal).**
Spawn #212.b as active spec (not stub) when EITHER:
- 5+ inbound CPMAI expressions of interest within 30 days post-Vassouras, OR
- 2nd academic partner LOI signed (independent of Vassouras outcome)

If neither triggers by Q3 2026, document conclusion: "CPMAI hypothesis without market signal — defer or close."

**C2 — Vassouras post-event observation as architecture input.**
PM-led debrief 1-2 weeks after 02-Jun: what did the 30 students + academic coordinator actually use? Which capabilities mattered? Which were ignored? **Use that signal to scope G1/G2/G3 implementation effort — not the persona simulation.** Persona-based scoping has produced 65-90h v1; real-user observation may compress it materially.

---

## 3. Resequenced work order (P0 → P3)

### P0 — THIS WEEK (within ~5 business days), non-negotiable

| # | Item | Effort | Owner | Blocker for |
|---|------|--------|-------|-------------|
| 0.1 | File Whisper Art. 11 remediation issue (separate from #212) | 30m | PM | All other AI work |
| 0.2 | Apply `DROP TRIGGER trg_video_ai_analysis_on_upload` migration | 30m | PM/Claude | New transcription INSERTs |
| 0.3 | Add `consent_voice_biometric_at` column + gate in `analyze_application_video_async` | 2-3h | Claude | Re-enabling trigger |
| 0.4 | Engage Angeline: Art. 48 written determination + Art. 18 §IV notification template + Termo de Speaker draft | 3-5d legal | PM ↔ Angeline | Notifying affected candidate(s) |
| 0.5 | Document remediation audit chain (5 docs per Section 2.1 A1) | 1-2h | PM | ADR-0094 ratification |
| 0.6 | BUG-212.A welcome URL fix (#217) | 30m | PM/Claude | External notifications |

### P0 — BY VASSOURAS T-13d (02-Jun-2026)

| # | Item | Effort | Owner |
|---|------|--------|-------|
| 1.1 | Manual runbook for ~50-person Vassouras add (SQL + spreadsheet) | 2-3h | PM/Claude |
| 1.2 | Vassouras MOU letter of intent (drafted + initiated with Universidade) | 4-6h drafting + back-and-forth | PM ↔ Angeline ↔ Universidade counterpart |
| 1.3 | Termo de Participação one-pager (Gate 1 — individual external acceptance) | 2-3h | Angeline |
| 1.4 | PMI-RJ chapter president courtesy notification email (Gate 2) | 30m + 1-week response window | PM |
| 1.5 | Service account org-owned provisioning (PM ops) + rotation runbook | 2-4h ops + 1h doc | PM |
| 1.6 | Aviso Privacidade Externos (Art. 9 collection-time doc) | 4-6h | Angeline |

### P1 — POST-VASSOURAS, OBSERVE & DECIDE (~2-4 weeks after 02-Jun)

| # | Item | Trigger | Owner |
|---|------|---------|-------|
| 2.1 | PM-led Vassouras debrief: what worked, what didn't, what students/coordinator used | T+1w to T+2w | PM |
| 2.2 | Count CPMAI inbound expressions of interest (target: 5+ for tripwire) | 30 days post-event | PM |
| 2.3 | ADR-0094 rewrite per Phase 2 §9 + Tier 3 amendments (B1, B2, B3) | 4-6h | PM/Claude |
| 2.4 | Spawn revised sub-issues from `INITIATIVE_COLLABORATION_HUB_SUB_ISSUES.md` rewrite (only after debrief signals which scope) | 1-2h | PM |

### P2 — CONDITIONAL (only if Vassouras signal validates)

| # | Item | Trigger condition |
|---|------|-------------------|
| 3.1 | #212 v1 implementation (G1 internal-member path + G3 metadata UI subsuming #211 + G4 service account audit) | Vassouras debrief shows real ongoing use OR 2nd academic partner LOI |
| 3.2 | G2 engagement-Drive sync (with audience filter B2 fix + UNIQUE redesign S2 + `write_board_assigned` RLS B3) | #209 ships first OR coordinated launch |
| 3.3 | Política Retenção (parallel with G2) | G2 starts |
| 3.4 | Adendo Privacidade Principal (Whisper section) | After A1 ANPD determination settled |

### P3 — POST-V1 (long-tail)

| # | Item | Trigger condition |
|---|------|-------------------|
| 4.1 | #212.b CPMAI active spec (G6 alumni + G7.1 cohorts + G7.3 payment + G5 full speakers) | C1 tripwire fires (5+ expressions OR 2nd partner) |
| 4.2 | Multi-hub IMPL investment | 2nd named hub commits + governance doc signed (Stage 2 gates) |
| 4.3 | Gemini/Antigravity integration (#204 umbrella) | Independent — proven ai-suggestion pattern extends; needs `provider` column on `ai_processing_log` first |

---

## 4. Effort comparison — original v1 vs Tier-3 resequenced

| Bucket | Phase 2 original | Tier 3 resequenced | Delta |
|--------|------------------|--------------------|----|
| Whisper remediation | "separate critical issue" (~2-3h) | **P0 this week (~5-7h dev + 3-5d legal)** | + made explicit, expanded scope |
| Vassouras enablement | included in 65-90h v1 | **P0 manual runbook + governance docs (~12-15h dev + 8-12h legal)** | -50-60h dev (manual runbook), +governance docs |
| #212 v1 implementation | 65-90h dev + 18-26h legal | **P2 conditional, scope TBD post-debrief** | deferred, scope likely smaller |
| ADR ratification | post-PM-signoff | **P1, gated on Whisper close** | sequential, not parallel |
| TOTAL P0 (5 weeks to T-13d Vassouras) | unsolved | **~17-22h dev + 11-17h legal-ops** | dramatically smaller scope, achievable |
| TOTAL through Sept 2026 (P0 + P1 + P2 conditional) | 105-116h dev + 18-26h legal | **~50-80h dev + 20-30h legal (if P2 triggers)** | net reduction via observation-led scoping |

**Key insight:** The Phase 2 council reached a defensible v1 scope by reading documents. Tier 3 strategic reaches a smaller v1 scope by observing what users actually do. Both councils are correct for their level — Tier 3 forces "what is the real-world signal that justifies this scope?" before committing capacity.

---

## 5. Council process refinement (accountability finding)

### 5.1 — When to invoke Tier 3

Codify in `docs/council/README.md`:

> **Tier 3 (`/council-review [topic]`) is invoked ONLY for:**
> - (a) Specs touching LGPD sensitive data or Art. 11 biometric
> - (b) Multi-chapter / inter-institutional decisions affecting PMI relationships
> - (c) >50h-effort architectural work (ADRs spanning multiple primitives)
> - (d) Pre-prod audit-readiness checks before a wave ships
> - (e) Strategic milestones touching path optionality (Trentim/LIM/whitepaper)
>
> For implementation sub-issues spawned from a Tier 3 spec, default to Tier 1 (platform-guardian + code-reviewer at close). Tier 2 specialists optional per ADR-coverage triggers (security for auth changes, data-architect for migrations, etc.).

### 5.2 — Tier 3 panel composition (for #212-class specs)

Five lenses worked well for #212 because each surfaced distinct findings the others missed:

| Lens | Findings unique to this council member |
|------|----------------------------------------|
| c-level-advisor | M1 trigger criterion missing; Path A is path-most-advanced; sustainability sequencing |
| startup-advisor | Naming framing; Vassouras as experiment not signal; partnership posture deliberate+limited |
| vc-angel-lens | IRR math vs CPMAI; investor due-diligence exposure on Whisper; concrete capital allocation ranking |
| accountability-advisor | PMI-RJ courtesy notification gate; service account governance docs; M1 governance maturity stages; council process audit itself |
| ai-engineer | Trigger-level remediation execution; `provider` column; `_can_all(view_pii)` rollout; secret hygiene Vault vs EF Secrets |

**Recommendation for future Tier 3:** Maintain 5-lens panel for ADR-class decisions. Drop ai-engineer if no AI surface in scope; drop accountability if no LGPD/multi-chapter. Default panel = c-level + startup + vc-angel + 2 domain-triggered.

### 5.3 — Cost/benefit measurement

For #212:
- Council agent time: ~5-8h across all 11 outputs (Phase 1 + 2 + 3)
- PM synthesis time: ~12-16h
- **Findings caught early that would have caused incidents:** 3 high-severity (Whisper retroactive, Drive trigger audience leak, PM-attested mass-forgery)
- Estimated incident cost prevented: ANPD inquiry + R&W exposure + institutional credibility = **>>20h council overhead**

Council process is net positive for #212-class decisions. Continue for similar specs; calibrate down for routine work.

---

## 6. Five PM signoff items (Tier 3 specific, beyond Phase 2's 8)

To convert this synthesis into action:

1. **Approve filing Whisper Art. 11 remediation as standalone critical issue (separate from #212).** Action TODAY.
2. **Authorize trigger DROP migration TODAY (1-line).** Pre-commits the architecture decision; reversible if Angeline determination opens a different path.
3. **Authorize Vassouras to execute via manual runbook only (M4).** No #212 v1 code dependency on the event.
4. **Approve ADR-0094 ratification GATING: cannot move from Draft → Proposed until Whisper remediation Phase 1 is live.** Adds discipline to spec process.
5. **Approve 5-lens Tier 3 panel composition + invocation criteria for `docs/council/README.md`.** Codifies the process for future milestones.

---

## 7. Files referenced

- Phase 2 synthesis: `docs/architecture/INITIATIVE_COLLABORATION_HUB_COUNCIL_SYNTHESIS.md` (branch `agent/issue-212-research`)
- ADR draft: `docs/adr/ADR-0094-initiative-collaboration-hub-architecture.md` (branch `agent/issue-212-research`)
- Persona findings: `docs/architecture/INITIATIVE_COLLABORATION_HUB_PERSONA_FINDINGS.md`
- Whisper migration: `supabase/migrations/20260519041719_p197d_d1_video_ai_schema_trigger.sql`
- Whisper consent pattern (existing): `supabase/migrations/20260519035312_p197d_a_consent_ai_status_and_pdf_invalid_flag.sql`
- MCP rules (to extend): `.claude/rules/mcp.md`
- Council README (to extend with §5.1 above): `docs/council/README.md`

---

**End of Tier 3 strategic review.** Five councillors, five GO-WITH-AMENDMENTS, three convergent unconditional amendments (A1-A3), three high-priority new ADR amendments (B1-B3), two sequencing tripwires (C1-C2), and resequenced work order P0-P3.

The architecture in #212 is not wrong. The work order was inverted. Tier 3 strategic frame produced the resequencing.

Assisted-By: Claude (Anthropic)
