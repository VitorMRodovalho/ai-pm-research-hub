# PR Window: Legacy Role Hard-Drop

## Objective
Finalize migration from legacy `role/roles` to `operational_role/designations` and prepare safe execution window for dropping legacy columns in `members`.

## Current Readiness (as of 2026-03-07)
- Core pages migrated to `operational_role` reads.
- Admin UI reads migrated to `operational_role` reads.
- Team and tribe sections migrated off legacy role reads.
- Route/build/test smoke checks green.

## Remaining Compatibility Scope (intentional)
- `admin_update_member` RPC payload still sends `p_role` and `p_roles` for backward compatibility.
- `admin/member/[id].astro` still sends `p_role` and `p_roles` while backend compatibility exists.

These are the final backend-contract blockers before hard-drop.

## Proposed PR Sequence
1. PR-A: Backend contract update
   - Remove requirement for `p_role` and `p_roles` in admin RPC contract.
   - Keep computed compatibility in responses only if needed temporarily.
2. PR-B: Frontend contract cleanup
   - Remove `p_role`/`p_roles` payload generation from admin pages.
   - Remove any dead legacy helper code tied to those params.
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
