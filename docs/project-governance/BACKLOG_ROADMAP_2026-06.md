# Backlog Roadmap — June 2026

**Date:** 2026-06-02
**Status:** Proposed for PM ratification (sequencing layer, not an implementation contract)
**Sources:**
- Per-issue analysis (summary, dependencies, business-decision gate, readiness, effort, recommended wave) from the deep multi-agent backlog analysis **`wf_388b2ff1`** (2026-06-02), raw result archived at `docs/drafts/backlog_roadmap_analysis_raw_wf_388b2ff1_2026-06-02.json`.
- Open-issue denominator and the out-of-cohort list **live-queried** via `gh issue list --state open` on **2026-06-02** (this is the grounded source of truth for counts below).
**Scope:** All currently-open GitHub issues. See the scope correction in §1 before reading the waves.

> **How to use this doc.** This is a *sequencing and decision-gate layer*, not a work order. It groups the
> backlog into coordinated waves, surfaces the cross-cutting business/legal decisions that gate each wave,
> and maps every open issue to a disposition so nothing is silently dropped. Dispatch narrow child tasks from
> a wave only when its decision gates are answered and its lane is clear. The authoritative per-issue dispatch
> state remains `docs/project-governance/ISSUE_REGISTRY.md`; this roadmap is the strategic overlay on top of it.

---

## 1. Executive summary

### 1.1 Scope correction (read first)

The originating analysis (`wf_388b2ff1`) deep-analyzed a **cohort of 60 issues**. A live `gh issue list --state open`
on 2026-06-02 returns **107 open issues**. All 60 analyzed issues are still open (none closed since the analysis),
so the cohort is intact — but **47 older open issues (#90–#194 range) were outside the analysis cohort.** They are
real, open, and several are **hard blockers of the analyzed 60** (see §1.3). This roadmap therefore covers **all 107**:
the 60 are placed into coordinated waves with full per-issue detail (Appendix A); the 47 are grouped into programs
with a disposition each, and the blockers among them are pulled forward (Appendix B). Coverage is reconciled to
60 + 47 = 107 in §6.

```
107 open issues (live, 2026-06-02)
├── 60  analyzed cohort (wf_388b2ff1) ........... Waves 0–5 + triage  → Appendix A
└── 47  out-of-cohort (older, #90–#194) ......... programs + triage   → Appendix B
        └── of which 7 are blockers of the 60 ... pulled forward      → §1.3
```

### 1.2 Portfolio at a glance (the 60 analyzed)

| Cluster | Program | Issues | n |
|---|---|---|---|
| A | Selection reliability (cycle 4) | 260, 292, 300, 347, 348, 356, 357, 365, 375, 411, 441, 447, 472 | 13 |
| B | Canonical metrics (ADR-0100) | 419, 420, 421, 424, 425 | 5 |
| C | Governance documents + legal/ANPD | 209, 301, 308, 311, 315, 333, 334, 335, 403, 455, 459 | 11 |
| D | RLS / data-integrity / live bugs | 201, 227, 231, 245, 246, 247, 440 | 7 |
| E | Initiative hub / calendar / events / UX | 204, 210, 211, 212, 217, 248, 249, 414, 415, 416 | 10 |
| F | MCP / AI / Gemini / connector | 206, 207, 208, 234, 280, 283 | 6 |
| G | Governance ops / bypass / misc | 195, 196, 200, 226, 233, 235, 374, 469 | 8 |

### 1.3 The plan in one paragraph

**Wave 0 (stop-the-line)** clears what blocks normal delivery: the CI drift that forces `--admin` merges (#226),
the bypass-threshold review that the CI drift caused (#374), live correctness/access bugs (#227 admin CV download,
#217 engagement-email 404, #248/#249 calendar render), the metrics-program closeout that everything downstream
reads (#419 metric 5 + #421 audit tracker), and ratification of the selection sprint plan (#292). **Wave 1** runs the
two active programs in parallel — selection reliability (A) and the metrics correctness defects (#420/#424) — plus
the governance decision-matrix gate (#315) that unblocks half of cluster C, the high-impact live RLS/UX bugs
(#245/#246/#247/#231), the calendar-recurrence hardening (#210/#414/#415), and the AI/connector decision gates
(#206/#208/#234/#283). **Wave 2** builds the layers those decisions unblock (governance evidence/curation grants,
collaboration-hub spec/UI, semantic gateway, analytics). **Waves 3–5** carry the deferred and externally-gated work
(alumni backfill #455, LGPD invariant U #333, legal-ops async #334). **Pulled forward from the 47:** the curatorship
primitives (#188/#190/#191/#192), counter-signature evidence (#181), semantic-layer roadmap (#166), and the
multi-role gate audit (#161) — because analyzed Wave 1/2 issues depend on them.

### 1.4 Critical-path tension to watch

- **Metrics → everything gamification.** #419 metric 5 (XP rank/pillar reorder) is the last core metric and is a
  **visible leaderboard reorder** (~46/49 positions move). It must be **flagged to PM before shipping** and sequenced
  carefully with `exec_tribe_dashboard` / `get_tribe_gamification`, which were touched by metric-4 work this week.
- **Governance decision matrix (#315) is a chokepoint.** Five issues (#310/#312/#314/#311/#403) cannot proceed
  until the 7-axis matrix is ratified. It is small effort (S) but high leverage — do it early in Wave 1.
- **Legal-ops (#334) is externally async** (Angeline, ~3–5 business days/cycle) and gates #332/#333. Start the
  contact clock in Wave 1 even though the engineering lands in Wave 4/5.
- **Selection has live candidates.** Cycle-4 corrections corr 1–4 are merged (#472, PRs #473–#476) and corr-2 worker
  is deployed; the candidate-facing communication policy (#260) and dual-interviewer intent (#347) are *decision*
  gates, not code gates — they block reliable comms for people currently in the funnel.

---

## 2. Cross-cutting business / legal decision gates

These are the decisions that gate waves. Effort on the issues is mostly small; the latency is in **getting the
decision made**. Resolve the Wave-0/Wave-1 gates first — they unblock the largest fan-out. "Ratified" gates are
recorded for traceability; the rest are **OPEN** and owned as noted.

| # | Decision gate | Owner | Blocks | Needed by |
|---|---|---|---|---|
| **G1** | Selection notification routing policy: which `selection_*` types are transactional (candidate-facing) vs digest vs admin; do candidate-facing emails bypass `suppress_all`? | PM | #260, #348, #411 | Wave 1 |
| **G2** | Dual-interviewer intent — is Vitor+Fabricio per researcher event intentional or accidental? Determines booking-URL routing schema (per-evaluator pool vs committee link) | PM + GP | #347 step 2, #357, #411 | Wave 1 |
| **G3** | `selection_cutoff_approved` trigger + auto-dispatch policy (above-target only; 50/day cutoff cap, 20/day rescue) | PM + Foundation | #260, #348, #411 | Wave 1 |
| **G4** | VEP re-import status freeze (do not rebind advanced apps to `submitted`) | Foundation | #472 B2 | **Shipped** (corr-2, worker `ed843957`) — confirm & close |
| **G5** | Calendar↔`selection_interviews` reconciliation (sync nucleoia@pmigo + evaluator calendars) | Foundation + Integration | #472 B1 | Wave 0/1 (corr-1 webhook mirror pending) |
| **G6** | ADR-0100 canonical metric definitions + participant-only member axis (`status='active' AND role<>'observer' AND kind<>'observer'`) | PM | #419, #420, #424, #425 | **Ratified** 2026-05-28 / 05-31 / 06-01 |
| **G7** | M5 XP visible leaderboard reorder (~46/49 move) — approve before shipping | PM | #419 metric 5 | Wave 0 (flag first) |
| **G8** | Champions award path: widen `admin.gamification` grant to `tribe_leader` **or** ship `/champion/award` page; pick ONE canonical champion-XP source | PM + Backend | #424 | Wave 1 |
| **G9** | Attendance combined-% visibility — restrict per-member %, or keep visible to all authenticated members? | PM + Privacy | #421, #425 | Wave 2 |
| **G10** | Governance documents **decision matrix** (7 axes: doc_type, visibility_class, status, acknowledgement mode, template/signed relationship, version-dependency graph, corpus backfill) + Frontiers Editorial Guide type/gate/visibility | PM | #310, #312, #314, #311, #403, #315 | Wave 1 (chokepoint) |
| **G11** | Evidence-bundle source: function/period from V4 engagements/history (not `operational_role` cache); bilingual at template level | PM + Eng | #308, #311 | Wave 1/2 |
| **G12** | ANPD Art. 48 §1 pre-disclosure; Art. 18 §IV notification template; DPO appointment stance; Adendo Privacidade Principal | PM → Angeline (external) | #334, #332 | Start clock Wave 1; lands Wave 5 |
| **G13** | Drive permission revocation: human approval gate (no auto-revocation), mirrors `admin_reactivate_member` | Security / DPO | #209 | Wave 1 |
| **G14** | Invariant U sequencing: C2 #332 before C3 #333, or C3 first with 1-row allowlist | PM | #333 | Wave 4 |
| **G15** | Role model: is `operational_role` single-valued (lateral designations) or should curator + ponto focal coexist? | Product / PM | #245, #161, #192 | Wave 1 |
| **G16** | Assignee model canonical: keep `assignee_id` (sync picker) or migrate to `board_item_assignments` junction | Product | #440 | Triage |
| **G17** | Test infra: adopt explicit try/finally cleanup vs rely on `Prefer: tx=rollback` for SECDEF rows | QA / CI | #231 | Wave 1 |
| **G18** | AI strategy: Gemini 3.5 Flash go/no-go (tri-model with Gemini 2.5 Flash + Sonnet 4.6) | PM | #204, #206, #207 | Wave 1 |
| **G19** | Connector strategy: private/custom vs official store listings (Claude/OpenAI/Perplexity/xAI) | PM + DevOps | #234, #280, #283 | Wave 1 |
| **G20** | YouTube ingestion: validate actual member use of `knowledge_search_text` before building | PM | #207 | Wave 2 |
| **G21** | Meet-transcripts privacy gate UX (file-by-file process/skip/private; LGPD logic for candidate mentions) | GP + PM | #208 | Wave 1 |
| **G22** | Canonical weekly digest path: RPC `get_weekly_member_digest` vs Edge Function `send-notification-digest` | PM | #195 | Wave 1 |
| **G23** | External member identity model (partner_contact vs lightweight identity) + Drive sync trigger on engagement lifecycle | PM + architect (ADR) | #212, #211 | Wave 2 |
| **G24** | Google Calendar sync conflict resolution (GCal wins phase 1; multi-tenant deferred) | Architect (ADR) | #416 | Triage |
| **G25** | CI drift recovery strategy: (A) wait PR#215 merge + capture migration, (B) drop orphan functions, (C) allowlist | Tech Lead / PM | #226 | **Wave 0** |
| **G26** | Bypass W22 legitimacy review (17 events > 2 threshold) against `bypass-protocol.md` | PM | #374 | **Wave 0** |
| **G27** | Canonical analytics sources + ROI attribution window + quality criteria spec | PM | #233 | Triage |

---

## 3. Coordinated waves

Each wave lists its goal, the issues (with cluster tag and effort), the decision gates it needs answered, and the
exit/quality gates that must hold before the wave is considered done. Effort: **S**/**M**/**L**/**XL**.

### Wave 0 — Stop-the-line

**Goal:** Restore a clean delivery baseline (CI green, bypass discipline) and clear live correctness/access defects
and the metrics closeout that downstream surfaces read.

| Issue | Cl | Eff | What | Gate |
|---|---|---|---|---|
| #226 | G | L | Clear 3 CI validate fails (orphan fns, SECDEF/REVOKE drift, 20+ body-hash) that force `--admin` merges | **G25** |
| #374 | G | S | PM review of W22 bypass count (17 > 2) per `bypass-protocol.md`; feed v2 audit (#235) | **G26** |
| #227 | D | S | RLS policy passes `auth.uid()` to `can()` (expects `persons.id`) → all admin CV downloads 400 | ADR-0007 (Option B `can_by_auth_uid` SECDEF helper) |
| #217 | E | S | `_enqueue_engagement_welcome` hardcodes `/iniciativas/` → all engagement emails 404 | none |
| #248 | E | S | Calendar day "19" renders struck-through/cancelled | none |
| #249 | E | S | T4 meeting shows wrong day-of-week (timezone/BYDAY) — verify with Fernando first | none (verify) |
| #419 | B | (metric 5) | Complete the last core metric: XP rank/pillar cycle-mode ordering + deterministic tiebreak | **G6 ratified; G7 flag-first** |
| #421 | B | — | Audit tracker — closes via #419 + #420 completion + G9 product call | depends on #419/#420 |
| #292 | A | S | Ratify the P0 Selection Reliability Sprint sequence; answer G1/G2/G3 | **G1, G2, G3** |
| #472 | A | (corr-5) | Selection pipeline: corr 1–4 merged; remaining corr-5 (consistency cron + retire `selection_topic_views`) + corr-1 webhook mirror (`/api/calendar-webhook` primary+alternate, `interviewer_emails` via `member_emails`) | **G5** |

**Exit gate:** CI `validate` green without `--admin`; bypass count back under threshold; no live 4xx on admin CV /
engagement email; #419 metric dictionary complete (metrics 1–8); selection sprint sequence ratified.

> Note on #419/#421/#472: these are XL/umbrella items whose *remaining* slice is small. They sit in Wave 0 because the
> rest of the gamification surfaces (B cluster) and selection comms (A cluster) read their output. Treat the listed
> remaining slice as the Wave-0 deliverable, not the whole epic.

### Wave 1 — Active programs + high-impact unblocks

**Goal:** Run the two live programs (selection reliability, metrics correctness) to completion; open the governance
decision-matrix chokepoint; fix the high-impact live RLS/UX bugs; harden calendar recurrence; and make the AI /
connector decisions so Wave 2 can build.

**A — Selection reliability** (depends on G1/G2/G3 from Wave 0):
- #260 (L) communications fix — transactional vs digest routing + safe replay · #300 (L) external_reviewer onboarding (triage HIGH gaps 1–4 first) · #347 (M) booking routing policy + calendar registry · #348 (M) per-evaluator booking URL roadmap · #356 (S) admin UI for `interview_booking_url` · #357 (S) cycle-4 committee reseed · #365 (S) objective-PERT column shows composite not objective · #375 (S) fix cron validation credential path · #411 (L) interview-invite lifecycle UI + crons.

**B — Metrics correctness:**
- #420 (S) four discrete defects: D14 PT/EN dropout-token fork, D6 `present=true` vs `id IS NOT NULL` (~4.5% overstate), D12 absent-rows in attendee_count, D10 hardcoded cycle default · #424 (M) champions award path + single canonical XP source (**G8**).

**C — Governance foundation gate:**
- #315 (S, **G10 chokepoint**) decision matrix — do early · #403 (S) fix `confirm_manual_version` + `link_attachment_to_governance` (missing `organization_id`/`visibility_class`/`acknowledgement_mode`), scoped by #315 · #209 (L) Drive revocation cascade on offboarding (**G13**) · #308 (L) curator evidence bundles (**G11**, planning).

**D — Live RLS / data-integrity bugs:**
- #245 (M) curator + ponto-focal dual-authority blocks `/admin/curatorship` (**G15**) · #246 (S) `/attendance` not refreshing in realtime · #247 (S) Jefferson absent-mark audit (depends #246 diagnosis) · #231 (S) tx=rollback leaks synth rows → false invariant violations (**G17**).

**E — Calendar recurrence hardening:**
- #210 (M) recurrence attendee cleanup (unblocked — #205 closed) · #414 (S) parametrized recurrence interval (weekly/biweekly/monthly) · #415 (M) recurrence-stockout cron · #204 (XL) Gemini/Drive/Calendar umbrella — triage + start G18.

**F — AI / connector decisions:**
- #206 (M) Gemini 3.5 Flash pilot (**G18**) · #208 (M) Meet transcripts → notes (**G21**) · #234 (M) connector OAuth refresh stability + listing eval (**G19**) · #283 (S) connector store readiness matrix (**G19**).

**G — Governance ops:**
- #195 (S) ratify canonical digest path (**G22**) · #196 (S) refresh PERMISSIONS_MATRIX + SITE_MAP stale counts.

**Pulled forward from the 47 (Wave-1 prerequisites):** #161 (multi-role gate audit → #245), #181 (counter-signature
evidence → #308), #166 (semantic-layer roadmap → #311), and the curation primitives #188/#190/#191/#192 (→ #201/#245/#301).

**Exit gate:** selection candidate-comms reliable end-to-end; metric defects fixed and surfaces converged; #315 matrix
ratified and #403 patched; live RLS/UX bugs closed; recurrence series self-healing; AI/connector go/no-go decisions
recorded as ADRs.

### Wave 2 — Layers unblocked by Wave-1 decisions

**Goal:** Build the structures the Wave-1 decisions unblock.

- **A:** #441 (M) VEP `service_history` stall + missing `pmi_chapter_memberships` table · #447 (S) `get_my_application_status` alternate-email self-view.
- **B:** #425 (M) tribe gamification → per-member coaching cockpit (folds canonical metrics from #419; **G9**).
- **C:** #301 (M) temporary Drive grants for submitted curation artifacts · #311 (L) generic evidence bundles all roles (after #308 design; **G11**) · #459 (S) MCP read of governance document body.
- **D:** #201 (M) curation review-modal artifact links + source context (after curation primitives).
- **E:** #211 (M) initiative metadata UI (after #212 spec) · #212 (L) collaboration-hub spec (**G23**).
- **F:** #207 (L) YouTube ingestion (**G20**, after #206 go) · #280 (L) semantic MCP gateway (after #234/#283).
- **G:** #200 (M) Cloudflare traffic analytics tab · #235 (S) bypass-audit v2 refinement.

**Exit gate:** governance evidence/curation surfaces consistent; collaboration-hub spec ratified with ADR; semantic
gateway design approved; analytics tab live.

### Wave 3 — Deferred operational

- **C:** #455 (M) alumni certificate backfill (17 legacy alumni) — needs the MCP emitter refactor (`issue_alumni_certificate(member_id)`, cycle int, `get_member_trail`); depends on #449/#451 offboarding fixes.

### Wave 4 — LGPD invariant (blocked)

- **C:** #333 (S) invariant U (voice-biometric consent enforcement) — blocked on **G14** sequencing + #332.

### Wave 5 — Legal-ops async (externally gated)

- **C:** #334 (S) Angeline legal-ops chain (ANPD Art. 48 / notification template / DPO / Adendo) — **G12**, external. Start the contact clock in Wave 1.

### Backlog / triage (analyzed cohort)

- **C:** #335 (S) author ADR-0094 (after C1/C2/C3 close; council ratification).
- **D:** #440 (M) board assignee-model divergence — needs **G16**.
- **E:** #416 (L) bidirectional Google Calendar sync — needs **G24** + OAuth/ADR.
- **G:** #233 (L) canonical analytics rebuild — needs **G27** spec · #469 (S) W23 bypass audit (clean) — close once discipline confirmed.

---

## 4. Dependency map (cross-cluster + cross-cohort)

Edges that cross cluster or cohort boundaries (intra-cluster sequencing is in §3 and the analysis JSON):

**Within the 60:**
- #419 → #420, #421, #424, #425 (canonical metric defs gate all gamification surfaces).
- #420 → #421 (remaining Bucket-A defects complete the audit remediation).
- #315 → #310, #312, #314, #311, #403 (governance decision matrix chokepoint).
- #308 → #311 (evidence-bundle design before generic model).
- #347 → #348 → #356, #357, #411 (booking routing spec → impl chain).
- #260 → #348, #411 ; #472 → #260, #411 (selection comms + pipeline state).
- #246 → #247 (realtime diagnosis before absent-mark root cause).
- #234 + #283 → #280 (connector readiness before gateway design).
- #206 → #207 (Gemini go/no-go before YouTube fallback route).
- #211 ↔ #212 (UI scoped by hub spec).

**From the 47 into the 60 (pulled forward — see Appendix B):**
- #190 (curation_queue_state semantic layer) → #201, #301, #308.
- #188 (MCP curator tools) → #201.
- #161 (multi-role gate audit) → #245.
- #191 (legacy curation APIs) , #192 (one-review-per-curator) → #245.
- #181 (counter-signature/certificate evidence) → #308, #311.
- #166 (semantic-layer roadmap) → #311.
- #205 (member_resolve_email) → #210 — **already CLOSED**, #210 unblocked.

---

## 5. Quality gates (apply to every wave)

Carried from `CLAUDE.md` + project rules, restated so the roadmap is self-contained:

1. **Grounding** — every count/%/metric in a PR, SPEC, or commit must come from a live tool result in that turn; never recite from memory.
2. **GC-097 pre-commit** — FK constraints, `auth.uid()` vs `members.id`, column-name/array-type checks for any SQL/RPC touch.
3. **DDL via `apply_migration`** (never `execute_sql`); sync local migration file + `migration repair` + `NOTIFY pgrst`.
4. **RPC signature changes** — DROP+CREATE (not CREATE OR REPLACE) on type/arity change; check overloads.
5. **i18n parity** — every new key in all 3 dictionaries; PT page ⇒ /en/ + /es/ redirects.
6. **LGPD/RLS** — new tables RLS-enabled; no anon access to PII; new public views REVOKE FROM anon (`pg_default_acl` trap).
7. **Build + test** — `npx astro build` 0 new errors; `npm test` 0 failures before commit.
8. **Bypass discipline** — `bypass-protocol.md` (≤2 `--admin`/7-day window); document each bypass.
9. **Council review** — Tier-1 (platform-guardian + code-reviewer) on structural changes; Tier-2 domain agents per cluster.
10. **No silent caps** — if a wave bounds coverage, say what was deferred (this doc is the ledger).

---

## 6. "Nothing left behind" — coverage ledger

**107 open issues (live, 2026-06-02) = 60 analyzed + 47 out-of-cohort.** Every issue appears exactly once below.

### Appendix A — the 60 analyzed cohort → wave/disposition

| Issue | Cl | Title (abbrev.) | Readiness | Eff | Wave |
|---|---|---|---|---|---|
| 292 | A | P0 Selection Reliability Sprint (plan) | ready | S | **0** |
| 419 | B | ADR-0100 canonical metrics (metric 5 XP pending) | blocked→active | XL | **0** (metric 5) |
| 421 | B | Cross-surface disparity audit tracker | blocked | XL | **0** (closes via 419/420) |
| 227 | D | RLS `can(auth.uid())` → admin CV download 400 | ready | S | **0** |
| 217 | E | engagement welcome email `/iniciativas/` 404 | ready | S | **0** |
| 248 | E | calendar day "19" strikethrough | ready | S | **0** |
| 249 | E | T4 wrong day-of-week (verify Fernando) | needs-triage | S | **0** |
| 226 | G | clean 3 CI drift fails (force `--admin`) | needs-decision | L | **0** |
| 374 | G | bypass W22 17 > 2 — PM review | needs-decision | S | **0** |
| 472 | A | off-platform interviews ≠ selection_interviews (corr-5 + webhook left) | needs-decision | XL | **0** (corr-5/webhook) |
| 260 | A | selection notifications stuck in digest path | needs-decision | L | **1** |
| 300 | A | external_reviewer onboarding refactor (10 gaps) | needs-triage | L | **1** |
| 347 | A | booking routing policy + calendar registry | ready | M | **1** |
| 348 | A | per-evaluator booking URL roadmap | ready | M | **1** |
| 356 | A | admin UI edit `interview_booking_url` | ready | S | **1** |
| 357 | A | cycle-4 committee reseed (Vitor+Fabricio) | ready | S | **1** |
| 365 | A | objective PERT column shows composite | ready | S | **1** |
| 375 | A | cron validation credential path | needs-decision | S | **1** |
| 411 | A | interview-invite lifecycle UI + crons | ready | L | **1** |
| 420 | B | Bucket-A defects (D14/D6/D12/D10) | ready | S | **1** |
| 424 | B | champions award path + single XP source | needs-decision | M | **1** |
| 209 | C | Drive revocation cascade on offboarding | ready | L | **1** |
| 308 | C | curator evidence bundles (planning) | needs-decision | L | **1** |
| 315 | C | governance docs decision matrix (chokepoint) | needs-decision | S | **1** |
| 403 | C | fix manual_version + link_attachment RPCs | blocked (315) | S | **1** |
| 231 | D | tx=rollback leaks synth rows (false invariants) | needs-decision | S | **1** |
| 245 | D | curator + ponto-focal blocks /admin/curatorship | blocked | M | **1** |
| 246 | D | /attendance no realtime refresh | needs-triage | S | **1** |
| 247 | D | Jefferson absent-mark audit | blocked (246) | S | **1** |
| 204 | E | Gemini + Drive/Calendar umbrella | needs-triage | XL | **1** |
| 210 | E | calendar recurrence attendee cleanup | blocked→ready | M | **1** |
| 414 | E | parametrized recurrence interval | ready | S | **1** |
| 415 | E | recurrence-stockout cron | ready | M | **1** |
| 206 | F | Gemini 3.5 Flash pilot | ready | M | **1** |
| 208 | F | Meet transcripts → notes pipeline | needs-decision | M | **1** |
| 234 | F | connector OAuth refresh + listing eval | needs-decision | M | **1** |
| 283 | F | connector store readiness matrix | needs-decision | S | **1** |
| 195 | G | ratify canonical weekly digest path | needs-decision | S | **1** |
| 196 | G | refresh PERMISSIONS_MATRIX + SITE_MAP | ready | S | **1** |
| 441 | A | VEP service_history stall + missing chapter table | needs-triage | M | **2** |
| 447 | A | get_my_application_status alternate-email self-view | ready | S | **2** |
| 425 | B | tribe gamification → coaching cockpit | blocked | M | **2** |
| 301 | C | temporary Drive grants for curation artifacts | ready | M | **2** |
| 311 | C | generic evidence bundles all roles | needs-decision | L | **2** |
| 459 | C | MCP read governance document body | needs-triage | S | **2** |
| 201 | D | curation modal artifact links + context | needs-triage | M | **2** |
| 211 | E | initiative metadata UI | needs-decision | M | **2** |
| 212 | E | collaboration-hub spec | needs-decision | L | **2** |
| 207 | F | YouTube ingestion pipeline | needs-decision | L | **2** |
| 280 | F | semantic MCP gateway | blocked | L | **2** |
| 200 | G | Cloudflare traffic analytics tab | ready | M | **2** |
| 235 | G | bypass-audit v2 refinement | ready | S | **2** |
| 455 | C | alumni certificate backfill (17 legacy) | needs-triage | M | **3** |
| 333 | C | invariant U voice-biometric consent | blocked | S | **4** |
| 334 | C | Angeline legal-ops chain (ANPD/DPO/Adendo) | blocked | S | **5** |
| 335 | C | author ADR-0094 collaboration hub | blocked | S | triage |
| 440 | D | board assignee-model divergence | needs-decision | M | triage |
| 416 | E | bidirectional Google Calendar sync | needs-decision | L | triage |
| 233 | G | canonical analytics rebuild | blocked | L | triage |
| 469 | G | W23 bypass audit (clean) | ready | S | triage (close) |

*(60 rows.)*

### Appendix B — the 47 out-of-cohort open issues → program / disposition

Not deep-analyzed by `wf_388b2ff1`. Grouped here by coarse program from title + labels. **⏫ = pulled forward as a
blocker of an analyzed issue (§4).** These need their own triage pass; the dispositions below are the recommended
landing, not a per-issue analysis.

**Curatorship program (10):** #185 align queue RPC gates w/ V4 `curate_content` · #186 broadcast submissions to committee · #187 replace V3 designation filter in reviewer picker · ⏫ #188 curator-native queue/review MCP tools (→#201) · #189 align card pipeline visual w/ curation_status · ⏫ #190 create `curation_queue_state` semantic layer (→#201/#301/#308) · ⏫ #191 reconcile legacy curation APIs (→#245) · ⏫ #192 enforce one review per curator (→#245) · #193 clean phantom FSM states + dead auto-publish trigger · #194 contract tests for p197 review flow.
→ **Disposition:** coherent program; run the 4 ⏫ blockers as Wave-1/2 prerequisites, fold the rest into a Curatorship hardening track adjacent to cluster D #201/#245.

**Volunteer lifecycle & agreements (11):** #159 p201 parallel-agent operating model · #160 Herlon study_group_owner authority · #168 triage WhatsApp action intake · #169 João Coelho event 02 Jun · #171 Ana Carla cannot read governance doc (access bug, HIGH) · #173 Rogério Peixoto reintegration as observer T07 · #177 issue agreements for special engagement kinds · #180 approved volunteers enter V4 graph · ⏫ #181 persist counter-signature + agreement evidence (→#308/#311) · #182 map agreement notifications/renewals · #183 canonical lifecycle MCP tools.
→ **Disposition:** Volunteer-lifecycle track; #181 ⏫ Wave-1 prerequisite; #171 access bug → triage near Wave-0/1; rest sequence after selection (A) stabilizes.

**Infra / MCP / security ops (5):** #155 supabase CLI v2.100.0 fork-bomb (infra, HIGH) · #162 293-tool contract matrix refresh · #163 Cloudflare BIC blocks MCP OAuth bootstrap (security, HIGH) · #164 restore local Supabase QA stack · #170 corrupted meeting notes via MCP (data-integrity, HIGH).
→ **Disposition:** triage #155/#163/#170 for Wave-0/1 (operational/security risk); #162/#164 are tooling-debt, Wave-2.

**Calendar / events / attendance reconcile (7):** #92 Núcleo↔GCal/Outlook integration (overlaps #416/#210) · #104 cancel-meeting discoverability + stale-events cron (overlaps #157/#248/#249) · #105 "minhas reuniões" widget · #107 attendance_rate denominator cohort (overlaps #419/#420!) · #156 /attendance vs events cohort divergence (overlaps #246) · #157 cancelled events show as 'absent' (overlaps #248) · #172 webinar calendar + Sympla lead time.
→ **Disposition:** **reconcile into cluster E (Wave 1) and B-metrics** — #107 with #419/#420, #156/#157 with #246/#248, #92 with #416 — to avoid duplicate work. Do not implement independently.

**Governance docs / semantic / permissions (3):** ⏫ #161 audit sensitive UI gates vs V4 `canFor` (→#245) · #165 governance + release backfill p40–p201 (docs) · ⏫ #166 semantic-layer roadmap for facts/dimensions/snapshots (→#311).
→ **Disposition:** #161 ⏫ Wave-1 prerequisite; #166 ⏫ feeds #311 (Wave 2); #165 docs triage (pairs with #196).

**Chapter / partnerships / strategic features (8):** #90 IN tracking (10 chapters + MOU + MCP) · #93 APM/WhatsApp-MCP/AI-briefing OSS analysis · #95 echo-chamber/originality detection for curation · #96 Newsletter Frontiers launch (HIGH; relates to C Frontiers gate) · #97 external speaker lifecycle (LATAM LIM 2026) · #106 chapter-facing dashboard for Diretores de Voluntariado · #110 Drive comms repository · #132 chapter shared resources (#89.5 split).
→ **Disposition:** strategic triage — lower operational urgency; #96/#97 relate to the Frontiers/LATAM governance gates (cluster C), surface in that conversation; rest are roadmap-optionality features.

**Misc / smoke / ops-backfill (3):** #100 PDF smoke for public_members view · #108 backfill `tribes.meeting_link` (8 Meet links, blocked on PM info) · #109 backfill items 1+11 — collect leader info (PM action).
→ **Disposition:** triage; #108/#109 are PM-data-collection-gated, not engineering-gated.

### §6 coverage check

```
Appendix A:  60  (analyzed cohort, each mapped to a wave/disposition)
Appendix B:  47  (10 curatorship + 11 lifecycle + 5 infra/MCP + 7 calendar + 3 gov-docs + 8 strategic + 3 misc)
             ───
Total:      107  ≡ live `gh issue list --state open` count (2026-06-02)  ✓
Pulled forward from B → A waves: #161, #166, #181, #188, #190, #191, #192  (7)
```

---

## 7. Recommended first moves (next session)

1. **Answer the Wave-0/Wave-1 decision gates that fan out the most:** G25 (#226 CI strategy), G26 (#374 bypass review),
   G10 (#315 governance matrix), G1/G2/G3 (selection comms + dual-interviewer + auto-dispatch), G7 (#419 XP reorder approval).
2. **Ship the ready Wave-0 bugs** (#227, #217, #248, #249) — no decisions needed, immediate trust wins.
3. **Open a triage pass on the 47** (Appendix B) — at minimum confirm the 7 ⏫ blockers and the calendar/attendance
   reconciliation overlaps before duplicating work in cluster E.
4. **Start the #334 legal-ops clock** even though it lands in Wave 5 — external latency dominates.
```
