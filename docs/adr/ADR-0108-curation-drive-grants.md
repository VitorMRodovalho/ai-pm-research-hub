# ADR-0108 — Temporary governed Drive access for curation (grant mirror of ADR-0107)

**Status:** Accepted
**Date:** 2026-06-27
**Source:** Issue [#301](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/301)
**Related:** ADR-0107 (#209 Drive revocation cascade — the primitive this mirrors), ADR-0094 (Initiative Collaboration Hub — G4.1 service-account), ADR-0105 (#785 confidential-initiative visibility gate), ADR-0007 (V4 authority), ADR-0097 (migration coverage), GC-162 (LGPD). Consumers (separate PRs): #201 (curation modal links), #190 (curation queue state envelope). Distinct from #212 (Initiative Collaboration Hub membership grants).
**Reuses:** the #209/ADR-0107 Drive-permission infra — SA auth (`_get_vault_secret('google_drive_service_account_json')`, now extracted to `_shared/drive-sa.ts`), the `isServiceRoleToken` gate, the ledger + partial-unique idempotency + deny-all RLS pattern, the EF + drain-cron + invariant discipline.

---

## Context

When a member submits an artifact for curation from a restricted tribe/team Drive folder, the
Curation Committee **cannot open it** — tribe folders are access-controlled by design (incident
Fabricio/Roberto). #201 surfaces the link in the curation modal, but curators hit Drive
"access denied". The platform lacked a mechanism for **temporary, auditable, least-privilege**
access to the submitted artifact without permanently opening the whole tribe folder.

#301 is the **GRANT mirror** of #209 (which REVOKES): same Drive-permission service-account infra,
ledger + fail-safe + invariant + drain-cron pattern. #301 **creates** permissions
(`POST /files/{id}/permissions`) where #209 **deletes** them
(`DELETE /files/{id}/permissions/{permission_id}`). The SA was raised to organizer for #209
(2026-06-27), so the grant side is unblocked at deploy — no new Workspace task.

Grounded facts at build time (live, `ldrfrvwhxsmgaabwmaik`):
- Curation FSM (`board_items.curation_status`): `submit_for_curation` → `curation_pending`
  (+`curation_due_at = now()+SLA`, default 7d); `submit_curation_review` exits (approved≥2 →
  `published`; returned/rejected → `draft`). "Leaves active curation" = `curation_status` no longer
  `curation_pending`.
- The submitted artifact lives in **`board_item_files`** (`drive_file_id`, `drive_file_url`).
  `board_items.attachments` (jsonb) is a legacy Storage/links lane — not Drive, out of scope.
- `curate_content` resolves (V4 Path 1 only) to **3 people** (Fabricio, Roberto, Sarah) — all on
  gmail, i.e. **out-of-domain** vs the SA's `pmigo.org.br`.

## Decision

**Eager-on-handoff auto-grant to the curation committee (PM decision, 2026-06-27).**

1. **Ledger `drive_curation_grants`** — clone of `drive_offboarding_audit`. Deny-all RLS + REVOKE
   anon/authenticated; `permission_email citext` is PII (SECDEF read only). Idempotency:
   `UNIQUE (drive_file_id, permission_email) WHERE status IN ('pending_grant','granted','pending_revoke')`
   — one active grant per (file × curator); terminal rows accrue as history; re-grant after
   revoke/cancel opens a fresh row. (Keyed on `permission_email` not `permission_id` because, unlike
   #209, the `permission_id` does not exist until the grant succeeds.)
2. **Trigger on `board_items.curation_status`**: entry → `curation_pending` queues a `pending_grant`
   per (submitted `board_item_files` row × `curate_content` holder); exit → queues `pending_revoke`
   for `granted` rows and `cancelled` for never-executed `pending_grant` rows. `assign_curation_reviewer`
   is extended to queue a grant for the specific assigned reviewer (the event row stores only the
   reviewer's name, not id, so the enqueue must happen where `p_reviewer_id` is in scope) — covering
   the "OR formal reviewers" clause (e.g. co_gp-designated reviewers outside the standing 3).
3. **No human approval gate.** Granting `commenter` to already-authorized curators is low-risk and
   "grant on handoff" requires immediacy; gating on GP (the #209 model) would block curators. Auth
   over the EF execution is the SA (service-role); the human surface is observability + manual
   remediation only.
4. **EF `manage-curation-drive-grant`** (`action: grant|revoke`), drained by `curation-grant-drain` /
   `curation-revoke-drain` (every 2 min — the **primary** executor, since there is no synchronous
   human path) + `curation-grant-ttl-expiry` (hourly safety-net: leave-of-curation backstop + 30-day
   absolute cap). Least-privilege: `commenter`, file-level (the submitted Doc), never the folder.
   **sendNotificationEmail:** Google rejects `false` for out-of-domain grantees (400) — all current
   curators are gmail — so the EF defaults to notify out-of-domain and retries with notify on a 400.
5. **Authority (V4, no seed expansion):** status RPC `get_board_item_drive_access` (consumed by
   #201/#190) gates `curate_content OR manage_platform` + the #785 confidential carve-out
   (`rls_can_see_board`); GP observability/remediation RPCs + 3 MCP tools gate `manage_platform`;
   EF-facing RPCs gate service-role (NULL-safe). Invariant **AM_drive_curation_grant_terminal_consistency**
   (total 39→40).

## Scope boundary

This wave ships the **backend primitive only** (ledger + EF + auto grant/revoke wiring + crons +
invariant + status RPC + 3 MCP tools + tests). #201 (modal `drive_permission_status`) and #190
(queue envelope fields) **consume** `get_board_item_drive_access` in their own PRs.

This is a **specialized temporary review-grant** lane, deliberately **distinct from #212** (Initiative
Collaboration Hub membership/participation grants) to keep the LGPD posture defensible: a curation
grant is a time-boxed exception tied to a specific artifact handle, not a participation grant.

## Consequences

- Curators get access automatically on handoff; revoked when the item leaves curation (or the 30-day
  cap). Full audit trail (grant + revoke in `admin_audit_log`; the ledger is the evidence bundle).
- If a file has no `board_item_files` row, `get_board_item_drive_access` returns
  `overall_status='missing'` (`missing_drive_access=true`) — the live curation queue's only pending
  card is exactly this case, so #201/#190 must render "missing artifact link".
- Out-of-domain grants send a notification email to the curator (Google requirement). Drive sharing
  policy that forbids external sharing surfaces as a `failed` row (400) with the captured error,
  remediable by the GP via `force_grant_curation_drive_access`.
- v2 follow-up (shared with ADR-0107): direct grants on non-folder files are exactly the curation
  case and are handled here; folder-level curation submissions stay file-first by policy.
