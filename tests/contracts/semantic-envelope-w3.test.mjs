/**
 * #1383 Wave 3 — Semantic envelope contract guard (events / attendance / meetings).
 *
 * Wave 3 adds 6 intent-level tools over the event domain. Beyond the stable envelope
 * { ok, data, summary, warnings, next_actions, audit }, this wave's whole point is that the
 * AUTHORITY CONTRACT is code, not prose:
 *
 *   - The Wave-0 CONFIRMED finding was a resourceless `can_by_member(caller, 'manage_event')`:
 *     any manage_event holder could write to EVERY initiative's events. Migration 444 scoped
 *     meeting_close / register_attendance_batch / mark_member_excused (+ _can_manage_event, which
 *     covers create_meeting_notes → upsert_event_minutes); migration 455 extended the same helper
 *     (`_manage_event_scope_ok`) to create_action_item / register_decision / resolve_action_item /
 *     update_event_instance / drop_event_instance. These tools BAKE that scoping at the semantic
 *     layer via eventWriteGate() so a future edit cannot silently widen it back.
 *   - attendance_report ADDS the #785 confidential gate the underlying
 *     get_initiative_attendance_grid RPC does not have.
 *   - get_agenda_smart is deliberately NOT absorbed (retired — unassigned-record bug).
 *
 * Pure static check over supabase/functions/nucleo-mcp/index.ts (no network / no DB) — runs in every
 * offline baseline. A future edit that drops the envelope or a gate fails CI here.
 *
 * Cross-ref: EPIC #1383, wave0-artifacts/taxonomy.md §2.3 + §4, .claude/rules/mcp.md, SPEC-280.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const SRC = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

// The 6 Wave-3 semantic tools, in traffic order (taxonomy §2.3).
const W3_TOOLS = [
  'event_search',
  'event_write',
  'attendance_record',
  'attendance_report',
  'meeting_minutes',
  'meeting_actions',
];

// Tools that perform event-domain writes → must route authority through eventWriteGate().
const EVENT_WRITE_TOOLS = new Set(['event_write', 'attendance_record', 'meeting_minutes', 'meeting_actions']);
// Tools that expose an action discriminator.
const ACTION_TOOLS = new Set(['event_write', 'attendance_record', 'meeting_minutes', 'meeting_actions']);

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

test('W3: eventScope() resolves an event to its initiative through the caller-scoped client', () => {
  const helper = SRC.match(/async function eventScope\(sb: Sb[\s\S]*?\n\}/);
  assert.ok(helper, 'eventScope() helper not found');
  assert.ok(/from\("events"\)/.test(helper[0]), 'eventScope() must read events (RLS applies for the caller)');
  assert.ok(/initiative_id/.test(helper[0]), 'eventScope() must surface initiative_id (the gate resource)');
});

test('W3: eventWriteGate() enforces #785 THEN resource-scoped manage_event (mirrors _manage_event_scope_ok)', () => {
  const helper = SRC.match(/async function eventWriteGate\([\s\S]*?\n\}/);
  assert.ok(helper, 'eventWriteGate() helper not found');
  const h = helper[0];
  assert.ok(/canSee\(sb,\s*"initiative",\s*initiativeId\)/.test(h), 'eventWriteGate must apply the #785 gate on the initiative');
  assert.ok(/canV4\(sb,\s*memberId,\s*"manage_event",\s*"initiative",\s*initiativeId\)/.test(h),
    'eventWriteGate MUST pass the initiative as p_resource_id — a resourceless can(manage_event) is the Wave-0 bypass');
  assert.ok(/canV4\(sb,\s*memberId,\s*"manage_event"\)/.test(h),
    'eventWriteGate must fall back to the org-wide check ONLY for events with no initiative');
});

test('W3: all 6 events/attendance/meetings semantic tools are registered', () => {
  for (const t of W3_TOOLS) {
    assert.ok(BLOCKS[t], `Wave-3 tool not registered in registerSemanticTools: ${t}`);
  }
});

for (const tool of W3_TOOLS) {
  test(`W3[${tool}]: conforms to the stable envelope (semanticOk success + buildSemanticError failure)`, () => {
    const b = BLOCKS[tool];
    assert.ok(b.includes('semanticOk('), `${tool}: success path must return via semanticOk() (stable envelope)`);
    assert.ok(b.includes('buildSemanticError('), `${tool}: error/unauth path must return via buildSemanticError() (ok:false envelope)`);
    assert.ok(/code:\s*"unauthenticated"/.test(b), `${tool}: missing structured unauthenticated error`);
  });

  test(`W3[${tool}]: never leaks a raw error (no bare err() / no return ok(data) escape)`, () => {
    const b = BLOCKS[tool];
    assert.ok(!/return\s+err\(/.test(b), `${tool}: uses raw err() — must use buildSemanticError() inside ok()`);
    const badOk = /return\s+ok\((?!\s*(?:buildSemanticError|\{))/.test(b);
    assert.ok(!badOk, `${tool}: return ok(...) must wrap an object literal or buildSemanticError(), not a raw payload`);
  });

  test(`W3[${tool}]: audit block sets an explicit gate_checked + caller_member_id + pii_level`, () => {
    const b = BLOCKS[tool];
    assert.ok(b.includes('gate_checked:'), `${tool}: audit must state gate_checked`);
    assert.ok(b.includes('caller_member_id:'), `${tool}: audit must state caller_member_id`);
    assert.ok(b.includes('pii_level:'), `${tool}: audit must state pii_level`);
  });
}

for (const tool of ACTION_TOOLS) {
  test(`W3[${tool}]: declares an action discriminator`, () => {
    const b = BLOCKS[tool];
    assert.ok(/action:\s*z\.enum\(/.test(b), `${tool}: must expose an action enum`);
  });
}

for (const tool of EVENT_WRITE_TOOLS) {
  test(`W3[${tool}]: routes event-domain authority through eventWriteGate() (resource-scoped manage_event)`, () => {
    const b = BLOCKS[tool];
    assert.ok(/await eventWriteGate\(sb,\s*member\.id/.test(b),
      `${tool}: must gate writes via eventWriteGate() — do NOT re-derive a resourceless can(manage_event)`);
  });

  test(`W3[${tool}]: never calls a resourceless canV4(manage_event) inline (the Wave-0 bypass shape)`, () => {
    const b = BLOCKS[tool];
    assert.ok(!/canV4\(sb,\s*member\.id,\s*"manage_event"\)\s*[);]/.test(b),
      `${tool}: inline resourceless canV4(manage_event) — scope it to the event's initiative via eventWriteGate()`);
  });
}

test('W3[event_write]: drop is confirm-gated (ADR-0018) and returns a preview first', () => {
  const b = BLOCKS['event_write'];
  assert.ok(/params\.confirm\s*!==\s*true/.test(b), 'event_write drop must require confirm=true to execute');
  assert.ok(/preview:\s*true/.test(b), 'event_write drop must return a preview when not confirmed');
  assert.ok(b.includes('drop_event_instance'), 'event_write must absorb drop_event_instance');
});

test('W3[event_write]: absorbs create/update/drop of event instances', () => {
  const b = BLOCKS['event_write'];
  for (const rpc of ['create_event', 'update_event_instance', 'drop_event_instance']) {
    assert.ok(b.includes(rpc), `event_write must dispatch ${rpc}`);
  }
});

test('W3[attendance_record]: absorbs the #3 tool (register_attendance_batch) and records registered_by (#1322)', () => {
  const b = BLOCKS['attendance_record'];
  assert.ok(b.includes('register_attendance_batch'), 'attendance_record must dispatch register_attendance_batch');
  assert.ok(/p_registered_by:\s*member\.id/.test(b),
    'attendance_record must pass registered_by — self-vs-batch attribution comes from registered_by/marked_by, not checked_in_at (#1322)');
  for (const rpc of ['mark_member_excused', 'bulk_mark_excused', 'register_event_showcase']) {
    assert.ok(b.includes(rpc), `attendance_record must dispatch ${rpc}`);
  }
});

test('W3[attendance_report]: ADDS the #785 gate the attendance-grid RPC lacks, and gates cross-member reads', () => {
  const b = BLOCKS['attendance_report'];
  assert.ok(/await canSee\(sb,\s*"initiative"/.test(b),
    'attendance_report must fail-fast on rls_can_see_initiative — get_initiative_attendance_grid has no #785 gate of its own');
  assert.ok(/canV4\(sb,\s*member\.id,\s*"view_internal_analytics"\)/.test(b),
    'attendance_report cross-member/cross-cohort scopes must require view_internal_analytics');
});

test('W3[meeting_minutes]: write/close carry the scoped gate; get_agenda_smart stays retired', () => {
  const b = BLOCKS['meeting_minutes'];
  assert.ok(b.includes('upsert_event_minutes'), 'meeting_minutes action=write must dispatch upsert_event_minutes');
  assert.ok(b.includes('meeting_close'), 'meeting_minutes action=close must dispatch meeting_close');
  assert.ok(b.includes('get_meeting_preparation'), 'meeting_minutes action=prepare must dispatch get_meeting_preparation');
  assert.ok(!b.includes('get_agenda_smart('), 'get_agenda_smart is retired (unassigned-record bug) — it must NOT be absorbed');
});

test('W3[meeting_actions]: carry-forward target is gated independently (mirrors migration 455)', () => {
  const b = BLOCKS['meeting_actions'];
  assert.ok(b.includes('carry_to_event_id'), 'meeting_actions resolve must support carry_to_event_id');
  const carryGate = /const tgt = await eventScope\(sb,\s*params\.carry_to_event_id\)[\s\S]{0,400}?await eventWriteGate\(sb,\s*member\.id,\s*tgt\.initiative_id\)/;
  assert.ok(carryGate.test(b),
    'meeting_actions must gate the carry-forward TARGET event too — carrying into another initiative is the same cross-initiative write');
});

test('W3[meeting_actions]: convert_to_card additionally requires write_board + board #785', () => {
  const b = BLOCKS['meeting_actions'];
  assert.ok(/canV4\(sb,\s*member\.id,\s*"write_board"\)/.test(b), 'convert_to_card must require write_board');
  assert.ok(/canSee\(sb,\s*"board",\s*params\.board_id\)/.test(b), 'convert_to_card must apply the #785 gate on the destination board');
});

test('W3[event_search]: read-only — absorbs the 4 event readers, no write RPC', () => {
  const b = BLOCKS['event_search'];
  for (const rpc of ['get_event_detail', 'get_near_events', 'list_initiative_events']) {
    assert.ok(b.includes(rpc), `event_search must dispatch ${rpc}`);
  }
  assert.ok(!/eventWriteGate\(/.test(b), 'event_search is read-only — it must not carry a write gate');
});

test('W3: /semantic health surface advertises 27 tools (4 bridge + 8 W1 + 9 W2 + 6 W3)', () => {
  const health = SRC.match(/"\/semantic":\s*\{[^}]*tools:\s*(\d+)/);
  assert.ok(health, '/semantic health entry not found');
  assert.equal(Number(health[1]), 27, '/semantic health tools count must be 27 after Wave 3');
});
