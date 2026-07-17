/**
 * #1383 Wave 4 — Semantic envelope contract guard (selection / evaluation).
 *
 * Wave 4 adds 6 intent-level tools over the selection domain. Beyond the stable envelope
 * { ok, data, summary, warnings, next_actions, audit }, this wave's authority model is:
 *
 *   - Every absorbed raw RPC self-gates INTERNALLY (audited live 2026-07-17): reads on
 *     candidate data require view_internal_analytics / manage_member / committee-of-cycle
 *     PLUS ADR-0109 conflict-of-interest recusal; writes require manage_platform (GP) /
 *     manage_member / promote / committee-scoping. The semantic layer passes through and
 *     surfaces the RPC's own {error}/RAISE in the ok:false envelope. Write tools ADD a
 *     proactive canV4() fail-fast mirroring the RPC gate.
 *   - There is NO resourceless-can() shape here (the Wave-0/W3 bypass class). The selection
 *     RPCs were audited and are resource/committee-scoped; migration 20260805000458 widened
 *     get_application_interviews from GP-only to committee (+ COI) and revoked an anon
 *     EXECUTE drift on recalculate_cycle_rankings.
 *   - Destructive decisions (selection_decide approve / recalc_rankings) are confirm-gated
 *     (ADR-0018) and return a preview first.
 *   - Deliberately NOT surfaced semantically (stay raw): compute_application_scores (dormant
 *     service-role helper), generate_interview_briefing (inline-Haiku, view_pii),
 *     capture_visitor_lead (public anon site entry, consent-gated).
 *
 * Pure static check over supabase/functions/nucleo-mcp/index.ts (no network / no DB) — runs in every
 * offline baseline. A future edit that drops the envelope, a gate, or the confirm-gate fails CI here.
 *
 * Cross-ref: EPIC #1383, wave0-artifacts/taxonomy.md §2.4 + §4, .claude/rules/mcp.md, SPEC-280.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const SRC = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

// The 6 Wave-4 semantic tools, in traffic order (taxonomy §2.4).
const W4_TOOLS = [
  'selection_dashboard',
  'application_get',
  'evaluation_submit',
  'interview_manage',
  'selection_decide',
  'visitor_leads',
];

// Tools that expose an action/mode/scope discriminator.
const DISCRIMINATOR = {
  selection_dashboard: 'scope',
  application_get: 'scope',
  evaluation_submit: 'mode',
  interview_manage: 'action',
  selection_decide: 'action',
  visitor_leads: 'action',
};

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

test('W4: all 6 selection/evaluation semantic tools are registered', () => {
  for (const t of W4_TOOLS) {
    assert.ok(BLOCKS[t], `Wave-4 tool not registered in registerSemanticTools: ${t}`);
  }
});

for (const tool of W4_TOOLS) {
  test(`W4[${tool}]: conforms to the stable envelope (semanticOk success + buildSemanticError failure)`, () => {
    const b = BLOCKS[tool];
    assert.ok(b.includes('semanticOk('), `${tool}: success path must return via semanticOk() (stable envelope)`);
    assert.ok(b.includes('buildSemanticError('), `${tool}: error/unauth path must return via buildSemanticError() (ok:false envelope)`);
    assert.ok(/code:\s*"unauthenticated"/.test(b), `${tool}: missing structured unauthenticated error`);
  });

  test(`W4[${tool}]: never leaks a raw error (no bare err() / no return ok(data) escape)`, () => {
    const b = BLOCKS[tool];
    assert.ok(!/return\s+err\(/.test(b), `${tool}: uses raw err() — must use buildSemanticError() inside ok()`);
    const badOk = /return\s+ok\((?!\s*(?:buildSemanticError|\{))/.test(b);
    assert.ok(!badOk, `${tool}: return ok(...) must wrap an object literal or buildSemanticError(), not a raw payload`);
  });

  test(`W4[${tool}]: audit block sets an explicit gate_checked + caller_member_id + pii_level`, () => {
    const b = BLOCKS[tool];
    assert.ok(b.includes('gate_checked:'), `${tool}: audit must state gate_checked`);
    assert.ok(b.includes('caller_member_id:'), `${tool}: audit must state caller_member_id`);
    assert.ok(b.includes('pii_level:'), `${tool}: audit must state pii_level`);
  });

  test(`W4[${tool}]: declares its ${DISCRIMINATOR[tool]} discriminator as a Zod enum`, () => {
    const b = BLOCKS[tool];
    assert.ok(new RegExp(`${DISCRIMINATOR[tool]}:\\s*z\\.enum\\(`).test(b), `${tool}: must expose a ${DISCRIMINATOR[tool]} enum`);
  });
}

// Write tools mirror each RPC's internal gate with a proactive canV4() fail-fast.
test('W4[selection_decide]: proactively gates each action via canV4 (manage_platform/manage_member/promote)', () => {
  const b = BLOCKS['selection_decide'];
  assert.ok(/canV4\(sb,\s*member\.id,\s*need\)/.test(b), 'selection_decide must fail-fast via canV4(need) before dispatch');
  for (const perm of ['manage_platform', 'manage_member', 'promote']) {
    assert.ok(b.includes(perm), `selection_decide GATE map must cover ${perm}`);
  }
});

test('W4[selection_decide]: approve + recalc_rankings are confirm-gated (ADR-0018) with a preview', () => {
  const b = BLOCKS['selection_decide'];
  assert.ok(/params\.confirm\s*!==\s*true/.test(b), 'selection_decide must require confirm=true for destructive actions');
  assert.ok(/preview:\s*true/.test(b), 'selection_decide must return a preview when not confirmed');
  for (const rpc of ['approve_selection_application', 'recalculate_cycle_rankings']) {
    assert.ok(b.includes(rpc), `selection_decide must dispatch ${rpc}`);
  }
});

test('W4[selection_decide]: does NOT surface the dormant compute_application_scores helper', () => {
  const b = BLOCKS['selection_decide'];
  assert.ok(!/sb\.rpc\(\s*"compute_application_scores"/.test(b),
    'compute_application_scores is a service-role-only helper (0 MCP calls) — must not be dispatched semantically');
});

test('W4[visitor_leads]: gates on manage_member (ghosts=manage_platform); never surfaces public capture', () => {
  const b = BLOCKS['visitor_leads'];
  assert.ok(/canV4\(sb,\s*member\.id,\s*need\)/.test(b), 'visitor_leads must fail-fast via canV4(need)');
  assert.ok(/"manage_platform"\s*:\s*"manage_member"/.test(b) || /ghosts.*manage_platform/.test(b),
    'visitor_leads must require manage_platform for ghosts and manage_member otherwise');
  assert.ok(!/sb\.rpc\(\s*"capture_visitor_lead"/.test(b),
    'capture_visitor_lead is the public anon site entry — must stay raw, not surfaced in the operator tool');
});

test('W4[application_get]: absorbs the widened get_application_interviews (committee-visible since mig 458)', () => {
  const b = BLOCKS['application_get'];
  for (const rpc of ['get_application_score_breakdown', 'get_application_interviews', 'get_application_gate_attempts']) {
    assert.ok(b.includes(rpc), `application_get must dispatch ${rpc}`);
  }
});

test('W4[evaluation_submit]: absorbs the evaluator loop incl. the #5 tool submit_evaluation', () => {
  const b = BLOCKS['evaluation_submit'];
  for (const rpc of ['get_my_pending_evaluations', 'get_evaluation_form', 'submit_evaluation', 'submit_interview_scores', 'get_evaluation_results']) {
    assert.ok(b.includes(rpc), `evaluation_submit must dispatch ${rpc}`);
  }
});

test('W4[selection_dashboard]: read-only — absorbs the cycle readers, no write RPC', () => {
  const b = BLOCKS['selection_dashboard'];
  for (const rpc of ['get_selection_dashboard', 'get_selection_rankings', 'get_selection_health', 'get_selection_committee']) {
    assert.ok(b.includes(rpc), `selection_dashboard must dispatch ${rpc}`);
  }
  assert.ok(!/canV4\(sb,\s*member\.id,\s*"manage_/.test(b), 'selection_dashboard is read-only — no manage_* write gate');
});

test('W4[interview_manage]: keeps generate_interview_briefing raw (inline-Haiku, view_pii)', () => {
  const b = BLOCKS['interview_manage'];
  assert.ok(!/sb\.rpc\(\s*"generate_interview_briefing"/.test(b),
    'generate_interview_briefing is an inline-AI raw tool — it has no RPC to dispatch');
  for (const rpc of ['schedule_interview', 'mark_interview_status', 'selection_rescue_stuck_interview']) {
    assert.ok(b.includes(rpc), `interview_manage must dispatch ${rpc}`);
  }
});

test('W4: /semantic health surface advertises 52 tools (4 bridge + 8 W1 + 9 W2 + 6 W3 + 6 W4 + 7 W5 + 7 W6a)', () => {
  const health = SRC.match(/"\/semantic":\s*\{[^}]*tools:\s*(\d+)/);
  assert.ok(health, '/semantic health entry not found');
  assert.equal(Number(health[1]), 52, '/semantic health tools count must be 52 after Wave 6a');
});

test('W4: nucleo-ia-semantic version bumped to 0.9.0 (Wave 6a)', () => {
  assert.match(SRC, /new McpServer\(\s*\{\s*name:\s*"nucleo-ia-semantic"\s*,\s*version:\s*"0\.10\.0"\s*\}\s*\)/,
    '/semantic McpServer must be v0.9.0 at Wave 6a');
});
