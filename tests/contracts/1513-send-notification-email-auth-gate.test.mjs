// #1513 — send-notification-email EF must gate on service-role.
//
// Measured live 2026-07-28 (version 34): verify_jwt=false AND the handler was
// `Deno.serve(async (_req) => {` — the request object was discarded, so the EF
// had no caller check at all and was reachable unauthenticated from the public
// internet. Two concrete harms, not hypothetical:
//
//   1. Quota. An anonymous POST force-drains the transactional queue. The
//      Resend daily allowance is shared with the campaign lane and blowing it
//      was a real incident (#1424) — the DAILY_SEND_CAP added there limits how
//      many mails go out, not who may trigger the run.
//   2. PII. The response body echoes member e-mail addresses in `errors[]`
//      (`errors.push(\`${member.email}: …\`)`), so a failing send hands
//      addresses to whoever called it. Anon must get nothing from PII (GC-162).
//
// The only legitimate caller is pg_cron jobid 9 (*/5 * * * *), which presents
// the vault `service_role_key`; isServiceRoleToken accepts it via the PostgREST
// probe (#738) and rejects forgeries, so the gate is non-breaking.
//
// Static source assertions (mirror of 1380-drive-create-subfolder-auth-gate):
// a deployed EF cannot be introspected from CI, so what this guards is that a
// future edit cannot silently drop or defang the gate. It does NOT prove the
// running version carries it — that pairing is verified by the merge+deploy+
// probe ritual recorded in the PR.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const ef = readFileSync("supabase/functions/send-notification-email/index.ts", "utf8");
const shared = readFileSync("supabase/functions/_shared/service-auth.ts", "utf8");

test("#1513: send-notification-email gates on service-role (isServiceRoleToken + bearerFrom)", () => {
  assert.match(
    ef,
    /import \{ isServiceRoleToken, bearerFrom \} from '\.\.\/_shared\/service-auth\.ts'/,
    "must import the shared caller-auth helpers, not re-implement them",
  );
  assert.match(ef, /if \(!\(await isServiceRoleToken\(SUPABASE_URL, bearerFrom\(req\)\)\)\)/);
});

test("#1513: the gate is awaited (an un-awaited Promise is always truthy → authorizes everyone)", () => {
  // The mutation that compiles, keeps the gate visibly in the source, and still
  // lets the whole internet through is dropping the `await`: `!Promise` is
  // always false. Assert the await explicitly rather than trusting the shape.
  const gateIdx = ef.indexOf("isServiceRoleToken(SUPABASE_URL, bearerFrom(req))");
  assert.ok(gateIdx !== -1, "gate present");
  const stmt = ef.slice(Math.max(0, gateIdx - 40), gateIdx);
  assert.match(stmt, /await\s*$/, "isServiceRoleToken must be awaited");
});

test("#1513: gate rejects non-service-role callers with 401 unauthorized", () => {
  const guard = ef.slice(ef.indexOf("isServiceRoleToken(SUPABASE_URL, bearerFrom(req))"));
  const block = guard.slice(0, 300);
  assert.match(block, /status:\s*401/);
  assert.match(block, /'unauthorized'|"unauthorized"/);
});

test("#1513: the gate runs before the Resend key, the DB client and any row fetch (fail-closed order)", () => {
  const serveIdx = ef.indexOf("Deno.serve");
  const gateIdx = ef.indexOf("isServiceRoleToken(SUPABASE_URL, bearerFrom(req))");
  const resendIdx = ef.indexOf("RESEND_API_KEY", serveIdx);
  const clientIdx = ef.indexOf("createClient", serveIdx);
  const fetchIdx = ef.indexOf("from('notifications')", serveIdx);
  assert.ok(gateIdx > serveIdx, "gate lives inside the handler");
  assert.ok(gateIdx < resendIdx, "gate precedes the Resend key read");
  assert.ok(gateIdx < clientIdx, "gate precedes service-role DB client creation");
  assert.ok(gateIdx < fetchIdx, "gate precedes the notifications fetch");
});

test("#1513: the handler binds the request (a `_req` signature discards it and cannot be gated)", () => {
  // This is the exact defect measured in production: the parameter was named
  // `_req`, so no gate could read a header even if one existed.
  assert.match(ef, /Deno\.serve\(async \(req\) =>/);
  assert.doesNotMatch(ef, /Deno\.serve\(async \(_req\)/);
});

test("#1513: bearerFrom is centralized in service-auth.ts and re-exported by drive-sa.ts", () => {
  // One implementation. drive-sa.ts keeps its export surface so the Drive EFs
  // (and the #1380 guard, which asserts that import path) stay untouched.
  assert.match(shared, /export function bearerFrom\(req: Request\): string \| null/);
  const driveSa = readFileSync("supabase/functions/_shared/drive-sa.ts", "utf8");
  assert.match(driveSa, /export \{ bearerFrom \} from "\.\/service-auth\.ts"/);
  assert.doesNotMatch(
    driveSa,
    /export function bearerFrom/,
    "drive-sa.ts must re-export, not carry a second copy",
  );
});
