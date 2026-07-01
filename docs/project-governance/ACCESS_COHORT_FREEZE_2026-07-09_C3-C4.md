# Access-cohort freeze — C3→C4 turn (day 9, 2026-07-09)

**Issue:** #1004 (EPIC #1002). **Procedure of record:** `docs/operations/cycle-turn-access-cohort-procedure.md` (#1013).
**Type:** frozen, dated, sign-before-execution list (council-review 2026-07-01 requirement).
**Grounded live:** 2026-07-01 via read-only `execute_sql` (queries 2a–2d of the procedure). Re-run 2a–2d
immediately before execution on 2026-07-09 and diff against this freeze — a turn is only as valid as its
freshest audit.

> **LGPD.** This committed doc carries **aggregates only** — no member identities. The identified per-person
> keep/enter/exit list lives in the operator's session at execution time (and, if archived, off-repo). Access
> is driven by **active engagement**, not "cycle" (ADR-0106: "access" = `member_status`/`is_active` read by RLS,
> not a UI toggle — a mistake here is a real leak or denial).

---

## 1. Decision (this turn)

**No offboarding is justified by the data this turn. Exit list = EMPTY.** The only day-9 action is closing a
small login gap for the entering cohort. Camada 5 (#976) is dormant, so this turn is executed **manually** by
the procedure of record — but this turn requires **no access-flip execution**, only the entering-gap nudge.

---

## 2. Frozen cohorts (grounded 2026-07-01)

Total active, non-revoked engagements: **153** (36 entering + 37 retained C3-origin + 80 legacy/no-cycle).

### 2.1 ENTER — Cycle 4 (`cycle4-2026`)
| Metric | Count | Meaning |
|---|---|---|
| Active `volunteer` engagements | 36 | all provisioned |
| Linked member record | 36/36 | none orphaned |
| **Loginable (`auth_id` set)** | **32/36** | **4 NOT loginable → day-9 gap** |
| Without agreement cert | 32 | expected — agreement is signed during onboarding |

**Criterion:** application accepted (VEP `Active`/`OfferExtended`) + active engagement provisioned. All 36 qualify.
**Action:** the **4 members without `auth_id`** cannot access on day 9 despite an active engagement → send a
targeted account-claim / auth invite before the turn. No directed per-member invite mechanism exists today
(`request_account_claim` needs prior auth; admin auth-invite is absent; `send-global-onboarding` over-sends) →
**workaround = GP manual nudge to the 4**; feature gap tracked in **#1014**.

### 2.2 RETAIN — Cycle 3 (`cycle3-2026` + `cycle3-2026-b2`)
| Metric | Count | Meaning |
|---|---|---|
| Active C3-origin engagements | 37 | retained |
| `volunteer_agreement` certs | 24 | all **issued**, period **2026-01-20 → 2026-12-19** |
| Non-volunteer kinds w/o agreement cert | 13 | workgroup/ambassador/observer/committee — no agreement cert by design |

**Criterion:** engagement/agreement still **vigente**. The 24 volunteer agreements run to **2026-12-19** — they do
**not** expire at this turn. **The retained-vs-exit frontier is empty this turn**: no C3 agreement lapses on
2026-07-09, so there is no ambiguous per-person boundary to adjudicate. All 37 retain access.

### 2.3 EXIT / RESTRICT (involuntary / data-driven)
**EMPTY.** No candidate for *involuntary* offboarding.
- **No leak (ended-but-active):** query 2a → **0** active engagements with a past `end_date` across all 22
  (origin × kind) rows.
- **No orphan access (2c):** every operational role has an active engagement — researcher 24/24,
  chapter_liaison 11/11, tribe_leader 6/6, sponsor 5/5, manager 2/2 (0 without engagement). The only roles
  without an active engagement are `alumni` (21), `none` (5), `guest` (1 of 35) — all correct non-access states.

### 2.3b VOLUNTARY transitions at the turn (member/governance-driven, NOT data-driven)
Separate from §2.3: the C3-closure review (2026-07-01, cross-ref #1003) surfaced **2 confirmed voluntary
transitions** — these are legitimate member-lifecycle actions decided by governance/the member, not by the leak
audit. The "empty exit list" above refers only to involuntary/data-driven offboarding.
1. **One `tribe_leader` (tribe 2) — non-renewal → `alumni`** at cycle turn. `admin_offboard_member(p_new_status
   => 'alumni', p_reason_category => 'end_of_cycle')` (return-preserving → auto-emits `alumni_recognition`).
   **Triggers a tribe-2 leadership succession for cycle 4** (name a successor before the leader steps down).
2. **One `researcher` (tribe 7) — own request → `observer`** for the rest of the cycle (capacity: work +
   graduate studies; well-regarded, 100% attendance when present, wants to keep following). `admin_offboard_member
   (p_new_status => 'observer', p_reason_category => 'personal_workload')` (return-preserving; keeps read access
   as observer, not a full exit).

> Both require the §3.1 named-approver sign-off before execution and must run via `admin_offboard_member` (§3.2),
> **not** direct UPDATE. Member identities + the health/personal context stay OFF this committed doc (public repo;
> LGPD Art. 11 sensitive data) — they live in the operator session / off-repo. Timing: the `observer` transition
> is "até o final do ciclo" (execute at/around C3 close 02/07); the non-renewal aligns with the C4 turn.

### 2.4 Legacy / no-cycle engagements (context, not part of the turn)
80 active engagements with no origin cycle (chapter_board 16, speaker 13, observer 12, volunteer 7,
ambassador 7, workgroup_coordinator 5, committee_member 5, sponsor 5, workgroup_member 4, external_reviewer 2,
committee_coordinator 2, study_group_participant 1, study_group_owner 1). All 0-leak; unaffected by the turn.

---

## 3. Execution runbook (only if a future re-run surfaces an exit)

This turn's exit list is empty, so **no execution step runs**. The runbook below is the standing procedure for
any turn where 2a/2c surface a genuine exit (ended-and-not-renewed engagement, or an operational-role orphan).

1. **Freeze + sign.** Re-run 2a–2d, refresh this doc, and have the **named approver (GP/Presidência) sign the
   list BEFORE execution** (never retroactive). Record approver name + timestamp in §5.
2. **Execute via RPC only — `admin_offboard_member`, NOT `offboard_member`.**
   ```
   admin_offboard_member(
     p_member_id      => <uuid>,
     p_new_status     => 'alumni' | 'observer' | 'inactive',   -- only these 3 are valid
     p_reason_category => 'end_of_cycle',                        -- correct category, see below
     p_reason_detail  => '<free text>',
     p_reassign_to    => <uuid or NULL>                          -- reassign that member's open board_items
   )
   ```
   - **Why `admin_offboard_member` and not `offboard_member`:** `offboard_member` is a thin wrapper that calls
     `admin_offboard_member` with `reason_category => 'other'` **hardcoded**. The council requires the *correct*
     `reason_category` (it drives `re_engagement_pipeline` eligibility + the LGPD anonymization guard, ADR-0116
     §6), so the wrapper is unusable for a governed turn. **⚠️ The procedure doc #1013 currently names
     `offboard_member` in §3.2 — that is a defect; the correct RPC is `admin_offboard_member`. File a one-line
     correction to #1013 (dev lane).**
   - **`reason_category` for a natural cycle turn = `end_of_cycle`** (`preserves_return_eligibility=true` → auto-
     emits an `alumni_recognition` certificate when `p_new_status='alumni'`). Other codes if applicable:
     `reacceptance_lapse` / `reacceptance_refusal` (Camada 5 paths, both preserve return), `policy_violation`
     (the only involuntary code — `preserves_return_eligibility=false`, no return, no alumni cert).
   - **ZERO direct `UPDATE`/DDL** on `members`/`engagements` — the RPC writes the native trail
     (`offboarded_by`, `admin_audit_log`, engagement `revoked_at/revoke_reason`) and preserves the LGPD chain;
     a manual UPDATE is indistinguishable from an error in audit.
3. **Enter gap (this turn's only real action):** GP nudge / account-claim for the 4 entering C4 members without
   `auth_id` so they can access on day 9 (#1014).
4. **Confirm entering readiness:** the C4 cohort has `onboarding_progress` and the cycle's `onboarding_steps` are
   configured (procedure §3.4).

---

## 4. Post-cut reconciliation (2026-07-09 → 2026-07-11)

Re-run the audit AFTER the turn and confirm planned == real, in both directions. Archive the output.
- **Exit reconciliation:** everyone on the (empty this turn) exit list is offboarded; nobody offboarded who was
  not on the signed list → `list_offboarding_records(p_since => '2026-07-09')` should show **exactly** the signed
  set (empty this turn).
- **Leak recheck:** re-run 2a + 2c → 0 ended-but-active, 0 operational-role orphans.
- **Enter recheck:** re-run 2d → `loginable == active_eng` for `cycle4-2026` (the 4-member gap closed), or the
  residual documented with the GP-nudge status.

---

## 5. Sign-off (fill before execution)

| Field | Value |
|---|---|
| Freeze grounded (audit run) | 2026-07-01 (re-run before 2026-07-09) |
| Exit list this turn | **EMPTY** |
| Day-9 action | GP nudge to 4 entering members w/o `auth_id` (#1014) |
| Approver (GP/Presidência) | _______________________ |
| Approval timestamp | _______________________ |
| Executed by | _______________________ |
| Reconciliation archived | _______________________ |

---

## 6. Camada 5 (#976) hook

When #976 is ratified/activated it automates §3 steps 1–2 (retained-cohort computation +
aviso→suspensão→desligamento clock + outward-notification gate #334). Until then this manual freeze is the
turn's governance artifact. A turn whose 2a/2c **does** surface an exit is the natural trigger to prioritize
#976 activation.
