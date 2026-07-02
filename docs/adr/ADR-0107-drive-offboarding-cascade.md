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

## Amendment 1 — Fatia B: alumni-only auto-approve/auto-revoke (#1039, 2026-07-02)

**Ratified:** PM Vitor Maia Rodovalho, 2026-07-02 (via council Tier-3 gate — see decision record
`docs/council/decisions/2026-07-02-1039-drive-auto-revoke-alumni-only.md`; Tier-3 review
`docs/council/2026-07-02-1039-fatia-b-auto-revoke-tier3.md`: legal-counsel, security-engineer,
data-architect, accountability-advisor — 4× APPROVE_WITH_CONDITIONS, zero blockers, all conditions
incorporated). Migration `20260805000319`.

### Why the original manual gate existed — and why relaxing it is now safe

The GP approval gate in this ADR's Decision was a **holding constraint, not a permanent policy**: at
#209 time (2026-06-27) the SA lacked the organizer role (every revoke returned 403), the revocation
path had never executed against real data, and a manual review compensated for both unknowns. Both
have since closed: the SA role elevation is done, and the full pipeline has demonstrated **10/10
zero-error revocations across the 27-member offboarded cohort** (grounded live 2026-07-02: 9 alumni +
1 inactive rows, all `revoked`, 0 `failed`). What remained of the gate's value was reversal safety —
and that is preserved structurally by the alumni-only scope (below) plus the new reactivation
queue-clear.

### The amendment

1. **Alumni-only auto-approve.** New service-role RPC `auto_approve_alumni_drive_revocations`
   (called by the detection EF after every upsert) flips `pending_revoke → approved` with
   `approval_mode='auto'`, `approved_by = NULL`, ONLY for members with `member_status='alumni' AND
   offboarded_at IS NOT NULL`, checked **at UPDATE time** (closes the detect→approve race). The
   hourly drain (cron 64) — which never filtered on who approved — executes the revocation within
   ~1h. No cron, revoke-EF, or trigger changes.
2. **`inactive` stays manual — the asymmetry is deliberate and legally grounded** (legal REC-3):
   `inactive` is reversible by design with NO pipeline gate before reactivation (ADR-0071 Amd 3-D
   sabbatical; ADR-0116 `_reacceptance_disengage` exits to inactive) — auto-revoking it would strand
   directly-reactivatable members. Alumni reactivation requires the multi-day re-engagement pipeline
   (staged → invited → accepted), a natural intervention window. LGPD Art. 16 requires elimination
   "without undue delay", not instantaneously — human review for reversible cases is not undue delay;
   for permanent exits (alumni) the ≤1h automation is the stronger compliance posture.
3. **Provenance model.** New column `approval_mode ('manual'|'auto')` — NOT a sentinel "system
   member" (which would fabricate a members row and lie in the audit trail). Invariant AL amended in
   lockstep: a `revoked` row needs `revoked_at` AND (`approved_by` OR `approval_mode='auto'`); an
   auto row may never carry a human approver nor sit `pending_revoke`; `already_absent` remains
   outside provenance checks by design (the grant was already gone — no proof of revocation is
   required). The authorization record is a self-contained `admin_audit_log` entry
   (`drive_revocation_auto_approved`, carries the exact `audit_ids`).
4. **Kill-switch, ships dark.** `site_config['drive_auto_revoke_enabled']` seeded `'false'::jsonb`
   (ADR-0116 precedent: dangerous automation ships dark; go-live is an explicit, audited OPS flip —
   checklist in the runbook, gated on legal COND-1 comms + COND-3 retention issue). NULL-safe
   fail-closed: a missing key means DISABLED. Write is superadmin-only; a GP cannot pause the switch.
5. **Reactivation queue-clear (closes a pre-existing gap).** The AL invariant always promised "a
   reversed offboarding must clear the revocation queue" but no mechanism existed.
   `admin_reactivate_member` now cancels open rows (`pending_revoke`/`approved` →
   `skipped`/`member_reactivated`) BEFORE clearing `offboarded_at`, in the same transaction — the
   drain can never revoke a reactivated member's access (the revoke EF's status re-read guard closes
   the cron race).
6. **`skipped` redefined as the generic closed-without-revocation lane**, structurally disambiguated
   by the new `skip_reason` column (`owner_permission` | `member_reactivated`, CHECK-enforced —
   legal COND-2: free-text notes are not audit evidence).
7. **NO auto re-grant on reactivation** (PM decision 2026-07-02, council-endorsed). Grounded in LGPD
   Art. 6 III data-minimization — re-granting a stale historical folder set would recreate treatment
   with obsolete scope and over-grant — not merely in the zero historical return rate. Re-grant is a
   manual GP step contextual to the member's NEW engagement; the `revoked` audit history documents
   what was revoked (runbook §Re-grant).
8. **Weekly catch-up semantics.** The no-arg auto-approve call on the weekly sweep approves ALL
   pending alumni rows globally — deliberate: rows accumulated while the switch was off drain on the
   first post-enable scan. A large first-run count is expected behavior.

### Known future constraint — multi-chapter expansion

The institutional SA `nucleoia@pmigo.org.br` scope covers the PMI-GO workspace. A volunteer who is
alumni in PMI-GO but active in another chapter sharing the same Drive subtree would be auto-revoked
incorrectly. Multi-chapter expansion requires per-chapter SA credentials (ADR-0094 M1 deferred
scope) or a membership-scope filter on the auto-approve RPC BEFORE enabling this feature for any
non-PMI-GO chapter.

### Follow-ups filed at amendment time

- **#1054** — PII retention for terminal queue rows (5y + anonymization cron + ROPA/DPO; legal
  COND-3 — gates go-live).
- **#1055** — courtesy notification to the offboarded member at revocation time (legal REC-4 /
  accountability).
- **#1056** — governed `set_site_config` RPC bundling flip + audit atomically; per-row `unapprove`
  escape hatch (security/accountability recommendations).

---

**Assisted-By:** Claude (Anthropic)
