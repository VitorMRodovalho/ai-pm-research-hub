# ADR-0124 — Drive membership auto-grant + provisioning (grant mirror of ADR-0107, membership side)

**Status:** Accepted
**Date:** 2026-07-15
**Source:** Issue [#1376](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/1376) (auto-grant asymmetry), origin [#1375](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/1375) (active members losing access)
**Related:** ADR-0107 (#209 Drive revocation cascade — the revoke primitive this mirrors), ADR-0108 (#301 curation FILE grant — the file-level cousin), ADR-0094 (Initiative Collaboration Hub — G4.1 service-account role), ADR-0007 (V4 authority), GC-162 (LGPD).
**Reuses:** the #209/#301 Drive-permission infra — SA auth via `_shared/drive-sa.ts`, `isServiceRoleToken` gate, ledger + partial-unique idempotency + deny-all RLS, the `listPermissions` folder helper, the drain/reconcile-cron discipline.

---

## Context

The platform had **auto-REVOKE** (ADR-0107/#209: offboarded members are detected and their Drive
permissions removed) and a **curation FILE grant** (ADR-0108/#301: curators get temporary `commenter`
access to a submitted artifact). It had **no auto-GRANT of the WORKSPACE folder to active tribe/initiative
members**. Access to a tribe folder depended on a human sharing it by hand, which broke silently on every
reorg, folder move, or new member — with no repair and no observability. The member only discovered the
break when they tried to open the folder (the #1375 incident: "todos os participantes perderam acesso").

Grounded at build time (live, `ldrfrvwhxsmgaabwmaik`, 2026-07-15):
- `drive_auto_revoke_enabled = false` and only 13 historical revocations (all offboarding). The platform
  **did not** revoke active members — confirming the loss is a Drive-side event the platform cannot repair.
- 6 of 12 active research tribes had **no** workspace link — the 6 created in July (C4), all unlinked;
  the 6 from April were linked by a one-off manual batch (2026-04-28). Tribe creation provisions nothing.
- 70 active engaged persons: 48 in initiatives WITH a workspace link (access depends on a manual share),
  32 in initiatives WITHOUT any folder.

Two symptoms, one root: **there is no provisioning automation** — every folder and every grant is manual.

## Decision

Close the auto-revoke ↔ auto-grant asymmetry with a **folder-anchored reconcile** (mirror of the
offboarding scan, grant side) plus a **GP-triggered provisioner** for the folder itself.

1. **Ledger** `drive_membership_grants` — GRANT mirror of `drive_offboarding_audit`. Keyed by
   `(initiative_id, drive_folder_id, grantee)`; role=`writer` (Editor — the tribe collaboration model,
   vs #301's least-privilege `commenter`); partial-unique on `(drive_folder_id, permission_email)` while
   live; deny-all RLS; `permission_email` is PII (SECDEF read only).

2. **Reconcile EF** `reconcile-initiative-drive-access` (service-role, SA `drive` scope). For each active
   workspace link: `listPermissions(folder)` (the SA CAN read the folder ACL — the "no ACL tool" caveat is
   about the assistant, not the EF) × active roster (`get_initiative_drive_roster`, PII-logged) → grant the
   missing emails (`POST /permissions`, role=writer, out-of-domain `sendNotificationEmail` wrinkle reused
   from #301) → `upsert_membership_drive_grants` (idempotent). Single-pass scan+grant (no human-approval
   gate — grants are low-risk, unlike revokes). Self-healing: re-run after any reorg re-grants.

3. **Daily cron** `membership-drive-reconcile-daily` (04:00 UTC) — full sweep, self-heal.

4. **Folder provisioning is GP-triggered, not cron-autonomous** (owner decision, #1376). `drive-create-subfolder`
   is OAuth user-delegated so folder OWNERSHIP falls to a human (governance/backup); a cron has no user.
   MCP tool `provision_initiative_drive` (GP, `manage_platform`) creates the subfolder (owner=human) +
   links it (workspace) + triggers the reconcile. The **weekly cron** `drive-workspace-missing-alert-weekly`
   only ALERTS the GP of tribes/workgroups still missing a folder (`notify_missing_drive_workspaces`).

5. **Observability** — `list_membership_drive_grants` + `get_membership_drive_grant_health` (GP), the
   latter surfacing the missing-folder queue that feeds `provision_initiative_drive`.

## Consequences

- **Prerequisite (unchanged from #209/ADR-0094 G4.1):** the SA needs organizer/fileOrganizer on the parent
  folder or every `POST` returns 403. Failures land as `failed` ledger rows (never crash), surfaced by
  the health RPC. Resolution is validated by **owner test** (folder opens), not ACL read — the SA creds are
  in the Vault and no tool reads an arbitrary folder ACL.
- Revocation stays the offboarding lane (#209). This ledger only records the grant side; when a member is
  offboarded, the offboarding scan detects+revokes the writer permission this created.
- The missing-folder alert is deliberately scoped to `research_tribe` + `workgroup` (avoids noise on
  community verticals, which have no folders by design). The GRANT reconcile is kind-agnostic — it works
  wherever a workspace link exists.

## Apply order

Same gate as #209: schedule the reconcile cron ONLY after the EF is deployed and the SA-role prerequisite
is confirmed (a `dry_run` reconcile returns a plan without granting). The weekly alert cron is pure SQL and
safe to schedule immediately.
