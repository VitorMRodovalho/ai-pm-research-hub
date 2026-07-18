/**
 * #1383 Wave 1 — Semantic envelope contract guard (boards & cards).
 *
 * The transition to the /semantic gateway (SPEC-280) promises a STABLE envelope on every
 * semantic tool: { ok, data, summary, warnings, next_actions, audit }. Wave 1 adds 8
 * intent-level boards/cards tools that must all conform, must fail via the structured error
 * envelope (never a raw `err()` / bare `ok(data)` that lets an RPC `{error:...}` escape inside
 * ok:true), and — for every write / initiative-linked read — must carry the #785 confidential
 * visibility gate (ADR-0105) and, for writes, write_board authority, as a CONTRACT.
 *
 * This is a pure static check over supabase/functions/nucleo-mcp/index.ts (no network / no DB),
 * so it runs in every offline baseline. It is the anti-drift guard: a future edit that drops the
 * envelope, the gate, or the authority on any Wave-1 tool fails CI here.
 *
 * Cross-ref: EPIC #1383, wave0-artifacts/taxonomy.md §2.1 + §4, .claude/rules/mcp.md, SPEC-280.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const SRC = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

// The 8 Wave-1 semantic tools, in traffic order (taxonomy §2.1).
const W1_TOOLS = [
  'card_checklist',
  'card_write',
  'card_comment',
  'card_search',
  'card_get',
  'board_overview',
  'platform_context',
  'portfolio_report',
];

const WRITE_TOOLS = new Set(['card_checklist', 'card_write', 'card_comment']);
// Reads that address a specific board/card/initiative resource → must carry the #785 fail-fast gate.
const GATED_READS = new Set(['card_search', 'card_get', 'board_overview']);

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

test('W1: the semanticOk() envelope helper carries the audit superset (caller_member_id, gate_checked, resource_id)', () => {
  const s = SRC.indexOf('function semanticOk(args:');
  assert.ok(s !== -1, 'semanticOk() helper not found');
  // The #785 gate comment immediately follows the helper — slice the whole helper body.
  const e = SRC.indexOf('// #785 confidential-visibility gate', s);
  assert.ok(e !== -1, 'semanticOk() end sentinel not found');
  const h = SRC.slice(s, e);
  for (const field of ['ok: true', 'data:', 'summary:', 'warnings:', 'next_actions:', 'audit:']) {
    assert.ok(h.includes(field), `semanticOk envelope missing field marker: ${field}`);
  }
  for (const field of ['caller_member_id', 'gate_checked', 'resource_id', 'source_tools', 'pii_level', 'permission', 'semantic_domain', 'generated_at']) {
    assert.ok(h.includes(field), `semanticOk audit block missing superset field: ${field}`);
  }
});

test('W1: the #785 canSee() gate helper resolves via the live rls_can_see_* chain, fail-closed', () => {
  const helper = SRC.match(/async function canSee\(sb:[\s\S]*?\n\}/);
  assert.ok(helper, 'canSee() helper not found');
  const h = helper[0];
  for (const fn of ['rls_can_see_item', 'rls_can_see_board', 'rls_can_see_initiative']) {
    assert.ok(h.includes(fn), `canSee() missing chain member: ${fn}`);
  }
  // fail-closed: returns true ONLY when the RPC returned data === true and no error.
  assert.ok(/return\s+!error\s*&&\s*data\s*===\s*true/.test(h), 'canSee() must be fail-closed (!error && data === true)');
});

test('W1: all 8 boards/cards semantic tools are registered', () => {
  for (const t of W1_TOOLS) {
    assert.ok(BLOCKS[t], `Wave-1 tool not registered in registerSemanticTools: ${t}`);
  }
});

for (const tool of W1_TOOLS) {
  test(`W1[${tool}]: conforms to the stable envelope (semanticOk success + buildSemanticError failure)`, () => {
    const b = BLOCKS[tool];
    assert.ok(b.includes('semanticOk('), `${tool}: success path must return via semanticOk() (stable envelope)`);
    assert.ok(b.includes('buildSemanticError('), `${tool}: error/unauth path must return via buildSemanticError() (ok:false envelope)`);
    // The unauthenticated guard is present and structured.
    assert.ok(/code:\s*"unauthenticated"/.test(b), `${tool}: missing structured unauthenticated error`);
  });

  test(`W1[${tool}]: never leaks a raw error (no bare err() / no return ok(data) escape)`, () => {
    const b = BLOCKS[tool];
    // The raw-tool escape hatches must NOT appear — every exit goes through the envelope helpers.
    assert.ok(!/return\s+err\(/.test(b), `${tool}: uses raw err() — must use buildSemanticError() inside ok()`);
    // `return ok(<identifier or member-call>)` without an object literal / buildSemanticError is the
    // raw pattern that lets an RPC {error:...} escape inside ok:true. Allow ok(buildSemanticError(...)).
    const badOk = /return\s+ok\((?!\s*(?:buildSemanticError|\{))/.test(b);
    assert.ok(!badOk, `${tool}: return ok(...) must wrap an object literal or buildSemanticError(), not a raw payload`);
  });

  test(`W1[${tool}]: audit block sets an explicit gate_checked + caller_member_id`, () => {
    const b = BLOCKS[tool];
    assert.ok(b.includes('gate_checked:'), `${tool}: audit must state gate_checked`);
    assert.ok(b.includes('caller_member_id:'), `${tool}: audit must state caller_member_id`);
  });
}

for (const tool of WRITE_TOOLS) {
  test(`W1[${tool}]: WRITE carries the #785 confidential-visibility gate (canSee)`, () => {
    const b = BLOCKS[tool];
    // canSee(...) is the #785 fail-fast (literal "item"/"board" or a resolved gateKind variable).
    assert.ok(/await canSee\(sb,/.test(b), `${tool}: write must fail-fast on rls_can_see_item/board (#785)`);
  });
}

for (const tool of ['card_checklist', 'card_write']) {
  test(`W1[${tool}]: WRITE carries write_board authority`, () => {
    const b = BLOCKS[tool];
    assert.ok(/canV4\(sb,\s*member\.id,\s*"write_board"/.test(b), `${tool}: must gate on canV4(write_board)`);
  });
}

for (const tool of GATED_READS) {
  test(`W1[${tool}]: initiative-linked READ carries the #785 gate (canSee) on the resource path`, () => {
    const b = BLOCKS[tool];
    assert.ok(b.includes('canSee(sb,'), `${tool}: resource-addressed read must fail-fast via canSee() (#785)`);
  });
}

test('W1[portfolio_report]: gated to manage_member OR view_partner (admin/sponsor)', () => {
  const b = BLOCKS['portfolio_report'];
  assert.ok(/canV4\(sb,\s*member\.id,\s*"manage_member"/.test(b), 'portfolio_report must check manage_member');
  assert.ok(/canV4\(sb,\s*member\.id,\s*"view_partner"/.test(b), 'portfolio_report must fall back to view_partner');
});

test('W1[card_write]: destructive verbs (archive/delete) honor the ADR-0018 confirm gate', () => {
  const b = BLOCKS['card_write'];
  assert.ok(/params\.confirm\s*!==\s*true/.test(b), 'card_write must return a preview unless confirm=true for destructive verbs');
  assert.ok(b.includes('preview: true'), 'card_write preview payload must be marked preview:true');
});

test('W1: /semantic health count is DERIVED (not a literal) — #1392', () => {
  // #1392 retired the hardcoded literal; /health now derives from the registrar. The authoritative
  // count (registerSemanticTools) is asserted in semantic-envelope-w6b (the surface is frozen at 52).
  assert.match(SRC, /"\/semantic":\s*\{[^}]*tools:\s*SEMANTIC_TOOL_COUNT\b/, '/semantic health must derive from SEMANTIC_TOOL_COUNT');
});
