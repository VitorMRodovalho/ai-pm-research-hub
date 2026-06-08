# Decision — #577: gamification cockpit progressive disclosure (toggle)

- **Date:** 2026-06-08
- **Issue:** #577 (follow-up to #425 / PR #575)
- **Decider:** PM (Vitor) via the PM-decision loop ([[working-agreement-decision-process-2026-06-07]])
- **Surface:** frontend-only — `src/components/tribes/TribeGamificationTab.tsx` (shared by tribe + initiative gamification tabs). No RPC / migration / deploy.
- **Branch / PR:** `feat/577-gamification-progressive-disclosure`

## Context

The #425 cockpit shipped the per-member coaching drill-down but left the summary table at **16 columns** (live-verified against the component, `TribeGamificationTab.tsx:273-288` pre-change). Seven of those are **raw-pillar point columns** — `Presença pts, Certs, Badges, Aprendizado, Produção, Curadoria, Champions` — that compete with the high-signal coaching columns (XP, Ciclo XP, Seq., Pres.%) for scan attention. A leader reads ~14 data columns before reaching the expand chevron.

## Options presented (PL/CTO framing — each grounded, not a plan)

1. **#577 cockpit UX (recommended next)** vs three build-ready alternatives (#580 hardening, #587 perf, #579 tech-debt). #577 was recommended because it **completes the #425 arc** (perf shipped in #576), is the **only user-facing** item, and is the only one needing the decision loop.
2. **UX approach for #577:**
   - **A — Full collapse** (the issue's literal proposal): the 7 point columns move *exclusively* into the drill-down.
   - **B — Toggle middle-ground (recommended):** default to a 9-column COMPACT view; a "show points breakdown" toggle reveals the 7 columns **inline**. Captures the scan benefit by default, zero regression risk, ~15 lines.
   - **C — Keep 16 columns / defer.**

## Recommendation + rationale (PL/CTO)

Recommended **#577, Option B (toggle)**. The toggle delivers ~all the progressive-disclosure scan benefit by default while eliminating the "where did my Curadoria column go?" regression risk that full removal carries for leaders who curate by a specific pillar. Cost is trivial — the 7 columns already render; gating them behind a `showBreakdown` boolean + a small toggle is the whole change.

## Decision

PM chose **#577** + **Option B (toggle)**.

## Grounding finding that confirmed Option B (material)

Reading the full `MemberDrillDown` component, the issue's premise — *"the seven raw-pillar point columns already exist in the coaching-signals section [of the drill-down]"* — is **FALSE**. The drill-down renders **only `champions_points`** of the 7 (in the Recognition `StatCard`); the other six (`attendance_points, cert_points, badge_points, learning_points, producao_points, curadoria_points`) appear **nowhere** in the drill-down.

→ **Option A (full removal) would have silently lost 6 of 7 pillar point values.** The chosen toggle keeps all 7 one click away inline in both states — **no data is lost either way.** This is the decisive reason the toggle was the correct call, and it is filed as a follow-up gap (below) for whoever wants true full-collapse later.

## Implementation

- New state `showBreakdown` (`useState(false)` — default COMPACT).
- Toggle `<button>` in the table header: `type=button`, `aria-pressed={showBreakdown}`, `aria-controls="gamif-members-table"`, focus ring, label switches `comp.gamification.showBreakdown` / `hideBreakdown`.
- The 7 pillar point columns gated behind `{showBreakdown && (...)}` in **both** `<thead>` and `<tbody>`. **Two** conditional blocks per section because the always-on **Pres. %** (`attendance_rate`) column sits *between* `Presença pts` and the cert→champions group.
- **Default-visible 9 columns:** `#, Nome, XP Total, Ciclo XP, Seq., Pres.%, CPMAI, Trilha, expand`. CPMAI and Pres.% are deliberately kept (credential / coaching signal — not point pillars).
- `TABLE_COLS = 16` → `TABLE_COLS_FULL = 16` / `TABLE_COLS_COMPACT = 9`; `visibleCols = showBreakdown ? FULL : COMPACT` drives both colSpans (drill-down row + empty-state row).
- i18n: `comp.gamification.showBreakdown` + `hideBreakdown` added to all 3 dicts (parity verified 3/3).
- Sort state is left untouched on toggle (visibility is orthogonal to sort).

## Verification

- `npx astro build` — pass.
- New contract test `tests/contracts/577-gamification-progressive-disclosure.test.mjs` (static TSX + i18n), in BOTH whitelists (`test` + `test:contracts`).
- Full suite — see PR.

## Follow-ups filed

- **GAP (enables future Option A):** the drill-down should render the per-pillar point breakdown (6 of 7 values are absent today) so a leader gets the full pillar picture without revealing the columns. If/when that lands, full-collapse becomes lossless.
- **Considered + deferred:** persisting the toggle (localStorage) for power users who always want the breakdown — kept in-memory for this PR (matches the decision precisely, zero hydration risk).

## Council review (Workflow `wf_94af79cb`, 5 reviewers on the draft, pre-commit)

**Verdict: 5/5 GO_W_FIXES, 0 NO_GO, 0 BLOCKER.** Reviewers: ux-leader, code-reviewer, senior-software-engineer, stakeholder-persona (gp-leader), a11y-i18n-verifier.

**Folded in-PR** (the findings ≥2 reviewers raised + every HIGH):

| # | Finding | Severity / who | Fix |
|---|---------|----------------|-----|
| A | **Orphan sort on collapse** — sorting by a pillar column then collapsing left the table sorted by an invisible key with no `aria-sort`. | HIGH (ux) / MEDIUM (senior-eng, gp-leader) — 3 reviewers | `BREAKDOWN_SORT_KEYS` const + `toggleBreakdown` resets to `total_points` on collapse. |
| B | **Table had no accessible name** (WCAG 1.3.1). | MEDIUM (ux) | `aria-labelledby` on `<table>` → `id` on the `<h3>`. |
| C | **Toggle discoverability** — a GP could think data "disappeared" and escalate. | **HIGH (gp-leader)** / LOW (ux) | Prepend a `⊞`/`▸` icon + append `(+7)` count to the collapsed label. |
| D | **i18n fallback drift** — `coachingTitle` JSX fallback `'Cockpit de coaching'` ≠ dict `'Coaching do membro'` (pre-existing). | NIT — 3 reviewers | Aligned the fallback literal. |
| E | **Focus ring invisible in forced-colors mode.** | LOW (a11y) | `forced-colors:focus:outline` on the new toggle button. |
| F | **Narrow-viewport (<360px) header overflow.** | LOW — 2 reviewers | `flex-wrap` on the header row. |
| G | **No 577 test coverage** (council saw the draft before the test existed). | MEDIUM/LOW (senior-eng) | `tests/contracts/577-…` already written; extended with the sort-reset, accessible-name, and 7-pillar-key parity assertions. |

**Deferred to follow-up** (reviewers unanimous "defensible for v1 / do not block"):

- **Toggle persistence** (session/localStorage) for power users — kept in-memory; rationale documented in-code; revisit on analytics.
- **Pre-existing a11y on the #425 expand buttons** (forced-colors ring + `aria-controls` → conditionally-rendered div) — not introduced by #577; out of scope.
- **Per-pillar point breakdown inside the drill-down** (6 of 7 absent today) — the GAP that would make a future full-collapse lossless.

**Not actioned (reviewer said "no action required"):** `aria-controls` whole-table imprecision; the two-conditional-block split (minimal-diff is the right call vs reordering columns away from Pres.%).
