# Cycle-turn access-cohort procedure (manual) — C3→C4 governance gate

**Issue:** #1004 (EPIC #1002). **Status of Camada 5 (#976 re-accept state machine):** DORMANT →
this turn is executed **manually** by the procedure below. When #976 is ratified/activated, this
manual procedure is the natural thing it automates.

> **LGPD note.** This procedure decides who has platform access at a cycle turn. Two symmetric
> risks: **leak** (engagement ended but access retained — Art. 18) and **gap** (accepted cohort
> without access). Access is driven by **active engagement**, not by "cycle". Any offboarding is
> a per-member governance decision — never bulk-executed from a query. Keep member PII out of
> this (committed) doc; the audit output lives on the issue (aggregate) and in the operator's
> session (identified list).

---

## 1. Cohort definition (day of the turn)

1. **Entering (new cycle):** application accepted (VEP `Active`/`OfferExtended`) + in onboarding.
2. **Retained (prior cycle):** engagement/agreement still **vigente** (agreement `period_end` in
   the future).
3. **Exit / restrict:** prior-cycle engagement **ended and not renewed** → offboard/anonymize per
   LGPD. Only members whose access basis has genuinely lapsed.

## 2. Audit queries (read-only, reproducible)

Set the cycle codes for the turn (e.g. retained `cycle3-2026`/`cycle3-2026-b2`, entering
`cycle4-2026`).

**2a. Active-engagement landscape by origin cycle + leak flag (ended-but-active):**
```sql
WITH active_eng AS (
  SELECT e.id, e.person_id, e.kind, e.status, e.end_date,
         e.agreement_certificate_id, e.selection_application_id, sc.cycle_code
  FROM public.engagements e
  LEFT JOIN public.selection_applications sa ON sa.id = e.selection_application_id
  LEFT JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
  WHERE e.status = 'active' AND e.revoked_at IS NULL
)
SELECT coalesce(cycle_code,'(no-cycle/legacy)') AS origin, kind, count(*) AS active_eng,
       count(*) FILTER (WHERE end_date IS NOT NULL AND end_date < current_date) AS ended_but_active_LEAK,
       count(*) FILTER (WHERE agreement_certificate_id IS NULL) AS no_agreement_cert
FROM active_eng GROUP BY 1,2 ORDER BY 3 DESC;
```

**2b. Retained-cycle agreement validity (are the prior-cycle agreements still vigentes?):**
```sql
WITH prior_eng AS (
  SELECT e.agreement_certificate_id
  FROM public.engagements e
  JOIN public.selection_applications sa ON sa.id = e.selection_application_id
  JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
  WHERE e.status='active' AND e.revoked_at IS NULL
    AND sc.cycle_code IN ('cycle3-2026','cycle3-2026-b2')  -- retained cycles
)
SELECT count(*) AS eng, count(c.id) AS with_cert,
       count(*) FILTER (WHERE c.status='issued') AS issued,
       jsonb_agg(DISTINCT jsonb_build_object('type',c.type,'p_start',c.period_start,'p_end',c.period_end)) AS periods
FROM prior_eng LEFT JOIN public.certificates c ON c.id = prior_eng.agreement_certificate_id;
-- `certificates.period_end` is TEXT (ISO date). Read the distinct periods; an agreement whose
-- period_end is in the FUTURE is vigente → retained legitimately (no offboarding).
```

**2c. Orphan-access (leak direction): operational-role members with NO active engagement:**
```sql
SELECT m.operational_role, count(*) AS members,
       count(*) FILTER (WHERE ae.person_id IS NULL) AS without_active_engagement
FROM public.members m
LEFT JOIN LATERAL (
  SELECT 1 AS person_id FROM public.engagements e
  WHERE e.person_id = m.person_id AND e.status='active' AND e.revoked_at IS NULL LIMIT 1
) ae ON true
WHERE m.operational_role IS NOT NULL
GROUP BY m.operational_role ORDER BY without_active_engagement DESC;
-- `alumni` / `none` / `guest` without an active engagement is CORRECT (non-access states).
-- An OPERATIONAL role (researcher / *_leader / manager / sponsor / …) without an active
-- engagement IS the leak — investigate each.
```

**2d. Entering-cohort readiness (can they access + onboard on day 9?):**
```sql
WITH new_eng AS (
  SELECT e.person_id, e.selection_application_id
  FROM public.engagements e
  JOIN public.selection_applications sa ON sa.id = e.selection_application_id
  JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
  WHERE e.status='active' AND e.revoked_at IS NULL AND sc.cycle_code = 'cycle4-2026'  -- entering cycle
)
SELECT count(*) AS active_eng,
       count(*) FILTER (WHERE m.id IS NOT NULL) AS linked_member,
       count(*) FILTER (WHERE m.auth_id IS NOT NULL) AS loginable,           -- < active_eng ⇒ gap
       count(*) FILTER (WHERE op.cnt > 0) AS with_onboarding_progress
FROM new_eng
LEFT JOIN public.members m ON m.person_id = new_eng.person_id
LEFT JOIN LATERAL (SELECT count(*) cnt FROM public.onboarding_progress o
                   WHERE o.application_id = new_eng.selection_application_id OR o.member_id = m.id) op ON true;
-- The entering members NOT loginable (auth_id IS NULL) need an account-claim / auth invite
-- BEFORE the turn — they otherwise cannot access on day 9 despite an active engagement.
```

**2e. Renewal radar — VEP service-end resolved by member email + renews flag (#1021):**
```sql
-- get_cycle_renewal_radar replaces the manual FK-only cross-join: it resolves each active
-- volunteer's VEP service-end across ALL email-matched applications (not just the engagement's
-- FK-linked app) and flags active_future / lapsing / unknown vs the turn date. Returns member PII →
-- run as the operator (service_role via MCP) or an in-app GP (manage_member). Pass the turn date.
SELECT jsonb_pretty(get_cycle_renewal_radar('2026-07-09'::date) -> 'summary');

-- Expand the volunteers needing review (lapsing first, then unknown):
SELECT r->>'member_name'          AS member,
       r->>'role'                 AS role,
       r->>'resolved_service_end' AS service_end,
       r->>'service_end_source'   AS source,     -- linked | email_matched | unknown
       r->>'renews_signal'        AS renews       -- active_future | lapsing | unknown
FROM jsonb_array_elements(get_cycle_renewal_radar('2026-07-09'::date) -> 'members') r
WHERE r->>'renews_signal' IN ('lapsing','unknown');
-- `unknown` renews_signal = VEP service-end missing for that volunteer (radar blind) → manual VEP
--   cross-check / backfill (off-issue, LGPD). It does NOT by itself mean "exit".
-- `lapsing` = service ends at/before the turn date → exit candidate to review per §3.2.
-- `email_matched` source = the date was recovered from a different app than the engagement's FK link
--   (the #1021 fix) — no data repair is required for the radar to fire.
```

## 3. Manual execution steps

1. Run 2a–2e. Produce the explicit **keep / enter / exit** list (with reasons) for the operator's
   review — keep member identities OFF this doc; put aggregates on the issue. 2e's renewal radar
   gives the per-volunteer service-end + renews flag so the exit decision no longer needs a manual
   cross-join; treat `unknown` as "verify", not "exit".
2. **Exit:** for each genuinely-lapsed member (2c operational-role orphan, or a retained-cycle
   engagement whose agreement `period_end` has passed and was not renewed) → `admin_offboard_member`
   with the **correct `reason_category`** (e.g. `end_of_cycle` for a natural turn), after per-member
   governance sign-off. **Never bulk.** Do NOT use the `offboard_member` wrapper — it hardcodes
   `reason_category => 'other'`, which erases the audit meaning that drives `re_engagement_pipeline`
   eligibility + the LGPD anonymization guard (ADR-0116 §6). Proven live 2026-07-03 (the C3 tribe-7
   voluntary exit recorded `'other'` and needed a governed post-hoc correction — freeze doc §2.3b).
   (Access-flip is offboarding-based; there is no direct `members` UPDATE — ADR/Camada-5 invariant.)
3. **Enter gap:** for each entering member not loginable, trigger the account-claim / auth invite
   so they can access on day 9.
4. Confirm the entering cohort's `onboarding_progress` exists and the cycle's `onboarding_steps`
   are configured (`selection_cycles.onboarding_steps`).
5. Communicate the turn to the retained/exiting cohorts (overlaps #1003 cycle-3 closure).

## 4. Mapping to Camada 5 (#976) when activated

The re-accept state machine (#976, dormant) automates steps 1–2: it computes the retained cohort
from active obligations, drives the aviso→suspensão→desligamento clock, and gates the outward
notification (#334). Until it is ratified, run this manual procedure at each turn; treat a turn
that would require offboarding as the trigger to prioritize #976 activation.

## 5. C3→C4 turn — audit result 2026-07-01 (see #1004 comment for the aggregate on the issue)

- **No leak:** 0 active engagements with a past `end_date`; 0 operational-role members without an
  active engagement (alumni/none/guest correctly hold no access).
- **Retained legitimate:** C3 `volunteer_agreement` certs are issued with `period_end` in **Dec
  2026** → vigentes; C3 retained keeps access (no expiry-driven offboarding this turn).
- **Entering provisioned:** the cycle-4 accepted cohort all have active engagements + member
  records + onboarding_progress; the cycle has 5 onboarding steps configured.
- **Only action for day 9:** a small subset of entering members are **not yet loginable**
  (`auth_id IS NULL`) → send account-claim / auth invites before the turn. **Exit list = empty.**
