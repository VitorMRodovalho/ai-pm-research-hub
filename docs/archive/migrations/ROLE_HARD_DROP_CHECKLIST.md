# Role Hard-Drop Checklist (`role`, `roles`)

## Scope
This checklist defines the production rollout to remove legacy `members.role` and `members.roles` after the frontend migration to `operational_role` and `designations`.

## Preconditions
- All core pages read role data from `operational_role` + `designations`.
- Admin flows are validated using `operational_role` + `designations`.
- Smoke route checks are green (`npm run smoke:routes`).
- Build and tests are green (`npm run build`, `npm test`).

## Preflight Validation (staging first)
1. Run SQL check for null or invalid operational role values.
2. Confirm `designations` values only use approved codes.
3. Validate `get_member_by_auth`, `admin_list_members`, `admin_update_member` return expected role payloads without relying on legacy fields.
4. Validate attendance, artifacts, gamification, profile, and admin role gates with:
   - superadmin
   - manager/deputy_manager
   - tribe_leader
   - researcher
   - guest

## Rollout Steps
1. Deploy frontend that no longer depends on `role/roles`.
2. Deploy RPC/view/policy updates that compute compatibility fields from `operational_role/designations` where still needed.
3. Run post-deploy smoke checks on:
   - `/`
   - `/attendance`
   - `/gamification`
   - `/artifacts`
   - `/profile`
   - `/admin`
   - `/teams`
   - `/rank`
   - `/ranks`
4. Execute hard-drop migration:
   - `ALTER TABLE public.members DROP COLUMN role;`
   - `ALTER TABLE public.members DROP COLUMN roles;`
5. Re-run high-risk functional checks (auth + admin CRUD + tribe selection + ranking).

## Rollback Plan
1. If regressions appear before hard-drop, rollback frontend release only.
2. If regressions appear after hard-drop:
   - restore DB from PITR/snapshot to pre-drop point, or
   - re-add columns and backfill from `operational_role/designations` using compatibility SQL.
3. Re-deploy previous stable app revision.
4. Re-run smoke checks and critical role-gate scenarios.

## Exit Criteria
- No frontend/runtime reads of `members.role` or `members.roles` in active codepaths.
- Admin/member edits work without legacy fields.
- Production smoke and functional checks pass twice (immediate + 24h follow-up).
