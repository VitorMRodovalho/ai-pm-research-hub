// #1380 — drive-create-subfolder EF must gate on service-role.
//
// The EF deploys with verify_jwt=false (confirmed live 2026-07-20, version 12),
// so the Supabase gateway does NOT authenticate callers. Without an app-level
// gate the EF is reachable UNauthenticated from the public internet and would
// create Drive folders under the org service account (quota/structure abuse,
// blast radius amplified by the #1376 provision_initiative_drive caller).
//
// Both legitimate callers (nucleo-mcp tools create_drive_subfolder /
// provision_initiative_drive) enforce the member's V4 authority and invoke the
// EF server-to-server with the SERVICE_ROLE_KEY, so a service-role gate is
// non-breaking. This is a static source assertion (mirror of the reconcile EF
// test in 1376-drive-membership-provisioning) so a future edit cannot silently
// drop the gate.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const ef = readFileSync("supabase/functions/drive-create-subfolder/index.ts", "utf8");

test("#1380: drive-create-subfolder gates on service-role (isServiceRoleToken + bearerFrom)", () => {
  assert.match(ef, /import \{ isServiceRoleToken \} from "\.\.\/_shared\/service-auth\.ts"/);
  assert.match(ef, /import \{ bearerFrom \} from "\.\.\/_shared\/drive-sa\.ts"/);
  assert.match(ef, /if \(!\(await isServiceRoleToken\(SUPABASE_URL, bearerFrom\(req\)\)\)\)/);
});

test("#1380: gate rejects non-service-role callers with 401 unauthorized", () => {
  // the guard block must return 401 (not fall through to folder creation)
  const guard = ef.slice(ef.indexOf("isServiceRoleToken(SUPABASE_URL, bearerFrom(req))"));
  const block = guard.slice(0, 300);
  assert.match(block, /status:\s*401/);
  assert.match(block, /"unauthorized"|error":\s*"unauthorized|error: "unauthorized"/);
});

test("#1380: the gate runs before any Vault read / Drive API call (fail-closed order)", () => {
  const gateIdx = ef.indexOf("isServiceRoleToken(SUPABASE_URL, bearerFrom(req))");
  const vaultIdx = ef.indexOf("getOAuthCreds()", ef.indexOf("Deno.serve"));
  const createIdx = ef.indexOf("createSubfolder(", ef.indexOf("Deno.serve"));
  assert.ok(gateIdx !== -1, "gate present");
  assert.ok(gateIdx < vaultIdx, "gate precedes Vault read");
  assert.ok(gateIdx < createIdx, "gate precedes folder creation");
});
