# SPEC #419 metrics 4-8 — Canonical Metrics Convergence (ADR-0100)

> **Status:** PM-ratified design (2026-05-31). The four open dictionary decisions were ratified this
> session (see §0.2). Implementation lands one metric per PR, smallest blast radius first (§9).
> **Program:** #419 / ADR-0100 canonical-metrics. Mirrors the structure + rigor of
> `docs/specs/SPEC_419_M3_ATTENDANCE_TWO_METRIC.md`.
> **Grounding:** Every "antes" number carries the exact SQL + live result, all queried against project
> `ldrfrvwhxsmgaabwmaik` on **2026-05-31** (cycle `cycle_3`, `cycle_start=2026-03-01`, `cycle_end=NULL`
> ⇒ open cycle, upper bound = now). Numbers were produced by an 11-agent design+adversarial-verify
> workflow (`wf_6c1ee407-948`) and **re-grounded in the main loop** before this SPEC was written
> (the project hard grounding rule: a number entering a SPEC must come from a live tool result this turn).
> Where the workflow map was refuted by its own verify pass or by re-grounding, the corrected value is used
> and flagged.

---

## 0. Summary

### 0.1 The five metrics + their headline live disparity

| Metric | The fork (live, today) | Canonical fix |
|---|---|---|
| **4 — member_count / tribe_roster** | tribe-8 shows **5** (`exec_tribe_dashboard`, kind='volunteer' drops curator Roberto) / **6** (`get_tribe_stats`, canonical) / **7** (`get_weekly_tribe_digest`, `current_cycle_active` alone adds offboarded Maria) | DISTINCT person with an **active, non-observer ROLE** engagement on the resolved initiative; one primitive `v_initiative_roster` + `get_initiative_roster_count()` |
| **5 — XP rank / pillar** | cycle-mode rank is ordered on **lifetime** XP: the #1 cycle earner (Marcos, 425 cycle XP) shows at **rank 14-15**; ties are non-deterministic (Fernando 415 = Débora 415); **46 of 49** pooled members reorder once fixed | `get_xp_rankings(mode)` (cycle-mode orders on cycle XP, deterministic `member_id` tiebreak) + pillar via the `gamification_rules.slug=category` JOIN (100% live coverage) |
| **6 — trail_completion + cpmai** | trail: home **44** (binary "all-6", hardcoded `/6.0`, cohort 37 incl. 2 guests) vs ranking **46.66** (partial-credit avg, cohort 35, dynamic total). cpmai: **wall=2 / meta=1** conflated | trail = partial-credit avg over a **shared** cohort with **dynamic** is_trail total; cpmai goal-metric = certified **in the goal year** (boolean + year window), wall = all-time |
| **7 — champions (#424)** | dual-written ledger (`champions_awarded`) + projection (`gamification_points` pillar='champions') with **no parity invariant**; award UI blocked to tribe leaders | `champions_awarded` ledger canonical, projection derived; parity invariant + contract test; **frontend-only** unblock (backend already authorizes leaders) |
| **8 — webinars** | webinars **table = 7** vs `events WHERE type='webinar'` = **4** | count the `webinars` table (architectural source of truth, CLAUDE.md decision #4) |

### 0.2 PM-ratified decisions (2026-05-31)

- **D-M6-CPMAI (goal-metric source):** the cpmai goal metric counts people who **certified during the
  goal year (2026)** — `members.cpmai_certified = true AND cpmai_certified_at` within the goal year. A member
  who entered already holding CPMAI (cert dated before the goal year, e.g. Pedro, 2025-10-23) appears on the
  **certificate wall (mural)** but **NOT** in the goal metric. Same rule for any future entrant whose cert
  predates the goal year. **This is a PMI-GO-board-pactuated business rule** — it is the reason the source is
  the dated boolean, not the gamification ledger and not a date-free count.
- **D-M7-SOURCE (champions canonical):** `champions_awarded` ledger is canonical; `gamification_points`
  pillar='champions' is a **derived projection**. (3 of 4 surfaces already read the ledger.)
- **D-M7-UNBLOCK (award path):** widen the award path to tribe leaders, **own-tribe scope**. **Refinement
  from live grounding (§M7.4):** the backend *already* authorizes this — the only missing piece is the
  tribe-page award UI; no grant/seed change is needed.
- **D-M6-TRAIL (trail metric shape):** canonical = **partial-credit average** over a **shared** cohort with a
  **dynamic** is_trail total (native initiatives → `N/A`, never `0%`). Home's binary "all-6 %" is retired in
  favor of the partial-avg so home and the ranking finally show the same number.

### 0.3 Two open (smaller) decisions surfaced by grounding — recommend-and-proceed

- **D-M4-AXIS** (Metric 4): reconcile `get_member_tribe` (the **shipped metric-3** cohort resolver + the
  `exec_tribe_dashboard` cross-tribe auth gate) onto the role axis? It filters `kind='volunteer'` (the wrong
  axis) and returns **NULL for the curator Roberto** despite his active tribe-8 engagement. **Recommend:**
  change to `role <> 'observer'` (PR-F, isolated, re-smoke metric-3 cohort_n before/after). If the PM prefers
  metric-3 frozen, document the KIND-vs-ROLE divergence in ADR-0100 instead.
- **D-M8-COMPLETED** (Metric 8): the `webinars` table has **no `done`/`completed` status** (statuses live =
  `planned`,`confirmed`); all 7 rows are past-dated. **Recommend:** "realized" = `scheduled_at < now()` (=7
  today), which is robust to the missing status enum; alternative is all-rows (=7 today, identical) or
  `status='confirmed'` (=3).

---

## 1. Window + cohort invariants (apply to all five)

1. **Window source = `cycles.is_current`, never a literal.** Live: `cycle_3`, `2026-03-01`, end `NULL`
   (open ⇒ upper bound = now). **Kill the `'2026-01-01'` fallback** in `get_member_cycle_xp` (M5).
   `gamification_points` has **no `cycle_id`** column — cycle windowing is strictly by `created_at`.
2. **Roster window = an active engagement** (M4). `engagements` has no `cycle_id`; `status='active'` *is* the
   current-cycle cohort. `members.current_cycle_active` is a different, drifting gate (it is the digest's
   over-count root).
3. **Filter on ROLE, not KIND** (M4/M7). `role <> 'observer'` is canonical; `kind='volunteer'` is the bug that
   drops the curator.
4. **Pillar bucketing via the `gamification_rules.slug = gamification_points.category` JOIN** (M5/M7), keyed on
   `(organization_id, slug)`. Live coverage is **100%** (0 of 19,910 points unmatched; 20 distinct categories;
   6 pillars: certificacoes, champions, curadoria, presenca, producao, trilha). Retire raw category-string lists.
5. **Rank order must match the displayed mode** (M5). Cycle view ranks on cycle XP; lifetime view on lifetime.
   Deterministic tiebreak = `member_id ASC` everywhere.
6. **No persisted gamification rank table** — all rank is read-time. `recalculate_cycle_rankings` /
   `calculate_rankings` are **admissions/selection** ranking, NOT gamification — never touched for #419.

---

## §M4. Metric 4 — tribe_roster / member_count

### M4.1 Problem
One conceptual quantity — "how many active members are in this tribe/initiative" — renders **three different
live numbers** for tribe 8, plus a client-side fourth:

- **5** — `exec_tribe_dashboard` / `TribeDashboardIsland.tsx` KPI. Predicate `kind='volunteer'` EXISTS, which
  **wrongly drops the curator Roberto Macêdo** (`role='curator'`, `kind='observer'`).
- **6** — `get_tribe_stats`, `get_initiative_stats`, `get_tribe_gamification`, admin cross-tribe. The canonical
  value, but each reaches it via a different path (`members.tribe_id`, engagement rows…) that only coincides today.
- **7** — `get_weekly_tribe_digest.aggregates.active_members`. Predicate `current_cycle_active` alone, which
  **wrongly adds the offboarded Maria Luiza** (`is_active=false`, `current_cycle_active=true`, tribe-8 engagement
  `status='offboarded'`).
- **(client)** — `tribe/[id].astro` header badge reads `membersMap.size`; the same page's stats card reads the
  RPC `member_count` — two counts on one page.

**Root trap — ROLE vs KIND.** `role` and `kind` are independent axes. Canonical filters on **role**
(`role <> 'observer'`); the broken surfaces filter on **kind**. Roberto passes the role filter (counted) but
fails the kind filter (dropped).

### M4.2 Canonical definition
> **member_count / tribe_roster** = `COUNT(DISTINCT engagements.person_id)` for the resolved initiative WHERE
> `engagements.status='active' AND engagements.role <> 'observer'`.

- **Bridge (ADR-0005):** tribe → initiative via `initiatives.legacy_tribe_id = tribe_id`.
- **Window:** an active engagement *is* the current-cycle cohort (no `cycle_id` exists).
- **Unit:** integer.
- **Opt-out:** the aggregate count tallies opt-out members (a count, not PII); **named** rosters mask opted-out
  identity to non-`view_pii` viewers (forward-defense; 0 opted-out in tribe 8 today).

### M4.3 Antes (VERIFIED live — tribe 8, initiative `9cbaf0b9-de4d-4e40-8375-5767cc97a9a4`)

| # | Quantity | Value | SQL |
|---|---|---|---|
| A | DISTINCT person, `status='active'`, `role<>'observer'` = **CANONICAL** | **6** | `SELECT count(DISTINCT e.person_id) FROM engagements e JOIN initiatives i ON i.id=e.initiative_id WHERE i.legacy_tribe_id=8 AND e.status='active' AND e.role<>'observer';` |
| B | DISTINCT person, `status='active'`, `kind='volunteer'` = `exec_tribe_dashboard` total **[UNDER-COUNT: drops curator]** | **5** | same, `… AND e.kind='volunteer'` |
| C | `members.tribe_id ∧ current_cycle_active` = digest `active_members` **[OVER-COUNT: adds offboarded]** | **7** | `SELECT count(*) FROM members WHERE tribe_id=8 AND current_cycle_active=true;` |
| D | `members.tribe_id ∧ is_active` | **6** | `SELECT count(*) FROM members WHERE tribe_id=8 AND is_active=true;` |
| E | `members.tribe_id ∧ is_active ∧ current_cycle_active` = `get_tribe_stats` | **6** | `… AND is_active AND current_cycle_active;` |

Cross-tribe (live): `members.tribe_id`-active equals canonical role-nonobserver for **all 8 tribes today**, so
the *visible* fork is the KIND filter (5) and the cycle-flag filter (7), not the members-table path. The
members-table path is still structurally wrong (it will drift) but is not today's delta source.

### M4.4 Canonical primitive
```sql
CREATE OR REPLACE VIEW v_initiative_roster AS
  SELECT DISTINCT e.initiative_id, i.legacy_tribe_id, e.person_id,
         e.role, e.kind
  FROM engagements e
  JOIN initiatives i ON i.id = e.initiative_id
  WHERE e.status = 'active' AND e.role <> 'observer';   -- ROLE axis, not kind

CREATE OR REPLACE FUNCTION get_initiative_roster_count(p_initiative_id uuid)
  RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path='public'
  AS $$ SELECT COUNT(DISTINCT person_id)::int FROM v_initiative_roster WHERE initiative_id = p_initiative_id; $$;
```
Reconcile (do not duplicate) the existing tribe↔initiative resolver: the frontend already calls a
`resolve_initiative_id`/`resolve_tribe_id` pair — verify the live signature before adding. Tribe-keyed count =
`get_initiative_roster_count(resolve_initiative_id(tid))`.

### M4.5 Per-surface changes / depois
| Surface | Change | Depois |
|---|---|---|
| `get_tribe_stats` | member_count → roster primitive | 6 (via primitive) |
| `get_initiative_stats` (native) | native count → primitive; bridge branch unchanged | 6 |
| `get_initiative_members` | add `role<>'observer'` + dedup person | rows stay 6 (no role=observer on tribe 8) |
| `exec_tribe_dashboard` | replace ~7 `EXISTS(kind='volunteer')` subqueries with the roster view | **5 → 6** |
| `get_tribe_gamification` / `get_initiative_gamification` | count + avg_xp/cert denominators ride the roster | 6 |
| `exec_cross_initiative_comparison` | per-initiative count → primitive | tribe-8 col 6, canonical all tribes |
| `get_weekly_tribe_digest` | `active_members` → primitive | **7 → 6** |
| `tribe/[id].astro` | header badge → RPC member_count (drop `membersMap.size`) | header + stats single source |
| `get_member_tribe` | **D-M4-AXIS (PR-F, conditional):** `kind='volunteer'` → `role<>'observer'` | Roberto resolves to tribe 8 |

### M4.6 PRs
- **PR4-A** (S, no dep): primitive `v_initiative_roster` + `get_initiative_roster_count` + reconcile resolver. Additive. Contract test: view=6 for tribe-8 initiative; includes curator; excludes a true role=observer.
- **PR4-B** (M, dep A): converge initiative-keyed RPCs (`get_initiative_stats` native, `get_initiative_gamification` native, `get_initiative_members`).
- **PR4-C** (L, dep A): converge tribe-keyed RPCs (`get_tribe_stats`, `exec_tribe_dashboard` 5→6, `get_tribe_gamification`, `get_weekly_tribe_digest` 7→6, `exec_cross_initiative_comparison`).
- **PR4-D** (S, dep B+C): frontend single-source cleanup (tribe header badge).
- **PR4-F** (M, conditional D-M4-AXIS, dep A+B): `get_member_tribe` axis change — touches shipped metric-3 + an AUTH gate; re-smoke metric-3 cohort_n before/after.

### M4.7 Risks
Visible change = **convergence to 6**: dashboard KPI rises 5→6, digest email drops 7→6 (call out in PR body +
digest changelog). `get_initiative_members` gaining `role<>'observer'` is a consumer-break only on an initiative
that has a true role=observer member (none on tribe 8). PR-F changes the dashboard cross-tribe auth gate
(`v_caller_tribe_id = p_tribe_id` fails when NULL) — smoke carefully.

---

## §M5. Metric 5 — XP rank / pillar

### M5.1 Problem
**Cycle-mode rank is computed on LIFETIME XP.** `get_gamification_leaderboard` always
`ORDER BY total_points (LIFETIME) DESC`; `get_member_cycle_xp` ranks via `ROW_NUMBER() OVER (ORDER BY SUM(points)
DESC)` over ALL points with no opt-out filter and no tiebreak (plus a hardcoded `'2026-01-01'` fallback). Four
independent rank paths exist (`get_gamification_leaderboard`, `get_member_cycle_xp`, `get_member_detail` inline,
`get_public_leaderboard`), each with a different pool/tiebreak. Pillar bucketing forks between the canonical
`gamification_rules.slug=category → pillar` JOIN and raw category-string lists.

### M5.2 Canonical definition
- **lifetime_xp** = `SUM(gamification_points.points)` all-time.
- **cycle_xp** = `SUM(points) WHERE created_at >= cycle_start AND (cycle_end IS NULL OR created_at < cycle_end +
  INTERVAL '1 day')`, cycle from `cycles.is_current`. No hardcoded date.
- **rank:** cycle mode = `ROW_NUMBER() OVER (ORDER BY cycle_xp DESC, member_id ASC)`; lifetime mode =
  `ORDER BY lifetime_xp DESC, member_id ASC`.
- **pool** = `gamification_opt_out=false AND (current_cycle_active=true OR has a gamification_points row in the
  current window)`.
- **pillar** = JOIN `gamification_rules ON (gr.organization_id=gp.organization_id AND gr.slug=gp.category)`,
  bucket on `gr.pillar`.

### M5.3 Antes (VERIFIED live, cycle_3)

**Rank-bug proof** (top cycle earners; `bugged` = lifetime-order, what the RPCs return; `canonical` =
cycle-order):

| Member | lifetime_xp | cycle_xp | rank BUGGED (lifetime) | rank CANONICAL (cycle) |
|---|---|---|---|---|
| Marcos Antunes Klemz | 535 | 425 | **14** (in-pool) / **15** (RPC all-points path) | **1** |
| Fernando Maquiaveli | 920 | 415 | 5 | 2 (tie) |
| Débora Moura | 960 | 415 | 3 | 2 (tie) |

`SELECT m.id, m.name, SUM(gp.points) life, SUM(gp.points) FILTER (WHERE gp.created_at >= '2026-03-01') cyc …`
(full query in workflow `wf_6c1ee407-948`). Fernando + Débora **tie at 415** → confirms the missing deterministic
tiebreak.

**Blast radius:** pool = **49**, **46 reorder** (94%) when cycle-mode is correctly ordered on cycle XP.
`WITH agg AS (… opt_out=false AND (current_cycle_active OR EXISTS points-in-window) …), r AS (ROW_NUMBER() OVER
(ORDER BY cyc_pts DESC, id::text) cr, ROW_NUMBER() OVER (ORDER BY life_pts DESC, name) lr) SELECT count(*),
count(*) FILTER (WHERE cr<>lr) FROM r;` → `{pool_n:49, rank_changes:46}`.

**Taxonomy:** 20 distinct categories, **0 of 19,910** points unmatched to `gamification_rules.slug`; pillars =
{certificacoes, champions, curadoria, presenca, producao, trilha}. Re-keying raw-string surfaces loses no XP today.

**False-positive exclusion (verified):** `recalculate_cycle_rankings` / `calculate_rankings` rank
`selection_applications` (admissions) — NOT gamification. `cycle_rankings` table does not exist. All gamification
rank is read-time.

### M5.4 Canonical primitive + PRs
New `get_xp_rankings(p_mode, p_cycle_code, p_scope_kind, p_chapter_code, p_initiative_id, p_limit, p_offset)`
returning `(member_id, lifetime_xp, cycle_xp, rank, total_count)` — single pool, single ORDER BY honoring
`p_mode`, single `member_id` tiebreak, window from the cycles row. Plus a shared
`v_member_xp_pillar(member_id, pillar, lifetime_pts, cycle_pts)` view so leaderboard/tribe/initiative stop
re-implementing the `FILTER(gr.pillar=…)` block. Harden the existing `get_member_xp_pillars` (it already JOINs
slug=category).

- **PR5-A** (M, no dep): `get_xp_rankings` + `v_member_xp_pillar` (shadow, no repoint). Contract test: cycle-mode order matches the canonical fixture (Marcos #1) + reads `gamification_rules` not inline strings + a CI assert that every `gamification_points.category` has a `gamification_rules` row.
- **PR5-B** (M, dep A): fix the global board (`get_gamification_leaderboard`) cycle-mode ORDER BY (highest visible impact: 46/49 reorder).
- **PR5-C** (M, dep A): fix self-view (`get_member_cycle_xp`) — rank via `get_xp_rankings('cycle')`; remove `'2026-01-01'`; raw buckets → pillar JOIN. Fixes MCP `get_my_xp_and_ranking` + profile transitively.
- **PR5-D** (S, dep A): admin `get_member_detail` rank → `get_xp_rankings('lifetime')`; categories by pillar.
- **PR5-E** (M, dep A+B): scoped boards (`get_tribe_gamification`/`get_initiative_gamification`) cycle-mode + opt-out + view + tiebreak; `get_public_leaderboard` add `member_id` tiebreak.
- **PR5-F** (S, dep A): harden `get_member_xp_pillars`; apply D-M5-CPMAI keep-separate (cpmai_prep, 0 live points, stays its own course-scoped surface).
- **PR5-G** (M, dep B+C): frontend consolidation (gamification/ranks/rank/profile/TribeGamificationTab); wire "Ciclo Atual" → cycle mode; remove client recompute; 3-dict i18n parity; verify `/en/` `/es/` stubs.

### M5.5 Risks
Intended, user-visible: fixing cycle-mode ORDER BY reorders **46 of 49** — ship with changelog. The displayed
cycle leader changes from the lifetime leader to the actual cycle leader. LGPD: several rank RPCs omit the
opt-out filter (live-empty: 0 opted out — latent, fix the pool on repoint). `ranks.astro`/`rank.astro` were not
opened — confirm which RPC each calls before assuming PR-G covers them.

---

## §M6. Metric 6 — trail_completion + cpmai_certified

### M6.1 Problem — trail
Two different metrics wear one name:
- **Home** `calc_trail_completion_pct()` = **44** — a **binary "completed ALL 6"** rate (`COUNT FILTER(status='completed')
  / 6.0` per member, then AVG×100), cohort = `is_active ∧ current_cycle_active ∧ operational_role NOT IN
  (sponsor, chapter_liaison, observer, candidate, visitor)` → **37 members incl. 2 guests** (Angeline, Mario).
  Trail total is **hardcoded `6.0`**.
- **Ranking** `get_public_trail_ranking()` = **46.66** — a **partial-credit average** (per-member `completed/total`)
  over cohort **35** (excludes guests), with the **dynamic** live is_trail count (**6** courses today).

The gap is **cohort** (37 vs 35 = the 2 guests) **and formula** (binary all-6 vs partial-credit). The hardcoded
`6.0` equals the dynamic count today (latent — breaks the moment a 7th trail course is added). GI-1 adds: trail
hardcoded `0` in both `get_tribe_gamification` / `get_initiative_gamification`.

### M6.2 Problem — cpmai
The cpmai goal metric conflates **wall** (all-time certified) with **meta** (certified in the goal year):
- `members.cpmai_certified` boolean all-time = **2** (Marcos 2026-03-04 + Pedro 2025-10-23).
- Goal-year-2026 (`cpmai_certified_at` in 2026) = **1** (Marcos). **This is the meta** (PMI-GO board rule:
  count only certifications earned during the goal year; pre-existing certs go on the wall, not the goal).
- Pedro is `inactive` with a pre-2026 cert → correctly on the wall, out of the meta.

### M6.3 Antes (VERIFIED live)

| Quantity | Value | SQL |
|---|---|---|
| Home `calc_trail_completion_pct()` | **44** | `SELECT calc_trail_completion_pct();` |
| Ranking cohort_n / avg | **35 / 46.66** | `SELECT count(*), round(avg(pct),2) FROM get_public_trail_ranking();` |
| Home cohort_n / of-which guests | **37 / 2** | `SELECT count(*) … operational_role NOT IN (…);` + `… operational_role='guest'` |
| Live is_trail courses | **6** | `SELECT count(*) FROM courses WHERE is_trail;` |
| cpmai wall (all-time) | **2** | `SELECT count(*) FROM members WHERE cpmai_certified;` |
| cpmai meta (goal-year 2026) | **1** | `SELECT count(*) FROM members WHERE cpmai_certified AND cpmai_certified_at >= '2026-01-01' AND cpmai_certified_at < '2027-01-01';` |
| cpmai NULL cert date | **0** | `… AND cpmai_certified_at IS NULL` |

### M6.4 Canonical definition + design
- **trail_completion** (D-M6-TRAIL): per-member `completed_trail_courses / NULLIF(count(courses WHERE is_trail),0)`,
  aggregate = **AVG-of-member-rates ×100**, over a **shared `trail_eligible_members`** cohort (drop the guest
  inclusion so home == ranking; recommend the ranking's cohort of 35 as canonical), **dynamic** total. Native
  initiatives → `N/A`. Fix `calc_trail_completion_pct` to read `count(courses WHERE is_trail)` not `6.0`, and the
  hardcoded-0 in both gamification RPCs. Single source = `course_progress` (align `trail_progress`'s
  `gamification_points category='trail'` read; they match 0/23 today but are two definitions).
- **cpmai_certified** (D-M6-CPMAI): canonical goal metric = `members.cpmai_certified = true AND cpmai_certified_at`
  within the goal year (resolve the goal year from the cycle, not a literal). The **wall** is the all-time
  boolean. Document the boundary; the gamification `cert_cpmai` ledger is a separate XP-pillar concern, not the
  goal metric.

> **Flag for PR time:** the goal "year" boundary — confirm whether the goal window is calendar-2026 or the cycle
> window; both yield meta=1 today (Marcos 2026-03-04 is inside cycle_3 too). Resolve from `cycles`, not a literal.

### M6.5 PRs
- **PR6-A** (M): `calc_trail_completion_pct` dynamic total + shared cohort + partial-credit; align native → N/A. Home **44 → ~the partial-avg over the shared cohort** (measure at PR time; home and ranking converge). Contract test: dynamic is_trail count read; cohort == ranking cohort; native N/A.
- **PR6-B** (S, dep A): wire `trail_completion` in `get_tribe_gamification` / `get_initiative_gamification` (retire the hardcoded `0`).
- **PR6-C** (M): cpmai goal metric = dated boolean within the goal window across the admin/portfolio/chapter surfaces; wall stays all-time; document the rule in ADR-0100. Contract test asserts meta excludes a pre-goal-year cert (Pedro fixture) and the wall includes it.

### M6.6 Risks
Home trail % visibly changes (binary 44 → partial-avg) — intended, ship with changelog; communicate "home now
shows the same partial-progress number as the ranking." cpmai meta vs wall must be **labelled** so 1 (meta) and 2
(wall) don't read as a disparity.

---

## §M7. Metric 7 — champions (#424)

### M7.1 Problem
`champions_awarded` (ledger: source of truth for `get_champions_ranking`, profile history, admin list) and
`gamification_points` pillar='champions' (read by the leaderboard 🏆 chip `gamification.astro:777,786` + the
tribe tab `champions_points`) are **dual-written** by `award_champion` / **dual-deleted** by `revoke_champion`
with **no reconciliation and no invariant**. The instant a real award is made they can drift silently. Live:
`champions_awarded` total = **1**, **active = 0** (a revoked smoke test), `gamification_points champion_*` = **0**.

### M7.2 Canonical (D-M7-SOURCE)
`champions_awarded` ledger is canonical; the `gamification_points` pillar='champions' rows are a **derived
projection**. Add a **parity invariant**: every `champions_awarded` row with `status='active'` has exactly one
`gamification_points` row (`category='champion_'||surface`, `ref_id=champion_id`); zero for revoked.

### M7.3 Antes (VERIFIED live)
`SELECT count(*) total, count(*) FILTER(WHERE status='active') active FROM champions_awarded;` → `{total:1,
active:0}`. `SELECT count(*) FROM gamification_points WHERE category LIKE 'champion\_%';` → `0`. ⇒ **repointing
the chip + tab to the ledger is a 0-visible-change, zero-risk convergence today** (both sources are empty), and
the parity invariant is pure forward-defense (the dual-write has never executed live).

### M7.4 Award-path unblock (D-M7-UNBLOCK) — refined by live grounding
**The backend already authorizes tribe leaders.** Live:
- `engagement_kind_permissions` for `award_champion`: `core_team/leader@organization`, `core_team/manager@organization`,
  **`volunteer/leader@initiative`**.
- The `award_champion` RPC's **tribe** surface gates on `can_by_member(caller, 'award_champion', 'initiative',
  v_target_init_id)`.
- A real tribe-8 leader (Ana Carla, `volunteer/leader`) → `can_by_member('award_champion','initiative',her_tribe)`
  = **TRUE**.

The **only** blocker is the frontend: `src/pages/admin/gamification.astro:631-632`
`canAward: isGP || isComms  // tribe leaders via tribe page TODO`. The tribe-page award UI was never built. So the
unblock = **frontend-only** (expose the award action on the tribe page / tribe gamification tab to leaders, calling
the existing RPC tribe surface). **No `engagement_kind_permissions` seed and no grant widening is needed** — which
also avoids the `database.md` "seed expansion as shortcut → privilege escalation" anti-pattern.

### M7.5 PRs
- **PR7-A** (S): repoint the leaderboard 🏆 chip + tribe-tab `champions_points` onto the ledger (or a ledger-backed view); 0 visible change today. Contract test = the parity invariant (active ⇒ exactly one projection row; revoked ⇒ zero). Optionally add to `check_schema_invariants`.
- **PR7-B** (M): tribe-leader award UI on the tribe page / tribe gamification tab (calls the existing `award_champion` tribe surface; backend unchanged). 3-dict i18n + `/en/` `/es/`. Smoke: Ana Carla can award within tribe 8; cannot award cross-tribe.

### M7.6 Risks
PR-A is zero-risk today (empty sources). PR-B is a permission-surface *exposure*, not a grant change — confirm the
RPC's own caps (per-event/per-cycle) + self-award block still hold; verify a non-leader still can't award.

---

## §M8. Metric 8 — webinars

### M8.1 Problem
The portfolio/KPI surfaces count `events WHERE type='webinar'` (live **4**) instead of the `webinars` table (live
**7**), the architectural source of truth (CLAUDE.md decision #4).

### M8.2 Antes (VERIFIED live)
`SELECT count(*) FROM webinars;` → **7** (status: `planned` 4, `confirmed` 3). `SELECT count(*) FROM events WHERE
type='webinar';` → **4**. Webinar dates: all **7 past-dated** (`2026-04-15` … `2026-05-28`), 0 future, 0 null.
**There is no `done`/`completed` status** — statuses are `planned`/`confirmed` only.

### M8.3 Canonical (+ D-M8-COMPLETED)
Count the `webinars` table. "Completed/realized" predicate (open decision, recommend-and-proceed): since there is
no `done` status, **`scheduled_at < now()`** = realized (=7 today), robust to the missing enum value. (All-rows =7
today identical; `status='confirmed'` =3 if "completed" means confirmed-only.) Resolve the window from `cycles`,
not the `'2026-01-01'` YTD literal the portfolio KPI uses.

### M8.4 Surfaces + PR
Repoint every webinar count off `events type='webinar'` onto the `webinars` table: `exec_portfolio_health`
(`webinars_completed`, YTD-2026 literal → cycle window), `get_kpi_dashboard`, `exec_cycle_report`,
`get_public_impact_data` (`.impact.webinars`), `get_annual_kpis` (tag-join), `list_radar_global`. Surfaces already
correct (read `public.webinars`): `list_webinars_v2`, `get_comms_pipeline`, `webinars_pending_comms` — leave.

- **PR8** (S–M): repoint the fork surfaces to the `webinars` table + realized predicate + cycle window. antes→depois:
  portfolio/KPI **4 (or 0 under the YTD literal) → 7**. Contract test asserts the count reads `webinars` not
  `events type='webinar'`. (Re-locate the `/impact` frontend consumer — the workflow could not find
  `ImpactPageIsland.tsx`; the DB-layer `.impact.webinars` is confirmed.)

### M8.5 Risks
Mostly mechanical. The visible number rises (4→7). One subtlety: the YTD-2026 literal makes `exec_portfolio_health`
currently return **0** (no 2026 *events*-table webinars), so that surface jumps 0→7 — flag it.

---

## §9. Ship sequence (smallest blast radius first)

| Order | PR | Metric | Gated on | Visible Δ |
|---|---|---|---|---|
| 1 | PR8 | webinars | D-M8-COMPLETED (recommend-proceed) | 4→7 |
| 2 | PR7-A | champions ledger + parity | — | 0 (forward-defense) |
| 3 | PR7-B | champions award UI | D-M7-UNBLOCK (ratified; frontend-only) | enables leaders |
| 4 | PR6-A/B/C | trail + cpmai | D-M6-TRAIL + D-M6-CPMAI (ratified) | home trail 44→partial-avg; cpmai meta/wall labelled |
| 5 | PR4-A→D | member_count | — | 5/7→6 convergence |
| 6 | PR4-F | get_member_tribe axis | D-M4-AXIS (recommend-proceed) | curator resolves |
| 7 | PR5-A→G | XP rank/pillar | — | 46/49 reorder (biggest) |

Each PR: same-signature `CREATE OR REPLACE` + live smoke (JWT-claim as the operator for SECDEF RPCs) +
contract test asserting the canonical primitive is read (not an inline formula) + label/i18n parity on affected
surfaces + GC-097 + Phase-C md5 file==live + apply_migration shadow-row reconcile (SEDIMENT-254.A / 269.B) +
`astro build` + `npm test`. antes→depois recorded in each PR body. p175 gate (PR10 of metric 3) forward-defends
the canonical-primitive discipline; extend its allowlist as each metric converges.

## §10. Provenance
Design workflow `wf_6c1ee407-948` (11 agents, 5 metrics × map+adversarial-verify + synthesis). All numbers
re-grounded in the main loop 2026-05-31 against `ldrfrvwhxsmgaabwmaik` (cycle_3). PM decisions ratified
2026-05-31. ADR-0100 §2.2 dictionary + §7 ratification log. Issues #419 (Bucket B), #424 (champions), #425
(coaching cockpit, downstream of M5/M6/M7).
