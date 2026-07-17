/**
 * #1383 Wave 2 — Semantic envelope contract guard (members / engagements / initiatives).
 *
 * Wave 2 adds 9 intent-level tools that must all conform to the STABLE envelope
 * { ok, data, summary, warnings, next_actions, audit }, fail via the structured error
 * envelope (never a raw `err()` / bare `ok(data)` that lets an RPC `{error:...}` escape inside
 * ok:true), and carry their authority contract as CODE:
 *   - member_search REDACTS PII (email/auth_id) unless view_pii (canSeePII) — LGPD data-minimization.
 *   - member_get / member_emails close the email-existence oracle (email resolve → manage_member).
 *   - engagement_write / initiative_roster / initiative_report carry the #785 confidential gate (canSee).
 *   - member_lifecycle is GP-only (manage_member) and warns Camada-5 on reissue.
 *   - my_status is SELF-only (pii_level: "self", no cross-member surface).
 *
 * Pure static check over supabase/functions/nucleo-mcp/index.ts (no network / no DB) — runs in every
 * offline baseline. A future edit that drops the envelope, a gate, or a PII guard fails CI here.
 *
 * Cross-ref: EPIC #1383, wave0-artifacts/taxonomy.md §2.2 + §4, .claude/rules/mcp.md, SPEC-280.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const SRC = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

// The 9 Wave-2 semantic tools, in traffic order (taxonomy §2.2).
const W2_TOOLS = [
  'member_search',
  'member_get',
  'member_emails',
  'member_lifecycle',
  'engagement_write',
  'initiative_roster',
  'initiative_directory',
  'initiative_report',
  'my_status',
];

// Write tools (carry mutating actions).
const WRITE_TOOLS = new Set(['member_emails', 'member_lifecycle', 'engagement_write']);
// Tools that address an initiative resource → must carry the #785 fail-fast gate (canSee).
const CANSEE_TOOLS = new Set(['engagement_write', 'initiative_roster', 'initiative_report']);

/** Isolate the registerSemanticTools(...) function body (ends right before the /actions comment). */
function semanticBody(src) {
  const start = src.indexOf('function registerSemanticTools(');
  assert.ok(start !== -1, 'registerSemanticTools() not found');
  const end = src.indexOf('// #1377 — /actions overflow surface.', start);
  assert.ok(end !== -1, 'end sentinel (/actions comment) not found after registerSemanticTools');
  return src.slice(start, end);
}

/** Split the body into per-tool blocks keyed by tool name (first string arg of mcp.tool(). */
function toolBlocks(body) {
  const idxs = [];
  const re = /mcp\.tool\(\s*\n?\s*"([a-zA-Z0-9_]+)"/g;
  let m;
  while ((m = re.exec(body)) !== null) idxs.push({ name: m[1], at: m.index });
  const blocks = {};
  for (let i = 0; i < idxs.length; i++) {
    const from = idxs[i].at;
    const to = i + 1 < idxs.length ? idxs[i + 1].at : body.length;
    blocks[idxs[i].name] = body.slice(from, to);
  }
  return blocks;
}

const BODY = semanticBody(SRC);
const BLOCKS = toolBlocks(BODY);

test('W2: the canSeePII() helper resolves view_pii (LGPD data-minimization), fail-closed via canV4', () => {
  const helper = SRC.match(/async function canSeePII\(sb:[\s\S]*?\n\}/);
  assert.ok(helper, 'canSeePII() helper not found');
  assert.ok(/canV4\(sb,\s*memberId,\s*"view_pii"\)/.test(helper[0]), 'canSeePII() must delegate to canV4(view_pii)');
});

test('W2: all 9 members/engagements/initiatives semantic tools are registered', () => {
  for (const t of W2_TOOLS) {
    assert.ok(BLOCKS[t], `Wave-2 tool not registered in registerSemanticTools: ${t}`);
  }
});

for (const tool of W2_TOOLS) {
  test(`W2[${tool}]: conforms to the stable envelope (semanticOk success + buildSemanticError failure)`, () => {
    const b = BLOCKS[tool];
    assert.ok(b.includes('semanticOk('), `${tool}: success path must return via semanticOk() (stable envelope)`);
    assert.ok(b.includes('buildSemanticError('), `${tool}: error/unauth path must return via buildSemanticError() (ok:false envelope)`);
    assert.ok(/code:\s*"unauthenticated"/.test(b), `${tool}: missing structured unauthenticated error`);
  });

  test(`W2[${tool}]: never leaks a raw error (no bare err() / no return ok(data) escape)`, () => {
    const b = BLOCKS[tool];
    assert.ok(!/return\s+err\(/.test(b), `${tool}: uses raw err() — must use buildSemanticError() inside ok()`);
    const badOk = /return\s+ok\((?!\s*(?:buildSemanticError|\{))/.test(b);
    assert.ok(!badOk, `${tool}: return ok(...) must wrap an object literal or buildSemanticError(), not a raw payload`);
  });

  test(`W2[${tool}]: audit block sets an explicit gate_checked + caller_member_id + pii_level`, () => {
    const b = BLOCKS[tool];
    assert.ok(b.includes('gate_checked:'), `${tool}: audit must state gate_checked`);
    assert.ok(b.includes('caller_member_id:'), `${tool}: audit must state caller_member_id`);
    assert.ok(b.includes('pii_level:'), `${tool}: audit must state pii_level`);
  });
}

for (const tool of CANSEE_TOOLS) {
  test(`W2[${tool}]: initiative-linked tool carries the #785 gate (canSee) on the resource path`, () => {
    const b = BLOCKS[tool];
    assert.ok(/await canSee\(sb,\s*"initiative"/.test(b), `${tool}: must fail-fast on rls_can_see_initiative (#785)`);
  });
}

for (const tool of WRITE_TOOLS) {
  test(`W2[${tool}]: write tool declares an action discriminator`, () => {
    const b = BLOCKS[tool];
    assert.ok(/action:\s*z\.enum\(/.test(b), `${tool}: write tool must expose an action enum`);
  });
}

test('W2[member_search]: gates on manage_member AND redacts PII (email/auth_id) unless view_pii', () => {
  const b = BLOCKS['member_search'];
  assert.ok(/canV4\(sb,\s*member\.id,\s*"manage_member"\)/.test(b), 'member_search must gate on manage_member');
  assert.ok(b.includes('canSeePII(sb, member.id)'), 'member_search must check canSeePII');
  assert.ok(/email:\s*null/.test(b) && /auth_id:\s*null/.test(b), 'member_search must redact email + auth_id when !view_pii');
});

test('W2[member_get]: accepts member_id (fixes get_person #2-failure) and gates email-resolve on manage_member (anti-oracle)', () => {
  const b = BLOCKS['member_get'];
  assert.ok(/member_id:\s*z\.string\(\)\.optional/.test(b), 'member_get must accept member_id');
  assert.ok(b.includes('member_resolve_email'), 'member_get must resolve email via member_resolve_email');
  assert.ok(/canV4\(sb,\s*member\.id,\s*"manage_member"\)/.test(b), 'member_get email-resolve must require manage_member (anti-enumeration)');
  assert.ok(b.includes('get_active_engagements'), 'member_get must absorb get_active_engagements');
});

test('W2[member_emails]: resolve action adds a manage_member gate (closes the email-existence oracle)', () => {
  const b = BLOCKS['member_emails'];
  assert.ok(/params\.action\s*===\s*"resolve"/.test(b), 'member_emails must special-case resolve');
  assert.ok(/canV4\(sb,\s*member\.id,\s*"manage_member"\)/.test(b), 'member_emails resolve must require manage_member');
});

test('W2[member_lifecycle]: GP-only (manage_member) and warns Camada-5 on reissue', () => {
  const b = BLOCKS['member_lifecycle'];
  assert.ok(/canV4\(sb,\s*member\.id,\s*"manage_member"\)/.test(b), 'member_lifecycle must gate admin verbs on manage_member');
  assert.ok(/Camada-5/i.test(b), 'member_lifecycle must warn about Camada-5 (reissue demotes authority)');
});

test('W2[my_status]: SELF-only — pii_level "self", no cross-member manage_member surface', () => {
  const b = BLOCKS['my_status'];
  assert.ok(/pii_level:\s*"self"/.test(b), 'my_status must declare pii_level: self');
  assert.ok(!/canV4\(sb,\s*member\.id,\s*"manage_member"\)/.test(b), 'my_status must NOT expose an admin (manage_member) surface');
});

test('W2: /semantic health surface still advertises the Wave-2 tools (count now 33 after Wave 4)', () => {
  const health = SRC.match(/"\/semantic":\s*\{[^}]*tools:\s*(\d+)/);
  assert.ok(health, '/semantic health entry not found');
  assert.equal(Number(health[1]), 33, '/semantic health tools count must be 33 after Wave 4 (4 bridge + 8 W1 + 9 W2 + 6 W3 + 6 W4)');
});
