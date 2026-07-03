/**
 * Contract: p277 / #419 (ADR-0100) metric 7 — champions ledger↔projection PARITY invariant (#424 item 2).
 *
 * PM-ratified (2026-05-31): `champions_awarded` is the CANONICAL source of truth for champion recognition
 * (read by get_champions_ranking, profile history, the admin list); the `gamification_points` rows with
 * category='champion_'||surface are a DERIVED PROJECTION (read by get_tribe_gamification.champions_points via
 * the canonical gr.pillar='champions' JOIN + the leaderboard chip). award_champion DUAL-WRITES both;
 * revoke_champion UPDATEs the ledger to 'revoked' + (since #1087 Onda 3, mig 20260805000333)
 * APPEND-ONLY REVERSES the projection: inserts an estorno row (negative points, same ref_id)
 * instead of deleting — the audit trail survives and SUM nets to zero. There was no invariant
 * guaranteeing they stay in sync — this test is that guarantee.
 *
 * THE INVARIANT (4 directions, all must be 0 live — 3+4 REPINNED for append-only, #1087 Onda 3):
 *   1. every champions_awarded status='active' row has >=1 matching projection row
 *      (gamification_points.ref_id = champion_id AND category = 'champion_'||surface);
 *   2. every active ledger row has EXACTLY ONE champion_% projection row (no duplicates —
 *      estorno rows only ever exist for revoked champions);
 *   3. no champion_% projection row is orphaned (points to a NON-EXISTENT ledger row; rows
 *      referencing a REVOKED champion are legitimate under append-only: original + estorno);
 *   4. every status='revoked' ledger row has a NET-ZERO projection (SUM(points)=0 across its
 *      champion_% rows — the estorno exactly absorbs the award; zero rows also nets zero).
 *
 * #424 item 1 (the award-path operational unblock) is ALREADY SHIPPED — see
 * p277-champion-award-leader-access.test.mjs (scoped `champion.award` gate; backend already authorizes
 * volunteer/leader@initiative via can_by_member). This test closes #424 item 2 (the structural half).
 *
 * Static checks lock the dual-write (award) + append-only reversal (revoke) so the invariant cannot
 * silently rot. Behavioural checks (DB-gated) assert the live ledger/projection are in parity.
 *
 * Cross-ref: SPEC_419_M4_M8_CANONICAL_METRICS.md §M7; ADR-0100 §2.2 champions row; issue #424;
 * #1087 Onda 3 (append-only repin) + tests/contracts/1087-wave3-ledger-append-only.test.mjs.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const AWARD_MIG = resolve(ROOT, 'supabase/migrations/20260675600000_p171_8_award_champion_criteria_validation.sql');
// #1087 Onda 3: revoke_champion's latest capture moved to the append-only migration
// (the p161 phase2 DELETE version is superseded history).
const REVOKE_MIG = resolve(ROOT, 'supabase/migrations/20260805000333_1087_wave3_ledger_append_only.sql');

const award = existsSync(AWARD_MIG) ? readFileSync(AWARD_MIG, 'utf8') : '';
const revoke = existsSync(REVOKE_MIG) ? readFileSync(REVOKE_MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC: the dual-write (award) ──────────────────────────────────────────────
test('M7 static: award_champion DUAL-WRITES the ledger + the projection', () => {
  assert.ok(award.length > 0, 'award_champion migration exists');
  // ledger insert returning the champion id
  assert.match(award, /INSERT INTO champions_awarded[\s\S]*?RETURNING id INTO v_champion_id/,
    'inserts the canonical ledger row and captures its id');
  // projection insert keyed on that id, category = 'champion_' || surface
  assert.match(award, /INSERT INTO gamification_points[\s\S]*?'champion_' \|\| p_surface[\s\S]*?v_champion_id/,
    'dual-writes a gamification_points projection (category champion_<surface>, ref_id = champion id)');
});

// ── STATIC: the append-only reversal (revoke) ───────────────────────────────────
test('M7 static: revoke_champion marks the ledger revoked + APPEND-ONLY reverses the projection', () => {
  assert.ok(revoke.length > 0, 'revoke_champion migration exists');
  assert.match(revoke, /UPDATE champions_awarded SET[\s\S]*?status = 'revoked'/,
    'marks the ledger row revoked (does not delete it — keeps the audit trail)');
  assert.match(revoke, /INSERT INTO gamification_points[\s\S]*?'Estorno \(champion revogado\): ' \|\| p_reason, p_champion_id, v_caller\.id/,
    'inserts an estorno projection row (negative points, same ref_id, granted_by = revoker)');
  assert.doesNotMatch(revoke, /DELETE\s+FROM\s+(public\.)?gamification_points/i,
    'never deletes projection rows (ledger is append-only — #1087 Onda 3)');
});

// ── BEHAVIOURAL (DB-gated): the live invariant holds (all 4 directions = 0) ──────
test('M7 behavioural: ledger↔projection parity is clean (4 orphan directions all 0)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  // Pull the minimal columns and evaluate the invariant in JS (service-role read; no PII).
  const { data: ledger, error: e1 } = await sb
    .from('champions_awarded').select('id, surface, status');
  assert.ifError(e1);
  const { data: proj, error: e2 } = await sb
    .from('gamification_points').select('ref_id, category, points').like('category', 'champion_%');
  assert.ifError(e2);

  const projByRef = new Map();
  for (const p of proj) {
    const arr = projByRef.get(p.ref_id) || [];
    arr.push(p);
    projByRef.set(p.ref_id, arr);
  }
  const knownIds = new Set(ledger.map((l) => l.id));

  // 1. active ledger without a matching projection
  const dir1 = ledger.filter((l) => l.status === 'active')
    .filter((l) => !(projByRef.get(l.id) || []).some((p) => p.category === 'champion_' + l.surface));
  // 2. active ledger without EXACTLY ONE champion_% projection (estorno rows only exist for revoked)
  const dir2 = ledger.filter((l) => l.status === 'active')
    .filter((l) => (projByRef.get(l.id) || []).length !== 1);
  // 3. projection orphaned (ref not a ledger row at all — revoked refs are legitimate under append-only)
  const dir3 = [...projByRef.keys()].filter((ref) => !knownIds.has(ref));
  // 4. revoked ledger must be NET-ZERO in the projection (estorno absorbs the award; #1087 Onda 3)
  const dir4 = ledger.filter((l) => l.status === 'revoked')
    .filter((l) => (projByRef.get(l.id) || []).reduce((s, p) => s + p.points, 0) !== 0);

  assert.equal(dir1.length, 0, `active ledger rows missing their projection: ${JSON.stringify(dir1)}`);
  assert.equal(dir2.length, 0, `active ledger rows without exactly one projection: ${JSON.stringify(dir2)}`);
  assert.equal(dir3.length, 0, `orphaned projection rows (ref not in ledger): ${JSON.stringify(dir3)}`);
  assert.equal(dir4.length, 0, `revoked ledger rows whose projection does not net to zero: ${JSON.stringify(dir4)}`);
});

// ── STATIC: the stale TODO is cleared (the unblock is shipped, #424 item 1) ──────
test('M7 static: gamification.astro no longer claims the award unblock is a pending follow-up', () => {
  const PAGE = resolve(ROOT, 'src/pages/admin/gamification.astro');
  const page = existsSync(PAGE) ? readFileSync(PAGE, 'utf8') : '';
  assert.ok(page.length > 0, 'gamification.astro exists');
  assert.doesNotMatch(page, /PM follow-up\s*\n?\s*\/\/\s*pending \(whether to widen permission/,
    'the obsolete "PM follow-up pending" award-unblock comment is removed');
  // the scoped award gate that resolved it must still be present
  assert.match(page, /champion\.award'\)\s*\)\s*\{\s*showChampionAwardOnly/,
    'the shipped scoped champion.award gate is intact');
});
