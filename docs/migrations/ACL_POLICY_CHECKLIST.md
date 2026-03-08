# ACL Policy Parity Checklist (S-RM4 v3)

## Objective
Ensure backend authorization (RLS + RPC checks) follows the same tier model used in frontend ACL.

## Tier Matrix
- `visitor` (0)
- `member` (1)
- `observer` (2)
- `leader` (3)
- `admin` (4)
- `superadmin` (5)

## Route/Action Mapping
- `admin_panel`: observer+
- `admin_analytics`: admin+
- `admin_member_edit`: superadmin
- `admin_manage_actions`: admin+

## Rollout Steps
1. Apply `docs/migrations/acl-tier-parity-v1.sql` in staging.
2. Run `docs/migrations/acl-tier-parity-audit.sql` in staging and capture output.
3. Validate helper functions:
   - `current_member_tier_rank()`
   - `has_min_tier(int)`
4. Validate RLS write policies:
   - `announcements` -> admin+
   - `member_cycle_history` -> superadmin
   - `tribes` updates -> leader+
5. Re-run privileged frontend flows with each tier account:
   - observer: read-only executive/admin panel slices only
   - leader: tribe settings/slots only
   - admin: reports/exports/announcements/member admin actions
   - superadmin: cycle history writes + full admin
6. Validate edge functions that already enforce superadmin:
   - `sync-credly-all`
   - `sync-attendance-points`
7. Repeat steps 1-6 in production and attach results to release evidence.

## RPC Hardening Rule
Every `SECURITY DEFINER` RPC that mutates data must check at least one of:
- `public.has_min_tier(required_rank)`, or
- explicit `is_superadmin`/role checks resolved from `members` by `auth.uid()`.

## Exit Criteria
- No privileged write path relies only on hidden UI controls.
- Frontend ACL outcomes match RLS/RPC behavior for each tier.
- Audit log/release notes updated after staging and production execution.
