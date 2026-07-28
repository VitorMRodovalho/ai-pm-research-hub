/**
 * Contract: #1464 (Onda 3 / B0) — gamification cycle attribution windows by the FACT date
 * (gamification_points.occurred_at), not the grant/insert date (created_at).
 *
 * BUG (audit 2026-07-21, docs/audit/2026-07-21_scoring_merit_audit.md §B0; re-grounded 2026-07-22):
 * the current-cycle scoreboard windowed gamification_points by created_at. The sync-attendance-points
 * Edge Function (cron every 5 days + admin button) inserts attendance points with ref_id=attendance.id
 * and NO created_at, so created_at = the run's now(). A 2026-07-11 flush dumped 560 rows of HISTORICAL
 * attendance (events from 2025-10 to 2026-07) into the current cycle — 526 rows / 5260 pts resolved to
 * events before cycle_start (2026-07-09). The aggregation math was correct; the cycle ATTRIBUTION was not.
 *
 * FIX (migration 20260805000480): add occurred_at (fact date; presence = events.date), backfill it, add
 * a caller-agnostic BEFORE INSERT trigger that derives occurred_at from ref_id for attendance rows, and
 * rewindow every cycle-scoped reader by COALESCE(occurred_at, created_at). created_at stays the audit
 * "when it was granted". Lifetime views (#1448 certificacoes-always-count; get_public_leaderboard) unchanged.
 *
 * Static checks lock the migration body. The DB-gated checks prove the two invariants against the live
 * ledger (the readers themselves are auth.uid()-gated and cannot be invoked by a service-role client):
 *   1. Windowing: a row whose created_at is IN-cycle but occurred_at is PRE-cycle is excluded from the
 *      occurred_at window (the fix) though a created_at window would have counted it (the bug).
 *   2. Trigger: an attendance row inserted WITHOUT occurred_at (ref_id -> a pre-cycle event) gets
 *      occurred_at = the event date (pre-cycle) — recurrence closed at the write layer, caller-agnostic.
 *
 * Cleanup (#231/#1170): tx=rollback does NOT undo SECDEF/committed INSERTs and CI+local write to PROD,
 * so every inserted probe is deleted by a unique reason-marker in a finally, with a residue assertion.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000480_1464_gamification_occurred_at_cycle_windowing.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC: migration shape ─────────────────────────────────────────────────────
test('#1464 static: migration file exists', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000480 exists on disk');
});

test('#1464 static: adds occurred_at column + caller-agnostic BEFORE INSERT trigger', () => {
  assert.match(migRaw, /ADD COLUMN IF NOT EXISTS occurred_at timestamptz/i, 'occurred_at column added');
  assert.match(migRaw, /CREATE OR REPLACE FUNCTION public\._gp_set_occurred_at\(\)/i, 'trigger function defined');
  assert.match(migRaw, /CREATE TRIGGER trg_gp_set_occurred_at\s+BEFORE INSERT ON public\.gamification_points/i,
    'BEFORE INSERT trigger created');
  // explicit occurred_at must win (backfills/tests/corrections)
  assert.match(migRaw, /IF NEW\.occurred_at IS NOT NULL THEN\s*RETURN NEW;/i, 'explicit occurred_at is preserved');
});

test('#1464 static: readers window the cycle by COALESCE(occurred_at, created_at), not bare created_at', () => {
  // stats + pillars + leaderboard cycle predicates all use the fact-date coalesce
  assert.match(migRaw, /COALESCE\(gp\.occurred_at, gp\.created_at\) >= v_cycle_start/i, 'cycle window uses occurred_at');
  assert.match(migRaw, /COALESCE\(gp_check\.occurred_at, gp_check\.created_at\) >= v_cycle_start/i,
    'membership EXISTS windows by occurred_at');
  // no cycle predicate left on bare gp.created_at
  assert.doesNotMatch(migRaw, /gp\.created_at\s*>=\s*v_cycle_start/i, 'no bare gp.created_at cycle predicate remains');
  assert.doesNotMatch(migRaw, /gp_check\.created_at\s*>=\s*v_cycle_start/i, 'no bare gp_check.created_at cycle predicate');
});

test('#1464 static: lifetime surfaces preserved (certificacoes always-count + leaderboard lifetime cols)', () => {
  // #1448 lifetime certificacoes exemption still present
  assert.match(migRaw, /r_win\.pillar = 'certificacoes'/i, 'certificacoes lifetime-always EXISTS preserved');
  // leaderboard lifetime columns remain bare SUM (no cycle window)
  assert.match(migRaw, /COALESCE\(sum\(gp\.points\) FILTER \(WHERE gr\.pillar = 'presenca'\), 0::bigint\)/i,
    'lifetime attendance column is not windowed');
});

test('#1464 static: get_member_xp_pillars ORDER BY includes protagonismo (was NULL-sorted)', () => {
  assert.match(migRaw, /WHEN 'protagonismo' THEN 7/i, 'protagonismo has a deterministic sort position');
});

test('#1464 static: migration notifies PostgREST', () => {
  assert.match(migRaw, /NOTIFY pgrst, 'reload schema'/i, 'schema reload notified');
});

// ── BEHAVIOURAL (DB-gated) ──────────────────────────────────────────────────────
async function currentCycleStart(sb) {
  const { data, error } = await sb.from('cycles').select('cycle_start').eq('is_current', true).limit(1);
  assert.ifError(error);
  return data && data[0] ? data[0].cycle_start : null;
}

async function anyActiveMember(sb) {
  const { data, error } = await sb.from('members').select('id,organization_id').eq('is_active', true).limit(1);
  assert.ifError(error);
  return data && data[0] ? data[0] : null;
}

test('#1464 behavioural: a created_at-in-cycle / occurred_at-pre-cycle row is excluded from the occurred_at window',
  { skip: dbGated ? false : skipMsg }, async (t) => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const cs = await currentCycleStart(sb);
    const mem = await anyActiveMember(sb);
    if (!cs || !mem) { t.skip('no current cycle / active member to probe'); return; }

    const MARKER = `occurred-at-window-probe-#1464-${randomUUID()}`;
    const csDate = new Date(cs + 'T00:00:00Z');
    const inCycle = new Date().toISOString();          // created_at now → inside the open cycle
    const preCycle = '2020-01-01T12:00:00Z';           // occurred_at long before any cycle_start

    try {
      const { error: insErr } = await sb.from('gamification_points').insert({
        member_id: mem.id, organization_id: mem.organization_id, points: 7,
        category: 'deliverable_completed', reason: MARKER, created_at: inCycle, occurred_at: preCycle,
      });
      assert.ifError(insErr);

      const { data, error } = await sb.from('gamification_points')
        .select('points,created_at,occurred_at,reason').eq('reason', MARKER);
      assert.ifError(error);
      const probe = (data || [])[0];
      assert.ok(probe, 'probe row present');

      // The bug window (created_at) WOULD have counted it; the fix window (occurred_at) does NOT.
      assert.ok(new Date(probe.created_at) >= csDate, 'probe created_at is inside the current cycle (bug window counts it)');
      assert.ok(probe.occurred_at && new Date(probe.occurred_at) < csDate,
        'probe occurred_at is before cycle_start (fix window excludes it) — the invariant');
    } finally {
      await sb.from('gamification_points').delete().eq('reason', MARKER);
    }
    const { data: residue } = await sb.from('gamification_points').select('id').eq('reason', MARKER);
    assert.equal((residue || []).length, 0, 'probe rows cleaned up (must not leak into PROD, #1170/#231)');
  });

test('#1464 behavioural: trigger derives occurred_at from ref_id for an attendance row inserted without it',
  { skip: dbGated ? false : skipMsg }, async (t) => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const cs = await currentCycleStart(sb);
    const mem = await anyActiveMember(sb);
    if (!cs || !mem) { t.skip('no current cycle / active member to probe'); return; }

    // an attendance row whose event predates the current cycle
    const { data: att, error: aErr } = await sb
      .from('attendance').select('id, event_id, events!inner(date)')
      .lt('events.date', cs).limit(1);
    assert.ifError(aErr);
    if (!att || !att[0]) { t.skip('no pre-cycle attendance row to exercise the trigger'); return; }
    const attId = att[0].id;
    const eventDate = att[0].events.date; // 'YYYY-MM-DD'

    const MARKER = `occurred-at-trigger-probe-#1464-${randomUUID()}`;
    try {
      // NOTE: occurred_at intentionally omitted — the BEFORE INSERT trigger must fill it from ref_id.
      const { error: insErr } = await sb.from('gamification_points').insert({
        member_id: mem.id, organization_id: mem.organization_id, points: 10,
        category: 'attendance', ref_id: attId, reason: MARKER, created_at: new Date().toISOString(),
      });
      assert.ifError(insErr);

      const { data, error } = await sb.from('gamification_points')
        .select('occurred_at,reason').eq('reason', MARKER);
      assert.ifError(error);
      const probe = (data || [])[0];
      assert.ok(probe, 'probe row present');
      assert.ok(probe.occurred_at, 'trigger set occurred_at (not left NULL)');
      // occurred_at is noon America/Sao_Paulo of the event date → same calendar day as events.date
      assert.equal(new Date(probe.occurred_at).toISOString().slice(0, 10), eventDate,
        'occurred_at resolves to the event date, not the insert date');
      assert.ok(new Date(probe.occurred_at) < new Date(cs + 'T00:00:00Z'),
        'the derived occurred_at is pre-cycle (would not inflate the current cycle)');
    } finally {
      await sb.from('gamification_points').delete().eq('reason', MARKER);
    }
    const { data: residue } = await sb.from('gamification_points').select('id').eq('reason', MARKER);
    assert.equal((residue || []).length, 0, 'probe rows cleaned up (must not leak into PROD, #1170/#231)');
  });
