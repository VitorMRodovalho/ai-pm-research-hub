/**
 * Contract: #192 — enforce one curation review per curator per round.
 *
 * Before: submit_curation_review() INSERTed unconditionally and the consensus
 * check counted ROWS (`count(*) WHERE decision='approved'`) with no round filter
 * and no distinct-curator dedup — so one curator approving twice could reach
 * reviewers_required and auto-publish with a single human.
 *
 * After (PM decision = per-round, mig 20260805000113):
 *   - curation_review_log.review_round int NOT NULL DEFAULT 1
 *   - UNIQUE(board_item_id, curator_id, review_round)
 *   - RPC pre-checks duplicates + counts count(DISTINCT curator_id) in the round.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000113_192_one_review_per_curator_per_round.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
// Companion: get_curation_dashboard display counters made round-aware to match the gate.
const MIG114 = resolve(ROOT, 'supabase/migrations/20260805000114_192_dashboard_round_aware_counters.sql');
const mig114Raw = existsSync(MIG114) ? readFileSync(MIG114, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const client = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
const TEST_ROUND = 9999; // isolated sentinel round, never used by a real flow

// ── STATIC ──────────────────────────────────────────────────────────────────────
test('#192 static: migration 113 exists', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000113 exists');
});

test('#192 static: adds review_round column + per-round UNIQUE constraint', () => {
  assert.match(migRaw, /ADD COLUMN IF NOT EXISTS review_round int NOT NULL DEFAULT 1/,
    'adds review_round column');
  assert.match(migRaw, /ADD CONSTRAINT curation_review_log_one_per_curator_per_round\s+UNIQUE \(board_item_id, curator_id, review_round\)/,
    'adds the per-round UNIQUE constraint');
});

test('#192 static: consensus counts DISTINCT curators filtered to the current round', () => {
  assert.match(migRaw, /count\(DISTINCT curator_id\)/, 'consensus uses count(DISTINCT curator_id)');
  assert.match(migRaw, /decision = 'approved'\s*AND review_round = v_current_round/,
    'consensus is filtered to the current round');
  // regression guard: the old row-count form must be gone
  assert.doesNotMatch(migRaw, /SELECT count\(\*\) INTO v_approved_count/,
    'old row-count consensus must be replaced');
});

test('#192 static: RPC pre-checks duplicate review in the same round', () => {
  assert.match(migRaw, /already submitted a review for this item in round/,
    'duplicate pre-check raises a clear error');
  assert.match(migRaw,
    /INSERT INTO curation_review_log \([\s\S]*?\breview_round\b[\s\S]*?v_current_round[\s\S]*?RETURNING id INTO v_log_id/,
    'review_round (col) + v_current_round (value) are written onto the inserted log row');
});

test('#192 static: ADD CONSTRAINT is idempotent (DO/EXCEPTION guard)', () => {
  assert.match(migRaw, /EXCEPTION WHEN duplicate_object THEN NULL/,
    'constraint add is wrapped so a re-apply is a no-op');
});

test('#192 static: get_curation_dashboard counters are round-aware (companion mig 114)', () => {
  assert.ok(existsSync(MIG114), 'migration 20260805000114 exists');
  assert.match(mig114Raw, /'reviews_approved',\s*\(SELECT count\(DISTINCT crl\.curator_id\)/,
    'reviews_approved counts DISTINCT curators (matches the publish gate)');
  assert.match(mig114Raw, /'reviews_approved'[\s\S]*?ble\.action = 'reviewer_assigned'/,
    'reviews_approved is filtered to the current round');
  assert.match(mig114Raw, /'review_count'[\s\S]*?ble\.action = 'reviewer_assigned'/,
    'review_count is round-scoped');
  // regression guard: the old all-rounds count(*) form for reviews_approved must be gone
  assert.doesNotMatch(mig114Raw, /'reviews_approved', \(SELECT count\(\*\) FROM curation_review_log crl WHERE crl\.board_item_id = bi\.id AND crl\.decision = 'approved'\)/,
    'old all-rounds reviews_approved count(*) must be replaced');
});

// ── DB-GATED ──────────────────────────────────────────────────────────────────────
test('#192 db: per-round UNIQUE constraint exists on curation_review_log',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    // Probe the constraint via a real duplicate INSERT (cleaned up after).
    const { data: item } = await sb.from('board_items').select('id').limit(1).single();
    const { data: member } = await sb.from('members').select('id').limit(1).single();
    assert.ok(item?.id && member?.id, 'have a board_item + member to exercise the constraint');
    const row = { board_item_id: item.id, curator_id: member.id, decision: 'approved', review_round: TEST_ROUND };
    try {
      const first = await sb.from('curation_review_log').insert(row);
      assert.ifError(first.error);
      const dup = await sb.from('curation_review_log').insert(row);
      assert.ok(dup.error, 'duplicate (item,curator,round) insert must be rejected');
      assert.equal(dup.error.code, '23505', `expected unique_violation 23505, got ${dup.error.code}: ${dup.error.message}`);
    } finally {
      await sb.from('curation_review_log')
        .delete().eq('board_item_id', item.id).eq('curator_id', member.id).eq('review_round', TEST_ROUND);
    }
  });

test('#192 db: a DIFFERENT round for the same curator+item is allowed (2-round model preserved)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { data: item } = await sb.from('board_items').select('id').limit(1).single();
    const { data: member } = await sb.from('members').select('id').limit(1).single();
    try {
      const r1 = await sb.from('curation_review_log')
        .insert({ board_item_id: item.id, curator_id: member.id, decision: 'returned_for_revision', review_round: TEST_ROUND });
      const r2 = await sb.from('curation_review_log')
        .insert({ board_item_id: item.id, curator_id: member.id, decision: 'approved', review_round: TEST_ROUND + 1 });
      assert.ifError(r1.error);
      assert.ifError(r2.error, 'same curator+item in a later round must be allowed (revise-and-resubmit)');
    } finally {
      await sb.from('curation_review_log')
        .delete().eq('board_item_id', item.id).eq('curator_id', member.id)
        .in('review_round', [TEST_ROUND, TEST_ROUND + 1]);
    }
  });
