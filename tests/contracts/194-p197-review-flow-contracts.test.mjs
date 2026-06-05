/**
 * Contract: #194 — contract tests for the p197 structured curation review flow.
 *
 * The p197 FSM (board_items.curation_status): draft → peer_review → leader_review →
 * curation_pending → published. Five RPCs/triggers drive it and had ZERO contract
 * coverage before this file. Each is asserted against the LATEST CREATE FUNCTION
 * capture across all migrations (so later fix-migrations are honoured), plus a
 * DB-gated existence+auth-gate probe.
 *
 *   complete_peer_review   (20260715 — H4 gate fix)
 *   complete_leader_review (20260716 — H1/H2 notify + peer reset)
 *   submit_for_curation    (20260427233000 — adr-0041)
 *   submit_curation_review (20260805000113 — #192 per-round)
 *   trg_auto_submit_curation_on_reviewer_assign (20260718 — H5 null guard)
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGDIR = resolve(ROOT, 'supabase/migrations');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const client = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const FILES = readdirSync(MIGDIR).filter((f) => f.endsWith('.sql')).sort();

/** Body text of the LATEST (highest-version migration) CREATE OR REPLACE FUNCTION public.<name>. */
function latestFunctionBody(name) {
  const createRe = new RegExp(`CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${name}\\s*\\(`, 'i');
  let chosen = '';
  for (const f of FILES) {
    const sql = readFileSync(join(MIGDIR, f), 'utf8');
    if (createRe.test(sql)) chosen = sql;
  }
  if (!chosen) return '';
  const m = createRe.exec(chosen);
  const tail = chosen.slice(m.index);
  const dq = /\bAS\s+(\$[a-zA-Z_]*\$)/.exec(tail);
  if (!dq) return tail;
  const tag = dq[1];
  const start = tail.indexOf(tag, dq.index) + tag.length;
  const end = tail.indexOf(tag, start);
  return end > start ? tail.slice(start, end) : tail.slice(start);
}

// ── complete_peer_review ───────────────────────────────────────────────────────────
test('#194 complete_peer_review: status guard + waiver + leader_review transition + 4-arm gate', () => {
  const b = latestFunctionBody('complete_peer_review');
  assert.ok(b, 'complete_peer_review body located');
  assert.match(b, /curation_status NOT IN \('draft', 'peer_review'\)/, 'only from draft/peer_review');
  assert.match(b, /p_waived AND \(p_waiver_reason IS NULL OR length\(trim\(p_waiver_reason\)\) = 0\)/, 'waiver needs a reason');
  assert.match(b, /curation_status = 'leader_review'/, 'transitions to leader_review');
  assert.match(b, /assignee_id = v_caller\.id/, 'gate arm: assignee');
  assert.match(b, /role IN \('author', 'contributor'\)/, 'gate arm: assignments author/contributor');
  assert.match(b, /e\.role = 'leader'/, 'gate arm: initiative leader');
  assert.match(b, /can_by_member\(v_caller\.id, 'participate_in_governance_review'\)/, 'gate arm: governance reviewer');
  assert.match(b, /'peer_review_completed'/, 'distinct lifecycle action (B1 fix)');
});

// ── complete_leader_review ─────────────────────────────────────────────────────────
test('#194 complete_leader_review: decision enum + transitions + peer-reset on return + gate', () => {
  const b = latestFunctionBody('complete_leader_review');
  assert.ok(b, 'complete_leader_review body located');
  assert.match(b, /p_decision NOT IN \('approved', 'returned', 'waived'\)/, 'decision enum');
  assert.match(b, /curation_status NOT IN \('leader_review', 'draft'\)/, 'only from leader_review/draft');
  assert.match(b, /p_decision IN \('approved', 'waived'\)[\s\S]*?curation_status = 'curation_pending'/, 'approved/waived → curation_pending');
  assert.match(b, /p_decision = 'returned'[\s\S]*?curation_status = 'draft'/, 'returned → draft');
  // H2 fix: returning resets peer-review state so a waived item must redo peer review
  assert.match(b, /peer_review_completed_at = NULL[\s\S]*?peer_review_waived = false/, 'return resets peer-review state (H2)');
  assert.match(b, /create_notification\([\s\S]*?'board_item'/, 'returns notify assignee with board_item source_type (H1)');
  assert.match(b, /can_by_member\(v_caller\.id, 'participate_in_governance_review'\)/, 'gov-review gate arm');
});

// ── submit_for_curation ────────────────────────────────────────────────────────────
test('#194 submit_for_curation: gate + status guard + SLA + curation_pending', () => {
  const b = latestFunctionBody('submit_for_curation');
  assert.ok(b, 'submit_for_curation body located');
  assert.match(b, /can_by_member\(v_caller\.id, 'participate_in_governance_review'\)[\s\S]{0,120}operational_role = 'tribe_leader'/, 'gate: gov-review OR tribe_leader');
  assert.match(b, /curation_status NOT IN \('leader_review', 'draft'\)/, 'only from leader_review/draft');
  assert.match(b, /curation_status = 'curation_pending'/, '→ curation_pending');
  assert.match(b, /curation_due_at = now\(\) \+ make_interval\(days =>/, 'sets SLA from board_sla_config');
  assert.match(b, /'submitted_for_curation'/, 'lifecycle action');
});

// ── submit_curation_review (with #192 per-round) ───────────────────────────────────
test('#194 submit_curation_review: gov-review gate + decisions + rubric + per-round consensus', () => {
  const b = latestFunctionBody('submit_curation_review');
  assert.ok(b, 'submit_curation_review body located');
  assert.match(b, /can_by_member\(v_caller\.id, 'participate_in_governance_review'\)/, 'gov-review gate');
  assert.match(b, /p_decision NOT IN \('approved', 'returned_for_revision', 'rejected'\)/, 'decision enum');
  assert.match(b, /curation_status <> 'curation_pending'/, 'only from curation_pending');
  assert.match(b, /'clarity','originality','adherence','relevance','ethics'/, 'rubric criteria');
  assert.match(b, /must be 1-5/, 'rubric 1-5 validation');
  assert.match(b, /publish_board_item_from_curation/, 'approved quorum → publish');
  // #192 contract: per-round distinct-curator consensus
  assert.match(b, /count\(DISTINCT curator_id\)[\s\S]*?review_round = v_current_round/, 'per-round distinct-curator consensus');
});

// ── auto-submit trigger ────────────────────────────────────────────────────────────
test('#194 trg_auto_submit_curation_on_reviewer_assign: role + done + draft → curation_pending', () => {
  const b = latestFunctionBody('trg_auto_submit_curation_on_reviewer_assign');
  assert.ok(b, 'auto-submit trigger body located');
  assert.match(b, /NEW\.role IS DISTINCT FROM 'curation_reviewer'/, 'only reacts to curation_reviewer assignment');
  assert.match(b, /v_item\.status = 'done' AND v_item\.curation_status = 'draft'/, 'only completed + never-submitted cards');
  assert.match(b, /curation_status = 'curation_pending'/, '→ curation_pending');
  assert.match(b, /COALESCE\(NEW\.assigned_by, v_item\.assignee_id\)/, 'H5 null guard for bulk/system inserts');
});

// ── DB-GATED: each RPC exists live and fail-closes on an unauthenticated caller ─────
const RPC_PROBES = [
  ['complete_peer_review', { p_item_id: '00000000-0000-0000-0000-000000000000' }],
  ['complete_leader_review', { p_item_id: '00000000-0000-0000-0000-000000000000', p_decision: 'approved' }],
  ['submit_for_curation', { p_item_id: '00000000-0000-0000-0000-000000000000' }],
  ['submit_curation_review', { p_item_id: '00000000-0000-0000-0000-000000000000', p_decision: 'approved' }],
];
for (const [name, args] of RPC_PROBES) {
  test(`#194 db: ${name} exists and fail-closes for an unauthenticated caller`,
    { skip: dbGated ? false : skipMsg }, async () => {
      const sb = client();
      const { error } = await sb.rpc(name, args);
      assert.ok(error, `${name} must raise for a service-role (auth.uid()=NULL) caller`);
      assert.match(String(error.message || ''),
        /Not authenticated|Requires|authority|permission/i,
        `${name} must hit its auth gate, got: ${JSON.stringify(error)}`);
    });
}
