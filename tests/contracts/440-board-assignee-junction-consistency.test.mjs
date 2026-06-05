/**
 * #440 contract test — board_items.assignee_id stays consistent with the
 * board_item_assignments junction.
 *
 * Bug: assignee_id ("Responsável") and board_item_assignments ("Participantes")
 * were never synced — create_board_item set assignee_id = COALESCE(p_assignee_id,
 * creator) while only inserting the CREATOR as the junction author, and
 * update_board_item could set assignee_id with no junction row. 132/593 items
 * had assignee_id pointing at a member absent from the junction. (Display symptom
 * already fixed in PR #442; this is the underlying data divergence.)
 *
 * Fix (migration 20260805000118 — PM "Option 2", sync): two triggers enforce the
 * invariant `assignee_id IS NULL OR assignee_id ∈ junction` from every write path,
 * plus a one-time backfill. No RPC body changes (no permission/display/semantic
 * regression).
 *   T1 ensure_assignee_in_board_junction — assignee set => added to junction.
 *   T2 clear_board_assignee_on_junction_delete — assignee removed => assignee_id NULL.
 *
 * Deferred (UX, needs author-vs-creator-vs-Responsável product decision): stop
 * create_board_item defaulting assignee to creator; picker overwriting Responsável.
 *
 * Cross-ref: #440, PR #442 (display fix).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const FIX_FILE = '20260805000118_440_board_assignee_junction_consistency.sql';
const FIX = readFileSync(join(MIGRATIONS_DIR, FIX_FILE), 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── (A) static: the migration declares both trigger functions + triggers + backfill ──
test('#440: T1 ensure_assignee_in_board_junction function + trigger declared', () => {
  assert.match(FIX, /CREATE OR REPLACE FUNCTION public\.ensure_assignee_in_board_junction\(\)/);
  assert.match(FIX, /CREATE TRIGGER trg_ensure_assignee_in_board_junction\s+AFTER INSERT OR UPDATE OF assignee_id ON public\.board_items/);
});

test('#440: T2 clear_board_assignee_on_junction_delete function + trigger declared', () => {
  assert.match(FIX, /CREATE OR REPLACE FUNCTION public\.clear_board_assignee_on_junction_delete\(\)/);
  assert.match(FIX, /CREATE TRIGGER trg_clear_board_assignee_on_junction_delete\s+AFTER DELETE ON public\.board_item_assignments/);
});

test('#440: T1 only inserts when assignee is absent from the junction (idempotent)', () => {
  assert.match(FIX, /NEW\.assignee_id IS NOT NULL\s+AND NOT EXISTS/);
  assert.match(FIX, /role,\s*assigned_by\)\s*VALUES\s*\(NEW\.id,\s*NEW\.assignee_id,\s*'author'/);
});

test('#440: migration includes the one-time backfill', () => {
  assert.match(
    FIX,
    /INSERT INTO public\.board_item_assignments[\s\S]*FROM public\.board_items bi\s+WHERE bi\.assignee_id IS NOT NULL\s+AND NOT EXISTS/,
    'migration must backfill the assignee as a junction author where missing'
  );
});

// ── (B) DB-gated invariant: assignee_id IS NULL OR assignee_id ∈ junction ──
test('#440 DB: no board_item has an assignee_id absent from the junction', { skip: !dbGated && skipMsg }, async () => {
  const supa = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const ITEMS_LIMIT = 20000;
  const ASSIGNS_LIMIT = 100000;
  const { data: items, error: e1 } = await supa
    .from('board_items')
    .select('id,assignee_id')
    .not('assignee_id', 'is', null)
    .limit(ITEMS_LIMIT);
  assert.equal(e1, null, e1 ? `board_items query failed: ${e1.message}` : '');
  // saturation guard: if the limit is hit, the cross-check below silently
  // under-counts — fail loudly so the limit gets raised instead.
  assert.ok((items || []).length < ITEMS_LIMIT, `board_items limit ${ITEMS_LIMIT} saturated — raise it or paginate`);

  const { data: assigns, error: e2 } = await supa
    .from('board_item_assignments')
    .select('item_id,member_id')
    .limit(ASSIGNS_LIMIT);
  assert.equal(e2, null, e2 ? `board_item_assignments query failed: ${e2.message}` : '');
  assert.ok((assigns || []).length < ASSIGNS_LIMIT, `board_item_assignments limit ${ASSIGNS_LIMIT} saturated — raise it or paginate`);

  const pairSet = new Set((assigns || []).map((a) => `${a.item_id}:${a.member_id}`));
  const divergent = (items || []).filter((it) => !pairSet.has(`${it.id}:${it.assignee_id}`));
  assert.equal(
    divergent.length,
    0,
    `Expected 0 items with assignee_id absent from the junction; got ${divergent.length}: ${divergent
      .slice(0, 10)
      .map((it) => it.id)
      .join(', ')}`
  );
});
