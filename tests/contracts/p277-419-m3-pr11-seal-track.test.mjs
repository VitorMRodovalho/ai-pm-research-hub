/**
 * Contract: p277 / #419 (ADR-0100) metric 3 — PR11: roster seal track.
 *
 * Locks the seal mechanism this migration ships so a future change cannot silently regress it. Structural
 * checks are STATIC over migration 20260805000079 (the canonical p175-gate style). Two behavioural checks are
 * DB-gated against the live RPCs.
 *
 *   1. SEAL PRIMITIVE — events.roster_sealed_at + seal_event_attendance(p_event_id):
 *      • resolves eligibility ONLY through the canonical primitive _attendance_eligible_events (SPEC §3b — no
 *        parallel tag/audience-rule model);
 *      • materializes absent rows (present=false, excused=false) for eligible no-shows in the operational-union
 *        cohort (researcher/tribe_leader/manager + is_active + current_cycle_active — identical to
 *        get_attendance_engagement_summary 'global'), ON CONFLICT (event_id, member_id) DO NOTHING (idempotent,
 *        non-destructive); gated by can_by_member('manage_event'), fail-closed; sets roster_sealed_at.
 *      • grant ladder: REVOKE PUBLIC/anon, GRANT authenticated + service_role; never anon.
 *
 *   2. SEALING-SAFETY of auto_complete_first_meeting — the AFTER INSERT trigger now fires only on the member's
 *      first PRESENT row (NEW.present = true), so a sealed ABSENT row cannot complete the 'first_meeting'
 *      onboarding step.
 *
 *   3. ENGAGEMENT ≤ RELIABILITY invariant (SPEC §2 / §6) — engagement is the honest endpoint; reliability is the
 *      near-100% diagnostic that sealing converges DOWN toward. Asserted DB-gated over the live summaries.
 *
 * NOTE (verified live this session, NOT mutated — documented in the migration header): sync_attendance_points
 * already awards XP only WHERE a.present = true, and detect_and_notify_detractors's "missed" predicate is
 * already NOT EXISTS(... a.present = true ...) — both are sealing-safe by construction, so PR11 leaves their
 * bodies untouched. (Source text of an arbitrary live function is not reachable via the test client, so these
 * are forward-defended by the migration header + PR body, not a brittle in-test grep.)
 *
 * Cross-ref: SPEC_419_M3_ATTENDANCE_TWO_METRIC.md §2.2 + §3 + §3b + §7 PR11; ADR-0100; issue #419.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const SPEC = resolve(ROOT, 'docs/specs/SPEC_419_M3_ATTENDANCE_TWO_METRIC.md');
const MIG = resolve(ROOT, 'supabase/migrations/20260805000079_p277_419_m3_pr11_seal_track.sql');

const spec = existsSync(SPEC) ? readFileSync(SPEC, 'utf8') : '';
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const mig = migRaw.replace(/^\s*--.*$/gm, ''); // strip SQL line-comments (prose mentions retired models)

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC: migration exists + column ───────────────────────────────────────────
test('PR11 static: migration adds events.roster_sealed_at', () => {
  assert.ok(existsSync(MIG), 'PR11 migration exists');
  assert.match(mig, /ALTER TABLE public\.events ADD COLUMN IF NOT EXISTS roster_sealed_at timestamptz/,
    'adds the roster_sealed_at column');
  assert.match(migRaw, /COMMENT ON COLUMN public\.events\.roster_sealed_at/, 'documents the column');
});

// ── STATIC: seal_event_attendance shape ─────────────────────────────────────────
test('PR11 static: seal_event_attendance is SECURITY DEFINER with a pinned search_path, RETURNS jsonb', () => {
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.seal_event_attendance\(p_event_id uuid\)/,
    'defines seal_event_attendance(uuid)');
  assert.match(mig, /RETURNS jsonb/, 'returns jsonb');
  assert.match(mig, /SECURITY DEFINER/, 'SECURITY DEFINER');
  assert.match(mig, /SET search_path TO 'public', 'pg_temp'/, 'pinned search_path');
});

test('PR11 static: seal resolves eligibility ONLY through the canonical primitive (SPEC §3b)', () => {
  assert.match(mig, /public\._attendance_eligible_events\(m\.id, NULL\)/,
    'seal consumes _attendance_eligible_events');
  for (const banned of ['event_tag_assignments', "'general_meeting'", "'tribe_meeting'", 'event_audience_rules',
                        'is_event_mandatory_for_member']) {
    assert.ok(!mig.includes(banned), `seal must NOT reintroduce a parallel eligibility model (${banned})`);
  }
});

test('PR11 static: seal materializes absent rows (present=false, excused=false), idempotent + non-destructive', () => {
  // the INSERT projects present=false, excused=false for the no-show roster
  assert.match(mig, /INSERT INTO public\.attendance[\s\S]*?\bfalse,\s*false,/,
    'inserts present=false, excused=false absent rows');
  assert.match(mig, /ON CONFLICT \(event_id, member_id\) DO NOTHING/,
    'ON CONFLICT (event_id, member_id) DO NOTHING — never overwrites a real row');
});

test('PR11 static: seal cohort is the operational union (matches engagement summary global)', () => {
  assert.match(mig, /operational_role IN \('researcher','tribe_leader','manager'\)/, 'operational-union roles');
  assert.match(mig, /is_active = true/, 'is_active filter');
  assert.match(mig, /current_cycle_active = true/, 'current_cycle_active filter');
});

test('PR11 static: seal is gated by manage_event (fail-closed) and sets roster_sealed_at', () => {
  assert.match(mig, /IF NOT public\.can_by_member\(v_caller_id, 'manage_event'\) THEN/, 'manage_event gate');
  assert.match(mig, /IF v_caller_id IS NULL THEN[\s\S]*?'Not authenticated'/, 'fail-closed for no-member caller');
  assert.match(mig, /UPDATE public\.events SET roster_sealed_at = COALESCE\(roster_sealed_at, now\(\)\)/,
    'stamps roster_sealed_at (preserving first-seal time)');
  // guards: cancelled + future events cannot be sealed
  assert.match(mig, /v_status = 'cancelled'/, 'rejects cancelled events');
  assert.match(mig, /v_date > CURRENT_DATE/, 'rejects future events');
});

test('PR11 static: grant ladder — REVOKE PUBLIC/anon, GRANT authenticated + service_role, never anon', () => {
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.seal_event_attendance\(uuid\) FROM PUBLIC, anon/,
    'revokes PUBLIC + anon');
  assert.match(mig, /GRANT EXECUTE ON FUNCTION public\.seal_event_attendance\(uuid\) TO authenticated, service_role/,
    'grants authenticated + service_role');
  assert.ok(!/GRANT EXECUTE ON FUNCTION public\.seal_event_attendance\(uuid\) TO [^;]*\banon\b/.test(mig),
    'never grants seal to anon');
});

// ── STATIC: sealing-safety of the onboarding trigger ────────────────────────────
test('PR11 static: auto_complete_first_meeting fires only on the first PRESENT row (sealing-safety)', () => {
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.auto_complete_first_meeting\(\)/,
    'recreates the trigger function');
  assert.match(mig, /IF NEW\.present = true AND NOT EXISTS/, 'guards the outer condition with NEW.present = true');
  assert.match(mig, /a\.member_id = NEW\.member_id AND a\.id != NEW\.id AND a\.present = true/,
    'inner NOT EXISTS only considers prior PRESENT rows');
});

test('PR11 static: auto_detect_onboarding_completions batch twin guards first_meeting with present=true', () => {
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.auto_detect_onboarding_completions\(\)/,
    'recreates the batch onboarding-completion function');
  // the first_meeting batch INSERT must be present-guarded (the twin of the trigger fix)
  assert.match(mig, /'first_meeting'[\s\S]*?FROM attendance a\s+WHERE a\.present = true/,
    "batch first_meeting completion requires a present=true row");
});

// ── STATIC: SPEC §7 records PR11 shipped ────────────────────────────────────────
test('PR11 static: SPEC §7 names the seal track and marks PR11 shipped', () => {
  assert.ok(existsSync(SPEC), 'SPEC exists');
  assert.match(spec, /PR11\s*[—-]\s*Seal track/i, 'SPEC §7 names PR11 the seal track');
  assert.match(spec, /roster_sealed_at/, 'SPEC names the roster_sealed_at column');
  assert.match(spec, /seal_event_attendance/, 'SPEC names the seal RPC');
  assert.match(spec, /PR11[\s\S]{0,260}✅ SHIPPED/i, 'SPEC §7 marks PR11 shipped');
});

// ── DB-GATED: seal gate-closes for a no-member caller (no anon/leak path) ────────
test('PR11 C-db: seal_event_attendance gate-closes for a no-member caller', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // nonexistent event UUID + no JWT subject ⇒ returns BEFORE any insert (auth check first). Read-only/no mutation.
  const { data, error } = await sb.rpc('seal_event_attendance',
    { p_event_id: '00000000-0000-0000-0000-000000000000' });
  assert.ok(!error, error?.message);
  assert.ok(data && data.success === false, 'no-member caller is refused (success:false)');
  assert.match(String(data.error || ''), /Not authenticated|Acesso negado/, 'gate fail-closed message');
});

// ── DB-GATED: engagement ≤ reliability invariant (sealing converges reliability DOWN) ──
test('PR11 C-db: engagement avg_rate ≤ reliability avg_rate (the honest-vs-diagnostic invariant)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const eng = await sb.rpc('get_attendance_engagement_summary',
    { p_scope: 'global', p_scope_id: null, p_cycle_start: null, p_chapter: null });
  const rel = await sb.rpc('get_attendance_reliability_summary',
    { p_scope: 'global', p_scope_id: null, p_cycle_start: null, p_chapter: null });
  assert.ok(!eng.error, eng.error?.message);
  assert.ok(!rel.error, rel.error?.message);
  const e = Number(eng.data?.avg_rate), r = Number(rel.data?.avg_rate);
  assert.ok(Number.isFinite(e) && Number.isFinite(r), 'both summaries return a numeric avg_rate');
  assert.ok(e <= r + 1e-9, `engagement (${e}) must be ≤ reliability (${r}) — reliability is the near-100% diagnostic`);
});
