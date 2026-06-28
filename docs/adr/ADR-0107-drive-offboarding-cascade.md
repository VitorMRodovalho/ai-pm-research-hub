# ADR-0107 — Drive permission revocation cascade on member offboarding

**Status:** Accepted
**Date:** 2026-06-27
**Source:** Issue [#209](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/209)
**Related:** ADR-0094 (Initiative Collaboration Hub — G2.4 cascade, G4.1 service-account), ADR-0064 (Drive integration auth), ADR-0007 (V4 authority), ADR-0097 (migration coverage), GC-162 (LGPD)
**Implements:** the #209 mechanism (the architecture is locked in ADR-0094 G2.4 + G4.1; this ADR records the concrete, shippable design and its two key constraints).

---

## Context

`admin_offboard_member` flips `member_status` → `inactive`/`alumni` but does **not** touch Google
Drive permissions. Offboarded members keep access to the Núcleo IA Drive folders — a violation of
LGPD Art. 16 (elimination of personal data after the end of processing). #209 closes the cascade.

Two facts grounded at implementation time **corrected the original "blocked on a credential" framing**:

1. **The service-account credential already exists and works for reads.** Vault key
   `google_drive_service_account_json` (institutional SA `nucleoia@pmigo.org.br`) has been seeded
   since 2026-04-28; the daily `drive-discover-atas-daily` cron that uses its JWT runs `succeeded`.
   So the **detection** half (listing files + permissions) can run now.
2. **The real remaining gate is narrow and is the PM's Workspace task:** to *delete* a permission,
   the SA needs (a) the `drive` (write) scope — a one-line JWT change, set in the revoke EF — and
   (b) an **organizer/fileOrganizer** role on the folders (it is currently *Editor*, which cannot
   delete other users' permissions). (b) is a Google Workspace admin operation, not code. Until it
   is done, Google returns **403** and the revoke EF **fails safe** (marks the row `failed`, stores
   the error, never crashes).

Per PM decision (2026-06-27): scope this wave to **#209 only** (curation grants, #301, reuse this
primitive in a later wave); ship **detection live** (weekly cron + GP notification) with
**revocation gated** behind the GP approval *and* the SA role elevation.

---

## Decision

A queue + GP-approval + Edge-Function cascade, mirroring ADR-0094 Principle 2:

- **Table `drive_offboarding_audit`** (mig `20260805000261`) — one row per (file × permission held by
  an offboarded member). RLS deny-all + `REVOKE` anon/authenticated; all access via SECURITY DEFINER
  RPCs (read) / service-role EFs (scan + revoke). `permission_email` is PII at rest.
  **Idempotency** = a *partial* unique index `(drive_file_id, permission_id) WHERE status IN
  ('pending_revoke','approved')`: at most one *actionable* row per grant, while terminal rows
  (`revoked`/`failed`/`already_absent`/`skipped`) accrue as immutable history and re-detection of a
  still-present grant can re-open a fresh row.
- **7 SECDEF RPCs** (mig `20260805000262`) — GP-facing (`admin_list_drive_revocation_audit`,
  `approve_drive_revocation`, `bulk_approve_drive_revocations`; gated `can_by_member('manage_member')`)
  + EF-facing service-role-only (`get_offboarded_member_emails`, `upsert_drive_revocation_candidates`,
  `get_drive_revocation_row`, `mark_drive_revocation_done`; NULL-safe `current_caller_role() IS
  DISTINCT FROM 'service_role'` gate + GRANT restricted to `service_role`).
- **Detection EF `audit-drive-offboarding-access`** — weekly cron (Mon 05:00 UTC), READ-ONLY
  (`drive.readonly`). Per offboarded email, one `files.list` query (`mimeType=folder and '<email>' in
  writers/readers`, `corpora=allDrives`, inline `permissions` + `parents`), then keeps only the
  **direct** grants via in-memory parent dedup (a matched folder is direct iff none of its parents is
  also matched — i.e. it is the top of a shared subtree; subfolders that merely inherit are skipped).
  Owner grants are skipped (undeletable). Upserts the survivors idempotently and notifies GP once.
  Scope = everything the institutional SA can see (the Núcleo workspace). Carries a permanent `dry_run`
  flag (see below).
- **Revoke EF `revoke-drive-permission`** — invoked synchronously by the approve tools (and a drain
  cron). Requests the `drive` write scope, `DELETE`s the permission, classifies fail-safe:
  204→`revoked`, 404→`already_absent`, 403/other→`failed` (+ stored `google_error`). Writes
  `admin_audit_log` kind=`drive_permission_revoked` on success.
- **3 MCP tools** (`list_drive_revocation_pending`, `approve_drive_revocation`,
  `bulk_approve_drive_revocations`) — `manage_member`-gated; approve calls the revoke EF directly
  (ADR-0094 "user-driven → direct EF call") for immediate inline feedback.
- **Invariant AL** `AL_drive_revocation_terminal_consistency` in `check_schema_invariants` — a
  `revoked` row must carry `approved_by`+`revoked_at`; no open row may reference a re-activated member.
- **Crons** (mig `20260805000264`) — weekly detection + a `revoke-drive-drain-hourly` safety net that
  drains GP-approved rows the synchronous path may have missed.

### Two load-bearing constraints

**Dry-run gate (before trusting live detection).** `permissions.list`/inline `permissions` returning
`emailAddress` is authorized under `drive.readonly`, but org policy can strip it. So detection is **not
declared live** until a one-shot `{"dry_run": true}` call confirms `emailAddress` is populated under the
SA's current scope/role. Validated 2026-06-27: `any_email_present: true`.

**Inherited-cascade trap (the scaling lever).** A naïve scan — walk the tree and `permissions.list`
every file, or query `'<email>' in writers` over all files — explodes: sharing a member on a top folder
makes **every descendant file** match by inheritance (measured: 10,057 candidate rows, and the single-
invocation scan blew the EF wall-clock). The fix is two-fold: query **folders only**, and keep only
**direct** grants via in-memory **parent dedup** (drop any matched folder whose parent is also matched).
This collapses the cascade to the handful of top-level direct folder grants (measured: **10**, scanning
27 offboarded members, with 0 errors and a fast scan). `permissionDetails.inherited` is NOT usable here
because the Núcleo folders live in My Drive, where the API does not expose it — parent dedup works for
both My Drive and shared drives.

**File-level vs drive-level boundary.** #209 deletes *folder-level direct* permissions (where access is
managed). It cannot delete an **owner** permission (skipped) or an **inherited** one
(`cannotDeleteInheritedPermission` → `failed`, surfaced); removing those is a drive-membership operation
outside scope. **Direct grants on individual non-folder files** (a member shared a single Doc, not a
folder) are a documented **v2 follow-up** — the dominant, highest-value targets are folder grants.
`anyone_with_link` / `domain` permissions have no `emailAddress` and are out of scope by design.

---

## Consequences

- **LGPD Art. 16 cascade by construction** — offboarded-member Drive access is detected, queued,
  audited, and (once the SA role is elevated) revoked, with a GP approval gate and full audit trail.
- **"approve does nothing until the SA role is elevated" is EXPECTED, not a defect.** Every approve
  returns `failed` (403) with a clear message until the PM completes the Workspace task. This is the
  gated steady state the PM chose; do not file it as a bug. The GP still gets the actionable list now.
- **PII at rest** (`permission_email`) — deny-all RLS, SECDEF-only read, `pii_access_log` on every read
  (the system scan logs with `accessor_id=NULL`; the GP read logs via `log_pii_access_batch`).
- **Schema mass** — 1 table, 7 RPCs, 1 invariant, 2 EFs, 2 crons, 3 MCP tools (308→311).
- **Credential reuse** — uses the existing institutional SA (`google_drive_service_account_json`),
  consistent with the other Drive read EFs, satisfying ADR-0094 G4.1's "org-owned dedicated identity"
  in spirit. The multi-hub `google_service_account_key_<organization_id>` naming (ADR-0094 M1) is
  deferred until a 2nd hub is real.

### ADR-0094 status note

ADR-0094 remains **Proposed**; its five §Open-items are a separate PM sign-off pass and are **not**
flipped by this work. #209 is its hard dependency (G2.4/G4.1) and ships independently.

---

## Acceptance-criteria status (#209)

Buildable criteria are met by this wave (table, RPCs, EFs, MCP tools, cron, invariant, tests, ADR,
docs). The criterion **"after 1 GP approve, 1 permission actually revoked (validated in Drive UI)"**
is **gated on the PM's Workspace task** (elevate the SA Editor→organizer/fileOrganizer on the Núcleo
folders + shared drive). Until then a real approve returns `failed` (403) by design. That criterion is
checked off in a follow-up after the role elevation.

---

## References

- Runbook: `docs/operations/DRIVE_OFFBOARDING_CASCADE.md`
- ADR-0094 §G2.4 (cascade), §G4.1 (service account) · Issue #209 · #301 (curation grants, reuses this primitive)
- Migrations `20260805000261..264` · EFs `audit-drive-offboarding-access`, `revoke-drive-permission`
- Contract test `tests/contracts/209-drive-offboarding.test.mjs`

---

**Assisted-By:** Claude (Anthropic)
