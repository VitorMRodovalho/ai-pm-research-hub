# Runbook — Curation temporary Drive grants (#301 / ADR-0108)

GRANT mirror of the #209 revocation cascade (`DRIVE_OFFBOARDING_CASCADE.md`). When a board item
enters `curation_pending`, the Curation Committee gets a temporary, auditable, file-level
`commenter` permission on the submitted artifact; it is revoked when the item leaves curation.

## How it works (auto path — no human action needed)

1. A curator/leader calls `submit_for_curation(item)` → `board_items.curation_status = 'curation_pending'`.
2. Trigger `trg_curation_drive_grants` → `enqueue_curation_drive_grants(item)` inserts one
   `pending_grant` row per (submitted `board_item_files` row × `curate_content` holder) into
   `drive_curation_grants`. Assigning a reviewer (`assign_curation_reviewer`) queues a grant for that
   reviewer too.
3. Cron `curation-grant-drain` (every 2 min) POSTs each `pending_grant` to the EF
   `manage-curation-drive-grant` (`action: grant`) → Google `POST /files/{id}/permissions`
   (`role=commenter`) → row `granted` + `permission_id` stored + `admin_audit_log`
   `drive_curation_grant_created`.
4. The item leaves curation (`submit_curation_review`: approved→published / returned/rejected→draft)
   → trigger queues `pending_revoke` (granted rows) / `cancelled` (never-executed). Cron
   `curation-revoke-drain` POSTs `action: revoke` → Google `DELETE` → row `revoked` +
   `admin_audit_log` `drive_curation_grant_revoked`.
5. `curation-grant-ttl-expiry` (hourly) is the safety net: backstops the exit trigger and enforces a
   30-day absolute cap.

## Prerequisites (already satisfied)

- Vault key `google_drive_service_account_json` (institutional SA `nucleoia@pmigo.org.br`) — seeded.
- **SA Workspace role = organizer/fileOrganizer** — raised by the PM 2026-06-27 for #209. Creating a
  permission for another user is organizer-only; until it is set Google returns **403** and the EF
  **fails safe** (row `failed`, error captured, never crashes).
- EF `manage-curation-drive-grant` deployed; crons `20260805000269` applied (apply crons AFTER the EF
  is deployed).

## Authority

- `get_board_item_drive_access(item)` (status; consumed by #201 modal / #190 queue): `curate_content`
  OR `manage_platform`, + #785 confidential carve-out. PII-clean (grantee names + counts, no emails).
- `list_curation_drive_grants` / `force_grant_curation_drive_access` / `force_revoke_curation_drive_access`
  (MCP tools) + `admin_list_curation_drive_grants`: **`manage_platform` (GP)**.
- EF-facing RPCs (`get_curation_grant_row`, `mark_curation_grant_done`, `mark_curation_grant_revoked`)
  + enqueue helpers: **service-role only** (NULL-safe `current_caller_role()` gate).

## Operate (GP, via MCP)

- **See grant status of a card:** the status RPC is what the curation modal reads; for the raw ledger
  use `list_curation_drive_grants` (filter by `status` / `board_item_id`).
- **A grant failed (403/400):** `list_curation_drive_grants status=failed`. 403 = SA role not
  organizer (Workspace task). 400 = Drive sharing policy forbids external (out-of-domain) sharing for
  that file. After fixing, `force_grant_curation_drive_access(board_item_id)` re-queues + executes.
- **Force revoke** (e.g. confidentiality change): `force_revoke_curation_drive_access(board_item_id)`.

## Status lifecycle

`pending_grant → granted | failed` · `granted → pending_revoke → revoked | revoke_failed` ·
`pending_grant → cancelled` (item left curation before the grant executed).

## Invariant

`AM_drive_curation_grant_terminal_consistency` (in `check_schema_invariants`, total 40): a `granted`
row carries `permission_id` + `granted_at` and no `revoked_at`; a `revoked` row carries `revoked_at`.
Baseline 0; a violation means a service_role write bypassed the EF mark RPCs.

## Diagnose

```sql
-- queue snapshot
SELECT status, count(*) FROM public.drive_curation_grants GROUP BY 1 ORDER BY 2 DESC;
-- a card's grants
SELECT id, grantee_member_id, permission_email, status, permission_id, api_error
FROM public.drive_curation_grants WHERE board_item_id = '<uuid>' ORDER BY created_at;
-- cron health
SELECT jobname, schedule, active FROM cron.job WHERE jobname LIKE 'curation-%';
-- invariant
SELECT * FROM public.check_schema_invariants() WHERE invariant_name = 'AM_drive_curation_grant_terminal_consistency';
```

## Scope

File-level grants over `board_item_files` only. `board_items.attachments` (legacy Storage/links) is
NOT Drive and gets no grant — such a card reads `overall_status='missing'` from the status RPC.
#201 (modal) and #190 (queue envelope) consume the status RPC in their own PRs.
