/**
 * Issue #906 — finalize_decisions surfaces the approve-authority error UP FRONT.
 *
 * A committee-lead-WITHOUT-manage_platform used to be able to submit 'approved'
 * decisions, have the inner approve_selection_application gate roll each one back
 * silently, and receive {approved:0} with a success-looking envelope (deceptive
 * UX). This static contract verifies that the canonical (latest) finalize_decisions
 * body now:
 *   1. computes manage_platform once at the outer gate (v_has_manage_platform);
 *   2. returns an explicit `approve_requires_manage_platform` authority error up
 *      front when the batch contains a real 'approved' decision (convert_to empty)
 *      and the caller lacks manage_platform;
 *   3. still admits committee leads for the dual outer gate (reject/waitlist/convert).
 *
 * Reads static migration SQL only — no DB env required. Mirrors the
 * canonical-approval-orchestration / selection static-contract suites.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function loadAllSQL() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => readFileSync(join(MIGRATIONS_DIR, f), 'utf8')).join('\n');
}

const allSQL = loadAllSQL();

function findLatestFunctionBody(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi'
  );
  const matches = [...allSQL.matchAll(regex)];
  return matches.length > 0 ? matches[matches.length - 1][2] : null;
}

const body = findLatestFunctionBody('finalize_decisions');

test('finalize_decisions: canonical body is captured in a migration', () => {
  assert.ok(body, 'expected a CREATE OR REPLACE FUNCTION finalize_decisions capture');
});

test('finalize_decisions: computes manage_platform once at the outer gate', () => {
  assert.match(body, /v_has_manage_platform\s+boolean/, 'declares v_has_manage_platform');
  assert.match(
    body,
    /v_has_manage_platform\s*:=\s*public\.can_by_member\(\s*v_caller\.id\s*,\s*'manage_platform'/,
    'assigns v_has_manage_platform from can_by_member',
  );
});

test('finalize_decisions: blocks approve without manage_platform UP FRONT (#906)', () => {
  // The #906 gate: an EXISTS over the decisions batch for a real 'approved'
  // (convert_to empty) combined with NOT v_has_manage_platform.
  assert.match(
    body,
    /NOT\s+v_has_manage_platform\s+AND\s+EXISTS\s*\(/i,
    'guards on NOT v_has_manage_platform AND EXISTS(...)',
  );
  assert.match(
    body,
    /jsonb_array_elements\(\s*p_decisions\s*\)[\s\S]*?->>'decision'\s*=\s*'approved'/i,
    'scans the batch for an approved decision',
  );
  assert.match(
    body,
    /coalesce\(\s*d->>'convert_to'\s*,\s*''\s*\)\s*=\s*''/i,
    'excludes conversion rows (non-empty convert_to) from the approve gate',
  );
  assert.match(
    body,
    /approve_requires_manage_platform/,
    'returns the explicit approve_requires_manage_platform error code',
  );
});

test('finalize_decisions: the approve gate returns BEFORE the decision loop (atomic, no silent no-op)', () => {
  const gateIdx = body.indexOf('approve_requires_manage_platform');
  const loopIdx = body.search(/FOR\s+v_decision\s+IN\s+SELECT/i);
  assert.ok(gateIdx > -1 && loopIdx > -1, 'both the gate and the loop are present');
  assert.ok(
    gateIdx < loopIdx,
    'the #906 authority gate must short-circuit before the per-decision loop',
  );
});

test('finalize_decisions: still admits committee lead OR manage_platform at the outer gate', () => {
  assert.match(
    body,
    /v_committee\s+IS\s+NULL\s+AND\s+NOT\s+v_has_manage_platform/i,
    'outer dual gate preserved (committee lead OR platform admin)',
  );
});
