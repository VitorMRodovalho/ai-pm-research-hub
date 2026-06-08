# Decision — #568: consent_records LGPD read surface (Art. 18)

**Date:** 2026-06-08 · **Decider:** PM (via PL/CTO synthesis) · **Issue:** #568 (follow-up from #564 council sweep) · **Migration:** `20260805000130`

## Context
`consent_records` was locked (`rpc_only_deny_all`) with read RPCs deferred ("futuras") and never created → `export_my_data()` omitted consent history (LGPD Art. 18 II access / V confirmation) and there was no admin audit path. `consent_records` holds no raw PII — only pseudonymized hashes (`email_hash`, `ip_hash`, `user_agent_hash`).

## Options & recommendation
The council (security-engineer + legal-counsel) reviewed a draft and both returned NO-GO / GO-com-condições with concrete required fixes. PL/CTO recommendation: ship the three-surface design (subject view / admin audit / export) with all required fixes folded. Kept **DB-only** — MCP exposure of these RPCs is a deliberate, separate follow-up.

## Decisions
1. **Three read surfaces.**
   - `list_my_consents()` — subject self-read (`auth.uid()`→member). Friendly fields, **omits** the capture hashes, adds `is_active = (revoked_at IS NULL)`.
   - `admin_list_member_consents(p_member_id)` — `view_pii`-gated audit read **with** the capture hashes; logs **every** call (incl. self) to `pii_access_log` (Art. 37).
   - `export_my_data()` — gains a `consent_records` key (explicit projection, incl. hashes — subject's own record).
2. **Multi-tenant org fence (CRITICAL, security-engineer #1).** SECDEF bypasses the RESTRICTIVE org RLS and `can_by_member('view_pii')` does not bound the *target* → a cross-org admin read was possible. `admin_list_member_consents` now verifies the target is a real member in the caller's org (and row-filters the query by `organization_id`). Verified live: a bogus/cross-org target raises `Access denied: target member not in caller organization`.
3. **Log every admin read, incl. self (legal R-1).** The original `p_member_id <> v_caller_id` carve-out would let an admin read their own consent-with-hashes via the admin path untraced — removed (Art. 37 accountability).
4. **Hashes in the subject's export — included by design (legal Q5).** `ip_hash`/`user_agent_hash`/`email_hash` are data generated **by the subject's own act** of consent; the subject has the right to the complete record of the act that binds them. Omitting them would be opaque retention, the inverse of minimization. Recorded here pre-emptively for ANPD defensibility.
5. **Explicit projection, not `row_to_json` (legal R-4).** So a future `consent_records` column is not auto-exported without an adequacy review.
6. **Grant posture.** New fns `REVOKE FROM PUBLIC, anon` + `GRANT authenticated, service_role`. `export_my_data` re-asserts the same explicitly (CREATE OR REPLACE would otherwise leave the auto-PUBLIC/anon grant lingering — anon dropped this PR).

## Drive-by fix (in-scope, same function)
`export_my_data` referenced `initiatives.name`, which the V4 refactor renamed to `title` → the export **RAISED `column i.name does not exist` for any member with engagements** (LGPD export was broken in prod). Corrected to `i.title`. Verified live: superadmin with 12 engagements now exports successfully.

## Verification (live)
`list_my_consents`→`[]`; `admin_list_member_consents` same-org→`[]`, cross-org/bogus→denied; `export` has `consent_records` key + 12 engagements; `pii_access_log` row written then removed (test artifact); anon revoked on all three; service_role fail-closes. Council code 0-blocker after fixes; Phase-C body-drift clean; `astro build` clean; `check_schema_invariants()` 0.

## Follow-ups
- MCP exposure of `list_my_consents` / `admin_list_member_consents` (separate PR if wanted).
- Member-facing "my consents" UI wiring (separate frontend task).
