/**
 * GAP-205.D contract test — member_emails write surface (remove + set_primary + update_kind)
 *
 * Static analysis tripwire over migration + MCP edge function. Asserts the
 * structural contract of the 3 new write RPCs introduced by migration
 * 20260802000013_p216_205d_member_emails_write_surface.sql and the 3
 * matching MCP tool registrations in supabase/functions/nucleo-mcp/index.ts.
 *
 * Issue: #205 GAP-205.D (P162 #126) — surfaced organically in p215 PM smoke
 * when an alternate email was added with the wrong `kind`. The earlier p213
 * batch shipped read + add surface only (member_resolve_email +
 * member_list_emails + member_add_alternate_email). The 3 missing write
 * operations required direct SQL until p216.
 *
 * Why static analysis (not behavioural):
 *   - The behavioural surface is already validated by the smoke DO block
 *     run during the migration application step (see migration header).
 *   - DB-aware tests gate on SUPABASE_URL + SERVICE_ROLE_KEY env which is
 *     not configured by default in offline CI (see WATCH-205.A / feedback
 *     memory contract_test_ci_skip_silent).
 *   - This test catches regressions where future migrations drop the
 *     primary-rejection branch, the auth gate, or the SECURITY DEFINER
 *     attribute — drift that would be invisible until a behavioural test
 *     happens to exercise the missing branch.
 *
 * Pattern: pattern-agnostic CREATE FUNCTION regex per WATCH-215.A (the
 * strict `CREATE OR REPLACE FUNCTION` form would silently latch stale
 * bodies when DROP+CREATE is used, as migration 20260802000013 does).
 *
 * Cross-ref:
 *   - ADR-0095 §4 (Canonical RPC APIs) + Amendment 2026-05-21 (GAP-205.D)
 *   - Migration 20260802000013 (3 RPCs)
 *   - supabase/functions/nucleo-mcp/index.ts (3 MCP tools)
 *   - P162 #126 GAP-205.D (docs/audit/P162_GAP_OPPORTUNITY_LOG.md)
 *
 * Scope: static analysis. Fast, no DB env required.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const MCP_INDEX_PATH = resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts');

function loadMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => ({
    name: f,
    content: readFileSync(join(MIGRATIONS_DIR, f), 'utf8'),
  }));
}

const migrations = loadMigrations();
const writeSurfaceMig = migrations.find(m => m.name.includes('p216_205d_member_emails_write_surface'));
const councilAmendmentsMig = migrations.find(m => m.name.includes('p216_205d_council_amendments'));
const mcpIndex = readFileSync(MCP_INDEX_PATH, 'utf8');

const RPC_NAMES = [
  'member_remove_alternate_email',
  'member_set_primary_email',
  'member_update_alternate_email_kind',
];

// Pattern-agnostic per WATCH-215.A: match CREATE FUNCTION or CREATE OR REPLACE FUNCTION
function createFnRegex(name) {
  return new RegExp(`CREATE(?:\\s+OR\\s+REPLACE)?\\s+FUNCTION\\s+public\\.${name}\\s*\\(`, 'i');
}

// ─── 1. Migration file exists and is named correctly ───
test('GAP-205.D: migration 20260802000013 exists with canonical p216_205d naming', () => {
  assert.ok(writeSurfaceMig,
    'Migration 20260802000013_p216_205d_member_emails_write_surface.sql must exist. ' +
    'This migration ships the 3 write RPCs that close GAP-205.D from p215 PM smoke.');
  assert.match(writeSurfaceMig.name, /20260802000013_p216_205d/,
    'Migration filename must encode p216 session + GAP-205.D for cross-ref.');
});

// ─── 2. Each of the 3 RPCs is defined in the migration ───
for (const rpc of RPC_NAMES) {
  test(`GAP-205.D: ${rpc} CREATE FUNCTION block exists`, () => {
    assert.ok(writeSurfaceMig, 'precondition: migration must exist');
    assert.match(writeSurfaceMig.content, createFnRegex(rpc),
      `Migration must define public.${rpc} via CREATE [OR REPLACE] FUNCTION ` +
      `(pattern-agnostic per WATCH-215.A — strict regex silently latches stale bodies).`);
  });
}

// ─── 3. Each RPC has SECURITY DEFINER + SET search_path (defense in depth) ───
for (const rpc of RPC_NAMES) {
  test(`GAP-205.D: ${rpc} has SECURITY DEFINER + SET search_path = public, pg_temp`, () => {
    assert.ok(writeSurfaceMig, 'precondition: migration must exist');
    // Extract the function body (CREATE FUNCTION ... $$...$$;) — pattern-agnostic
    const blockRe = new RegExp(
      `CREATE(?:\\s+OR\\s+REPLACE)?\\s+FUNCTION\\s+public\\.${rpc}\\s*\\(([\\s\\S]+?)\\$\\$;`,
      'i'
    );
    const m = writeSurfaceMig.content.match(blockRe);
    assert.ok(m, `Could not locate full ${rpc} body block`);
    assert.match(m[0], /SECURITY\s+DEFINER/i,
      `${rpc} must declare SECURITY DEFINER (table has RLS deny-all; RPC is the only ` +
      `legitimate write path per ADR-0095 §3).`);
    assert.match(m[0], /SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i,
      `${rpc} must SET search_path = public, pg_temp (defense against search_path ` +
      `injection on SECDEF functions per database.md rules).`);
  });
}

// ─── 4. Each RPC has the canonical self-OR-manage_member auth gate ───
for (const rpc of RPC_NAMES) {
  test(`GAP-205.D: ${rpc} enforces self-OR-manage_member auth gate`, () => {
    assert.ok(writeSurfaceMig, 'precondition: migration must exist');
    const blockRe = new RegExp(
      `CREATE(?:\\s+OR\\s+REPLACE)?\\s+FUNCTION\\s+public\\.${rpc}\\s*\\(([\\s\\S]+?)\\$\\$;`,
      'i'
    );
    const m = writeSurfaceMig.content.match(blockRe);
    assert.ok(m, `Could not locate ${rpc} body`);
    // self check: v_caller.id = p_member_id
    assert.match(m[0], /v_caller\.id\s*=\s*p_member_id/,
      `${rpc} must allow self (v_caller.id = p_member_id).`);
    // manage_member capability check
    assert.match(m[0], /can_by_member\s*\(\s*v_caller\.id\s*,\s*'manage_member'\s*\)/,
      `${rpc} must check can_by_member(v_caller.id, 'manage_member') as the ` +
      `delegated authority path.`);
    // RAISE on unauthorized
    assert.match(m[0], /RAISE\s+EXCEPTION\s+'Unauthorized/i,
      `${rpc} must RAISE EXCEPTION on unauthorized access (not return NULL/false silently).`);
  });
}

// ─── 5. Primary-email rejection branches ───
test('GAP-205.D: member_remove_alternate_email rejects primary', () => {
  assert.ok(writeSurfaceMig, 'precondition: migration must exist');
  const blockRe = /CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION\s+public\.member_remove_alternate_email\s*\(([\s\S]+?)\$\$;/i;
  const m = writeSurfaceMig.content.match(blockRe);
  assert.ok(m, 'Could not locate member_remove_alternate_email body');
  assert.match(m[0], /IF\s+v_is_primary\s+THEN[\s\S]{0,200}RAISE\s+EXCEPTION\s+'Cannot remove primary/i,
    'member_remove_alternate_email must RAISE when target row is primary; ' +
    'caller must use member_set_primary_email to demote first.');
});

test('GAP-205.D: member_update_alternate_email_kind rejects primary', () => {
  assert.ok(writeSurfaceMig, 'precondition: migration must exist');
  const blockRe = /CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION\s+public\.member_update_alternate_email_kind\s*\(([\s\S]+?)\$\$;/i;
  const m = writeSurfaceMig.content.match(blockRe);
  assert.ok(m, 'Could not locate member_update_alternate_email_kind body');
  assert.match(m[0], /IF\s+v_is_primary\s+THEN[\s\S]{0,200}RAISE\s+EXCEPTION\s+'Cannot change kind on primary/i,
    'member_update_alternate_email_kind must RAISE when target row is primary; ' +
    'primary kind follows backfill convention per ADR-0095 amendment.');
});

// ─── 6. member_set_primary_email routes through UPDATE members.email (trigger path) ───
test('GAP-205.D: member_set_primary_email routes through UPDATE members.email (sync trigger)', () => {
  assert.ok(writeSurfaceMig, 'precondition: migration must exist');
  const blockRe = /CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION\s+public\.member_set_primary_email\s*\(([\s\S]+?)\$\$;/i;
  const m = writeSurfaceMig.content.match(blockRe);
  assert.ok(m, 'Could not locate member_set_primary_email body');
  assert.match(m[0], /UPDATE\s+public\.members\s+SET\s+email\s*=/i,
    'member_set_primary_email must UPDATE public.members SET email — this is the ' +
    'canonical trigger path per ADR-0095 amendment (PM p216 ABCD Option A). ' +
    'Bypassing the trigger would lose the cross-member theft guard from mig 20260802000009.');
});

// ─── 7. update_kind validates p_new_kind against the allowed set ───
test('GAP-205.D: member_update_alternate_email_kind validates p_new_kind set', () => {
  assert.ok(writeSurfaceMig, 'precondition: migration must exist');
  const blockRe = /CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION\s+public\.member_update_alternate_email_kind\s*\(([\s\S]+?)\$\$;/i;
  const m = writeSurfaceMig.content.match(blockRe);
  assert.ok(m, 'Could not locate member_update_alternate_email_kind body');
  assert.match(m[0], /p_new_kind\s+NOT\s+IN\s*\(\s*'personal'\s*,\s*'institutional'\s*,\s*'chapter'\s*,\s*'other'\s*\)/i,
    'member_update_alternate_email_kind must validate p_new_kind against the same ' +
    'set as the table CHECK constraint (personal, institutional, chapter, other). ' +
    'Drift between CHECK and validation would cause RAISE EXCEPTION at INSERT/UPDATE ' +
    'instead of the user-friendly RPC-level error.');
});

// ─── 8. Each RPC has a GRANT EXECUTE TO authenticated ───
for (const rpc of RPC_NAMES) {
  test(`GAP-205.D: ${rpc} GRANT EXECUTE TO authenticated`, () => {
    assert.ok(writeSurfaceMig, 'precondition: migration must exist');
    const grantRe = new RegExp(`GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${rpc}\\s*\\([^)]*\\)\\s+TO\\s+authenticated`, 'i');
    assert.match(writeSurfaceMig.content, grantRe,
      `${rpc} must GRANT EXECUTE TO authenticated (RLS deny-all + SECDEF means the GRANT ` +
      `is the only execution surface for authenticated callers).`);
  });
}

// ─── 9. MCP tool registrations for the 3 new RPCs ───
for (const rpc of RPC_NAMES) {
  test(`GAP-205.D: MCP tool ${rpc} is registered in nucleo-mcp/index.ts`, () => {
    const toolRe = new RegExp(`mcp\\.tool\\s*\\(\\s*"${rpc}"`, 'i');
    assert.match(mcpIndex, toolRe,
      `nucleo-mcp/index.ts must register mcp.tool("${rpc}", ...). Without the MCP ` +
      `registration the RPC is reachable only via direct PostgREST or sql client, ` +
      `defeating the agentic-workflow surface described in ADR-0095 §5.`);
  });
}

// ─── 10. MCP server version is bumped past p215's 2.77.0 ───
test('GAP-205.D: McpServer version is bumped past p215 (>= 2.78.0)', () => {
  const versionRe = /McpServer\s*\(\s*\{[^}]*version:\s*"([^"]+)"/;
  const m = mcpIndex.match(versionRe);
  assert.ok(m, 'Could not find McpServer({ name, version }) constructor in nucleo-mcp/index.ts');
  const [major, minor] = m[1].split('.').map(Number);
  assert.ok(major >= 2, `McpServer version major must be >= 2, got ${m[1]}`);
  assert.ok(major > 2 || minor >= 78,
    `McpServer version must be >= 2.78.0 (was 2.77.0 at p215 close), got ${m[1]}. ` +
    `This PR adds 3 tools and a behavioural surface change worth a minor bump.`);
});

// ─── 11. /health endpoint tool count matches catalog claim (ratchet) ───
// p222 #280 update: /health was restructured to report BOTH /mcp and /semantic surfaces,
// so the regex now targets the surfaces."/mcp".tools field specifically (was: greedy first
// `tools: N` after /health which picked up /semantic.tools=3 after the restructure).
// p239b #332 update: ratchet 299 → 301 to absorb +2 LGPD retroactive operator tools.
// History: 296 (p215) → 299 (GAP-205.D) → 301 (p239b #332).
test('GAP-205.D + p239b #332: /health endpoint reports /mcp tools = 301 (matches catalog ratchet)', () => {
  const healthBlockRe = /app\.get\s*\(\s*"\/health"[\s\S]{0,800}?\}\)\s*\)\s*;/;
  const block = mcpIndex.match(healthBlockRe);
  assert.ok(block, 'Could not find /health endpoint block in nucleo-mcp/index.ts');
  // Match the /mcp surface's tools count specifically. Resilient to additional sibling surfaces.
  const mcpToolsRe = /"\/mcp"\s*:\s*\{[^}]*?tools:\s*(\d+)/;
  const m = block[0].match(mcpToolsRe);
  assert.ok(m, 'Could not find "/mcp" surface tools count in /health endpoint');
  const count = Number(m[1]);
  assert.equal(count, 301,
    `/health /mcp surface tools count must equal 301 (= 296 at p215 close + 3 GAP-205.D + 2 p239b #332 ` +
    `LGPD retroactive operator tools). Source-of-truth is the runtime tools/list, but the /health label ` +
    `should track to avoid the WATCH-205.G drift class.`);
});

// ─── 12. Council Tier 1 amendments migration exists ───
test('GAP-205.D: council amendments migration 20260802000014 exists', () => {
  assert.ok(councilAmendmentsMig,
    'Migration 20260802000014_p216_205d_council_amendments.sql must exist. ' +
    'This migration ships HIGH (LGPD oracle) + MED (FOR UPDATE concurrency + org boundary) + LOW (internal name) fixes from PR #244 Council Tier 1 review.');
  assert.match(councilAmendmentsMig.name, /20260802000014_p216_205d_council_amendments/,
    'Council amendments migration filename must encode p216 session + 205d + council_amendments anchor for cross-ref.');
});

// ─── 13. HIGH (LGPD): member_set_primary_email uses generic "Email not found for this member" msg ───
test('GAP-205.D council HIGH: set_primary error msg is generic (no member_id echo, no helper-RPC hint)', () => {
  assert.ok(councilAmendmentsMig, 'precondition: amendments migration must exist');
  const blockRe = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.member_set_primary_email\s*\(([\s\S]+?)\$\$;/i;
  const m = councilAmendmentsMig.content.match(blockRe);
  assert.ok(m, 'Could not locate member_set_primary_email body in amendments migration');
  assert.match(m[0], /RAISE\s+EXCEPTION\s+'Email not found for this member;\s+ensure it was previously added\.'/i,
    'member_set_primary_email must use the generic LGPD-safe message ' +
    '"Email not found for this member; ensure it was previously added." — no %s ' +
    'placeholders for member_id, no helper-RPC hint. Replaces the original p216 message ' +
    'that exposed p_member_id (enumeration oracle for callers with manage_member).');
  // Explicit negative checks: must NOT contain the leaky patterns from migration 13
  assert.doesNotMatch(m[0], /Email % is not registered for member %/i,
    'set_primary must not have the original "Email % is not registered for member %" format — it leaks member_id via %s.');
  assert.doesNotMatch(m[0], /add it via member_add_alternate_email first/i,
    'set_primary must not hint at the helper RPC name in the user-facing error.');
});

// ─── 14. MED #1 (concurrency): member_remove_alternate_email uses FOR UPDATE on the SELECT ───
test('GAP-205.D council MED #1: remove uses SELECT ... FOR UPDATE to serialize against trigger UPDATEs', () => {
  assert.ok(councilAmendmentsMig, 'precondition: amendments migration must exist');
  const blockRe = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.member_remove_alternate_email\s*\(([\s\S]+?)\$\$;/i;
  const m = councilAmendmentsMig.content.match(blockRe);
  assert.ok(m, 'Could not locate member_remove_alternate_email body in amendments migration');
  assert.match(m[0], /SELECT\s+id,\s+is_primary[\s\S]{0,200}FROM\s+public\.member_emails[\s\S]{0,200}LIMIT\s+1[\s\S]{0,40}FOR\s+UPDATE/i,
    'member_remove_alternate_email must use SELECT ... LIMIT 1 FOR UPDATE on member_emails. ' +
    'Without the row-level lock, a concurrent member_set_primary_email on another connection ' +
    'can promote the row between our SELECT (is_primary=false) and our DELETE — leaving the ' +
    'member with zero primary rows, violating T_member_has_exactly_one_primary_email.');
});

// ─── 15. MED #2 (org boundary): all 3 RPCs anchor on members.id existence check ───
for (const rpc of RPC_NAMES) {
  test(`GAP-205.D council MED #2: ${rpc} has org boundary anchor (SELECT organization_id FROM members + Member not found raise)`, () => {
    assert.ok(councilAmendmentsMig, 'precondition: amendments migration must exist');
    const blockRe = new RegExp(
      `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${rpc}\\s*\\(([\\s\\S]+?)\\$\\$;`,
      'i'
    );
    const m = councilAmendmentsMig.content.match(blockRe);
    assert.ok(m, `Could not locate ${rpc} body in amendments migration`);
    assert.match(m[0], /SELECT\s+organization_id\s+INTO\s+v_target_org_id\s+FROM\s+public\.members\s+WHERE\s+id\s*=\s*p_member_id/i,
      `${rpc} must perform "SELECT organization_id INTO v_target_org_id FROM public.members WHERE id = p_member_id" as an org-boundary anchor. ` +
      `SECDEF functions bypass RLS, so the member_emails_v4_org_scope RESTRICTIVE policy does not apply. ` +
      `The anchor (a) raises Member not found if the target member does not exist (matches member_add_alternate_email pattern), ` +
      `and (b) creates a single point for future cross-org scoping when policy tightens.`);
    assert.match(m[0], /IF\s+NOT\s+FOUND\s+THEN[\s\S]{0,80}RAISE\s+EXCEPTION\s+'Member not found:/i,
      `${rpc} must RAISE 'Member not found: %' (with p_member_id format arg in the developer-debugging context — ` +
      `acceptable here because the member_id was already supplied by the caller, so this is not a privacy oracle).`);
  });
}

// ─── 16. LOW #1 (LGPD-adjacent): remove primary error msg drops internal RPC name "member_set_primary_email" ───
test('GAP-205.D council LOW #1: remove primary error msg uses neutral guidance (no internal RPC name)', () => {
  assert.ok(councilAmendmentsMig, 'precondition: amendments migration must exist');
  const blockRe = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.member_remove_alternate_email\s*\(([\s\S]+?)\$\$;/i;
  const m = councilAmendmentsMig.content.match(blockRe);
  assert.ok(m, 'Could not locate member_remove_alternate_email body in amendments migration');
  assert.match(m[0], /RAISE\s+EXCEPTION\s+'Cannot remove primary email;\s+promote a different alternate to primary first\.'/i,
    'remove primary error msg must be neutral: "Cannot remove primary email; promote a different alternate to primary first."');
  assert.doesNotMatch(m[0], /promote another alternate via member_set_primary_email/i,
    'remove primary error msg must not reference the internal RPC name member_set_primary_email.');
});
