# P168 D=1 Brief — Paulo Alves Auth Hijack (LGPD P0)

**Date:** 2026-05-15
**Status:** Active vulnerability — exploiting itself in real time
**Investigator:** Claude (Opus 4.7) under PM read-only mandate (no DML this session)
**Decision required:** PM authorization for 6 remediation steps below

---

## TL;DR

Two unrelated people whose names both start with "Paulo":

- **Paulo Alves De Oliveira Junior** — researcher, member `57fcf33c…`, legitimate owner of member row
- **Paulo Roberto de Camargo Filho** — NO member row, only an `auth.users` entry (signed up via Google 2026-05-02)

`paulorobertodecamargofilho@gmail.com` ended up inside Paulo Alves' `members.secondary_emails` array. The live `get_member_by_auth()` RPC matches incoming auth users against any member's `secondary_emails` and **silently reassigns `members.auth_id` to the new login**, demoting the prior primary to `secondary_auth_ids`. There is no ownership-verification step.

Result: every time Paulo Roberto's browser session refreshes, his Google identity steals Paulo Alves' member row. Paulo Roberto's session sees Paulo Alves' full PII (`email`, `phone`, `pmi_id`, `address`, `city`, `birth_date`, `signature_url`, `secondary_emails`, badges, gamification) and inherits Paulo Alves' `researcher` role + tribe membership.

Last contamination event: **today 2026-05-15 22:39:41 UTC** (session-token silent refresh, members row updated 0.6s later).

This is a **P0 LGPD incident** (unauthorized PII disclosure) and an **active identity-hijack vulnerability** that can affect any member whose `secondary_emails` list contains an address later used by a different person to sign up.

Blast-radius scan: currently **1 member affected** (Paulo Alves only). The vulnerability surface is platform-wide for any future collision.

---

## Identity facts

| Attribute | Paulo Alves De Oliveira Junior (real owner) | Paulo Roberto de Camargo Filho (hijacker by accident) |
|---|---|---|
| `members.id` | `57fcf33c-25a3-4555-b358-a168a4151794` | *(none)* |
| `persons.id` | `9eee76a1-5671-4a41-8eee-2d211af2ec68` | *(none)* |
| `members.email` (canonical) | `paulo-junior@outlook.com` | n/a |
| Google `auth.users.id` | `75642574-8ab4-4555-82fa-5ee1ea0c876e` (pejota81@gmail.com) | `a2407bdc-c524-45d4-bb54-2b18d628dee5` (paulorobertodecamargofilho@gmail.com) |
| LinkedIn `auth.users.id` (historical) | `c82d70f7-35c3-4ddf-a129-bbeecbe820fd` (paulo-junior@outlook.com) | n/a |
| Last sign-in | 2026-05-08 19:59:44 | 2026-05-08 21:12:05 (sessions still refreshing silently — last refresh 2026-05-15 22:39:41) |

Current contaminated state:

```
members[57fcf33c]
  email             = paulo-junior@outlook.com
  auth_id           = a2407bdc  ← Paulo Roberto (WRONG)
  secondary_auth_ids = [a37f02f4, ffe43ecd, c82d70f7, 75642574]  ← Paulo Alves' real ids here
  secondary_emails  = [pejota.paulojr@gmail.com, pejota81@gmail.com,
                       paulorobertodecamargofilho@gmail.com  ← contaminating alias]

persons[9eee76a1]
  email             = paulo-junior@outlook.com
  auth_id           = 75642574  ← Paulo Alves' Google (CORRECT)
  secondary_emails  = [pejota.paulojr@gmail.com, pejota81@gmail.com]  ← clean
  legacy_member_id  = 57fcf33c
```

`persons` is clean and authoritative; `members` is the contaminated side. The `D_auth_id_mismatch_person_member` invariant catches exactly this gap (count = 1 today).

`auth.users` entries `a37f02f4` and `ffe43ecd` (in secondary_auth_ids) no longer exist — likely deleted in a prior cleanup. Not load-bearing.

---

## Root cause (code)

`public.get_member_by_auth()` — live body in prod, **not captured by any migration in `supabase/migrations/`** (drift; baseline at `supabase/migrations/00000000_baseline_rpcs.sql:19` is a simple `WHERE auth_id = auth.uid()`):

```sql
-- Step 1: direct hit on auth_id  → return
-- Step 2: match on secondary_auth_ids → swap (a2407bdc into primary, old primary into secondary)
-- Step 3: match by email
--   3a. members.email lower = auth.email lower
--   3b. EXISTS unnest(secondary_emails) where lower(se) = lower(auth.email)
--   When found AND existing auth_id IS NOT NULL:
--     UPDATE members SET auth_id = v_uid,
--                        secondary_auth_ids = array_append(secondary_auth_ids, v_existing_auth_id),
--                        updated_at = now()
--      WHERE id = v_member_id;
```

The branch at 3b runs on **every call** to `get_member_by_auth()` from a session whose `auth.email` matches some other member's `secondary_emails`. There is no:
- ownership verification on adding to `secondary_emails`
- cooldown
- audit trail to `admin_audit_log`
- consent step

`secondary_emails` is writable directly via PostgREST from the client at `src/pages/profile.astro:1876`:

```ts
const newList = [...existing, email];
await sb.from('members').update({ secondary_emails: newList }).eq('id', currentMember.id);
```

Any authenticated member can add any string to their own `secondary_emails`. RLS allows self-update of the row. No verification email is sent.

---

## Timeline

| When (UTC) | Event |
|---|---|
| 2026-03-05 17:35 | Paulo Alves' member row created (admin or VEP), `auth_id NULL` |
| 2026-03-06 00:21 | Paulo Alves signs up via LinkedIn (`c82d70f7`, paulo-junior@outlook.com) → `try_auto_link_ghost()` matches primary email, sets `members.auth_id = c82d70f7` |
| *(unknown)* | `paulorobertodecamargofilho@gmail.com` added to `members.secondary_emails`. Likely via profile.astro by Paulo Alves himself (mistake / typo / autocomplete) — no audit log entry exists for this write |
| 2026-05-02 19:45 | Paulo Roberto signs up via Google (`a2407bdc`). `get_member_by_auth()` matches Paulo Alves' member row via secondary_emails branch → flips `members.auth_id` to `a2407bdc`, demotes `c82d70f7` to secondary |
| 2026-05-07 22:32 | Paulo Alves signs in via Google (`75642574`). `get_member_by_auth()` matches via secondary_emails branch → flips `members.auth_id` to `75642574`, demotes `a2407bdc` to secondary |
| 2026-05-08 19:14 | An admin (member `880f736c`) reads Paulo Alves' email/phone via `get_initiative_member_contacts` (PII access log) — legitimate |
| 2026-05-08 19:59 | Paulo Alves session #2 (last legitimate-owner sign-in to date) |
| 2026-05-08 21:12 | Paulo Roberto session #2 → re-flips `members.auth_id` to `a2407bdc` |
| 2026-05-08 23:59 | Admin script (p123-close) runs `persons.auth_id_synced_from_members` — moves persons.auth_id from `c82d70f7` → `75642574`. Audit-log comment notes "ghost-resolution updated members.auth_id but persons.auth_id stale" → at the moment of fix, members.auth_id was `75642574` |
| 2026-05-14 | PM audit (p159 S#3) inspected ghost-visitor list, misclassified `paulorobertodecamargofilho@gmail.com` as a "duplicate of Paulo" — comment encoded in `supabase/migrations/20260636000000_p159_s3b_get_ghost_visitors_filter_primary_email.sql` lines 4-7. This sealed the assumption in the codebase |
| 2026-05-15 00:15-00:20 | Admin `880f736c` reads Paulo Alves' contact via tribe/initiative RPCs (PII log) — legitimate |
| 2026-05-15 22:39:41 | Paulo Roberto's session token refresh (auth.sessions row 390ee646 `refreshed_at`) |
| 2026-05-15 22:39:42 | `members[57fcf33c].updated_at` — `get_member_by_auth` re-claimed Paulo Alves' row |
| 2026-05-15 *now* | Platform-guardian invariant D = 1; this brief written |

---

## Blast radius

### PII exposed to Paulo Roberto's session

Each call to `get_member_by_auth()` from Paulo Roberto's session returned the entire Paulo Alves member row to the client. From the current function body, the returned JSON includes:

```
id, name, email, secondary_emails, pmi_id, phone, operational_role,
designations, role, roles, chapter, tribe_id, current_cycle_active,
is_superadmin, is_active, member_status, state, country,
share_whatsapp, signature_url, address, city, birth_date,
share_address, share_birth_date, privacy_consent_*, photo_url,
linkedin_url, auth_id, credly_url, credly_badges, cpmai_certified,
created_at, updated_at
```

All sensitive fields. Plus any downstream RPC keyed on `auth.uid()` would treat Paulo Roberto's session as Paulo Alves — including write actions if Paulo Roberto took them (XP grants, board cards, applications, etc).

### Cross-member PII access from Paulo Roberto's session

`pii_access_log` table has no entries with `accessor_id = 57fcf33c` since 2026-05-02 — but `accessor_id` is `members.id`, not auth_id. Since Paulo Roberto's session resolves to member 57fcf33c, any cross-member PII read he triggered would log as Paulo Alves accessing it. **There are no such entries**, suggesting Paulo Roberto did not actively browse other members' contacts. (Self-reads of Paulo Alves' own data are not logged.)

### Other members affected

```
Members with secondary_emails containing an email that belongs to a DIFFERENT
auth.users entry (i.e., the hijack precondition):  1   ← only this Paulo Alves row
```

No other members are presently at risk under the same exact pattern. The vulnerability surface remains platform-wide for future collisions.

### Forward-going damage if untreated

While Paulo Roberto's browser tab remains open, every session refresh (Supabase default 1h JWT TTL, with refresh tokens) re-runs the hijack. Any data Paulo Alves enters via his own session (if he could even sign in — his auth_id is currently demoted to secondary, so login works via the secondary_auth_ids branch which re-flips back to him, then Paulo Roberto's next refresh re-flips again) is racing against Paulo Roberto's refreshes.

This also means Paulo Alves' **persons.auth_id = 75642574** is now stale relative to members.auth_id = a2407bdc → the `D_auth_id_mismatch_person_member` invariant remains tripped indefinitely.

---

## Why this didn't surface earlier

1. The `D` invariant was added long ago but treated as cosmetic drift (D=1 has appeared in handoffs as "pre-existing carry" without escalation).
2. The 2026-05-08 admin fix (`p123-close`) ran one-shot `UPDATE persons` to align with members — it did not address the recurring `members` write.
3. The 2026-05-14 PM audit (p159 S#3) categorized the suspicious `paulorobertodecamargofilho@gmail.com` ghost as a "Paulo duplicate" and silenced it from the visitor list, removing the surface signal.
4. `admin_audit_log` does not record changes from `get_member_by_auth()` (the function does not call any audit-log writer).

---

## Recommendations — PM decision required

Each item below requires explicit PM authorization. Nothing applied this session.

### R1 (urgent, blocks bleed) — revoke Paulo Roberto's active sessions

```sql
-- Forces immediate sign-out + no further silent refreshes from a2407bdc
-- (Paulo Roberto's auth.users.id — full UUID redacted from doc, see audit_log entry)
DELETE FROM auth.refresh_tokens WHERE user_id = '<paulo-roberto-auth-uuid>';
DELETE FROM auth.sessions      WHERE user_id = '<paulo-roberto-auth-uuid>';
```

After this, Paulo Roberto's next sign-in attempt would still hit the vulnerability (R3 patch must precede or accompany).

### R2 — clean the contaminated arrays

```sql
-- Full UUIDs are in the corresponding admin_audit_log entry (action =
-- 'members.auth_state_restored_p168_r2'); inlined here as <placeholders>.
UPDATE members
   SET secondary_emails  = ARRAY['pejota.paulojr@gmail.com','pejota81@gmail.com']::text[],
       secondary_auth_ids = ARRAY['<linkedin-auth-uuid>']::uuid[],  -- Paulo Alves' historical LinkedIn only
       auth_id           = '<google-pejota81-auth-uuid>',           -- Paulo Alves' Google (canonical)
       updated_at        = now()
 WHERE id = '<paulo-alves-member-uuid>';

-- Verify persons remains aligned (already correct):
-- persons.auth_id = google-pejota81, secondary_emails clean.
```

Decision: should `c82d70f7` (LinkedIn, last sign-in 2026-03-30) remain in `secondary_auth_ids`? It IS Paulo Alves — keeping it preserves continuity if he reverts to LinkedIn login. Removing it would force a fresh ghost flow. **Recommendation:** keep, since it has no contamination risk (email is paulo-junior@outlook.com = primary).

### R3 (vulnerability patch) — gate `get_member_by_auth` secondary-email claim

Two paths, PM choice:

**R3-a (conservative, recommended):** remove the secondary_emails branch entirely from `get_member_by_auth`. Force secondary-email claims to go through an explicit verified-email flow (send confirmation email to address, click link → admin RPC writes `secondary_auth_ids`). Migration: redefine `get_member_by_auth` to only auto-claim when `members.email` (primary) matches AND `auth_id IS NULL`. Drift-from-baseline gets captured in a real migration file.

**R3-b (compromise):** keep secondary_emails branch but only when `auth_id IS NULL` (never overwrite an existing primary). Plus: emit `admin_audit_log` entry for any auto-claim, with details. This still permits the "Paulo Roberto signs up first" race if `secondary_emails` was populated before any sign-in.

In either case, `try_auto_link_ghost()` (migrations `20260403080000`, `20260415090000`, `20260425201155`) also has the dangerous "different auth_id" reassignment branch and should get the same treatment.

### R4 (ownership hardening) — require email verification before write to `secondary_emails`

Currently `src/pages/profile.astro:1876` writes `secondary_emails` directly via PostgREST. Replace with a SECURITY DEFINER RPC `request_secondary_email_verification(p_email)` that:

1. Generates a verification token, stores in a new `email_verification_pending` table
2. Sends an email to `p_email` with a confirmation link
3. The link calls `confirm_secondary_email(p_token)` which appends to `secondary_emails`

Also tighten RLS on `members.secondary_emails` to deny client writes (force them through the RPC).

### R5 (capture drift, deploy via migration) — bring `get_member_by_auth` back into migrations

The live function body has no source-of-truth file. After R3 is agreed, the new function body lands as a real migration with header explaining the prior gap. This restores `tests/contracts/rpc-migration-coverage.test.mjs` coverage (RPC body drift audit p50 sediment).

### R6 (forward audit + alerting) — wire D=1 to a real alert

`check_schema_invariants()` returns D drift counts but no one is notified when D > 0. Add an alert: send notification to admins (Vitor) when D > 0 for >24h. Or: extend `get_anomaly_report` / `get_operational_alerts` to surface it visibly in admin dashboard.

---

## Open questions for PM

1. **Identity attribution:** is `a2407bdc-c524-45d4-bb54-2b18d628dee5` (`paulorobertodecamargofilho@gmail.com`) a person you/PMI-GO know? Was this someone who applied to be a researcher and somehow got listed as an alias on Paulo Alves' account? Or a completely unrelated third party?
2. **Notification:** does Paulo Alves need to be told? (LGPD Art. 48: incidents likely to cause "relevant risk to data subject rights" trigger notification to ANPD + holder. Single-incident PII exposure to an unaffiliated third party probably qualifies.)
3. **Retention of Paulo Roberto's auth.users row:** if he is unaffiliated, delete his account entirely after R1? Or preserve in case he is a legitimate visitor who needs his own genuine ghost flow later?
4. **Ordering:** apply R1 (revoke sessions) immediately and accept that R3 patch comes after a short coding session? Or hold R1 until R3 is ready (~30 min) so we don't lock Paulo Roberto out before fixing the underlying bug?
5. **Disclosure:** is this severe enough to log under any compliance/incident-tracking obligation already in place (e.g., a `security_incidents` log)? I did not find such a table.

---

## What this session DID

- Read-only investigation only
- 3 task items tracked (verify scope · map attribution · this brief)
- No DML applied to any table
- Source files inspected (not modified):
  - `supabase/migrations/00000000_baseline_rpcs.sql:19`
  - `supabase/migrations/20260403080000_auto_link_ghost_and_identity_linking.sql`
  - `supabase/migrations/20260415090000_v4_phase7c_ghost_resolution_persons.sql`
  - `supabase/migrations/20260425201155_qb_drift_correction_2touch_batch4_completion_b.sql:720`
  - `supabase/migrations/20260635000000_p159_s3a_get_ghost_visitors_filter_secondary_emails.sql`
  - `supabase/migrations/20260636000000_p159_s3b_get_ghost_visitors_filter_primary_email.sql`
  - `supabase/migrations/20260428120000_adr0015_phase5_a2_c1_get_my_member_record.sql`
  - `src/pages/profile.astro:1860-1902`
- Live function body retrieved via `pg_get_functiondef` — confirmed drift from migrations
- Blast-radius query confirms scope is currently 1 member; vulnerability surface is platform-wide
