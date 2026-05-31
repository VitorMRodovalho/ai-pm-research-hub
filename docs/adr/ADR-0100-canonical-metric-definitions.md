# ADR-0100 — Canonical Metric Definitions (single source of truth per metric)

| Field | Value |
|---|---|
| Status | Accepted (2026-05-28; revised 2026-05-30) — dictionary spec + **active per-metric rollout**. Metric 1 (impact_hours), metric 2 (active_member), and **metric 3 (attendance — two-metric model, this revision)** shipped; metrics 4-8 + the p175 gate (PR10) + the seal track (PR11) in progress (Bucket B of the 2026-05-28 disparity audit) |
| Date | 2026-05-28 (revised 2026-05-30 — metric 3) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude (Anthropic)) |
| Supersedes | none |
| Amends | none |
| Related | [[ADR-0096]] (impact_hours_total view — accepted-risk; this ADR proposes to make it canonical and retire the looser parallel) · [[ADR-0005]] (initiatives primitive / tribes-as-bridge) · [[ADR-0007]] (`can()` authority) · [[ADR-0050]] (gamification visibility opt-out) · [[ADR-0097]] (migration drift amnesty + ratchet — the p175 gate this ADR extends) · `docs/audit/METRIC_DISPARITY_AUDIT_2026-05-28.md` (Bucket B findings) · `docs/specs/SPEC_419_M3_ATTENDANCE_TWO_METRIC.md` (metric 3 two-metric design + the D1–D10 ratification) |
| Migrations | none spec-side — implementation lands one metric per PR. Metric 3 (attendance) shipped in `20260805000064`–`20260805000075` (eligibility primitive + engagement/reliability summaries + 8 surface convergences) |

---

## 1. Context

The 2026-05-28 cross-surface disparity audit (`docs/audit/METRIC_DISPARITY_AUDIT_2026-05-28.md`)
found that the same logical metric is computed differently on different surfaces — not as an
accident, but as the predictable result of **every metric being re-implemented inline in every
RPC**, with no shared base. Concrete evidence:

- **Impact hours** has 4 live formulas. The only canonical primitive,
  `get_impact_hours_canonical` (ADR-0096), is consumed by exactly **one of the five** RPCs that
  report hours; `get_homepage_stats` and `get_cycle_report` use a looser formula (includes
  excused, 60-min fallback, ROUND 0), and a parallel `impact_hours_summary` view uses yet
  another. A GP reporting "impact hours delivered" gets three different numbers across the
  homepage, the cycle report, and the admin dashboard.
- **Active members** has ~5 incompatible predicates across 6 RPCs.
- **Attendance rate** has 6+ structurally different formulas (denominator, unit, rounding,
  excused handling, present-detection all fork).
- **Member count / XP rank / trail completion / CPMAI** each fork similarly.
- The **V4 tribe-bridge** is a special case: `get_initiative_stats` delegates to
  `get_tribe_stats` for a bridged initiative, but `get_initiative_members` and
  `get_initiative_events_timeline` do **not**, so a bridged initiative page mixes tribe-table
  and initiative-table math.

**Why not fix finding-by-finding.** 13 reconciliation PRs that each tweak one inline formula
will pass review and re-drift within a few sessions. The project's own p175 body-drift history
(225 drifted function bodies at p175; ADR-0097) is the proof. Inline tweaks do not produce a
single source of truth; the headline GP↔Sponsor KPIs keep disagreeing.

**Why not a materialized metrics warehouse.** Overkill for the current scale, and against the
project norm "match scope to ask / no premature helper module." The canonical-views approach
reuses the existing SECDEF-RPC + migration + contract-test machinery already in place.

---

## 2. Decision

**(A) A metric dictionary.** This ADR defines, once, each logical metric that appears on two or
more surfaces. Each definition fixes: the **predicate**, the **window source**, the
**excused/present** rule, the **rounding/unit**, and the **LGPD opt-out rule per tier**.

**(B) A small set of canonical SQL views/functions** backing the dictionary. Every surface RPC
is migrated to read from these — **one metric per PR** — instead of re-implementing.

**(C) A forward-defense gate.** Extend the p175 body-drift contract test (ADR-0097) with a
"no inline re-implementation of a canonical metric" assertion so new RPCs must consume the
canonical primitive.

### 2.1 The window-source invariant (applies to ALL metrics)

A metric's time window is resolved from `cycles.is_current` (or an explicit caller-passed
cycle) — **never** a hardcoded date literal (`'2026-01-01'`) and **never** a hardcoded cycle
code (`'cycle3-2026'`). This single rule retires D10, D11, and the YTD-literal forks.

### 2.2 The metric dictionary (v1)

| Metric | Canonical definition | Window | LGPD opt-out |
|---|---|---|---|
| **active_member** | `is_active = true AND current_cycle_active = true` | current cycle | n/a |
| **impact_hours** | `SUM(COALESCE(duration_actual, duration_minutes)/60) FILTER (present = true AND excused IS NOT TRUE)`, ROUND 1; **no** 60-min fallback | param window (default current cycle) | n/a |
| **attendance_engagement** *(Participação — the headline; every audience surface)* | per `(member, event)` `present=true`; denominator = **eligible** past non-cancelled events from `_attendance_eligible_events` — a no-show that left **no row still counts as absent**; **excused excluded** (neutral, D1); fraction 0..1 ROUND 2 (surfaces ×100); cohort aggregate = **AVG-of-member-rates** (D2). Live global **76.9%** (cohort 37). | `cycles.is_current` (open ⇒ `CURRENT_DATE`), type set `{geral,kickoff,tribo,lideranca}` | n/a |
| **attendance_reliability** *(Confiabilidade de registro — ops/self diagnostic, NEVER a headline until roster sealing)* | `present=true` over events that **have a recorded** non-excused row (`a.id exists AND excused IS NOT TRUE`); excused removed both sides. **There is no `attendance.status` column** — both metrics use the `present`/`excused` pair. Structurally ≈100% until absent-row capture (live **99.2%**, only **5** genuine absent rows cohort-wide). **Visibility (D10):** member-self + admin only, **always with raw present/absent/excused counts**; public/headline **BANNED** until `seal_event_attendance` coverage is real (PR10 hard-gate). | same window + type set | n/a |
| **tribe_roster / member_count** | DISTINCT persons with an **active, non-observer** engagement on the initiative, `is_active`; resolve legacy `tribe_id` ↔ engagements onto **engagements** (ADR-0005) | current cycle | n/a |
| **lifetime_xp** | `SUM(gamification_points.points)` all-time | all-time | honored on member + public surfaces; admin carve-out documented |
| **cycle_xp + rank** | cycle points = points in window; rank `ORDER BY cycle_points DESC` **in cycle mode** (not lifetime), deterministic tiebreak `member_id`; pool = `gamification_opt_out=false AND eligible-this-cycle` | current cycle | honored except admin carve-out |
| **trail_completion** | `completed_trail_courses / NULLIF(count(is_trail courses),0)`; **dynamic** trail total (no hardcoded 6); native initiatives → `N/A`, never `0%` | all-time | n/a |
| **cpmai_certified** | `COUNT(DISTINCT member_id)` with a CPMAI credential; one source (decide: `gamification_points` category vs `members.cpmai_certified` boolean — dictionary picks ONE) | param (cycle or all-time, stated) | n/a |
| **champions** | champion recognition XP/count; ONE canonical source — decide between `champions_awarded` (table, source of truth for ranking/profile/admin) and `gamification_points` pillar='champions' (leaderboard/tribe). Today they are dual-written with NO reconciliation; the leaderboard chip reads 0 rows structurally. Pick one + add a parity invariant. (issue #424) | current cycle (ranking) / all-time (leaderboard) | honored except admin/leader carve-out |
| **webinars_completed** | `COUNT(*)` from the **`webinars` table** (the architectural source of truth, decision #4) — NOT `events WHERE type='webinar'`, which the portfolio KPI currently reads (live 4 vs 7) | param window | n/a |

### 2.3 Canonical views / functions (v1)

- `v_active_members` — the §2.2 active_member predicate.
- `get_impact_hours_canonical(p_scope, p_window)` — **already exists** (ADR-0096); parameterize
  by scope/window and make **every** hours surface call it. Retire/rename
  `impact_hours_summary` to signal non-canonical.
- **Attendance (metric 3) — 4 primitives + shared eligibility + seal precondition** (two-metric model, §7 ratification 2026-05-30):
  - `_attendance_eligible_events(p_member_id, p_cycle_start)` → TABLE — the **single** eligibility source (type-based `{geral,kickoff,tribo,lideranca}`, §3b Canonical Eligibility Principle); consumed by **both** engagement RPCs **and** the seal track. No surface may reintroduce a parallel (tag-based / `event_audience_rules`) eligibility model.
  - `get_attendance_engagement_rate(p_member_id, p_cycle_start)` → numeric · `get_attendance_engagement_summary(p_scope, p_scope_id, p_cycle_start, p_chapter)` → jsonb — **ENGAGEMENT** (the headline); the summary replaces 4 divergent inline aggregates.
  - `get_attendance_rate(p_member_id, p_cycle_start)` → numeric · `get_attendance_reliability_summary(p_scope, p_scope_id, p_cycle_start, p_chapter)` → jsonb — **RELIABILITY** (diagnostic); `get_attendance_rate` was type-scoped in PR6 so reliability shares the eligibility set and can converge with engagement once sealing materializes absent rows.
  - **Invariant: engagement ≤ reliability** (CI-asserted) — reliability conditions on complete data, so it systematically over-states vs the expected-denominator engagement.
  - `seal_event_attendance(p_event_id)` + `events.roster_sealed_at` — **deferred PR11** (separate track): materializes absent rows for eligible no-shows; the precondition before reliability may be promoted from diagnostic to a shown indicator.
- `v_tribe_roster(initiative_id)` — the §2.2 roster predicate, resolving the legacy
  `tribe_id` vs V4 `engagements` fork onto engagements (ADR-0005).
- one **pillar-bucketing helper** keyed on `gamification_rules` (retires the raw-category-string
  and `cpmai_prep`-namespace forks; pick the `gamification_rules` JOIN as canonical taxonomy).

### 2.4 V4 bridge consolidation (D15 / D18)

Either (a) make the **whole** initiative surface delegate to the tribe path when
`resolve_tribe_id(initiative_id)` is non-null (cheap, immediately consistent — recommended for
now), or (b) finish the ADR-0005 consolidation so tribes are purely a bridge and all reads go
through initiatives (tracked follow-up). At minimum, align `exec_tribe_dashboard` and
`get_tribe_stats` onto one event-type set, window source, and excused rule.

---

## 3. Migration strategy

One metric per PR, smallest-blast-radius first:

1. `active_member` → `v_active_members`, migrate the 6 RPCs. (lowest risk; predicate-only)
2. `impact_hours` → all hours surfaces call `get_impact_hours_canonical`; retire
   `impact_hours_summary`.
3. `attendance_rate` → **expanded into the two-metric model** (engagement + reliability) — see the
   §2.2 rows, the §2.3 four-primitive set, and the 2026-05-30 §7 ratification. Shipped across PR1–PR8
   (eligibility primitive + both summaries + 8 surface convergences); also fixed the D6 `a.id IS NOT NULL`
   present-detection bug and the D12 attendee-count bug. PR10 (gate) + PR11 (seal) remain.
4. `tribe_roster` → `v_tribe_roster` + V4 bridge delegation (D15/D18).
5. XP rank/pillar → pillar helper + cycle-mode ordering + deterministic tiebreak (D8/D9).
6. trail_completion + cpmai_certified → dictionary picks the single source; native-initiative
   `N/A` rendering (D17).

Each PR: same-signature `CREATE OR REPLACE`; live smoke; contract test asserting the RPC reads
the canonical primitive (not an inline formula); update the affected surfaces' labels (D11).

---

## 4. Consequences

**Positive:** GP↔Sponsor headline KPIs reconcile across homepage / cycle report / admin; new
RPCs have one spec to conform to; the p175 gate prevents recurrence; tier/opt-out rules become
explicit and testable.

**Costs:** ~6 PRs of careful migration; some numbers will *change* on some surfaces as they
converge onto the canonical definition (expected and desirable — communicate to stakeholders
which surface was "wrong").

**Out of scope (ship regardless of this ADR):** the Bucket A consent/security defects
(D1/D2/D3/`get_member_cycle_xp`) — already shipped in migration `20260805000055`.

---

## 5. Status notes

Spec-only. Implementation is the Bucket B program, triaged against the active sprint by the PM.
The dictionary §2.2 is the contract; the views §2.3 are the mechanism; the per-PR sequence §3 is
the rollout. Reopen/version this ADR if a metric's canonical definition is contested during a
per-metric PR.

---

## 6. Gamification-probe addenda (2026-05-29)

A live-DB gamification integrity probe (audit doc §"GAMIFICATION PROBE") found five issues
(GI-1..GI-5) that map onto this dictionary:

- **GI-3 (cycle binding) — partially shipped.** `exec_portfolio_health` now resilient-resolves the
  cycle code (migration `20260805000057`): a code with no targets (incl. the live
  `cycles.is_current` code `cycle_3`, whose targets live under `cycle3-2026`) falls back to the
  latest cycle_code that has targets instead of returning an empty metric set. STILL OPEN: the
  deeper namespace reconciliation (`cycles.cycle_code='cycle_3'` vs `portfolio_kpi_targets='cycle3-2026'`,
  same cycle, parallel namespaces) — a data/architectural decision, not made in the resilience fix.
- **GI-5 (KPI headlines) — partially shipped.** Removed the false chapters "Superada"
  (`kpis.ts`, live 7 < target 8). The remaining `webinars_completed` wrong-table read is now a
  dictionary line item (read the `webinars` table per decision #4). Labeling target-as-headline
  values explicitly as "Meta" is a deferred frontend/UX decision (issue, Lane C).
- **GI-4 (trail 42% vs 44%)** = the `active_member` + `trail_completion` dictionary lines. The
  homepage `certification_trail` card (`calc_trail_completion_pct`, role-exclusion blocklist,
  cohort 39) and the `#trailKPI` ranking average (`get_public_trail_ranking`, inclusion rule,
  cohort 37) disagree purely on cohort membership (2 `operational_role='guest'` members with 0/6
  in the first but not the second). Both must derive from ONE eligibility predicate
  (`v_active_members` / a shared `trail_eligible_members`), and `calc_trail_completion_pct` must
  read `count(courses WHERE is_trail)` instead of a hardcoded `6.0`.
- **GI-1 (tribe coaching columns)** — `trail_completion` hardcoded `0` in both
  `get_tribe_gamification`/`get_initiative_gamification` (compute it under the `trail_completion`
  line); badge/cert columns read 0 despite real Credly badges (cert/badge dictionary convergence);
  champions column dead (champions line). Coaching-depth additions tracked in the coaching issue.
- **GI-2 (champions)** — see the new `champions` dictionary line + the discrete champions issue
  (operational unblock + single source + parity invariant).

## 7. Ratified PM decisions (during #419 implementation)

- **2026-05-29 — `active_member` first converges (metric 2).** Shipped `v_active_members` view
  (`is_active AND current_cycle_active`) + converged 3 real-drift org-level RPCs
  (get_platform_usage, get_sustainability_projections, get_pilot_metrics: 53→52). The legacy
  `public.active_members` view (is_active-only, consumed by BoardEngine/AttendanceForm + FK metadata)
  was deliberately NOT reused — v_ prefix avoids a silent consumer break; its reconciliation is a
  separate open decision.
- **2026-05-29 — CARVE-OUT (PM-ratified): chapter dashboards keep `member_status`.** The
  chapter dashboards (get_chapter_dashboard people.active/by_role) and the admin members roster
  (MemberListIsland) intentionally count "active members" by `member_status = 'active'` (the member
  LIFECYCLE enum), NOT the canonical cycle-activity predicate. This is a deliberate, ratified
  carve-out: chapter/admin lifecycle views answer "who is an active member of the chapter" (lifecycle),
  which is a different question from "who is active in the current cycle" (the org-level canonical
  headline). The `active_member` canonical convergence therefore applies to ORG-LEVEL headcounts only;
  chapter/admin member_status counts are out of scope by design. Revisit only if the chapter program
  decides its dashboards should track cycle-activity instead of lifecycle.

- **2026-05-30 — metric 3 (attendance): TWO-metric model ratified + shipped (PR1–PR8 of 11).**
  PM ratified **Option C**: two canonical indicators — **engagement/*Participação*** (the headline, on every
  audience surface) and **reliability/*Confiabilidade de registro*** (an ops/self diagnostic, never a headline
  until roster sealing). The single §2.2 `attendance_rate` row is replaced by the two dictionary rows above;
  §2.3 now lists the four primitives + shared eligibility + the seal precondition. Full design + grounding:
  `docs/specs/SPEC_419_M3_ATTENDANCE_TWO_METRIC.md`.

  **§3b CANONICAL ELIGIBILITY PRINCIPLE (prerequisite for ALL future attendance metrics).**
  `public._attendance_eligible_events(member, cycle_start)` is the SINGLE source of attendance eligibility —
  **type-based**: candidates are `{geral,kickoff,tribo,lideranca}` in the `cycles.is_current` window
  (open ⇒ `CURRENT_DATE`); per-member scoping is `geral/kickoff` → all operational, `tribo` → own tribe via
  `get_member_tribe` (resolved through `initiatives.legacy_tribe_id`; events has **no** tribe column),
  `lideranca` → `can_by_member('manage_event')`. **No surface may reintroduce a parallel eligibility model** —
  not the tag-based one (`general_meeting`/`tribe_meeting`) nor `event_audience_rules`/`is_event_mandatory_for_member`.
  Both were live and produced a divergent global number (panel **70.5%** vs canonical **76.2%** at PR7 time) because
  they select different candidate events and scope eligibility differently. **Decision (Option B): type-based wins**;
  PR7 converged the last hold-out (`get_attendance_panel`) onto it and dropped the orphan `get_attendance_summary`.
  The PR10 p175 gate forward-defends this (no new tag/audience-rule attendance eligibility in any RPC).

  **The ten ratified business-rule decisions** (SPEC §6; recommended defaults adopted as ratified):
  - **D1** — excused is **removed** from the engagement denominator (neutral; both metrics treat excused identically — an org-sanctioned absence must not penalize a recognition KPI). Extended in PR8: excused is also neutral for dropout-risk flagging.
  - **D2** — cohort = the **37-member operational union** {researcher, tribe_leader, manager} (curator kept); aggregate = **AVG-of-member-rates** (not pooled present/expected).
  - **D3** — `lideranca` eligibility = `can_by_member('manage_event')` (single V4 authority basis); the phantom `deputy_manager` is dropped.
  - **D4** — `tribo` eligibility = **own-tribe only**; the org-manager is excluded from the tribo dimension; the legacy `tribe_id` ↔ engagements **bridge bug** (Roberto Macêdo: `tribe_id=8` but `get_member_tribe=NULL`) is treated V4-consistently (tribe-8 excluded from his eligible set; the data/intent question stays the PM's).
  - **D5** — 1-on-1 events **excluded** (coaching artifact, no roster).
  - **D6** — `evento_externo` / comms types **excluded** (neither type exists live; the comms branch stays dormant).
  - **D7** — *(superseded by PM Option B / §3b)* the original "hybrid: delegate to `is_event_mandatory_for_member`" was reversed; **type-based eligibility is canonical**.
  - **D8** — point-in-time eligibility for late joiners/changers is **as-of event date, but shipped OFF/parameterized** until separately ratified (the `created_at` proxy is useless — all 37 share 2026-03-05).
  - **D9** — `get_attendance_summary`'s hidden 0.4/0.6 weighting is **dropped to flat present/expected**; the orphan was retired in PR7.
  - **D10** — reliability **visibility**: member-self + admin only, **mandatory raw present/absent/excused counts**, public/headline **BANNED** until `seal_event_attendance` coverage is real; window open ⇒ `CURRENT_DATE` / closed ⇒ `cycle_end`, no date literal. The PR10 hard-gate enforces this.

  **antes → depois (live-grounded 2026-05-30, `cycle_3` from `cycles.is_current`):**
  - **Home hero** (`calc_attendance_pct` → engagement): **64.4%** (a buggy hybrid denominator, PR-time per SPEC §1/§5) → canonical engagement, **live 76.9%** (was 76.2% at PR2 merge — the same metric drifts up as attendance accrues; home now == `engagement_global`).
  - **Engagement global** (`get_attendance_engagement_summary('global',…)`): **76.9%** (`0.7686`, AVG-of-rates, cohort_n=37, at_risk_count=4, coverage `ok`; present 576 / expected 734 / excused 53).
  - **Reliability global** (`get_attendance_reliability_summary('global',…)`): **99.2%** (`0.9916`, cohort_n=37, coverage `partial`) — structurally pinned near 100% because **absences are never written**: only **5** genuine absent rows cohort-wide vs 583 present (54 excused). This is exactly why reliability must stay a diagnostic until the seal track materializes absent rows.
  - There is **no `attendance.status` column** live — both metrics operate on the `present`/`excused` pair.

  **Remaining:** PR10 (p175 gate extension — inline-rate forward-defense + the D10 reliability-visibility hard-gate +
  grant ladder) and PR11 (seal track — `events.roster_sealed_at` + `seal_event_attendance`, coordinating
  `sync_attendance_points` no-XP-for-sealed-absents + `detect_and_notify_detractors`). Only after real seal coverage
  may reliability be promoted from diagnostic to a shown indicator.
