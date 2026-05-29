# ADR-0100 — Canonical Metric Definitions (single source of truth per metric)

| Field | Value |
|---|---|
| Status | Proposed (2026-05-28) — spec; implementation deferred to per-metric PRs (Bucket B of the 2026-05-28 disparity audit) |
| Date | 2026-05-28 |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude (Anthropic)) |
| Supersedes | none |
| Amends | none |
| Related | [[ADR-0096]] (impact_hours_total view — accepted-risk; this ADR proposes to make it canonical and retire the looser parallel) · [[ADR-0005]] (initiatives primitive / tribes-as-bridge) · [[ADR-0007]] (`can()` authority) · [[ADR-0050]] (gamification visibility opt-out) · [[ADR-0097]] (migration drift amnesty + ratchet — the p175 gate this ADR extends) · `docs/audit/METRIC_DISPARITY_AUDIT_2026-05-28.md` (Bucket B findings) |
| Migrations | none (spec-only) — implementation lands one metric per PR |

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
| **attendance_rate** | per `(member, event)`: `present=true`; denominator = eligible events where status ∈ (present, absent), **excused excluded**; emit as fraction 0..1 ROUND 2 at the data layer (surfaces format ×100) | param scope (member / tribe / initiative / global), current cycle | n/a |
| **tribe_roster / member_count** | DISTINCT persons with an **active, non-observer** engagement on the initiative, `is_active`; resolve legacy `tribe_id` ↔ engagements onto **engagements** (ADR-0005) | current cycle | n/a |
| **lifetime_xp** | `SUM(gamification_points.points)` all-time | all-time | honored on member + public surfaces; admin carve-out documented |
| **cycle_xp + rank** | cycle points = points in window; rank `ORDER BY cycle_points DESC` **in cycle mode** (not lifetime), deterministic tiebreak `member_id`; pool = `gamification_opt_out=false AND eligible-this-cycle` | current cycle | honored except admin carve-out |
| **trail_completion** | `completed_trail_courses / NULLIF(count(is_trail courses),0)`; **dynamic** trail total (no hardcoded 6); native initiatives → `N/A`, never `0%` | all-time | n/a |
| **cpmai_certified** | `COUNT(DISTINCT member_id)` with a CPMAI credential; one source (decide: `gamification_points` category vs `members.cpmai_certified` boolean — dictionary picks ONE) | param (cycle or all-time, stated) | n/a |

### 2.3 Canonical views / functions (v1)

- `v_active_members` — the §2.2 active_member predicate.
- `get_impact_hours_canonical(p_scope, p_window)` — **already exists** (ADR-0096); parameterize
  by scope/window and make **every** hours surface call it. Retire/rename
  `impact_hours_summary` to signal non-canonical.
- `get_attendance_rate(p_member_id, p_scope, p_cycle)` — one per-(member,event) definition.
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
3. `attendance_rate` → `get_attendance_rate`; also fix the D6 `a.id IS NOT NULL` present-detection
   bug and the D12 attendee-count bug in the same pass.
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
