# Drive offboarding revocation cascade — runbook (#209 / ADR-0107 + Amendment 1)

Detects Google Drive permissions still held by **offboarded** members (member_status
`inactive`/`alumni` with `offboarded_at` set), queues them, and revokes them via the Service Account.
LGPD Art. 16. Since #1039 (ADR-0107 Amendment 1) the approval lane is **mixed**: **alumni rows are
auto-approved** (when the kill-switch is on), **inactive rows stay manual** (reversible by design,
ADR-0071 Amd 3-D).

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
| Cron `revoke-drive-drain-hourly` | `7 * * * *` → drains ALL `approved` rows (manual and auto) the synchronous path missed. |
| RPC `auto_approve_alumni_drive_revocations` | **#1039 auto-approve** (service-role only, called by the detection EF post-upsert). Set-based flip `pending_revoke`→`approved` with `approval_mode='auto'`, ALUMNI-ONLY, no-op unless the kill-switch is on. |
| `site_config['drive_auto_revoke_enabled']` | **Kill-switch** (jsonb boolean). Ships `false` (dark). NULL-safe fail-closed: a missing key = disabled. Write is **superadmin-only** — a GP cannot pause auto-revoke; escalate to the PM. |
| Panel `/admin/members/drive-teardown` | GP rollup + drill-down (Fatia C). Shows in-flight autos, `auto` provenance badge and the `skipped` exception lane. |
| Invariant `AL_drive_revocation_terminal_consistency` | `revoked` rows carry provenance (`approved_by` manual OR `approval_mode='auto'`); auto rows never carry a human approver nor sit pending; `skipped` requires `skip_reason`; re-activation clears the queue (mechanism: `admin_reactivate_member` cancels open rows). |

Vault key (already seeded): `google_drive_service_account_json` (institutional SA
`nucleoia@pmigo.org.br`). Folders: parent `1PFLzCa8dwjFNhc_y3TPOnkN9O7jfbqnA`, shared drive
`0ABRgwbztNXgDUk9PVA`.

## Status lifecycle

- **inactive members (manual lane):** `pending_revoke` → (GP approve) → `approved` → (Drive DELETE) →
  `revoked` | `already_absent` | `failed`.
- **alumni members (auto lane, #1039, switch on):** `pending_revoke` → (auto-approve,
  `approval_mode='auto'`, `approved_by=NULL`) → `approved` → (hourly drain ≤1h) → `revoked` |
  `already_absent` | `failed`. Switch off = falls back to the manual lane above.
- `skipped` = **closed without revocation**, disambiguated by `skip_reason` (structural, CHECK-enforced):
  - `owner_permission` — an owner grant the SA cannot delete (exception review);
  - `member_reactivated` — open row cancelled by `admin_reactivate_member` (#1039; the drain must never
    revoke a reactivated member's access).
- The no-arg weekly auto-approve call is a deliberate **catch-up**: rows that accumulated while the
  switch was off are approved on the first post-enable scan — a large first-run count is expected, not
  a bug.

## Re-grant on reactivation (decided #1039 — NO auto re-grant)

`admin_reactivate_member` cancels open queue rows but does **NOT** re-grant Drive access (council +
PM 2026-07-02: data-minimization — re-granting a stale historical folder set would be an over-grant).
Re-grant is an explicit **manual GP step, contextual to the member's NEW engagement**: use the
drive-teardown panel drill-down (the member's `revoked` history shows exactly WHAT was revoked) to
inform what, if anything, to re-share. A returning member with unexpected Drive-access loss is this
policy working as designed — plus one documented edge: a reactivation racing the drain can leave a row
`skipped` whose permission was in fact deleted (µs window; diagnose via `admin_audit_log`
`drive_permission_revoked` vs the row's `skip_reason`).

## Go-live OPS checklist (#1039 — flip the kill-switch)

Preconditions (legal COND-1/COND-3, council 2026-07-02): the Privacy Notice §6 revocation-window text
is live; the PII-retention follow-up issue is filed (**#1054**); the decision record exists
(`docs/council/decisions/2026-07-02-1039-drive-auto-revoke-alumni-only.md`).

Run BOTH statements together (the flip itself must leave an audit trail — the auto-approve entries
record the EFFECTS, this records the CAUSE):

```sql
UPDATE public.site_config
   SET value = 'true'::jsonb, updated_at = now()
 WHERE key = 'drive_auto_revoke_enabled';

INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
VALUES (
  (SELECT id FROM public.members WHERE auth_id = auth.uid()),  -- NULL under service_role: fill your member id
  'site_config_changed', 'site_config', NULL,
  jsonb_build_object('key','drive_auto_revoke_enabled','from','false','to','true'),
  jsonb_build_object('reason','Fatia B go-live per ADR-0107 Amendment 1 (#1039)',
                     'decision_record','docs/council/decisions/2026-07-02-1039-drive-auto-revoke-alumni-only.md')
);
```

To pause: same two statements with `'false'`/from-to inverted and reason. Only a **superadmin** can
write `site_config` — GPs must escalate to the PM.

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

- `admin_audit_log`: `drive_permission_revocation_queued` (scan summary), `drive_permission_revoked`
  (success; `actor_id=NULL` for auto rows — the authorization record is the separate
  `drive_revocation_auto_approved` entry, which carries the exact `audit_ids` flipped for O(1) forensic
  correlation), `drive_revocation_auto_approved` (#1039 authorization record), `site_config_changed`
  (kill-switch flips, via the go-live checklist above).
- `pii_access_log`: every read of offboarded emails (system scan → `accessor_id=NULL` context
  `audit_drive_offboarding_access`; GP read → `admin_list_drive_revocation_audit`).
- `check_schema_invariants()` → `AL_drive_revocation_terminal_consistency` must stay 0.
