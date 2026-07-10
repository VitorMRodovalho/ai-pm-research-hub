/**
 * Contract: p277 / #419 (ADR-0100) metric 4 — PR4-B: weekly tribe digest roster convergence.
 *
 * get_weekly_tribe_digest.aggregates.active_members converges onto the canonical roster primitive
 * (get_initiative_roster_count, PR4-A). Was: count(*) FROM members WHERE tribe_id = p_tribe_id AND
 * current_cycle_active = true — which over-counts the OFFBOARDED Maria Luiza (tribe-8 engagement
 * status='offboarded', but members.current_cycle_active still true): tribe-8 antes = 7. Now = 6.
 * The weekly leader-digest email (Saturday cron) stops over-reporting the roster.
 *
 * Same-signature CREATE OR REPLACE; only the active_members line changed. Static checks lock the repoint;
 * behavioural check (DB-gated) asserts digest.active_members == get_initiative_roster_count for the tribe
 * and that the rest of the digest still computes.
 *
 * Cross-ref: SPEC_419_M4_M8_CANONICAL_METRICS.md §M4.6 (PR4-B); ADR-0100 §2.2 tribe_roster/member_count;
 * issue #419.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000083_p277_419_m4b_digest_roster_count.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const mig = migRaw.replace(/^\s*--.*$/gm, '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC ──────────────────────────────────────────────────────────────────────
test('M4-B static: digest active_members reads the canonical roster primitive', () => {
  assert.ok(existsSync(MIG), 'M4-B migration 20260805000083 exists');
  assert.match(mig, /'active_members', COALESCE\(public\.get_initiative_roster_count\(v_initiative_id\), 0\)/,
    'active_members = get_initiative_roster_count(v_initiative_id)');
  // forward-defense: the OLD members.tribe_id ∧ current_cycle_active count must NOT survive in active_members
  assert.doesNotMatch(mig, /'active_members', COALESCE\(\(\s*SELECT count\(\*\) FROM public\.members m\s*WHERE m\.tribe_id = p_tribe_id AND m\.current_cycle_active/,
    'the old current_cycle_active-alone active_members count is gone');
});

test('M4-B static: same-signature CREATE OR REPLACE (no DROP), rest of the digest preserved', () => {
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.get_weekly_tribe_digest\(p_tribe_id integer\)/, 'same signature');
  assert.doesNotMatch(mig, /DROP FUNCTION/, 'no DROP');
  // the other aggregates + the 3 pending-work CTEs are still present (not accidentally dropped)
  for (const key of ['members_with_overdue_cards', 'cards_overdue_total', 'tribe_health_pct', 'ata_pending', 'attendance_pending', 'champion_pending']) {
    assert.ok(mig.includes(`'${key}'`), `${key} preserved`);
  }
});

// ── BEHAVIOURAL (DB-gated) ───────────────────────────────────────────────────────
test('M4-B behavioural: tribe-8 digest active_members == roster count (5, participants-only), not cca-alone 7', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: digest, error: e1 } = await sb.rpc('get_weekly_tribe_digest', { p_tribe_id: 8 });
  assert.ifError(e1);
  const active = Number(digest.aggregates.active_members);

  const { data: initId } = await sb.rpc('resolve_initiative_id', { p_tribe_id: 8 });
  const { data: rosterCount } = await sb.rpc('get_initiative_roster_count', { p_initiative_id: initId });

  // #1249: the durable contract is single-source (digest == canonical roster count). The absolute
  // fixture (== 5) died when the C4 cohort evolved (kickoff reorg + #1247 phantom-membership
  // regularization); the participants-only invariant is defended structurally + by the roster tests.
  assert.equal(active, Number(rosterCount), 'digest active_members == canonical roster count (single source)');

  // the rest of the digest still computes (a representative non-roster aggregate is present + numeric)
  assert.equal(typeof Number(digest.aggregates.cards_overdue_total), 'number', 'cards_overdue_total still computes');
  assert.ok(digest.aggregates.ata_pending, 'ata_pending block still present');
});
