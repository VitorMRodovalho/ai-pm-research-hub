# SPEC #419 metric 3 — Two-metric attendance model (reliability + engagement)

> **Status:** proposal awaiting PM ratification of the §6 business-rule decisions.
> **Source:** multi-agent design workflow (discovery → design → 3-lens adversarial review → revision),
> all numbers live-verified against `ldrfrvwhxsmgaabwmaik` (cycle_3, window 2026-03-01..today, open cycle).
> **Governs:** ADR-0100 metric 3 (`attendance_rate`). Supersedes the single §2.2 `attendance_rate` row.
> **PM decision already taken:** Option C — TWO canonical indicators (reliability + engagement).

---

## 1. The problem (why two metrics)

The platform's attendance % differs wildly by **which denominator** you use:

| Model | Denominator | Live value | What it actually measures |
|---|---|---|---|
| `calc_attendance_pct()` (home hero today) | "expected events" (buggy hybrid) | **64.4%** | inflated/buggy — see below |
| Canonical recorded (ADR-0100 §2.2 as written, `get_attendance_rate`) | events with a **recorded** present/absent row | **99.1%** | recorder diligence, NOT participation |
| **Engagement (proposed)** | events the member was **eligible/expected** for | **76.2%** | true participation |

The 99.1% is structurally pinned near 100% because **absences are never written**: cycle-wide there are
**623 present rows, 57 excused, and only 6 genuine absent rows**. A no-show simply leaves no row, so the
recorded denominator collapses to ≈ the present count. The most recent `geral` (2026-05-21) reads **100%
reliability at ~51% true participation**.

Conclusion (grounded below): **engagement is the audience-facing truth; reliability is a data-quality
diagnostic** that must be gated behind real absence capture before it can ever be shown as a headline.

---

## 2. The two metrics

### 2.1 ENGAGEMENT — *Participação* (the headline)

- **Question:** of the events a member was **expected** to attend, what fraction were present?
- **Denominator:** the set of **eligible** past, non-cancelled events (independent of whether a row exists).
  A no-show that left no row **still counts as absent** — exactly what a participation signal must do.
- **Numerator:** `present = true`.
- **Excused:** removed from the denominator (ratified default D1 — neutral, mirrors reliability).
- **Window:** `cycles.is_current` (open ⇒ `CURRENT_DATE`; closed ⇒ `cycle_end`). **No date literal.**
- **Event-type set:** `{geral, kickoff, tribo, lideranca}` only.
- **Emit:** fraction 0..1 ROUND 2; `NULL` when zero eligible events. Cohort aggregate = **AVG-of-member-rates**.
- **Live:** cohort=37 operational → **76.2%**. Per-tribe: tribe2 51.7% · tribe7 75.0% · tribe6 77.9% ·
  tribe8 79.4% · tribe4 88.4% · tribe1 90.7% · tribe5 92.7%.

### 2.2 RELIABILITY — *Confiabilidade de registro* (ops diagnostic)

- **Question:** when a roll **was** taken about this person, did they show up?
- **Denominator:** events with a **recorded** non-excused row (`a.id exists AND excused IS NOT TRUE`).
  *(There is no `attendance.status` column live — both metrics operate on the `present`/`excused` pair.)*
- **Numerator:** `present = true`. **Excused** removed from both sides (neutral).
- **Backed by:** the already-shipped `get_attendance_rate` (migration `20260805000065`) — **+ event-type
  scope added** in PR6 so it shares `{geral,kickoff,tribo,lideranca}` with engagement and can converge.
- **Live:** avg 99.1%, min 89.5%, **32/37 at exactly 100%** — structurally near-100% until roster sealing.
- **Visibility (D10):** member-about-themselves + admin-about-a-member **only**, **always with raw
  present/absent/excused counts**. **Never** a public/headline KPI until `seal_event_attendance` coverage
  is real (enforced by a PR10 contract hard-gate).

### 2.3 Clarity (the PM ask)

The two words self-distinguish: **"Participação"** answers *"did people show up to what they committed
to"* (the truth, audience-facing); **"Confiabilidade de registro"** answers *"is our roster data
trustworthy"* (the ops diagnostic). Reserving the plain word *Presença/Participação* for engagement and
giving reliability the explicit qualifier is what resolves the ambiguity. **Banned:** labelling the bare
99.1% recorded number as "Taxa de Presença".

---

## 3. Grounding (embasamento)

- **ITT vs per-protocol (clinical trials):** recorded-denominator reliability is the *per-protocol*
  analogue (conditions on complete data → systematically over-states). Engagement is the *intention-to-treat*
  analogue (everyone expected; missing = failure) — the literature's gold-standard honest endpoint.
- **Education chronic-absenteeism / ADA:** denominator = days **enrolled/expected**; schools are *required*
  to record an absence, not just a presence. Direct precedent for both (a) headlining the expected-denominator
  participation rate and (b) the **seal-the-roster / materialize-absent-row** fix.
- **PMI chapter / volunteer bylaws:** participation requirements ("missing 3 consecutive *scheduled* meetings
  = deemed resigned") count against the **scheduled** roster, not roll-taken meetings.
- **CHAOSS (OSS community health):** explicitly treats a near-100% "of those who showed up, they showed up"
  figure as a **non-metric** / data-hygiene indicator, distinct from activity/engagement.
- **AAPOR survey standards / gym no-show analytics:** never report a bare rate without its eligible-contact
  denominator + completeness disposition; count booked-but-no-show against the member (the booking is the roster).

**Recommendation:** ship engagement **now** as the headline; **gate reliability behind absence capture**
(the `seal_event_attendance` track). Until sealing is real, reliability is admin/self-only, always with raw
counts. Once sealing materializes absent rows, reliability and engagement **converge** and reliability becomes
a meaningful "of your sealed roster, % present".

---

## 3b. CANONICAL ELIGIBILITY PRINCIPLE (PM ratified 2026-05-29 — prerequisite for ALL future metrics)

**`public._attendance_eligible_events(member, cycle_start)` is the SINGLE source of attendance eligibility.**
It is **type-based**: candidate events are `{geral, kickoff, tribo, lideranca}` in the `cycles.is_current`
window (open ⇒ `CURRENT_DATE`); per-member scoping is `geral/kickoff` → all operational; `tribo` → own tribe
via `get_member_tribe` (resolved through `initiatives.legacy_tribe_id`); `lideranca` → `can_by_member('manage_event')`.

**No surface may reintroduce a parallel eligibility model** — specifically NOT the tag-based one
(`general_meeting`/`tribe_meeting` via `event_tag_assignments`) nor the `event_audience_rules` /
`is_event_mandatory_for_member` one. Both were live and produced a **divergent** global number (panel operational
avg **70.5%** vs the canonical **76.2%**) because the two models select different candidate events (tag-set vs
type-set — e.g. ~10 events carry the `general_meeting` tag vs 14 of type `geral/kickoff/lideranca`) and scope
eligibility differently (audience-rules + curator exclusion vs per-member type eligibility). **Decision (Option B):**
type-based wins — simplest, least maintenance, self-consistent, already shipped on 5 surfaces. PR7 converged the
last hold-out (`get_attendance_panel`, the 3 consumers home-widget/workspace/ranking) onto it (measured **70.5 →
76.2**, now == home `calc_attendance_pct` 76.2 == `engagement_global` 76.19; Roberto Macêdo, a curator the old panel
excluded, **0 → 22.2** consistent with his home/member-detail) and dropped the orphan `get_attendance_summary`. The
**PR10 p175 gate** forward-defends this principle (no new tag/audience-rule attendance eligibility in any RPC). The
richer `event_audience_rules` precision is parked as a possible *future* enhancement only after a data-quality audit
of rule + tag coverage — never as a second live model.

---

## 4. RPC architecture

| Primitive | Status | Role |
|---|---|---|
| `_attendance_eligible_events(p_member_id, p_cycle_start)` → TABLE | **NEW** (BLOCKER) | the **single** eligibility source; consumed by both engagement RPCs **and** `seal_event_attendance` |
| `get_attendance_rate(p_member_id, p_cycle_start)` → numeric | **exists** (`…65`); **converges** PR6 | RELIABILITY per-member (+ add type-scope, − remove `'2026-03-01'` fallback) |
| `get_attendance_reliability_summary(p_scope, p_scope_id, p_cycle_start)` → jsonb | **NEW** | RELIABILITY aggregate `{cohort_n, avg_rate, present/absent/excused totals, coverage_flag}` |
| `get_attendance_engagement_rate(p_member_id, p_cycle_start)` → numeric | **NEW** | ENGAGEMENT per-member |
| `get_attendance_engagement_summary(p_scope, p_scope_id, p_cycle_start)` → jsonb | **NEW** | ENGAGEMENT aggregate; replaces 4 divergent inline aggregates |
| `seal_event_attendance(p_event_id)` + `events.roster_sealed_at` | **NEW** (separate track) | materializes absent rows for eligible no-shows; reliability-honesty precondition |

All: `STABLE`/`VOLATILE` `SECURITY DEFINER`, pinned `search_path`, **REVOKE anon/authenticated + GRANT
service_role**. Eligibility: `geral/kickoff`→all operational; `tribo`→own tribe via `get_member_tribe`
resolved through **`initiatives.legacy_tribe_id`** (events has **no** tribe column); `lideranca`→
`can_by_member('manage_event')`. Hybrid delegation to `is_event_mandatory_for_member` where
`event_audience_rules` exist (284 events live).

---

## 5. Surface → metric map (11 surfaces, by impact)

| # | Surface | Metric | antes → depois |
|---|---|---|---|
| 1 | **Home hero** (`calc_attendance_pct`→`get_annual_kpis`) | **Engagement** "Presença / dos encontros esperados" | **64.4% → 76.2%** (64.4 was a buggy hybrid) |
| 2 | `/attendance` ranking (`get_attendance_panel`) | Engagement headline + own-reliability w/ counts | engagement ~76% |
| 3 | `tribe/[id]` KPI (`exec_tribe_dashboard`) | Engagement | tribe2 ~99%→51.7%, tribe5→92.7% |
| 4 | tribe gamification (`get_tribe_stats`) | Engagement | honest engagement |
| 5 | admin index (`get_admin_dashboard`/`get_kpi_dashboard`) | Engagement headline + reliability drill-down | ~76.2% |
| 6 | admin cross-tribe (`exec_cross_initiative_comparison`) | Engagement (remove `Math.min` clamp) | ~76.2% |
| 7 | cycle/chapter reports (`exec_cycle_report`/`get_chapter_dashboard`) | **Both** + raw counts; fix 90-day window | quantify D9 cascade |
| 8 | `initiative/[id]` | Engagement; delegate via `resolve_tribe_id`; native → N/A | aligns w/ tribe |
| 9 | admin member detail (`get_member_detail`) | **Both** per-member; **fix 3 bugs** | both shown |
| 10 | `get_attendance_summary` (leader) | Engagement; D9 weighting decision | per D9 |
| 11 | `get_attendance_panel` dropout C+B | keep richer `event_audience_rules` model (D7 hybrid) | no downgrade |

**Out-of-scope (named, not silent):** `get_my_attendance_history`, `get_my_tribe_attendance`, weekly digests
→ fast-follows; `*_attendance_hours` → metric-2 (hours, not rate); `get_event_attendance_health` = reliability
by nature (relabel); `get_public_impact_data` (LGPD-public, hardcoded `'2026-03-01'`) → **PR2 sibling**;
`detect_and_notify_detractors` → reconcile with seal track.

---

## 6. Business-rule decisions — **PM ratification needed**

> Recommended defaults in **bold**. The three marked 🚦 **gate the headline PR2** (they move the number).

| # | Decision | Recommended default | Why |
|---|---|---|---|
| **D1** 🚦 | Excused in engagement denominator | **A — removed (neutral)** → 76.2% (vs B counts → 70.9%) | both metrics treat excused identically; org-sanctioned absence shouldn't penalize a recognition KPI |
| **D2** | Cohort + averaging | **37 operational union (curator kept) + AVG-of-rates** | 39=incl. guests; 34=wrongly drops a manager who is also curator; AVG-of-rates is the §7 rule |
| **D3** | `lideranca` eligibility | **`can_by_member('manage_event')`** + drop phantom `deputy_manager` | single V4 authority basis; 8≡8 capability/role today (0 change) |
| **D4** 🚦 | `tribo` eligibility + NULL-tribe | **own-tribe only; org-manager excluded from tribo dim; fix the bridge bug** | blast radius = **8** holders not 2; Roberto Macedo is a live bridge bug to fix before convergence |
| **D5** | 1on1 events | **Exclude** | coaching artifact, no roster; only `calc_pct` counts it |
| **D6** | evento_externo / comms | **C — exclude; keep comms branch dormant** | neither type exists live |
| **D7** | Eligibility source | **C — hybrid: delegate to `is_event_mandatory_for_member` where rules exist** | preserves panel's 284-event richness; avoids downgrade |
| **D8** 🚦 | Point-in-time eligibility (joiners/changers) | **A — as-of event date, but ship OFF/parameterized until ratified** | fairness for late joiners; `created_at` proxy is useless (all 37 = 2026-03-05) |
| **D9** | `get_attendance_summary` 0.4/0.6 weighting | **A — drop to flat present/expected** | hidden product call; cascades into `exec_cycle_report` |
| **D10** | Reliability visibility + window | **B — member-self + admin-only, mandatory raw counts; public BANNED until seal; open⇒CURRENT_DATE/closed⇒cycle_end, no literal** | resolves the self-contradiction; PR10 hard-gate enforces |

---

## 7. Phased plan (11 PRs, smallest-blast-radius first)

1. **PR1 — Foundation** (additive, 0 number change): `_attendance_eligible_events` + `get_attendance_engagement_rate` + `get_attendance_engagement_summary` + `get_attendance_reliability_summary`. Excused **parameterized** (no unratified default baked). Contract test asserts live cohort_n=37 + engagement 75-77% + no `deputy_manager`/`events.tribe`/date-literal.
2. **PR2 — Home hero** 🚦 (gated on D1+D4+D8): `calc_attendance_pct` → engagement summary; **also fix `get_public_impact_data`** literal. **64.4% → 76.2%** + changelog explaining 64.4 was buggy.
3. **PR3 — Tribe surfaces:** `exec_tribe_dashboard` + `get_tribe_stats` → engagement; remove both `LEAST(…,1.0)` guards + kickoff-ILIKE window.
4. **PR4 — Admin + cross-tribe:** `get_admin_dashboard`/`get_kpi_dashboard`/`exec_cross_initiative_comparison`; remove `Math.min` clamp.
5. **PR5 — Reports:** `exec_cycle_report` + `get_chapter_dashboard` show both; fix 90-day window + type filter + `count(a.id)`-as-attended; quantify D9 cascade.
6. **PR6 — Member-detail + grid + reliability type-scope:** fix `get_member_detail`'s 3 bugs; converge `get_attendance_rate` (add type-scope, drop literal); sem-dados machinery scoped to reliability only.
7. **PR7 — Summary + panel:** `get_attendance_summary` → flat engagement; panel keeps richer model (D7).
8. **PR8 — Completeness fix:** retire/repoint the **live-broken** `get_dropout_risk_members` (references nonexistent event types → flags nobody) + migrate `HomepageHero`/`DropoutRiskBanner`. **✅ SHIPPED** (migration `20260805000075`): repointed onto canonical `_attendance_eligible_events` (8-col shape + `p_threshold` + `manage_event` gate preserved); **EXCUSED treated as neutral** (extends D1 — an org-sanctioned absence must not flag a dropout risk; the old body wrongly counted it as a miss). Measured antes→depois (threshold 3): **0 → 4 flagged**. Folded the home-hero dead-read (`get_attendance_panel.tribe_events_count`/`tribe_total` → real `tribe_mandatory`). Deferred to a PR8b fast-follow (still #420): AttendanceGrid engagement headline + `/attendance` designation filter reading a non-existent panel column.
9. **PR9 — ADR-0100 revision** (no code): two dictionary rows + 4 primitives + 10 §7 rules + the antes→depois record.
10. **PR10 — p175 gate extension:** forward-defense regex (no inline rate re-impl) + visibility hard-gate + grant ladder.
11. **PR11 — Seal track** (separate): `events.roster_sealed_at` + `seal_event_attendance`; coordinate `sync_attendance_points` (no XP for sealed absents) + `detect_and_notify_detractors`. Only after real coverage may reliability be promoted to a shown indicator.

---

## 8. Key risks / findings (review-caught)

- **Number moves on convergence** (home 64.4→76.2): ship PR2 with a changelog ("64.4 was a buggy hybrid").
- **NULL-tribe correctness hole** (biggest): Roberto Macedo has `tribe_id=8` but `get_member_tribe=NULL` (no active engagement on the tribe-8 initiative) → **bridge bug, fix before convergence** or his tribo rate is wrong.
- **Blast radius = 8 not 2** (D3+D4 affect all `manage_event` holders).
- **Dead dropout banner:** `get_dropout_risk_members` is live-broken today.
- **`get_member_detail` has 3 bugs** (count-any-row as attended; silent third denominator; `att.id IS NOT NULL` as present).
- **Drift recurrence:** 6+ `CREATE OR REPLACE` convergences → PR10 gate + SEDIMENT-269.A md5-diff every payload + `apply_migration` not `execute_sql`.
- **Reliability-as-vanity:** the 99.1% must never headline before sealing (PR10 hard-gate).

---

## 9. Provenance

Multi-agent workflow `wf_892717cf-416` (8 agents, ~1.07M tokens): 3-agent parallel discovery (surface map +
definitional inputs + grounding) → design synthesis → 3-lens adversarial review (product/business-rule +
technical/data + completeness) → revision incorporating all must-fixes. Every live number re-verified in the
revision pass. Cross-ref: ADR-0100, `docs/audit/METRIC_DISPARITY_AUDIT_2026-05-28.md`, migrations
`20260805000064` (D6/D12) + `20260805000065` (reliability primitive, shipped).
