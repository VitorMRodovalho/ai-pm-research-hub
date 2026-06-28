# Drive offboarding revocation cascade — runbook (#209 / ADR-0107)

Detects Google Drive permissions still held by **offboarded** members (member_status
`inactive`/`alumni` with `offboarded_at` set), queues them for GP approval, and revokes them via the
Service Account. LGPD Art. 16.

## Moving parts

| Component | What it does |
|-----------|--------------|
| `drive_offboarding_audit` (table) | The queue. RLS deny-all; read only via SECDEF RPCs. `permission_email` is PII. |
| EF `audit-drive-offboarding-access` | **Detection** (read-only). Weekly cron Mon 05:00 UTC. Scans folders, matches offboarded emails, queues `pending_revoke`, notifies GP. |
| EF `revoke-drive-permission` | **Revocation** (write). Deletes one approved permission; fail-safe on 403/404. |
| MCP `list_drive_revocation_pending` | GP reads the queue (`manage_member`). |
| MCP `approve_drive_revocation(audit_id)` | GP approves one + revokes immediately. |
| MCP `bulk_approve_drive_revocations(member_id)` | GP approves + revokes all of a member's pending. |
| Cron `audit-drive-offboarding-weekly` | `0 5 * * 1` → detection EF. |
| Cron `revoke-drive-drain-hourly` | `7 * * * *` → drains GP-approved rows the synchronous path missed. |
| Invariant `AL_drive_revocation_terminal_consistency` | `revoked` rows carry approval+revocation provenance; re-activation clears the queue. |

Vault key (already seeded): `google_drive_service_account_json` (institutional SA
`nucleoia@pmigo.org.br`). Folders: parent `1PFLzCa8dwjFNhc_y3TPOnkN9O7jfbqnA`, shared drive
`0ABRgwbztNXgDUk9PVA`.

## Status lifecycle

`pending_revoke` → (GP approve) → `approved` → (Drive DELETE) → `revoked` | `already_absent` | `failed`.
`skipped` = an owner permission the SA cannot delete (out of scope).

## ⚠️ The one PM operational task (gates real revocation)

Revocation is **inert until the SA can delete permissions**. The credential exists; what's missing:

1. **Scope** — handled in code (the revoke EF requests `https://www.googleapis.com/auth/drive`).
2. **Role** — in Google Workspace, raise the SA `nucleoia@pmigo.org.br` from **Editor** to
   **organizer / fileOrganizer (Content manager)** on the parent folder + shared drive. An Editor
   cannot remove other people's permissions.

Until step 2 is done, every approve returns `failed` with a 403 and a "needs role elevation" note.
**This is expected, not a bug.** The detection half (queue + GP notification) works regardless.

## First-run validation (do this before trusting live detection)

`permissions.list` must return `emailAddress` under the SA's scope/role, especially on the shared
drive. Confirm with a dry run (writes nothing):

```bash
curl -sS -X POST "https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/audit-drive-offboarding-access" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -d '{"dry_run": true}'
```

Look for `any_email_present: true` in the probes. If false or a 403 surfaces, detection also depends on
the role elevation above — do not enable the weekly cron until it passes.

## Manual operations

Run the detection scan now (real; queues + notifies GP):
```bash
curl -sS -X POST ".../functions/v1/audit-drive-offboarding-access" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -d '{"source":"manual"}'
# → { files_scanned, grants_found, inserted, refreshed, errors }
```

GP review + approve (via MCP, as a `manage_member` user):
`list_drive_revocation_pending` → `approve_drive_revocation(audit_id)` (or `bulk_approve_drive_revocations(member_id)`).

## Troubleshooting

- **503 `drive_integration_not_configured`** — Vault key absent/invalid. (Should not happen; it's seeded.)
- **401 unauthorized** — caller is not service-role. The cron uses the vault `service_role_key` bearer;
  the MCP tools use the EF's service-role env key. Both verified via `isServiceRoleToken` (#850).
- **approve → `failed` 403** — the SA role elevation (PM task above) is not done yet. Expected.
- **approve → `failed` `cannotDeleteInheritedPermission`** — the access is inherited from a parent
  folder / shared-drive membership; remove it at the drive level (outside #209's file-level scope).
- **GP not notified** — notification fires only when the scan inserts NEW pending rows; a re-scan of
  already-queued grants refreshes `last_detected_at` without re-notifying (by design).

## Audit / observability

- `admin_audit_log`: `drive_permission_revocation_queued` (scan summary), `drive_permission_revoked` (success).
- `pii_access_log`: every read of offboarded emails (system scan → `accessor_id=NULL` context
  `audit_drive_offboarding_access`; GP read → `admin_list_drive_revocation_audit`).
- `check_schema_invariants()` → `AL_drive_revocation_terminal_consistency` must stay 0.
