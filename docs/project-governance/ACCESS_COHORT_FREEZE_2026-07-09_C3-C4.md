# Access-cohort freeze — C3→C4 turn (day 9, 2026-07-09)

**Issue:** #1004 (EPIC #1002). **Procedure of record:** `docs/operations/cycle-turn-access-cohort-procedure.md` (#1013).
**Type:** frozen, dated, sign-before-execution list (council-review 2026-07-01 requirement).
**Grounded live:** 2026-07-01; **re-grounded + adversarially verified 2026-07-03** (queries 2a–2e re-run via
read-only `execute_sql`; a 7-agent adversarial verification pass hunted leak and gap from independent angles).
Re-run 2a–2e immediately before execution on 2026-07-09 and diff against this freeze — a turn is only as valid
as its freshest audit.

> **LGPD.** This committed doc carries **aggregates only** — no member identities. The identified per-person
> keep/enter/exit list lives in the operator's session at execution time (and, if archived, off-repo). Access
> is driven by **active engagement**, not "cycle" (ADR-0106: "access" = `member_status`/`is_active` read by RLS,
> not a UI toggle — a mistake here is a real leak or denial).

---

## 1. Decision (this turn) — signed 2026-07-03

**Exit side (leak): CONFIRMED clean, adversarially.** No involuntary/data-driven offboarding is justified.
The 2026-07-03 adversarial pass attacked from 8+ angles (status-lens, role-cache drift recomputation, end_date
windows through the turn, renewal-radar unknowns, RLS/`can()` internals, identity-bridge drift) and refuted
nothing material: **0 leaks**. Involuntary exit list = **EMPTY**.

**Enter side (gap): REFRAMED on 2026-07-03 — the original "40 provisioned = access on day 9" overstated what
day 9 delivers.** Mechanically (grounded in `pg_proc`/`pg_policies`): **provisioned ≠ authoritative**. 36/40
entering members hold `operational_role='guest'` because their volunteer engagement lacks the signed agreement
(`kind='volunteer'` has `requires_agreement=true` → `auth_engagements.is_authoritative=false` → `can()` denies
and `rls_is_authoritative_member()` excludes guests across ~24 RLS-gated tables). **Nothing flips automatically
on day 9** — the flip is per-member self-service: claim account → complete profile → `sign_volunteer_agreement`.
Day 9 therefore delivers **login + onboarding surface** (checklist, term signing, profile); **full member
surface lands as terms are signed during the following week**. See §2.5 for the readiness plan.

Camada 5 (#976) is dormant, so this turn is executed **manually** by the procedure of record.

---

## 2. Frozen cohorts (grounded 2026-07-01 · re-grounded 2026-07-03)

Total active, non-revoked engagements: **153** (40 entering + 35 retained C3-origin + 78 legacy/no-cycle).
(01→03/07 delta: +4 C4 approvals; −2 C3-origin from the §2.3b item-2 executed exit; −2 legacy observer
engagements expired 2026-07-02. Total coincidentally unchanged.)

### 2.1 ENTER — Cycle 4 (`cycle4-2026`)
| Metric | Count (2026-07-03) | Meaning |
|---|---|---|
| Active `volunteer` engagements | 40 | all provisioned (34 VEP `Active` + 6 `OfferExtended`) |
| Linked member record | 40/40 | none orphaned |
| With `onboarding_progress` | 40/40 | cycle has 5 onboarding steps configured |
| **Loginable (`auth_id` set)** | **36/40** | **4 NOT loginable → day-9 gap (#1014)** |
| Without agreement cert | 36/40 | **= pre-onboarding `guest`, no member surface until signed (§1, §2.5)** |
| Volunteer term signed | 4/40 | term TEMPLATE approved on the weekend of 04–05/07; campaign runs the following week |

**Criterion:** application accepted (VEP `Active`/`OfferExtended`) + active engagement provisioned. All 40 qualify.
**In-flight:** 7 further cycle-4 applications (3 interview_pending, 2 interview_scheduled, 2 final_eval) may still
be approved; provisioning is a manual GP RPC (`approve_selection_application`) — late approvals enter the same
pre-onboarding state and fold into the §2.5 campaign.
**Action:** §2.5 readiness plan (signing campaign + auth outreach + tribe-deadline fix + leader allocation).

### 2.2 RETAIN — Cycle 3 (`cycle3-2026` + `cycle3-2026-b2`)
| Metric | Count (2026-07-03) | Meaning |
|---|---|---|
| Active C3-origin engagements | 35 (22 distinct members) | retained |
| `volunteer_agreement` certs | 23 | all **issued**, period **2026-01-20 → 2026-12-19** |
| Non-volunteer kinds w/o agreement cert | 12 | workgroup/ambassador/observer/committee — no agreement cert by design |

**Criterion:** engagement/agreement still **vigente**. The 23 volunteer agreements run to **2026-12-19** — they do
**not** expire at this turn. **The retained-vs-exit frontier is empty this turn.** Adversarial gap-check
2026-07-03: all 22 retained members are `member_status='active'`, `is_active=true`, loginable, zero `guest` —
**no accidental denied state on the retained side.** All retain access.

### 2.3 EXIT / RESTRICT (involuntary / data-driven)
**EMPTY — adversarially confirmed 2026-07-03.**
- **No leak (ended-but-active):** query 2a → **0** across all (origin × kind) rows; additionally **0** active
  engagements with `end_date` ≤ 2026-07-09 (nothing lapses unattended at the turn).
- **No orphan access (2c):** every operational role has an active engagement — researcher 23/23,
  chapter_liaison 11/11, tribe_leader 6/6, sponsor 5/5, manager 2/2 (0 without engagement). Roles without
  an active engagement are `alumni` (22), `none` (5), `guest` (1 of 39) — all correct non-access states.
- **Renewal radar (2e, turn date 2026-07-09):** lapsing **0** · active_future 55 · unknown 15 (unknown = VEP
  service-end unresolvable — renewal-forecasting backlog, NOT an access lapse: all 15 have engagement
  `end_date` NULL or ≥ 2026-12-19).
- Latent-hardening findings from the adversarial pass (none exploitable today — 0 affected rows) are tracked
  in the session log, not here: `is_authoritative` not checking `revoked_at`; `rls_is_authoritative_member`
  trusting the role cache; 3 identity-bridge under-grant drifts; offboarded-member residuals (open checklist
  assignment, retained `tribe_id`).

### 2.3b VOLUNTARY transitions at the turn (member/governance-driven, NOT data-driven)
Separate from §2.3: the C3-closure review (2026-07-01, cross-ref #1003) surfaced **2 confirmed voluntary
transitions** — legitimate member-lifecycle actions decided by governance/the member, not by the leak audit.
1. **One `tribe_leader` (tribe 2) — non-renewal → `alumni`** at cycle turn. `admin_offboard_member(p_new_status
   => 'alumni', p_reason_category => 'end_of_cycle')` (return-preserving → auto-emits `alumni_recognition`).
   **STATUS 2026-07-03: PENDING — GP decision (this freeze): execute at the 09/07 turn; the tribe-2 successor
   will be named AFTER the transition.** This is a **conscious exception** to the doc's original
   successor-first precondition, recorded here per the GP's 2026-07-03 in-session decision; tribe 2 runs
   temporarily leaderless until the successor is named.
2. **One `researcher` (tribe 7) — own request → `alumni`** at C3 closure (capacity: work + graduate studies).
   **STATUS: EXECUTED 2026-07-03 12:00 UTC** via the platform offboarding flow — member → `alumni`,
   `is_active=false`, 2 C3-origin engagements offboarded, `alumni_recognition` auto-emitted, return
   eligibility preserved. **Governance notes (recorded honestly):** (a) execution preceded the formal §5
   sign-off of this freeze — **ratified retroactively by the GP on 2026-07-03** (in-session decision) as the
   member's own documented request; (b) the flow recorded `reason_category_code='other'` (the
   `offboard_member` wrapper default) instead of the prescribed `personal_workload` — **corrected 2026-07-03
   via a governed 1-row UPDATE** (both codes preserve return eligibility; the correction aligns the record
   with the actual reason for `re_engagement_pipeline` semantics). NOT `observer`: the member proposed an
   "ouvinte" role, but per PM the observer state was governance-rejected (a non-volunteer is unbound by the
   term → LGPD/data/IP exposure). **WhatsApp groups + Drive are external and must be revoked separately** —
   1 Drive `pending_revoke` awaits GP approval (see #1020 handoff + `DRIVE_OFFBOARDING_CASCADE.md`).

> Voluntary transitions run via `admin_offboard_member` (§3 step 2), **not** direct UPDATE. Member identities +
> personal context stay OFF this committed doc (public repo; LGPD Art. 11) — they live in the operator session.

### 2.4 Legacy / no-cycle engagements (context, not part of the turn)
78 active engagements with no origin cycle (chapter_board 16, speaker 13, observer 10, volunteer 7,
ambassador 7, workgroup_coordinator 5, committee_member 5, sponsor 5, workgroup_member 4, external_reviewer 2,
committee_coordinator 2, study_group_participant 1, study_group_owner 1). All 0-leak; unaffected by the turn.
(2 observer engagements expired 2026-07-02 → 80 became 78.)

### 2.5 ENTER-side readiness plan (added 2026-07-03 after the adversarial gap findings)

The adversarial pass refuted "all 40 will have access on day 9" — the real day-9 deliverable is the funnel
below. GP approved this plan 2026-07-03 (with the timing fact that the **C4 volunteer-term template is
approved on the 04–05/07 weekend**, so signing starts the week of 06/07 with target *all signed that week*).

| # | Action | Owner / when |
|---|---|---|
| 1 | **Term-signing campaign** for the 36 unsigned (32 loginable now): sequence = claim account → complete profile (7 required fields; ~22/36 pass today) → `sign_volunteer_agreement`. Set `sla_deadline` on the pending `volunteer_term` + `complete_profile` onboarding steps so `detect_onboarding_overdue` nudges. **The 2 incoming C4 tribe leaders sign FIRST** (GP decision 2026-07-03). | GP + comms · week of 06/07 (template gated on the weekend approval) |
| 2 | **Tribe-selection deadline fix**: `home_schedule.selection_deadline_at` is stale at 2026-03-09 → `select_tribe()` returns "Seleção encerrada" even for signed members. Update to a C4 window BEFORE signatures land; verify capacity (6 slots/tribe × incoming 36+). | governed 1-row UPDATE · before 09/07 |
| 3 | **Leader allocation**: leaders don't self-select (`select_tribe` blocks by design) — admin-allocate the 2 C4 tribe leaders once signed. Without it the C4 tribes open leaderless. | GP/admin · before 09/07 |
| 4 | **Auth outreach to the 4 `auth_id IS NULL`** (0 logins ever; 1 of the 4 never received the cutoff-approved email; passive account-linking only — #1014 feature gap). Direct e-mail/WhatsApp nudge to claim account; kick-off calendar invite (sent 2026-07-03, 09/07 19:00 BRT) doubles as a hook. | GP · this week |
| 5 | **In-flight owner**: run `approve_selection_application` same-day for any of the 7 pipeline approvals landing before 09/07; late entrants fold into the campaign. | GP (RPC is `manage_platform`-gated) |

Supporting actions executed 2026-07-03: pre-onboarding WhatsApp-group link **fixed** in
`campaign_templates:cycle4_pre_onboarding_whatsapp_20260613` (a stale/wrong invite link went to 25 recipients
on 13/06 — the complaint that surfaced it); **kick-off event created** (09/07 19:00–20:30 BRT, Meet, all 67 =
40 entering + 31 continuing invited, recording notice + pre-meeting checklist in the invite); affiliation
verification automation proposed as **#1095**.

---

## 3. Execution runbook (for exits surfaced by a re-run)

The involuntary exit list is empty, so **no involuntary execution step runs**. The runbook below is the
standing procedure for any turn where 2a/2c surface a genuine exit, and governs the §2.3b item-1 voluntary
transition at this turn.

1. **Freeze + sign.** Re-run 2a–2e, refresh this doc, and have the **named approver (GP/Presidência) sign the
   list BEFORE execution** (never retroactive). Record approver name + timestamp in §5.
2. **Execute via RPC only — `admin_offboard_member`, NOT `offboard_member`.**
   ```
   admin_offboard_member(
     p_member_id      => <uuid>,
     p_new_status     => 'alumni' | 'inactive',                 -- only these 2 are valid ('observer' retired, #1022-C)
     p_reason_category => 'end_of_cycle',                        -- correct category, see below
     p_reason_detail  => '<free text>',
     p_reassign_to    => <uuid or NULL>                          -- reassign that member's open board_items
   )
   ```
   - **Why `admin_offboard_member` and not `offboard_member`:** the correct `reason_category` drives
     `re_engagement_pipeline` eligibility + the LGPD anonymization guard (ADR-0116 §6). Until 2026-07-08 BOTH
     paths lost it: the record was written by `trg_offboarding_stub`, which infers the category from
     `members.status_change_reason` and lands on `'other'` whenever a free-text detail is passed (the wrapper
     propagates the parameter correctly — the earlier "wrapper hardcodes 'other'" reading was wrong). The
     §2.3b executions proved the failure mode live twice (both recorded `'other'`, corrected post-hoc).
     **Fixed structurally 2026-07-08 (mig `20260805000375`, #1200):** `admin_offboard_member` now writes
     `member_offboarding_records` itself with the FK-validated caller category. The direct RPC remains the
     prescribed path for governed turns (native trail, no MCP layer).
   - **`reason_category` for a natural cycle turn = `end_of_cycle`** (`preserves_return_eligibility=true` → auto-
     emits an `alumni_recognition` certificate when `p_new_status='alumni'`). Voluntary capacity exits use the
     matching personal code (e.g. `personal_workload`). Other codes: `reacceptance_lapse` /
     `reacceptance_refusal` (Camada 5 paths, both preserve return), `policy_violation` (the only involuntary
     code — `preserves_return_eligibility=false`), `other` (wrapper default — avoid; preserves return but
     carries no audit meaning).
   - **ZERO direct `UPDATE`/DDL** on `members`/`engagements` — the RPC writes the native trail
     (`offboarded_by`, `admin_audit_log`, engagement `revoked_at/revoke_reason`) and preserves the LGPD chain;
     a manual UPDATE is indistinguishable from an error in audit.
3. **Enter side:** execute the §2.5 readiness plan (signing campaign, deadline fix, leader allocation, auth
   outreach, in-flight owner).
4. **Confirm entering readiness:** the C4 cohort has `onboarding_progress` and the cycle's `onboarding_steps`
   are configured (procedure §3.4). Confirmed 2026-07-03: 40/40 + 5 steps.

---

## 4. Post-cut reconciliation (2026-07-09 → 2026-07-11)

Re-run the audit AFTER the turn and confirm planned == real, in both directions. Archive the output.
- **Exit reconciliation (anchor 2026-07-03, NOT 07-09 — it must capture the §2.3b executions):**
  `list_offboarding_records(p_since => '2026-07-03')` must show **exactly** the signed set: the §2.3b item-2
  record (executed 03/07, ratified) + the §2.3b item-1 record (if executed at the turn). Nothing else.
- **Leak recheck:** re-run 2a + 2c → 0 ended-but-active, 0 operational-role orphans.
- **Enter recheck:** re-run 2d → `loginable == active_eng` for `cycle4-2026` (the 4-member gap closed, or the
  residual documented with the outreach status) **+ term-signing progress vs the §2.5 target (all signed by
  ~12/07)** + tribe assignment progress once the deadline fix lands.

---

## 5. Sign-off

| Field | Value |
|---|---|
| Freeze grounded (audit run) | 2026-07-01 · re-grounded + adversarially verified 2026-07-03 (re-run 2a–2e before 2026-07-09 execution) |
| Involuntary exit list this turn | **EMPTY** (adversarially confirmed) |
| Voluntary transitions | item 2 (tribe-7 researcher → alumni) EXECUTED 03/07, ratified retroactively + category corrected; item 1 (tribe-2 leader → alumni) approved to execute at the 09/07 turn, successor named after (conscious exception) |
| Day-9 / turn-week actions | §2.5 readiness plan (5 actions) + GP outreach to the 4 no-auth entrants |
| Approver (GP/Presidência) | **Vitor Maia Rodovalho (GP)** — approved in-session (AskUserQuestion decisions) |
| Approval timestamp | **2026-07-03** |
| Executed by | GP + dev session (governed RPC/DML only) |
| Reconciliation archived | pending — due 2026-07-09 → 2026-07-11 (§4); pre-check run 2026-07-08 (green, see execution note) |

**Execution note (2026-07-08) — turn executed one day EARLY with owner authorization.** The owner revoked the
05/07 no-anticipation decision in-session (explicit AskUserQuestion approval; the tribe-2 team had already been
notified). Executed, all re-grounded live before applying (full report in #1124):
- **§2.3b item 1** (tribe-2 leader → `alumni`): executed via MCP `offboard_member` preview→confirm — 2 active
  engagements closed, `alumni_recognition` auto-emitted. The record initially carried `'other'` (the
  trigger-inference failure described in §3 step 2) and was corrected same-day to `end_of_cycle` via governed
  1-row UPDATE; the root cause is now fixed structurally (mig `20260805000375`, #1200).
- **Tribe 2 archived**: `tribes id=2 is_active=false`, its initiative archived, `members.tribe_id` cleared on
  7 rows (runbook predicted 4; live grounding found 3 additional stale pointers). Re-selection window open
  until 17/07 (cap 7/tribe).
- **§4 pre-check green**: exit reconciliation anchor ✓ (exactly 3 offboarding records since 03/07); leaks
  2a = 0, 2c = 0; enter side 2d = 47 active engagements / 47 linked / 47 onboarding, 45 loginable (residual
  gap = 2 pre-onboarding guests, #1014 — auth is created on first login).
- **Cycle close bookkeeping**: batch `cycle3-2026-b2` → closed/announcement; 251 C3 cards archived (live count
  08/07; the C2 precedent was 236/236). Schema invariants: 0 violations after each mutation.
- **Residuals** (PM/GP, not dev): C3 `general` champion decision; Onda 1 certificates counter-signature
  (#1169); #1003 remainder (C3 certificates, [LL] lessons, closing comms).

---

## 6. Camada 5 (#976) hook

When #976 is ratified/activated it automates §3 steps 1–2 (retained-cohort computation +
aviso→suspensão→desligamento clock + outward-notification gate #334). Until then this manual freeze is the
turn's governance artifact. A turn whose 2a/2c **does** surface an exit is the natural trigger to prioritize
#976 activation. The §2.5 enter-side funnel (sign-the-term campaign mechanics) is likewise the natural seed
for the entering half of that automation.
