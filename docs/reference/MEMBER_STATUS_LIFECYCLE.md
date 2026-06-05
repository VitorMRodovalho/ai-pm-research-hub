# Member status lifecycle — canonical semantics

> **Status:** code-confirmed (2026-06-05, #483). Reflects live behaviour of
> `members.member_status`, the `sync_member_status_consistency()` B-trigger, and
> the offboarding RPCs. **PM may refine the prose wording**, but the column
> behaviour described here is what the code does today.

## The four `member_status` values

`members.member_status` is the lifecycle state. It drives `is_active`,
`operational_role`, `designations`, and `current_cycle_active` (CCA) via the
`sync_member_status_consistency()` BEFORE trigger
(`BEFORE INSERT OR UPDATE OF member_status, operational_role, is_active, designations`).

| status | `is_active` | re-engageable? | how it is set | meaning |
|---|---|---|---|---|
| `active` | `true` | n/a | onboarding / approval | in good standing, participating |
| `observer` | `false` | per offboarding reason | offboard | watching, not a full participant |
| `alumni` | `false` | **yes** (good-standing egress) | **automatic** | finished/left in good standing; eligible for re-engagement |
| `inactive` | `false` | **no** | **manual** | paused or severed; **not** re-engagement-eligible |

### alumni vs inactive — the distinction

Both have `is_active=false`. The difference is **re-engagement eligibility**:

- **`alumni`** is the *good-standing egress*. It is set **automatically** —
  `_auto_stage_alumni_on_cycle_open` → `stage_alumni_for_re_engagement`, and an
  offboard whose reason has `preserves_return_eligibility=true` also auto-emits an
  `alumni_recognition` certificate. Alumni are surfaced to the re-engagement
  pipeline (`invite_alumni_to_re_engage`, `list_re_engagement_pipeline`).
- **`inactive`** is the *paused/severed* state, set **manually**. It is **not**
  re-engagement-eligible. Use it when a member should not be auto-invited back.

> Rule of thumb: if the person left cleanly and could be welcomed back, they are
> `alumni`. If they were paused/removed and should not be auto-recirculated, they
> are `inactive`.

## Coercions enforced by `sync_member_status_consistency()`

On any write that touches `member_status`/`operational_role`/`is_active`/`designations`,
the trigger coerces:

1. `active` ⇒ `is_active=true`.
2. `observer|alumni|inactive` ⇒ `is_active=false`.
3. `observer|alumni|inactive` ⇒ **`current_cycle_active=false`** (added #483 — see below).
4. `alumni` ⇒ `operational_role='alumni'`.
5. `observer` ⇒ `operational_role IN (observer, guest, none)`.
6. `observer|alumni|inactive` ⇒ `designations='{}'`.

## `current_cycle_active` (CCA)

`current_cycle_active` is a stored boolean meaning **"counts in the current
cycle's active cohort."** It is set `true` only on the way *into* a cycle
(`approve_selection_application`, `update_onboarding_step`).

**#483 fix:** before #483, no writer reset CCA on the way *out* — offboarding left
it `true`, so 3 offboarded members (Andressa Martins, Maria Luiza, Herlon Alves de
Sousa) carried `current_cycle_active=true` while `is_active=false`. The B-trigger
now resets CCA to `false` for any terminal status (coercion #3), and migration
`20260805000117` one-time-cleared the existing drift.

### Known consumer caveat (tracked in #419/#421)

`get_gamification_leaderboard` and `get_public_leaderboard` gate their cohort on
`gamification_opt_out=false AND (current_cycle_active=true OR EXISTS current-cycle
points)` — with **no `is_active`/`member_status` filter**. So an offboarded member
who still has current-cycle gamification points surfaces in the cycle leaderboard
via the `OR EXISTS` branch even after CCA is corrected. Hardening that predicate
(adding an `is_active` guard, the canonical "active now" definition) is owned by
**#419/#421**, not #483.

## Invariant coverage

- `B_is_active_status_mismatch` (check_schema_invariants) — `is_active` ⟷ `member_status`.
- `C_designations_in_terminal_status` — designations empty in terminal status.
- `N_terminal_status_offboarded_at_present` — terminal ⇒ `offboarded_at` set.
- `L_offboarding_record_present` — terminal ⇒ a `member_offboarding_records` row.
- **CCA ⟷ terminal status** — currently guarded by the `#483` contract test
  (`tests/contracts/483-current-cycle-active-terminal-status.test.mjs`); promoting
  it into `check_schema_invariants()` as `B2_current_cycle_active_terminal_status`
  is a deferred follow-up.
