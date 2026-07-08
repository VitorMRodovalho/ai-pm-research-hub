/**
 * Contract: #1147 (Fio 1/3, umbrella #1150) — deliverable_completed XP derives from board_items.
 *
 * BUG (live-grounded 2026-07-06, re-grounded 2026-07-08): the only XP trigger for the producao
 * pillar's deliverable rule lived on tribe_deliverables (status='completed'), a dormant surface
 * (71 rows, 1 completed ever). Real work completes as board_items.status='done' — which had NO
 * XP trigger — so the pillar was effectively dead for the real flow: 18 done tribe cards at the
 * 2026-07-06 snapshot vs 1 deliverable_completed row platform-wide (a p277 manual backfill).
 *
 * FIX (migration 20260805000376): trg_board_item_deliverable_xp on board_items grants
 * deliverable_completed via _grant_auto_xp when a card reaches done, scoped (PM 2026-07-08) to
 * tribe boards + is_portfolio_item=true, mirrors excluded. The tribe_deliverables XP trigger is
 * RETIRED (single-source, class #1032 — two parallel surfaces would double-credit the same work);
 * its completed_at bookkeeping survives in a slim BEFORE trigger with no XP grant.
 * Idempotency (reopen→redone must not re-credit) lives in _grant_auto_xp's EXISTS guard over
 * (ref_id, category, member_id) — proven live via RAISE-rollback smoke (PR): portfolio done →
 * 1 row/40pts (on-time), reopen→redone → still 1 row, non-portfolio → 0 rows.
 *
 * Backfill (PM 2026-07-08, p277 pattern): the 18 snapshot cards got 30 pts base, NO on-time
 * bonus (not reconstructible), created_at pinned 2026-07-08T12:00Z (inside the C3 window;
 * C4 starts 2026-07-09) — the DB-gated check locks those 18 refs to existing ledger rows.
 *
 * Cross-ref: #1147, #1150, #1032 (single-source class), #1080 (pillar taxonomy), p277 backfill.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000376_1147_deliverable_xp_from_board_items.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
// executable SQL only (strip `-- ...` lines; the header narrates the retired trigger by name).
const code = migRaw.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// The 18-card backfill cohort (status='done' on tribe boards at the 2026-07-06 snapshot,
// reconstructed via board_lifecycle_events new_status='done' + DIA-9 archive updated_at).
const BACKFILL_REFS = [
  '7cc6f269-4f1a-4043-af16-c4a3729e3e43',
  '5b753c84-e125-4bcc-9185-5106b7154c55',
  'a39fc203-ec3d-4fda-844e-2951eef412a4',
  'c3f5c262-6344-42ae-9a9f-44dcbf013304',
  'ab1d21a3-5627-483f-adf1-9c4265283b88',
  '94e27914-afbb-4957-91cb-0772fa908744',
  'a7708fac-5375-47ff-9828-f38b2e69e53f',
  'b4bf0150-add6-4ffa-8f21-1c55565e65cb',
  '642fe90f-20ad-4ba4-a9e7-05470ed7c5de',
  '8f33e4ac-5028-4fbb-bcde-668eab8181ff',
  'e9f8df82-52d6-47b0-ad7d-72be14a11a79',
  'c409da8f-b472-40dd-bf87-8dac8e73e6fa',
  '3dee35ca-359b-4cfa-acae-964f4e5fe007',
  'b06fcf2c-8072-4b60-b115-85868b8f0042',
  'bf9b03f2-fc38-4cdc-af5b-dd14fd7c8040',
  '5c095ab8-6b52-4d80-a32e-5c27eec6d3f1',
  'd70efc66-b80c-44d8-aa10-7c8faa878edb',
  'c562b766-727d-4231-ba11-d5827beb6f25',
];

// ── STATIC: the XP trigger moved to board_items with the ratified scope ─────────
test('#1147 static: migration exists and installs the board_items XP trigger', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000376 exists on disk');
  assert.match(code, /CREATE OR REPLACE FUNCTION public\.trg_board_item_deliverable_xp\(\)/);
  assert.match(code, /CREATE TRIGGER trg_board_item_deliverable_xp\s*\n?\s*AFTER INSERT OR UPDATE OF status ON public\.board_items/,
    'trigger fires on INSERT and UPDATE OF status (catches every write path, RPC or direct)');
});

test('#1147 static: ratified scope — done + tribe board + portfolio item, mirrors and unassigned excluded', () => {
  assert.match(code, /NEW\.status = 'done'/, "fires on the board_items vocabulary ('done', not 'completed')");
  assert.match(code, /TG_OP = 'INSERT' OR OLD\.status IS DISTINCT FROM 'done'/,
    'edge-fires only when the card just became done (no re-grant on unrelated updates)');
  assert.match(code, /NEW\.is_portfolio_item IS TRUE/, 'PM 2026-07-08: only portfolio items score (anti-inflation)');
  assert.match(code, /NEW\.is_mirror IS NOT TRUE/, 'mirrors are projections of the work, not the work');
  assert.match(code, /NEW\.assignee_id IS NOT NULL/, 'no recipient, no grant');
  assert.match(code, /pb\.board_scope = 'tribe'/, 'only tribe-scope boards');
});

test('#1147 static: grants via _grant_auto_xp (idempotency + rule lookup delegated)', () => {
  assert.match(code, /_grant_auto_xp\(\s*\n?\s*'deliverable_completed'/,
    'must reuse the shared grant path — its EXISTS(ref_id,category,member) guard is the reopen→redone dedup');
  assert.match(code, /COALESCE\(NEW\.due_date, NEW\.baseline_date\)/,
    'deadline = due_date with baseline_date fallback (issue: map baseline/due to the bonus)');
  assert.match(code, /COALESCE\(NEW\.actual_completion_date, CURRENT_DATE\)/,
    'on-time compares the completion date move_board_item writes in the same UPDATE');
});

test('#1147 static: tribe_deliverables XP trigger retired (single-source, #1032)', () => {
  assert.match(code, /DROP TRIGGER IF EXISTS tribe_deliverable_completed_xp ON public\.tribe_deliverables/);
  assert.match(code, /DROP FUNCTION IF EXISTS public\.trg_tribe_deliverable_completed_xp\(\)/);
});

test('#1147 static: completed_at bookkeeping survives without any XP grant', () => {
  const at = code.indexOf('CREATE OR REPLACE FUNCTION public.trg_tribe_deliverable_completed_at()');
  assert.ok(at > -1, 'slim completed_at trigger function exists');
  const slim = code.slice(at);
  assert.doesNotMatch(slim, /_grant_auto_xp/, 'the bookkeeping trigger must not grant XP');
  assert.match(slim, /BEFORE INSERT OR UPDATE OF status ON public\.tribe_deliverables/,
    'BEFORE trigger sets NEW directly (no AFTER-trigger self-UPDATE)');
});

// ── BEHAVIOURAL (DB-gated): done portfolio card ⇒ XP row exists ─────────────────
test('#1147 behavioural: every done portfolio card on a tribe board has a deliverable_completed row',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

    const { data: boards, error: bErr } = await sb
      .from('project_boards').select('id').eq('board_scope', 'tribe');
    assert.ifError(bErr);
    const tribeBoardIds = (boards || []).map((b) => b.id);
    assert.ok(tribeBoardIds.length > 0, 'tribe boards exist');

    const { data: cards, error: cErr } = await sb
      .from('board_items')
      .select('id,assignee_id,is_mirror')
      .eq('status', 'done')
      .eq('is_portfolio_item', true)
      .in('board_id', tribeBoardIds);
    assert.ifError(cErr);

    const eligible = (cards || []).filter((c) => c.assignee_id && c.is_mirror !== true);
    if (eligible.length === 0) return; // vacuously true right after a cycle-turn archive sweep

    const { data: pts, error: pErr } = await sb
      .from('gamification_points')
      .select('ref_id,member_id')
      .eq('category', 'deliverable_completed')
      .in('ref_id', eligible.map((c) => c.id));
    assert.ifError(pErr);
    const paid = new Set((pts || []).map((p) => `${p.ref_id}:${p.member_id}`));

    for (const c of eligible) {
      assert.ok(paid.has(`${c.id}:${c.assignee_id}`),
        `done portfolio card ${c.id} must have a deliverable_completed row for its assignee`);
    }
  });

test('#1147 behavioural: the 18 backfilled snapshot cards are paid, 30 pts base, inside the C3 window',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data: pts, error } = await sb
      .from('gamification_points')
      .select('ref_id,points,created_at')
      .eq('category', 'deliverable_completed')
      .in('ref_id', BACKFILL_REFS);
    assert.ifError(error);

    const byRef = new Map((pts || []).map((p) => [p.ref_id, p]));
    for (const ref of BACKFILL_REFS) {
      const row = byRef.get(ref);
      assert.ok(row, `backfill ref ${ref} must have a ledger row`);
      assert.equal(row.points, 30, `backfill ref ${ref} is base-only (no on-time bonus, p277 pattern)`);
      assert.ok(new Date(row.created_at) < new Date('2026-07-09T00:00:00Z'),
        `backfill ref ${ref} must sit inside the C3 window (before C4 start 2026-07-09)`);
    }
  });
