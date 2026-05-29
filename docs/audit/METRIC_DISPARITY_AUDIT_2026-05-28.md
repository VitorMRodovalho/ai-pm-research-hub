# Cross-Surface Metric / Data Disparity Audit — 2026-05-28

**Scope:** Every indicator, chart, KPI, badge, ranking and table rendered on the
Núcleo IA surfaces the PM named — **Home**, **Gamification menu** (`/gamification`,
`/ranks`, `/rank`), **Tribe detail** (`/tribe/[id]`), **Initiative detail**
(`/initiative/[id]`), **Attendance + tribe-event** (`/attendance`), and **Admin**
(`/admin/*`) — cross-referenced against the **live** RPC bodies feeding them, across
access tiers (anon/ghost · member · leader · curator · GP/admin).

**Method:** 13-agent orchestration (6 surface mappers → live RPC source-of-truth tracing
via `pg_get_functiondef` → adversarial synthesis). Every load-bearing claim was
independently re-verified against the live database (project `ldrfrvwhxsmgaabwmaik`) and
the migration files by a second reviewer, which corrected three severities (see
**Reviewer amendments**).

**Root cause (Bucket B):** every metric is re-implemented inline in every RPC. The only
shared primitive that exists (`get_impact_hours_canonical`) is consumed by exactly **one of
the five** RPCs that report hours, and a looser parallel view (`impact_hours_summary`)
coexists. This is the same class of drift the p175 body-drift gate was built to fight.

---

## Verdict & two-bucket remedy

The PM's "audit disparities" framing is the right **diagnostic** but the wrong **remedy**
for the systemic findings. Split the work:

- **Bucket A — fix now as discrete defects** (security / consent / correctness). **SHIPPED
  2026-05-28** — see *Resolution* below.
- **Bucket B — systemic metric forks.** Do **not** fix finding-by-finding (13 inline tweaks
  re-drift within a few sessions — p175 history proves it). Adopt a **metric-dictionary ADR
  + ~6 canonical SQL views** instead → **ADR-0100**.

---

## Metric matrix (where definitions diverge)

| Metric | Surfaces | Divergence |
|---|---|---|
| **Active members** | Home (hero+platform), Admin index, Admin report, Admin chapter, Admin chapter-report, Platform Health | ~5 predicates: `is_active ∧ current_cycle_active` (home/admin) vs `is_active`-only (cycle_report, platform_usage) vs `member_status='active'` enum (chapter dash) vs `current_cycle_active`-only (chapter-report) |
| **Impact hours** | Home hero+KPI, Attendance KpiBar, Admin index/report/chapter/chapter-report | 4 live formulas: homepage (incl excused, 60-min fallback, ROUND 0) vs canonical (excl excused, ROUND 1) vs chapter (`duration_minutes`-only, all-time) — GP↔Sponsor headline disagrees across 3 surfaces |
| **Attendance rate %** | Home hero, Attendance ranking+grid, Tribe/Initiative KPI+tab, Admin cross-tribe/twin/chapter/member-detail | 6+ formulas: denominator (mandatory-tagged vs present+absent vs members×events vs per-event-binary), unit (fraction vs %), excused handling, rounding (0/1/2dp), present-detection (`present=true` vs `a.id IS NOT NULL`) all fork |
| **Tribe/initiative member count** | Tribe header+KPI, Initiative header+KPI, Admin cross-tribe/twin | 4+ paths: engagement-rows-incl-observers vs distinct persons vs legacy `tribe_id` vs volunteer-kind-only vs client `membersMap.size` |
| **Lifetime/cycle XP + rank** | Gamification (3 variants), Tribe/Initiative, Admin member-detail/report, MCP self-tool | XP via `gamification_rules` JOIN vs raw category strings vs `cpmai_prep` namespace; rank ordered on **lifetime** XP even in "Ciclo Atual" mode; pool + tiebreak differ per surface |
| **Trail completion** | Home, Gamification, Tribe/Initiative, Admin report | dynamic `is_trail` count vs hardcoded `TRAIL_TOTAL=6`; native initiatives hardcode `0%` |
| **CPMAI certified** | Admin index/report/chapter/chapter-report, Tribe/Initiative | distinct-per-cycle vs count-all-time vs `members.cpmai_certified` boolean vs cert-coverage fraction |
| **Per-event attendee count** | Attendance card, roster modal, Tribe/Initiative timeline | card counts ALL attendance rows (incl absent/excused); roster + timeline count `present=true` |
| **Events count** | Home platform, Attendance KpiBar, grids, Platform Health | YTD-literal-2026 vs calendar-YTD (mislabeled "Ciclo 3") vs cycle-scoped vs all-time |

(Full per-appearance matrix with the exact source RPC + definition + scope + tier for each
cell is in the workflow output; condensed here for readability.)

---

## Bucket A — fix-now defects (SHIPPED 2026-05-28)

| ID | Sev | Finding | Status |
|---|---|---|---|
| **D2** | 🔴 **CRITICAL** | `get_attendance_panel` — SECDEF + **GRANT EXECUTE to anon** + no in-body auth → unauthenticated callers read every active member's attendance % + `dropout_risk` flag + behavioral typology. | ✅ gated: require active member; mask `dropout_risk`/`typology` to leadership (`manage_event`) or self; ranking preserved. |
| **D1** | 🔴 High (consent) | `get_public_leaderboard` + `get_public_trail_ranking` ignored `gamification_opt_out` (ADR-0050) → opted-out members shown by name to anon. | ✅ `AND m.gamification_opt_out = false` added (matches `get_gamification_leaderboard`). |
| **D3** | 🔴 High | `get_global_research_pipeline` (author PII) had no in-body auth; `get_initiative_attendance_grid` native path had no scope check. | ✅ pipeline gated `manage_platform`; native grid mirrors tribe grid (`manage_member`/`manage_partner`/own-engagement). |
| **XP** | 🟠 Med-high | `get_member_cycle_xp` (MCP `get_my_xp_and_ranking`) — arbitrary `p_member_id`, `authenticated` grant → enumerate any member's XP/rank. | ✅ gated self-or-`view_pii`. |
| **D14** | 🟠 High (dead) | `get_dropout_risk_members` uses EN event-type tokens (`general_meeting`…) but live `events.type` is 100% PT → Home dropout alert returns **empty always**. | ⏳ tracked (Bucket A follow-up issue) — vocabulary normalization. |
| **D6-bug** | 🟡 Med | `get_attendance_grid` detects present via `a.id IS NOT NULL` not `present=true` (~4.5% rows mis-promoted live). | ⏳ tracked. |
| **D12** | 🟡 Med | `get_events_with_attendance` "N presentes" counts ALL rows (incl absent/excused). | ⏳ tracked. |
| **D10** | 🟡 Risk | `exec_portfolio_health` hardcoded `cycle3-2026` default won't track `cycles.is_current`. **Reviewer downgrade:** "bars show prior cycle" is UNVERIFIED — live `cycles.is_current = cycle_3`; `cycle3-2026/4-2026` are a separate (selection/portfolio-target) namespace. Treat as maintainability risk; confirm the live portfolio-target cycle before acting. | ⏳ tracked (needs confirmation). |

### Resolution (the four leaks)
Migration **`20260805000055_p276_bucket_a_lgpd_auth_hardening.sql`** — six same-signature
`CREATE OR REPLACE` (no DROP, no consumer break). Live smoke (`SMOKE_ALL_PASS`):
- anon/no-auth `get_attendance_panel` → **0 rows**; `get_global_research_pipeline` →
  `Unauthorized`; `get_member_cycle_xp` → raises.
- manager: full panel + `dropout_risk` for all + pipeline + native grid all work.
- researcher: ranking preserved, **0 other-member `dropout_risk`** (no leak), pipeline
  blocked, own XP works, other-member XP blocked.

Contract test: `tests/contracts/p276-bucket-a-lgpd-auth-hardening.test.mjs` (14 static +
4 DB-gated; forward-defense locks the opt-out clause, the anon gate, and the pipeline gate).

> Note: today **0 active members are opted-out**, so D1 has no visible effect yet — it is
> forward-defense restoring the consent mechanism. `manage_partner` is broad
> (researchers hold it), so the initiative grid mirror is mostly consistency + own-engagement
> semantics; tightening `manage_partner` is a separate cross-cutting decision.

### Attendance-ranking visibility — RESOLVED (model C+B, shipped 2026-05-28)

The open product/privacy question ("should the combined-% ranking show all members' % to every
authenticated member?") was decided by the PM: **model C+B**, migration
`20260805000056_p277_attendance_ranking_visibility_cb.sql`.

- **C:** a non-privileged caller now gets **only their own row** + an **anonymous cohort
  aggregate** (`cohort_avg_pct`, `cohort_percentile`, `cohort_size`) — no peer names/%. Leadership
  (`manage_event`) + GP keep the full nominal ranking. This **completes D2**: without other
  members' raw `combined_pct`, the `< 50` dropout-risk flag can no longer be re-derived by eye.
- **B:** the gamification opt-out keeps its XP-leaderboard meaning; leaders intentionally retain
  operational attendance visibility (legitimate interest), so opt-out does not blind a leader.
- The aggregate is computed from the existing `computed` CTE — **no new inline attendance
  formula** (ADR-0100 discipline). The leftover anon/PUBLIC execute grant was revoked. The
  `/attendance` Ranking tab renders a private "sua presença" standing card for rank-and-file.
- LGPD basis: data minimization (Art. 6 III) — members keep the motivational signal (own % vs
  anonymous cohort) without seeing any third party's personal attendance datum.

---

## Bucket B — systemic forks (→ ADR-0100)

D4 (impact_hours ×4), D5 (active_members ×5), D6/D7 (attendance_rate / member_count forks),
D8/D9 (XP rank/pillar forks), D15/D18 (V4 tribe-bridge dual-source: `get_initiative_stats`
delegates to `get_tribe_stats` but `get_initiative_members`/`_events_timeline` do **not**, so
a bridged page mixes two tables' math), D11/D13/D16/D17 (hardcoded "Ciclo 3" labels,
`eligible_count` per-event-vs-scalar, public-vs-member leaderboard shape, native-initiative
`0%`/`#—` stubs that read as real data).

**Remedy:** see **ADR-0100 — Canonical Metric Definitions**. Define each cross-surface metric
once (predicate + window source = `cycles.is_current`, never hardcoded + excused/present
handling + rounding + LGPD opt-out rule per tier); back it with `v_active_members`,
parameterized `get_impact_hours_canonical`, `get_attendance_rate`, `v_tribe_roster`
(resolving `tribe_id` ↔ engagements per ADR-0005), and one pillar helper on
`gamification_rules`; migrate one metric per PR; extend the p175 gate with a
"no inline re-implementation of a canonical metric" forward-defense.

---

## Tier / LGPD matrix findings

1. **Opt-out enforced inversely to risk:** honored on the member tier
   (`get_gamification_leaderboard`, `get_champions_ranking`) but **absent** on the anon/public
   tier (`get_public_leaderboard`, `get_public_trail_ranking`) and on
   `tribe`/`initiative_gamification` + `cpmai` — the lowest-trust surface was the least
   protected (D1; public RPCs fixed; the tribe/initiative/cpmai variants remain as
   Bucket B tier carve-outs to document).
2. **Opt-out suppresses nothing in attendance** anywhere.
3. **4 ungated SECDEF RPCs** relied on client guards (not a boundary): `get_attendance_panel`
   [anon!], `get_global_research_pipeline`, `get_initiative_attendance_grid` native path,
   `get_member_cycle_xp` — **all fixed in Bucket A**.
4. **UI-gate vs RPC-gate asymmetry** on Gamification certificate tabs (curator denied in UI
   but authorized at RPC; comms_leader sees bulk panel but RPC requires `manage_platform`) —
   documented; not yet reconciled.
5. **Correct by design:** anon/ghost denied on gated routes; chapter-scope downscopes
   correctly; the Attendance Grid suppresses Detractor/At-Risk for `chapter_board`; admin
   reads bypass opt-out deliberately (should be documented as a carve-out, not silent drift).

---

## Reviewer amendments (live-verified)

- **D2 → CRITICAL** (was high): `get_attendance_panel` is anon-granted (ACL `anon=X`), so the
  dropout-risk leak was reachable **without authentication**.
- **`get_member_cycle_xp` added to Bucket A** as a 4th ungated SECDEF (synthesis had treated it
  only as a rank-math issue).
- **D14 confirmed dead, not conditional**: live `events.type` is 100% Portuguese tokens → the
  EN-token `get_dropout_risk_members` matches zero rows today.
- **D10 over-stated → downgraded**: `cycles.is_current = cycle_3` live; the
  `cycle3-2026/4-2026` codes are a different namespace. Reframed as a hardcoded-default
  maintainability risk pending confirmation.
- **False positive noted**: `get_homepage_stats.members` vs `get_public_platform_stats` use the
  identical `is_active ∧ current_cycle_active` predicate — cannot disagree today (latent
  maintainability concern, not a live disparity).

---

## Provenance

Workflow run `wf_e008b3d8-e12` (task `w12k6vhgq`). Memory:
`memory/project_metric_disparity_audit_2026_05_28.md`. Bucket A migration
`20260805000055`. Bucket B design: `docs/adr/ADR-0100-canonical-metric-definitions.md`.
