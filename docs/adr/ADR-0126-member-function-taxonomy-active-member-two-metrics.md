# ADR-0126 — Canonical member-function taxonomy: "active member" is two distinct metrics (system-user vs operational)

**Status:** Accepted
**Date:** 2026-07-20
**Source:** Issues [#1437](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/1437) (redefine "membros ativos" to operational-only) + [#1354](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/1354) ("Pesquisadores ativos" counts board/sponsor/reviewer + synthetic rows; member categorization must be canonical across home/admin/campaigns). Raised grounding the Ciclo 4 recurring-meeting roster (owner: home shows 96/87 vs the real operating team of ~68).
**Related:** ADR-0006 (persons + engagements model identity), ADR-0007 (`can()`/`operational_role` authority SSOT), ADR-0100/#419 (`v_active_members` canonical active-member view), #625 (pre-onboarding cohort split), #205 (synthetic test rows), #1358 (chapter stakeholder != núcleo focal point).
**SSOT reused:** `sync_operational_role_cache` (the priority-ladder trigger that derives `members.operational_role` from authoritative `auth_engagements`).

---

## Context

The public home headline "Pesquisadores ativos" and the admin dashboard KPI counted
`is_active AND current_cycle_active AND NOT member_is_pre_onboarding` and read **87** (raw
`is_active AND current_cycle_active` reads 89). The owner flagged the divergence from the real
research team (~68). Investigation (all counts live, `ldrfrvwhxsmgaabwmaik`, 2026-07-20) showed the
**number** was the defect, not the label: the count folded in chapter board / sponsors / external
reviewers / observers who are NOT part of the research operation, so "Pesquisadores ativos" was reporting
a polluted population. The label is correct — the research team IS the operational tier (research
management / GP + theme leaders + researchers + curators); only the count must be narrowed to it.

Grounded decomposition of the 89 active system users:

| operational_role | active | function tier |
|---|---:|---|
| researcher | 54 | operational (incl. curators, facilitators, communicators, committee/workgroup/study members — all collapse here) |
| tribe_leader | 12 | operational (leaders + comms leaders) |
| manager | 2 | operational (GP + Co-GP collapse here) |
| chapter_liaison | 10 | stakeholder (chapter board / focal point) |
| sponsor | 5 | stakeholder |
| guest | 6 | pending / non-operational |

Two false leads were ruled out by grounding, not intuition:

1. A "has an issued volunteer term" proxy (would read 72) is **rejected** — it is a proxy for function,
   not the function itself, and it leaks 1 stakeholder-who-once-signed-a-term into the count.
2. "The `operational_role` cache loses 4 núcleo directors" (would read ~72) is **rejected** — grounding
   the 4 people showed they are **PMI-GO chapter board directors** (diretor de filiação / voluntariado /
   certificação **do capítulo**, plus a chapter-PMO volunteer analyst), active engagement `chapter_board`.
   They are chapter stakeholders, not núcleo operators; `operational_role='chapter_liaison'` is correct
   for them (confirmed by the owner; consistent with #1358). Promoting them would be the inverse mistake.

The `operational_role` priority ladder (`sync_operational_role_cache`) is therefore **faithful as-is**: it
deliberately ranks `sponsor` and `chapter_board`→`chapter_liaison` **above** `researcher` ("governança
vence" / "sponsor outranks researcher"), so a chapter director or sponsor who also sits on a committee or
observes a tribe still shows in their governance/stakeholder role. It does NOT need changing for this work.

## Decision

### 1. "Active member" is two distinct, separately-labeled metrics — not one number

| Tema | Meaning | Canonical rule | Live (2026-07-20) | Surfaces |
|---|---|---|---:|---|
| **A — active system user** | has a live account operating this cycle (platform metric) | `is_active AND current_cycle_active` (optionally `AND NOT member_is_pre_onboarding` for the operating subset) | 89 (87 post-onboarding) | admin/analytics, cycle report roster, platform-usage / adoption denominators, `/admin/members` total |
| **B — active research team** | operates the research núcleo by function: research management (GP/Co-GP), curadores, líderes de tema (tribo/iniciativa), pesquisadores — **regardless of tribe allocation** (project metric). This IS "Pesquisadores ativos". | `is_active AND current_cycle_active AND operational_role IN ('manager','deputy_manager','tribe_leader','researcher')` | **68** | home headline "Pesquisadores ativos", `/admin/members` grouped by function, campaign audience selector |

These are **temas diferentes** and coexist. Neither replaces the other; each surface uses the one it means.

### 2. The operational tier is defined by the `operational_role` ladder (SSOT), not an ad-hoc list

The operational set `{manager, deputy_manager, tribe_leader, researcher}` is the operational tier the
`sync_operational_role_cache` ladder emits. By that ladder:

- **GP and Co-GP** collapse into `manager`; **deputy_manager** is its own value.
- **Líderes** (tribe/initiative leaders) and **comms leaders** collapse into `tribe_leader`.
- **Curadores** collapse into `researcher` (`role='curator' → 'researcher'`) — curation is an authority
  overlaid on operational members (`can('curate_...')`), NOT a separate population. So curators are
  already counted; there is no distinct `operational_role='curator'`.
- Committee / workgroup / study-group members and coordinators also resolve to `researcher`.

Allocation to a tribe is irrelevant: the tier is role-derived, so an un-allocated researcher or a leader
between tribes still counts.

The **stakeholder tier** = `{sponsor, chapter_liaison}`; the **non-operational remainder** =
`{observer, external_signer, institutional_auditor, alumni, candidate, guest}`.

### 3. The home headline stays "Pesquisadores ativos" — only the population is fixed

The label is correct and does NOT change. The home headline switches its COUNT from Tema A (87, polluted
with chapter board / sponsors / reviewers / observers) to **Tema B (68 — the research team)**. No i18n
change; the existing "Pesquisadores ativos" / "Active researchers" / "Investigadores activos" strings
finally report the population they always claimed. Research management (GP), theme leaders, researchers,
and curators are all "pesquisadores" in the research-operation sense.

### 4. One canonical derivation, reused (closes #1354 frente 3)

Ship a single canonical surface — a helper/view (working name `v_operational_members`, mirroring
`v_active_members` column order) — consumed by the home headline, the admin KPI, `/admin/members` grouping,
and the campaign audience selector. No surface re-derives "who is operational" ad-hoc (today
`get_admin_dashboard`, the attendance roster, and the cycle report each use a different inline exclusion
list — this ADR makes them converge on the tier taxonomy).

### 5. Explicit non-goals

- **Do NOT touch `v_active_members`** — it is the general Tema A active-member view, correctly consumed by
  `get_cycle_report` / `get_pilot_metrics` / `get_platform_usage` / `get_sustainability_projections` (a
  broader cohort). Converging it to Tema B would be wrong and would break
  `p277-419-cycle-report-active-member-converge` (mig 063).
- **Do NOT change the `operational_role` ladder** — it is correct; "governança vence" is deliberate.
- The 9 synthetic `__205_synthetic__` rows (already soft-retired, not counted) are purged in a separate
  follow-up (#1437 Pendente 1, FK scan) — out of scope here.

## Consequences

- Home number drops 87 → 68 under the unchanged "Pesquisadores ativos" label, which finally reports the
  research team it always claimed; the two concepts stop being conflated across surfaces.
- `operational_role` becomes the single lever for "who operates the project"; when a curator/leader/GP
  changes, the ladder (already trigger-maintained) keeps every consumer in sync.
- Stakeholders (sponsors, chapter board/liaisons, observers, reviewers) get their own categories in
  `/admin/members` and campaign targeting; "Pesquisadores" as an audience no longer drags them in.
- New risk surface: a member with an active operational engagement whose governance role outranks it
  (the 6 double-function people) counts as **stakeholder** by design. If a future need arises to count
  "anyone doing operational work" (Tema B by activity, ~74), that is a THIRD metric, added explicitly —
  never by quietly loosening this one.

## Grounding (live, `ldrfrvwhxsmgaabwmaik`, 2026-07-20)

- Active system users (Tema A): 89; post-onboarding 87.
- Active operational (Tema B): 68 = researcher 54 + tribe_leader 12 + manager 2.
- Stakeholder tier active: chapter_liaison 10 + sponsor 5 = 15. Pending: guest 6, no-active-engagement 2.
- Ladder SSOT: `sync_operational_role_cache` (curator/GP/Co-GP/comms-leader/committee collapses verified in
  the live function body).
- The 4 chapter-director cases: Eder Valasco (chapter PMO volunteer analyst), Graziele Brescansin (filiação
  director), Lorena Souza (voluntariado director + PMI-GO countersigner), Welma Alves de Melo (certificação
  director) — all PMI-GO chapter board, engagement `chapter_board`, correctly `chapter_liaison`.

## Implementation (follows this ADR)

1. Canonical `v_operational_members` (+ optional `is_operational_member(member_id)` helper),
   `security_invoker=true`, REVOKE anon, GRANT authenticated/service_role (mirror `v_active_members`).
2. Rewrite the "Pesquisadores ativos" COUNT in `get_public_platform_stats`, `get_homepage_stats`,
   `get_admin_dashboard` (KPI + `adoption_7d` denominator) to read from it. No i18n / label change.
3. Contract test: locks the operational tier set, the 87-vs-68 distinction, and cross-surface convergence
   (home ≡ public ≡ admin).
4. Follow-ups: `/admin/members` function grouping + campaign audience selector reuse (#1354 frente 3);
   synthetic purge (#1437 Pendente 1).

## Addendum — the "third metric" was added (#1476 Onda 2, 2026-07-23)

The risk surface flagged in Consequences ("anyone doing operational work... is a THIRD metric, added
explicitly — never by quietly loosening this one") materialized as a real bug on the operational-intervention
surfaces (attendance seal, dropout risk, cohort health, attendance summaries, credly): they gated their cohort
by `operational_role IN (...)`, so the double-function people (chapter focal point + active tribe researcher)
were erased from intervention — on the WRITE path (`seal_event_attendance`) their attendance was never
materialized. Owner decision (2026-07-23): **do NOT rebase `v_operational_members`** — the "Pesquisadores
ativos" headline stays a COMPOSITION metric where a dual-hat counts as their governance/stakeholder role
(governance-wins is deliberate). Instead, Onda 2 added the explicit third canonical:

- **`v_member_operational_tiers`** (migration `20260805000485`): a per-`(member, operational_tier)` junction
  derived from authoritative **volunteer** engagements (multi-hat aware — a dual-hat produces one row per tier),
  mirroring the ladder's operational tiers MINUS the committee/workgroup sub-clause (that was folded into
  `researcher` for `canFor()` authority per p164, never for attendance eligibility). Each intervention
  consumer semi-joins (`EXISTS`) its own tier subset and keeps its own member-activity base filter.

The two canonicals are deliberately distinct and MUST NOT be unified: `v_operational_members` (label-based,
governance-wins, the published KPI, 69) answers "who composes the research team as displayed"; the junction
(engagement-based, multi-hat, 71) answers "who must the platform intervene on operationally". Live 2026-07-23:
the delta is exactly +2 (the same dual-hats, tribes 1 and 7), 0 regressions. #1477 (TCV exemption, an inverse
gate with a 45-member behavioral ripple) is a separate follow-up, NOT folded in.
