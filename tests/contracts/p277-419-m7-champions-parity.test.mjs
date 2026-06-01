/**
 * Contract: p277 / #419 (ADR-0100) metric 7 — champions ledger↔projection PARITY invariant (#424 item 2).
 *
 * PM-ratified (2026-05-31): `champions_awarded` is the CANONICAL source of truth for champion recognition
 * (read by get_champions_ranking, profile history, the admin list); the `gamification_points` rows with
 * category='champion_'||surface are a DERIVED PROJECTION (read by get_tribe_gamification.champions_points via
 * the canonical gr.pillar='champions' JOIN + the leaderboard chip). award_champion DUAL-WRITES both;
 * revoke_champion UPDATEs the ledger to 'revoked' + DUAL-DELETEs the projection. There was no invariant
 * guaranteeing they stay in sync — this test is that guarantee.
 *
 * THE INVARIANT (4 directions, all must be 0 live):
 *   1. every champions_awarded status='active' row has >=1 matching projection row
 *      (gamification_points.ref_id = champion_id AND category = 'champion_'||surface);
 *   2. every active ledger row has EXACTLY ONE champion_% projection row (no duplicates);
 *   3. no champion_% projection row is orphaned (points to a non-active / non-existent ledger row);
 *   4. no status='revoked' ledger row still has a champion_% projection row (revoke must dual-delete).
 *
 * #424 item 1 (the award-path operational unblock) is ALREADY SHIPPED — see
 * p277-champion-award-leader-access.test.mjs (scoped `champion.award` gate; backend already authorizes
 * volunteer/leader@initiative via can_by_member). This test closes #424 item 2 (the structural half).
 *
 * Static checks lock the dual-write (award) + dual-delete (revoke) so the invariant cannot silently rot.
 * Behavioural checks (DB-gated) assert the live ledger/projection are in parity (both empty today: ledger
 * active=0, projection=0 — so this is forward-defense before the dual-write ever executes in anger).
 *
 * Cross-ref: SPEC_419_M4_M8_CANONICAL_METRICS.md §M7; ADR-0100 §2.2 champions row; issue #424.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const AWARD_MIG = resolve(ROOT, 'supabase/migrations/20260675600000_p171_8_award_champion_criteria_validation.sql');
const REVOKE_MIG = resolve(ROOT, 'supabase/migrations/20260646000000_p161_champion_rpcs_phase2.sql');

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

// ── STATIC: the dual-delete (revoke) ────────────────────────────────────────────
test('M7 static: revoke_champion marks the ledger revoked + DUAL-DELETES the projection', () => {
  assert.ok(revoke.length > 0, 'revoke_champion migration exists');
  assert.match(revoke, /UPDATE champions_awarded SET[\s\S]*?status = 'revoked'/,
    'marks the ledger row revoked (does not delete it — keeps the audit trail)');
  assert.match(revoke, /DELETE FROM gamification_points\s+WHERE ref_id = p_champion_id\s+AND category LIKE 'champion_%'/,
    'dual-deletes the projection rows by ref_id');
});

// ── BEHAVIOURAL (DB-gated): the live invariant holds (all 4 directions = 0) ──────
test('M7 behavioural: ledger↔projection parity is clean (4 orphan directions all 0)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  // Pull the minimal columns and evaluate the invariant in JS (service-role read; no PII).
  const { data: ledger, error: e1 } = await sb
    .from('champions_awarded').select('id, surface, status');
  assert.ifError(e1);
  const { data: proj, error: e2 } = await sb
    .from('gamification_points').select('ref_id, category').like('category', 'champion_%');
  assert.ifError(e2);

  const projByRef = new Map();
  for (const p of proj) {
    const arr = projByRef.get(p.ref_id) || [];
    arr.push(p.category);
    projByRef.set(p.ref_id, arr);
  }
  const activeIds = new Set(ledger.filter((l) => l.status === 'active').map((l) => l.id));
  const ledgerById = new Map(ledger.map((l) => [l.id, l]));

  // 1. active ledger without a matching projection
  const dir1 = ledger.filter((l) => l.status === 'active')
    .filter((l) => !(projByRef.get(l.id) || []).includes('champion_' + l.surface));
  // 2. active ledger without EXACTLY ONE champion_% projection
  const dir2 = ledger.filter((l) => l.status === 'active')
    .filter((l) => (projByRef.get(l.id) || []).length !== 1);
  // 3. projection orphaned (ref not an active ledger row)
  const dir3 = [...projByRef.keys()].filter((ref) => !activeIds.has(ref));
  // 4. revoked ledger still has a projection
  const dir4 = ledger.filter((l) => l.status === 'revoked')
    .filter((l) => (projByRef.get(l.id) || []).length > 0);

  assert.equal(dir1.length, 0, `active ledger rows missing their projection: ${JSON.stringify(dir1)}`);
  assert.equal(dir2.length, 0, `active ledger rows without exactly one projection: ${JSON.stringify(dir2)}`);
  assert.equal(dir3.length, 0, `orphaned projection rows (ref not active ledger): ${JSON.stringify(dir3)}`);
  assert.equal(dir4.length, 0, `revoked ledger rows that still have a projection: ${JSON.stringify(dir4)}`);
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
