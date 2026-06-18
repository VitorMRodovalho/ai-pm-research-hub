/**
 * Contract: ÉPICO D — detect_stuck_selection_funnel (detecção + nudge ao GP do
 * stuck pós-convite). #766 follow-up, PR DB-first. SPEC:
 * docs/specs/SPEC_D_STUCK_FUNNEL_DETECTION.md. Migration: 20260805000208.
 *
 * Surfaces two post-invite stall classes the existing overdue cron misses:
 *   A) invited_never_booked — invited (cutoff_approved_email_sent_at set), no
 *      selection_interviews row, aged past interview_booking_grace (= D5);
 *   B) noshow_not_recovered — has a no-show row, no recovery after it, no future
 *      slot, aged past noshow_recovery_grace (= D3).
 * Notifies GP managers (operational_role='manager') — ADR-0011 Amendment A
 * fast-path fan-out. No schema invariant (ephemeral detection). 7-day idempotency.
 *
 * Council: data-architect GO-with-changes (booking_grace=10d, managers-only,
 * source_type='selection_application', bucket B qualified by created_at).
 * DB assertions are read-only / dry-run and do NOT pin volatile prod cohort counts.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');
const MIG = read('supabase/migrations/20260805000208_d_stuck_funnel_detection.sql');
const CATALOG = JSON.parse(read('docs/adr/ADR-0022-notification-types-catalog.json') || '{"types":{}}');

// Slice the RPC body, anchored on CREATE FUNCTION (NOT on ROLLBACK comments that
// may name a DROP) — sediment: comment-naming a function breaks naive slicing.
const FN = (() => {
  const m = MIG.match(/CREATE OR REPLACE FUNCTION public\.detect_stuck_selection_funnel[\s\S]*?\$function\$([\s\S]*?)\$function\$/);
  return m ? m[1] : '';
})();

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── Offline: migration shape ───────────────────────────────────────────────────
test('migration file exists and declares the RPC SECURITY DEFINER / search_path / jsonb / dry-run-default', () => {
  assert.ok(MIG, 'migration 20260805000208 exists');
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.detect_stuck_selection_funnel\(p_dry_run boolean DEFAULT true\)/);
  assert.match(MIG, /SECURITY DEFINER/);
  assert.match(MIG, /SET search_path TO ''/);
  assert.match(MIG, /RETURNS jsonb/);
});

test('seeds 2 new SLA windows (booking 10d, noshow 3d) as category=sla, idempotent', () => {
  assert.match(MIG, /'interview_booking_grace', interval '10 days', 'sla'/);
  assert.match(MIG, /'noshow_recovery_grace', interval '3 days', 'sla'/);
  assert.match(MIG, /ON CONFLICT \(policy_key\) DO NOTHING/);
});

test('reads both windows from sla_policies with a fallback literal (J4 config-driven pattern)', () => {
  assert.match(FN, /policy_key = 'interview_booking_grace'/);
  assert.match(FN, /v_booking_grace := interval '10 days'/);
  assert.match(FN, /policy_key = 'noshow_recovery_grace'/);
  assert.match(FN, /v_noshow_grace := interval '3 days'/);
});

test('bucket A (invited_never_booked): invited + reschedule-NULL + no interview row + past grace', () => {
  assert.match(FN, /cutoff_approved_email_sent_at IS NOT NULL/);
  assert.match(FN, /interview_reschedule_requested_at IS NULL/);
  assert.match(FN, /cutoff_approved_email_sent_at < now\(\) - v_booking_grace/);
  // "never booked" = NO selection_interviews row at all
  assert.match(FN, /NOT EXISTS\s*\(\s*SELECT 1 FROM public\.selection_interviews si WHERE si\.application_id = a\.id\s*\)/);
});

test('bucket B (noshow_not_recovered): noshow + no recovery AFTER last noshow + no future slot', () => {
  assert.match(FN, /si\.status = 'noshow'/);
  assert.match(FN, /ns\.last_noshow_at < now\(\) - v_noshow_grace/);
  // recovery qualified temporally — created_at > last noshow (no false-negative for completed-before-noshow)
  assert.match(FN, /si2\.status IN \('scheduled', 'completed'\)[\s\S]*?si2\.created_at > ns\.last_noshow_created/);
  // future-slot exclusion (excludes legit reschedule like Hanae)
  assert.match(FN, /si3\.status IN \('scheduled', 'rescheduled'\)[\s\S]*?si3\.scheduled_at > now\(\)/);
});

test('scope = ACTIVE cycle + status interview_pending', () => {
  assert.match(FN, /FROM public\.selection_cycles ORDER BY created_at DESC LIMIT 1/);
  assert.match(FN, /a\.status = 'interview_pending'/);
});

test('fan-out to GP managers only (ADR-0011 Amendment A documented)', () => {
  assert.match(FN, /m\.operational_role = 'manager'/);
  assert.match(MIG, /Amendment A/i);
});

test('7-day idempotency keyed on (recipient, source_application, the 2 new types)', () => {
  assert.match(FN, /source_type = 'selection_application'/);
  assert.match(FN, /n\.source_id\s*=\s*t\.application_id/);
  assert.match(FN, /n\.type IN \('selection_candidate_unbooked', 'selection_noshow_unrecovered'\)/);
  assert.match(FN, /n\.created_at > now\(\) - interval '7 days'/);
});

test('INSERT derives delivery_mode via helper + dry-run gates the write', () => {
  assert.match(FN, /public\._delivery_mode_for\(ti\.n_type\)/);
  assert.match(FN, /WHERE NOT p_dry_run/);
});

test('grants: cron-only (REVOKE PUBLIC/anon/authenticated, GRANT service_role)', () => {
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.detect_stuck_selection_funnel\(boolean\) FROM PUBLIC, anon, authenticated/);
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.detect_stuck_selection_funnel\(boolean\) TO service_role/);
});

test('cron registered daily 16:00 UTC, idempotent unschedule, invokes the RPC', () => {
  assert.match(MIG, /cron\.unschedule\('detect-stuck-selection-funnel-daily'\)/);
  assert.match(MIG, /'detect-stuck-selection-funnel-daily',\s*'0 16 \* \* \*'/);
  assert.match(MIG, /SELECT public\.detect_stuck_selection_funnel\(p_dry_run := false\)/);
  assert.match(MIG, /NOTIFY pgrst, 'reload schema'/);
});

test('NO schema invariant added (ephemeral detection — does not touch check_schema_invariants)', () => {
  assert.ok(!/check_schema_invariants/.test(MIG), 'migration must not modify the invariant function');
});

test('ADR-0022 catalog registers both new types as digest_weekly (covered by ELSE; in-app immediate)', () => {
  for (const t of ['selection_candidate_unbooked', 'selection_noshow_unrecovered']) {
    assert.ok(CATALOG.types[t], `catalog has ${t}`);
    assert.equal(CATALOG.types[t].delivery_mode, 'digest_weekly', `${t} is digest_weekly`);
    assert.ok((CATALOG.types[t].rationale || '').length > 10, `${t} has a rationale`);
  }
});

test('relies on the existing _delivery_mode_for ELSE branch — must NOT redefine the helper', () => {
  // Deliberate deviation (review LOW): digest_weekly types resolve via the ELSE
  // default; adr-0022 helper-parity test skips digest_weekly types (line 95). This
  // PR must not transcribe the helper body (avoids Phase-C drift on that function).
  assert.ok(!/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\._delivery_mode_for/i.test(MIG),
    'PR must rely on the ELSE branch, not redefine _delivery_mode_for');
});

test('grounding: no hardcoded cohort numbers as facts (counts come from the live query, not the body)', () => {
  // The body must not bake in cohort sizes (e.g. the discovery "40/36/86"). Day-diffs
  // are computed via EXTRACT; the only integer literals allowed are the grace fallbacks,
  // the 7-day window, the cron minute (16/0), and the *::int / round() machinery.
  assert.ok(!/\b(40|36|86|84|57|66)\b/.test(FN), 'no discovery cohort numbers hardcoded in the RPC body');
});

// ── DB-gated: dry-run shape (no writes, no volatile-count pinning) ──────────────
test('DB: dry-run returns the envelope shape and never inserts (notified=0)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('detect_stuck_selection_funnel', { p_dry_run: true });
  assert.ok(!error, error?.message);
  assert.equal(data.success, true);
  assert.equal(data.dry_run, true);
  assert.equal(data.notified, 0, 'dry-run must never insert');
  // grace windows reflect the seeded config (10d / 3d) — config-driven, not pinned cohort.
  assert.equal(data.booking_grace_days, 10);
  assert.equal(data.noshow_grace_days, 3);
  // counts exist and are non-negative integers (do NOT pin the volatile value).
  assert.ok(Number.isInteger(data.unbooked_apps) && data.unbooked_apps >= 0);
  assert.ok(Number.isInteger(data.noshow_apps) && data.noshow_apps >= 0);
});

test('DB: both SLA windows are live in sla_policies', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.from('sla_policies').select('policy_key, value_interval')
    .in('policy_key', ['interview_booking_grace', 'noshow_recovery_grace']);
  assert.ok(!error, error?.message);
  const byKey = Object.fromEntries((data || []).map((r) => [r.policy_key, r.value_interval]));
  assert.equal(byKey['interview_booking_grace'], '10 days');
  assert.equal(byKey['noshow_recovery_grace'], '3 days');
});
