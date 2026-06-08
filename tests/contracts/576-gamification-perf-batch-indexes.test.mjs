/**
 * Contract: #576 — gamification cockpit RPC performance (follow-up to #425 / PR #575).
 *
 * PERF, NOT CORRECTNESS. The two functions get_tribe_gamification(integer) +
 * get_initiative_gamification(uuid) were rewritten (same signatures, CREATE OR REPLACE)
 * to remove an N+1 and hoist the roster, with byte-identical JSON output (proven live
 * this session: 6/7 tribe fingerprints + 2 initiative fingerprints raw-identical; tribe 4
 * identical modulo a documented total_points tie; 37/37 per-member attendance-map probe).
 *
 * This test guards the OPTIMIZATION SHAPE going forward (the 425 static test pins the OLD
 * file 20260805000128 — which still calls get_attendance_rate per member — so the batch is
 * otherwise unguarded). Mig: 20260805000132_p576_gamification_perf_batch_indexes.sql.
 *
 * What this locks:
 *   - attendance_rate batched into a jsonb map (no per-member get_attendance_rate call);
 *   - last_activity folded into points_per_member MAX(created_at);
 *   - roster hoist via v_member_ids = ANY(...) (no per-initiative v_initiative_roster re-scan);
 *   - item-5 delegation reorder (resolve_tribe_id before the auth fetch);
 *   - index topology: + idx_gp_member_created, + idx_cp_member_status, - idx_gamification_member;
 *   - ACL preservation (REVOKE FROM PUBLIC,anon) + auth gate on BOTH RPC paths.
 *
 * Cross-ref: #425 (PR #575), council review wf_f8f73ec7, issue #576.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000132_p576_gamification_perf_batch_indexes.sql');
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
// strip comments so the header's documentation of the OLD per-member call does not trip
// the "no executable get_attendance_rate" forward-defense.
const code = body.replace(/--[^\n]*/g, '');

// the get_initiative_gamification function body slice (for the item-5 ordering assertion)
const initFnStart = code.indexOf('FUNCTION public.get_initiative_gamification');
const initFn = initFnStart >= 0 ? code.slice(initFnStart) : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const TRIBE8 = 8;
const MESA = '6e9af7a8-1696-4169-a1a1-c0e160600002'; // native (no-tribe) initiative -> standalone path

// ── STATIC: migration shape ───────────────────────────────────────────────────────
test('576 static: two same-signature CREATE OR REPLACE (no DROP FUNCTION), both SECDEF', () => {
  assert.ok(existsSync(MIG), 'migration 132 exists');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_tribe_gamification\(p_tribe_id integer\)/i);
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_initiative_gamification\(p_initiative_id uuid\)/i);
  assert.ok(!/DROP FUNCTION/i.test(body), 'same signatures → no DROP (preserves ACL)');
  assert.equal((code.match(/SECURITY DEFINER/gi) || []).length, 2, 'both stay SECURITY DEFINER');
  assert.equal((code.match(/SET search_path TO 'public', 'pg_temp'/gi) || []).length, 2, 'search_path preserved on both');
});

test('576 static: attendance_rate N+1 removed — no per-member get_attendance_rate call', () => {
  assert.ok(!/get_attendance_rate/.test(code),
    'no executable get_attendance_rate (batched into a map); SSOT fn itself is untouched');
  // batched into a jsonb map keyed by member, read with (v_attendance -> member::text)
  assert.equal((code.match(/jsonb_object_agg\(ar\.member_id::text, ar\.rate\)/g) || []).length, 2,
    'attendance batched into a member->rate map in BOTH functions');
  assert.equal((code.match(/v_attendance -> \w+\.id::text/g) || []).length, 2,
    'attendance_rate read from the pre-batched map in BOTH functions');
});

test('576 static: last_activity folded into points_per_member MAX(created_at)', () => {
  assert.equal((code.match(/MAX\(gp\.created_at\) AS last_activity_ts/g) || []).length, 2,
    'last_activity_ts aggregated once per member in BOTH functions');
  assert.ok(!/SELECT MAX\(gp2\.created_at\)/.test(code),
    'old per-member correlated MAX subquery removed');
  // LGPD Art. 9: still gamification activity, never members.last_seen_at
  assert.ok(!/last_seen_at/.test(code), 'last_activity must NOT derive from members.last_seen_at');
});

test('576 static: roster hoist — reuse v_member_ids array, no per-initiative roster re-scan', () => {
  // the collected array is reused for every membership test (members / cert / trend / trail).
  assert.ok((code.match(/= ANY\(v_member_ids\)/g) || []).length >= 3,
    'membership tests reuse the collected v_member_ids array');
  // the tribe fn keeps exactly ONE initiative-filtered scan (the v_member_ids collection);
  // the five former consumer re-scans are hoisted away.
  assert.equal((code.match(/FROM v_initiative_roster WHERE initiative_id = v_initiative_id/g) || []).length, 1,
    'only the single v_member_ids collection scans the roster by initiative (consumers hoisted)');
  assert.ok(!/IN \(SELECT member_id FROM v_initiative_roster WHERE initiative_id = v_initiative_id\)/.test(code),
    'no consumer IN (SELECT member_id FROM roster WHERE initiative_id=...) re-scan remains');
  assert.ok(/SELECT DISTINCT legacy_tribe_id, member_id FROM v_initiative_roster/.test(code),
    'the global cross-tribe roster scan (tribe_rank/ranking) is intentionally retained');
});

test('576 static: item-5 — resolve_tribe_id runs BEFORE the members-by-auth_id fetch', () => {
  assert.ok(initFn.length > 0, 'get_initiative_gamification body located');
  const idxResolve = initFn.indexOf('resolve_tribe_id');
  const idxAuth = initFn.indexOf('SELECT * INTO v_caller FROM members WHERE auth_id');
  assert.ok(idxResolve >= 0 && idxAuth >= 0, 'both landmarks present');
  assert.ok(idxResolve < idxAuth,
    'routing resolves before the auth fetch (delegation path avoids the double members lookup)');
});

test('576 static: index topology — add composite + status, drop redundant member-only', () => {
  assert.match(code, /CREATE INDEX IF NOT EXISTS idx_gp_member_created\s+ON public\.gamification_points \(member_id, created_at DESC\)/i,
    'composite (member_id, created_at DESC) added');
  assert.match(code, /DROP INDEX IF EXISTS public\.idx_gamification_member/i,
    'redundant bare (member_id) index dropped');
  assert.match(code, /CREATE INDEX IF NOT EXISTS idx_cp_member_status\s+ON public\.course_progress \(member_id, status\)/i,
    'status-filtered course_progress index added');
  // the issue's proposed (course_id, member_id) is intentionally NOT added (redundant with
  // the existing UNIQUE course_progress_member_id_course_id_key).
  assert.ok(!/course_progress \(course_id, member_id\)/.test(code),
    '(course_id, member_id) intentionally NOT added (redundant)');
});

test('576 static: defensive REVOKE FROM PUBLIC,anon re-applied for both functions', () => {
  assert.match(code, /REVOKE ALL ON FUNCTION public\.get_tribe_gamification\(integer\) FROM PUBLIC, anon/i);
  assert.match(code, /REVOKE ALL ON FUNCTION public\.get_initiative_gamification\(uuid\) FROM PUBLIC, anon/i);
});

// ── BEHAVIOURAL (DB-gated) ──────────────────────────────────────────────────────────
test('576 DB: auth gate intact on BOTH RPC paths (no-auth → in-band Unauthorized)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // service-role caller has no auth.uid() -> gate fires
  const { data: dt, error: et } = await sb.rpc('get_tribe_gamification', { p_tribe_id: TRIBE8 });
  assert.ifError(et);
  assert.equal(dt?.error, 'Unauthorized', 'tribe path gate holds');
  // standalone path (item-5 reorder must still gate after resolve_tribe_id)
  const { data: di, error: ei } = await sb.rpc('get_initiative_gamification', { p_initiative_id: MESA });
  assert.ifError(ei);
  assert.equal(di?.error, 'Unauthorized', 'standalone path gate holds after delegation reorder');
});

test('576 DB: get_attendance_rate (the SSOT) is still present & callable for other consumers', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { error } = await sb.rpc('get_attendance_rate', {
    p_member_id: '00000000-0000-0000-0000-000000000000', p_cycle_start: null,
  });
  assert.ifError(error, 'get_attendance_rate remains the canonical SSOT (only the cockpit stopped calling it per-member)');
});
