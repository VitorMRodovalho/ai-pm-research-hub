# PR Window: Legacy Role Hard-Drop

## Objective
Finalize migration from legacy `role/roles` to `operational_role/designations` and prepare safe execution window for dropping legacy columns in `members`.

## Current Readiness (as of 2026-03-07)
- Core pages migrated to `operational_role` reads.
- Admin UI reads migrated to `operational_role` reads.
- Team and tribe sections migrated off legacy role reads.
- Route/build/test smoke checks green.

## Remaining Compatibility Scope (intentional)
- `admin_update_member` backend contract still needs native v2 deployment in Supabase.
- Frontend now sends only v2 fields by default and uses `p_role`/`p_roles` only as automatic fallback if RPC v2 fails.

After backend v2 deployment is validated, legacy fallback can be removed.

## Proposed PR Sequence
1. PR-A: Backend contract update
   - Remove requirement for `p_role` and `p_roles` in admin RPC contract.
   - Keep computed compatibility in responses only if needed temporarily.
2. PR-B: Frontend contract cleanup
   - Status: done in app code (primary payload now sends only `operational_role`/`designations`).
   - Legacy fields remain only in temporary fallback helper path.
3. PR-C: DB hard-drop migration
   - Execute:
     - `ALTER TABLE public.members DROP COLUMN role;`
     - `ALTER TABLE public.members DROP COLUMN roles;`
   - Run smoke + functional checks.

## Execution Window Recommendation
- Preferred: low-traffic maintenance window, weekday evening BRT.
- Freeze non-critical merges during rollout.
- Validate immediately after deploy and again after 24h.

## Go/No-Go Checklist
- `npm test` pass
- `npm run build` pass
- `npm run smoke:routes` pass
- Admin member edit flow validated end-to-end
- Auth + role gating validated for: superadmin, admin, leader, researcher, guest
- Rollback path pre-approved (PITR/snapshot strategy)
