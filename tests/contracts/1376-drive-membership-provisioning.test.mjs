// #1376 / ADR-0124 — Drive membership auto-grant + provisioning.
// Static contract test (file-based, no DB): guards the structural invariants of the mechanism so a
// future edit cannot silently drop the RLS gate, the service-role scoping, the crons, the EF auth, or
// the MCP authority gates. DB-aware behavior (grants actually land) is validated post-deploy by owner
// test (the Drive ACL is not readable from CI — SA creds live in the Vault).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const MIG = "supabase/migrations/";
const table = readFileSync(MIG + "20260805000440_1376_drive_membership_grants_table.sql", "utf8");
const rpcs = readFileSync(MIG + "20260805000441_1376_drive_membership_grants_rpcs.sql", "utf8");
const cron = readFileSync(MIG + "20260805000442_1376_drive_membership_reconcile_cron.sql", "utf8");
const ef = readFileSync("supabase/functions/reconcile-initiative-drive-access/index.ts", "utf8");
const mcp = readFileSync("supabase/functions/nucleo-mcp/index.ts", "utf8");

test("#1376: ledger table is RLS deny-all + revoked from PUBLIC/anon/authenticated (LGPD fail-closed)", () => {
  assert.match(table, /CREATE TABLE IF NOT EXISTS public\.drive_membership_grants/);
  assert.match(table, /ENABLE ROW LEVEL SECURITY/);
  assert.match(table, /USING \(false\) WITH CHECK \(false\)/);
  assert.match(table, /REVOKE ALL ON public\.drive_membership_grants FROM PUBLIC, anon, authenticated/);
  assert.match(table, /permission_email\s+citext/); // PII stored as citext, deny-all protected
});

test("#1376: idempotency — one live grant per (folder, email)", () => {
  assert.match(table, /CREATE UNIQUE INDEX[^;]*drive_membership_grants_active_uidx[\s\S]*?\(drive_folder_id, permission_email\)[\s\S]*?WHERE status IN \('pending_grant','granted','failed'\)/);
  // ON CONFLICT target in the upsert must mirror the partial-index predicate exactly (inference).
  assert.match(rpcs, /ON CONFLICT \(drive_folder_id, permission_email\) WHERE status IN \('pending_grant','granted','failed'\)/);
});

test("#1376: EF-facing RPCs are service-role only + granted to service_role, revoked from anon/authenticated", () => {
  for (const fn of ["get_membership_drive_targets", "get_initiative_drive_roster", "upsert_membership_drive_grants", "notify_missing_drive_workspaces"]) {
    assert.match(rpcs, new RegExp(`FUNCTION public\\.${fn}\\b`), `${fn} defined`);
    assert.match(rpcs, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}[^;]*TO service_role`), `${fn} granted to service_role`);
    assert.match(rpcs, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}[^;]*FROM PUBLIC, anon, authenticated`), `${fn} revoked from clients`);
  }
  // the three EF-invoked-via-PostgREST RPCs hard-gate on service-role
  const svcGuards = rpcs.match(/service-role only/g) || [];
  assert.ok(svcGuards.length >= 3, "service-role guards present on EF-facing RPCs (targets/roster/upsert)");
});

test("#1376: cron-invoked RPCs use the cron-context bypass, not auth.role() (ADR-0028 p89)", () => {
  // notify_missing_drive_workspaces + list_initiatives_missing_drive_workspace run under pg_cron with
  // NO PostgREST JWT context, so a current_caller_role()/auth.role() gate would raise on every run.
  for (const fn of ["notify_missing_drive_workspaces", "list_initiatives_missing_drive_workspace"]) {
    const body = rpcs.slice(rpcs.indexOf(`FUNCTION public.${fn}`), rpcs.indexOf(`FUNCTION public.${fn}`) + 1400);
    assert.match(body, /current_setting\('role', true\) IN \('service_role','postgres'\)/, `${fn} uses cron-context bypass`);
    assert.match(body, /current_user IN \('postgres','supabase_admin'\)/, `${fn} accepts pg_cron user`);
    assert.doesNotMatch(body, /current_caller_role\(\) IS DISTINCT FROM 'service_role'/, `${fn} must NOT gate on auth.role()`);
  }
});

test("#1376: roster RPC logs the PII (email) read system-side (accessor NULL)", () => {
  assert.match(rpcs, /INSERT INTO public\.pii_access_log[\s\S]*?reconcile_initiative_drive_access/);
});

test("#1376: GP observability RPCs gate on manage_platform via members.auth_id", () => {
  for (const fn of ["admin_list_membership_drive_grants", "get_membership_drive_grant_health"]) {
    const body = rpcs.slice(rpcs.indexOf(`FUNCTION public.${fn}`));
    assert.match(body, /SELECT id FROM public\.members WHERE auth_id = auth\.uid\(\)/, `${fn} resolves caller`);
    assert.match(body, /can_by_member\(v_caller_id, 'manage_platform'\)/, `${fn} gates manage_platform`);
  }
});

test("#1376: crons scheduled — daily reconcile + weekly missing-folder alert", () => {
  assert.match(cron, /cron\.schedule\(\s*'membership-drive-reconcile-daily'/);
  assert.match(cron, /reconcile-initiative-drive-access/);
  assert.match(cron, /cron\.schedule\(\s*'drive-workspace-missing-alert-weekly'/);
  assert.match(cron, /notify_missing_drive_workspaces/);
});

test("#1376: reconcile EF is service-role gated, grants writer via SA, upserts the ledger", () => {
  assert.match(ef, /isServiceRoleToken/);
  assert.match(ef, /DRIVE_WRITE_SCOPE/);
  assert.match(ef, /role:\s*"writer"/);
  assert.match(ef, /upsert_membership_drive_grants/);
  assert.match(ef, /get_membership_drive_targets/);
  assert.match(ef, /get_initiative_drive_roster/);
});

test("#1376: MCP tools registered and GP-gated; write tools in /actions allowlist", () => {
  for (const t of ["provision_initiative_drive", "reconcile_initiative_drive_access", "list_membership_drive_grants", "get_membership_drive_grant_health"]) {
    assert.match(mcp, new RegExp(`mcp\\.tool\\("${t}"`), `${t} registered`);
  }
  // write tools gate manage_platform
  for (const t of ["provision_initiative_drive", "reconcile_initiative_drive_access"]) {
    const block = mcp.slice(mcp.indexOf(`mcp.tool("${t}"`), mcp.indexOf(`mcp.tool("${t}"`) + 2500);
    assert.match(block, /canV4\(sb, member\.id, "manage_platform"\)/, `${t} gates manage_platform`);
    // and is re-exposed on the /actions overflow surface (past the 256 alphabetical cut)
    assert.match(mcp, new RegExp(`"${t}",`), `${t} in ACTIONS_ALLOWLIST`);
  }
});
