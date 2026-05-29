/**
 * Contract: p277 / #419 (ADR-0100) metric 3 step 3a — attendance present-detection bugs.
 *
 * D6: get_attendance_grid classified ANY non-excused attendance row as 'present', mis-promoting
 *   explicit-absent rows (present=false, excused=false). The other two grids already check
 *   a.present=true — only this one was wrong. Fixed to distinguish present=true from present=false.
 * D12: get_events_with_attendance.attendee_count counted ALL attendance rows (present+absent+excused)
 *   but its sole consumer (attendance.astro) renders it "N presentes". Fixed to present=true,
 *   matching list_meetings_with_notes + get_meeting_detail.
 *
 * Live before-impact: 6 absent-not-excused rows (D6); 28 events over-counted / 63 non-present rows (D12).
 * Live after: grid distinguishes present=true; sum(attendee_count) 1394→1331 == raw present count.
 *
 * Migration: supabase/migrations/20260805000064_p277_419_m3a_attendance_present_detection_bugs.sql
 * Cross-ref: ADR-0100 §2.2/§3.3 · audit D6/D12.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000064_p277_419_m3a_attendance_present_detection_bugs.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

test('m3a D6: get_attendance_grid same-signature CREATE OR REPLACE, distinguishes present=true', () => {
  assert.ok(existsSync(MIG));
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_attendance_grid\(p_tribe_id integer DEFAULT NULL::integer, p_event_type text DEFAULT NULL::text\)/i);
  assert.ok(!/DROP FUNCTION/i.test(body), 'same signature → no DROP');
  assert.match(body, /WHEN a\.id IS NOT NULL AND a\.present = true THEN 'present'\s*\n\s*WHEN a\.id IS NOT NULL THEN 'absent'/i, 'present=true → present, any other existing row → absent');
  assert.match(body, /STABLE SECURITY DEFINER/i);
  assert.match(body, /SET search_path TO 'public', 'pg_temp'/i);
});

test('m3a D6 forward-defense: the bare non-excused→present promotion must not reappear', () => {
  // strip line comments first — the ROLLBACK note legitimately quotes the old buggy pattern
  const code = body.replace(/--[^\n]*/g, '');
  // the buggy classification ("WHEN a.id IS NOT NULL THEN 'present'", no present check) must be gone
  assert.ok(!/a\.id IS NOT NULL THEN 'present'/i.test(code), 'no bare a.id-IS-NOT-NULL → present promotion');
});

test('m3a D12: get_events_with_attendance attendee_count filters present=true (same signature)', () => {
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_events_with_attendance\(p_limit integer DEFAULT 500, p_offset integer DEFAULT 0\)/i);
  assert.match(body, /count\(\*\) FROM public\.attendance a WHERE a\.event_id = e\.id AND a\.present = true\) AS attendee_count/i, 'present-only count');
  assert.match(body, /NOTIFY\s+pgrst/i);
});

test('m3a D12 forward-defense: attendee_count must not count all attendance rows', () => {
  assert.ok(!/count\(\*\) FROM public\.attendance a WHERE a\.event_id = e\.id\) AS attendee_count/i.test(body), 'attendee_count must not be the all-rows count (no present filter)');
});

// ── DB-gated ──────────────────────────────────────────────────────────────────
test('m3a D12 DB: attendee_count is present-only (no absent/excused inflation)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_events_with_attendance', { p_limit: 500, p_offset: 0 });
  assert.ok(!error, error?.message);
  const rows = data || [];
  const sumAttendee = rows.reduce((s, e) => s + Number(e.attendee_count || 0), 0);
  const { count: totalPresent } = await sb.from('attendance').select('id', { count: 'exact', head: true }).eq('present', true);
  if (rows.length < 500) {
    // all events returned → every present row belongs to a returned event → totals must match
    assert.equal(sumAttendee, totalPresent, 'sum(attendee_count) must equal total present attendance rows (present-only)');
  } else {
    assert.ok(sumAttendee <= totalPresent, 'attendee_count sum cannot exceed total present rows');
  }
});

test('m3a D12 DB: gate-free RPC still returns rows (regression that the fix did not break the shape)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_events_with_attendance', { p_limit: 5, p_offset: 0 });
  assert.ok(!error, error?.message);
  assert.ok(Array.isArray(data), 'returns a table');
  if (data.length) assert.ok(Object.prototype.hasOwnProperty.call(data[0], 'attendee_count'), 'attendee_count column preserved');
});
