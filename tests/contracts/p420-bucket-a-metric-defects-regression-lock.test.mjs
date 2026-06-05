/**
 * #420 — Bucket-A metric defects regression-lock.
 *
 * SEDIMENT-244.A: the 4 defects in #420 were verified live (2026-06-04) to be
 * ALREADY FIXED by the #419 M3 canonical-attendance refactor (the issue's
 * readiness tag was stale). This test LOCKS those fixes so they cannot silently
 * regress (they are proven-regression-prone — they happened once already).
 *
 *   - D14  get_dropout_risk_members: no longer matches ENGLISH event-type tokens
 *          (live events.type is 100% Portuguese); uses _attendance_eligible_events
 *          + present IS TRUE. Previously returned 0 rows always (dead alert).
 *   - D6   get_attendance_grid present_count counts status='present' (which
 *          requires a.present = true), NOT bare a.id IS NOT NULL (~4.5% overstate).
 *   - D12  get_events_with_attendance.attendee_count filters a.present = true.
 *
 * D10 (exec_portfolio_health hardcoded 'cycle3-2026' default) is NOT a data bug —
 * cycle3-2026 is the only/current portfolio_kpi_targets cycle and there is a
 * most-recent fallback; left as documented maintainability, not locked here.
 *
 * DB-gated (live prosrc via _audit_list_public_function_bodies) — these functions
 * were last declared across several #419 M3 migrations, so a live-body check is the
 * reliable guard (skips locally; runs in CI).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

async function bodies(names) {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('_audit_list_public_function_bodies', { p_names: names });
  assert.ok(!error, error?.message);
  assert.ok(Array.isArray(data), 'helper returns rows');
  const map = {};
  for (const r of data) map[r.proname] = r.prosrc || '';
  return map;
}

test('D14: get_dropout_risk_members has no English event-type tokens + uses canonical eligible events', { skip: dbGated ? false : skipMsg }, async () => {
  const { get_dropout_risk_members: src } = await bodies(['get_dropout_risk_members']);
  assert.ok(src, 'body present');
  for (const tok of ['general_meeting', 'tribe_meeting', 'leadership_meeting']) {
    assert.ok(!src.includes(tok), `must not match the English event-type token '${tok}' (live events.type is Portuguese — caused 0 rows always)`);
  }
  assert.match(src, /_attendance_eligible_events/, 'must derive eligible events from the canonical helper');
  assert.match(src, /present IS TRUE/i, 'must detect presence via present IS TRUE');
});

test("D6: get_attendance_grid present_count counts status='present' (requires a.present=true)", { skip: dbGated ? false : skipMsg }, async () => {
  const { get_attendance_grid: src } = await bodies(['get_attendance_grid']);
  assert.ok(src, 'body present');
  assert.match(src, /FILTER \(WHERE cs\.status = 'present'\)/, "present_count must count the 'present' status bucket");
  assert.match(src, /a\.present = t/i, "the 'present' status must require a.present = true");
  // regression guard: presence must not be counted by bare row-existence
  assert.ok(!/count\([^)]*a\.id[^)]*\)\s+FILTER/i.test(src) && !/count\(a\.id\)/i.test(src),
    'presence must not be counted via count(a.id) / row-existence');
});

test('D12: get_events_with_attendance.attendee_count filters a.present = true', { skip: dbGated ? false : skipMsg }, async () => {
  const { get_events_with_attendance: src } = await bodies(['get_events_with_attendance']);
  assert.ok(src, 'body present');
  assert.match(src, /a\.present = true\)\s+AS attendee_count/i,
    'attendee_count must count only present=true rows (not all attendance rows incl absent/excused)');
});
