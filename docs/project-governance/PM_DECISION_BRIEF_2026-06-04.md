# PM Decision Brief — 2026-06-04

> **Purpose:** the pending decisions that gate forward work, each as **scenario → options → recommendation + rationale → what it unblocks**, so the PM can decide fast (incl. async) without reading code.
> **Grounding:** every number here was produced by a live query/tool call on **2026-06-04** (cycle `cycle_3`, started 2026-03-01). Re-ground before acting if more than a few days pass (SEDIMENT-244.A: readiness tags read issue bodies, not live state).
> **State at write time:** main `e7122e94`; #494 Part A shipped+merged+**deployed** (platform `f74325db`, smoke 200/200) — pending only the 30-sec UI verify to close.

---

## D1 — #419 **M5: XP leaderboard rank fix** (gate G7) — *go / no-go on a visible reorder*

### The situation (live-grounded)
The leaderboard is **already wrong**, not "about to change." `get_member_cycle_xp` **displays** each member's *cycle* XP (points since 2026-03-01) but computes their **rank by *lifetime* XP** (`ROW_NUMBER() OVER (ORDER BY SUM(points) DESC)`, no cycle filter, no tiebreak). So a member can show "425 cycle XP, rank #14" where #14 reflects their all-time total, not the 425. M5 fixes the rank to match the displayed cycle XP (+ deterministic `member_id` tiebreak, + window read from `cycles` instead of a hardcoded `'2026-01-01'`).

**Live reorder magnitude (queried 2026-06-04):** of the **60 members with any XP**, **59 (98%)** land at a different rank position once ranked on cycle XP; **9** have zero cycle XP. (The 2026-05-31 note "46/49" was the opted-in *pooled* subset — same story: a near-total reshuffle.) This is why it's flagged FLAG-PM-FIRST: it's a **correctness fix that looks like a leaderboard earthquake** to members.

### Options
| Option | What happens | Risk |
|---|---|---|
| **A. Ship with a member-facing note (recommended)** | Correct the rank; publish a short "we fixed cycle-XP ranking — positions now reflect this cycle's activity" notice. | Low technical (same-sig RPC + tests); **social**: people who "dropped" may ask why. The note absorbs it. |
| **B. Ship silently** | Correct the rank, no announcement. | Same fix; higher chance of confused DMs ("why did I drop 10 spots?") with no framing. |
| **C. Defer to the next cycle boundary** | Hold M5 until cycle_4 starts, ship then so the reset feels natural. | Leaves a *known-wrong* metric live longer; cycle_4 start date is not set (cycle_3 `cycle_end` is null). |

### Recommendation → **A, ship with a note.** Embasamento:
- The current behavior is a **defect**, not a preference — we display X and rank by Y. Leaving a wrong number live erodes trust more than a one-time corrected reshuffle.
- The blast radius is **display-only** (rank ordering); no XP is changed, no gamification award logic touched. `recalculate_cycle_rankings`/`calculate_rankings` are **admissions**, not gamification — M5 must not touch them.
- A 1–2 sentence in-app/notification note converts "surprise" into "we improved accuracy."
- Cadence is the proven metric-3/M4 one (same-sig `CREATE OR REPLACE` + contract test reading the canonical primitive + Phase-C md5 + 0 `--admin`). It's a multi-PR slice (PR5-A primitive → B board → C self-view → D admin → E scoped boards → F pillars → G frontend) — **not a one-shot** — so approving "A" authorizes the *sequence*, shipped incrementally with the note landing alongside the visible PR (B/G).

**Unblocks:** closes gate **G7**; completes the #419 Bucket-B metric program (M5 is the last big slice). **Decision needed:** A / B / C, and if A, who writes the member note (me draft → you approve).

---

## D2 — #292 **P0 Selection Reliability Sprint (Cycle 4)** — *ratify the sequencing?*

### The situation
#292 is a **sequencing/prioritization plan** (proposed 2026-05-23), not an implementation issue — it orders ~11 selection-lifecycle issues by operational risk. Much of it is **already done** since it was written: the #472 selection-pipeline work shipped extensively (status recompute, VEP freeze, calendar match, offline-interview, consistency cron), and the plan's own table marks **#217 / #227 / #224** as close-candidates and **#251 / #116 / #179** as investigation/QA leaves.

### Options
| Option | What happens |
|---|---|
| **A. Ratify as the dispatch order for Wave-1 Cluster A (recommended)** | Adopt #292 as the sequencing layer; dispatch its remaining *ready leaves* (e.g. #260 candidate-comms, #251 evidence, #230 volunteer-agreement path) in its stated order; close the resolved candidates. |
| **B. Re-prioritize first** | Re-triage the 11 issues from scratch before adopting. |
| **C. Leave unratified** | Selection cluster stays unsequenced; Wave-1 Cluster A can't cleanly dispatch. |

### Recommendation → **A, ratify.** Embasamento:
- The plan's core thesis is sound and **still true**: the candidate lifecycle can go *partial* across VEP-import → visibility → eval → PERT → booking → approval → onboarding → agreement. Sequencing by that risk is correct.
- Most P0 trust-work it gated has **already shipped** (#472 cluster), so ratifying mostly means "adopt the order + close the done ones," which is cheap and unblocks the rest.
- Re-prioritizing from scratch (B) re-does work already validated by the #472 sessions — low value.

**Unblocks:** Wave-1 **Cluster A** (selection reliability: #260/#300/#347/#348/#356/#357/#365/#375/#411) can dispatch in a sane order; lets me close the stale candidates (#217/#227/#224 already verified fixed in prior sessions). **Decision needed:** ratify Y/N; if Y, I'll re-verify the close-candidates live and dispatch the first ready leaf.

---

## D3 — #315 **Governance documents decision spec** (gate G10) — *5 business sub-decisions*

### The situation
This is the **highest-fan-out governance chokepoint** (G10): #310/#312/#314 (admin intake wizard, member library, recirculation) are built but encode **inconsistent assumptions** until these 5 rules are set. It is **not** a one-liner — it needs 5 explicit calls. My recommended defaults (so you can approve-or-amend rather than start blank):

| # | Decision | My recommended default | Why |
|---|---|---|---|
| 1 | **Doc taxonomy** (`doc_type`) | Add `editorial_guide`, `governance_guideline`, `privacy_policy`, `ip_policy` as first-class; keep `template` generic with a `template_for` pointer. | Frontiers + LGPD docs need distinct types for visibility/acknowledgement to differ; avoids overloading `policy`. |
| 2 | **Visibility classes** | 6 classes: `public_anon`, `members_active`, `members_active_plus_alumni`, `role_scoped` (curators/leaders), `signers_only`, `gp_only` + an `audit_only` attachment flag. | Matches the member-library (#314) needs; maps cleanly to existing `can()`/designation gates. |
| 3 | **Status semantics** | Keep `approved` and `active` **separate** (approved-but-future-effective is real for charters/policies); flow: draft→under_review→approved→active→superseded→withdrawn. | A doc can be ratified now, effective later — collapsing them loses that. |
| 4 | **Acknowledgement vs ratification vs signature** | 4 tiers: *read-only*, *informational ciência* (`acknowledge`), *formal ratification* (signoff chain), *legal signature* (counter-signed). Map each `doc_type` to one. | This is the **legal-exposure** decision — conflating "ciência" with "legal acceptance" is the real risk. **Worth a legal-counsel pass.** |
| 5 | **Template ↔ signed-document relationship** | A signed instance references its `template_id` + `template_version`; template edits never mutate signed instances. | Audit integrity — a signed volunteer term must freeze the wording it was signed against. |

### Recommendation → **Approve my defaults async, OR book a focused 30-min pass; route #4 (+#1 for `ip_policy`/`privacy_policy`) through `legal-counsel` before locking.** Embasamento:
- #4 (acknowledgement vs ratification vs **legal signature**) carries genuine LGPD/IP-rights exposure — it should not be defaulted by me alone; it's the one sub-decision I'd gate on `legal-counsel` (the council agent) review.
- 1/2/3/5 are architecture-shaped and have clear best answers (above) — fast to approve.
- This is **high fan-out**: locking it unblocks the entire governance Wave-2 (#301/#311/#459 curation-evidence + #312 recirculation). Doing it EARLY is the roadmap's explicit advice.

**Unblocks:** gate **G10** → governance Wave-2 cluster. **Decision needed:** approve defaults 1–5 (amend any), and say whether to run `legal-counsel` on #4 first (recommended).

---

## D4 — Gates **G1 / G2 / G3** (selection comms) — *bundle with D2*

These three (notification routing / dual-interviewer / dispatch threshold) gate Wave-1 Cluster A leaves. They're **small decisions, latency = your call**. Recommendation: fold into the D2 ratification pass — once #292 is ratified, I'll bring G1–G3 as a 3-line sub-brief with recommended thresholds grounded against live selection data. **No separate action needed now.**

---

## D5 — Deferred **#494 audience-rule follow-up** — *file it?*

The #494 review surfaced a pre-existing gap (not introduced): the recurring modal's `all`/`leadership`/`curators` scopes write no `event_audience` rule, and there's no `target_type='initiative'` in the audience model. Impact is marginal (self-checkin fall-open on those scopes; no metric/visibility/exposure effect). Recommendation → **file a low-priority issue** so it's tracked, don't fix now. **Decision needed:** want me to open it? (1-min, low pri.)

---

## Suggested decision order
1. **D1 (#419 M5)** — clearest, unblocks the most-complete program (just needs go + note).
2. **D2 (#292)** — cheap ratify, unblocks the whole selection cluster.
3. **D3 (#315)** — highest fan-out; the only one needing real deliberation (book the pass / approve defaults + legal on #4).
4. D4 folds into D2; D5 is a 1-min yes/no.

> After decisions are recorded here (or in the issues), the next session executes top-down. Council deep-dives (`/council-review <topic>`) are available for D1 (product/ux) or D3 (legal-counsel/accountability) if you want more than my single-voice recommendation before deciding.

---

## ⚖️ VALIDATION & DECISIONS RECORDED — 2026-06-04 (re-grounded + 4-agent workflow)

> The original recommendations above were validated against live code/DB/issues + a 4-agent validation workflow. **Numbers all hold, but two recommendations were materially wrong (D1 under-scoped, D3 stale/already-decided).** PM decisions captured below. All figures here from live `execute_sql`/`gh`/code reads on 2026-06-04.

**State re-grounded:** HEAD `e7122e94` · 101 open issues · cycle `cycle_3` (start 2026-03-01, `cycle_end` NULL).

### D1 — #419 M5 — ✅ defect confirmed, but the brief MIS-SCOPED it
- `get_member_cycle_xp` displays cycle XP but ranks by lifetime (`ROW_NUMBER() OVER (ORDER BY SUM(points) DESC)`, no cycle filter / no tiebreak / `'2026-01-01'` hardcode). Live reorder re-measured: **60 members, 59 (98.3%) reorder, 9 zero-cycle.**
- **Correction:** `rank_position` is **never rendered on the web** — sole web consumer `profile.astro:413` reads only points (0 matches for `rank_position`); the visible member board (`gamification.astro`) re-sorts **client-side** on a toggle **defaulted to `lifetime` (:549)**; the public board (`get_public_leaderboard`) is **lifetime-by-design**. The broken rank's only surface is the **AI chat** (`get_my_xp_and_ranking`). `get_xp_rankings` (cited in #419 memory) **does not exist**. `calculate_rankings`/`recalculate_cycle_rankings` = selection admissions (out of scope, correct).
- **PM DECISION:** chat rank fix **+ flip member-board default to cycle** (the only change that visibly reshuffles → warrants the member note). **Public board stays lifetime.**

### D2 — #292 — ✅ ratify thesis, but the "9 leaves" list is stale
- `#217/#227/#224/#251/#116/#179` all already CLOSED. Of the 9 "Cluster-A leaves": **#356 / #357 / #365 = shipped-but-open** (verified live: booking_url admin field + i18n×3 + 2 members set; cycle4 committee = Vitor+Fabricio `can_interview`; `objective_score` bound at `admin/selection.astro:1671-1673` + PR#410). **#260** = QA-window (smoke only). **#411** = partially shipped (wave 1a done; **1b-3 remain = the real next dev**). **#347/#348** = specs. **#300** = mis-grouped onboarding umbrella. **#375** = transient infra non-bug. #292's own body sequences a *different* set (#251/#260/#116/#179/#230/#229).
- **PM DECISION:** re-ground first — **close #356/#357/#365** (verified done), smoke-only #260, then **dispatch #411 waves 1b-3**. Triage #300/#347/#375 separately. *(✅ #356/#357/#365 CLOSED 2026-06-04 with verification comments.)*

### D3 — #315 — ❌ recommendation REJECTED: already ratified
- The 5 sub-decisions were **RATIFIED 2026-05-24** (#315 comments `2026-05-25T00:01` council pre-review *with legal-counsel* → `00:09` "Decision matrix RATIFIED"). #315 is OPEN only due to a PR-keyword auto-close+reopen (SEDIMENT-235.A), **not** pending decisions.
- The brief's defaults **contradict** the ratified+shipped matrix: `ip_policy`/`privacy_policy` as `doc_type` (ratified → `policy`+`metadata.subtype`); 6 new visibility names (ratified → the **5 structural classes already live**); 4-tier ack (ratified+shipped → **3-tier** `{informational,binding,legal_signature}`). `approved`/`active` already separate in the live CHECK.
- **Real open item the brief missed:** `governance_documents` has **no `metadata` column** → the ratified `subtype`/`template_role` cannot be stored. That's the Wave-1b blocker.
- **PM DECISION:** **re-affirm the 2026-05-24 ratification** + ship **Wave 1b foundation** (add `metadata` column). **Do NOT re-decide taxonomy / do NOT re-run legal-counsel** (already in the room). #315 stays open as the Wave-1b tracker.

### D5 — #494 audience gap — ✅ file, broader than "marginal"
- Gap confirmed: `RecurringModal.astro:43-50` emits `all/leadership/curators/initiative`; `buildAudienceRules` (`attendance.astro:1553-1569`) handles only `all_active_operational/tribe/role/specific_members`, gated on `tagIds.length`. Severity low (visibility = separate `events.visibility`; `event_audience_rules` read RLS `USING(true)` = no PII leak; metrics from actual attendance). **But volume not marginal:** live fall-open = `leadership` **79/139 (57%)**, `all` 9/160, `tribe` 0/83.
- **PM DECISION:** **file the follow-up** (corrected scope: vocab mismatch + single-event modal shares `buildAudienceRules` + 79 rule-less leadership events backfill? + `audience_level`↔`event_audience_rules` split-truth). *(✅ filed as #500, 2026-06-04.)*

### Next execution (post-decision)
1. ✅ **D2 loop-close DONE 2026-06-04**: #356/#357/#365 CLOSED (verified shipped); D5 follow-up filed as **#500**.
2. **D1 M5** (multi-PR): chat rank fix (cycle-scoped + `member_id` tiebreak + kill `'2026-01-01'`) → flip `gamification.astro:549` default to `cycle` → member note draft.
3. **D3 Wave 1b**: add `governance_documents.metadata` column (migration) → unblocks ratified subtype/template_role.
4. **D2 #411** waves 1b-3 (filter chips / bulk / stuck-rescue RPC / crons).
