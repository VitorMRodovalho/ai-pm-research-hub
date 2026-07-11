/**
 * #1321 — get_events_with_attendance must return i_attended (per-caller).
 *
 * Root cause of the "Check-In button never turns off" bug: the frontend
 * (src/pages/attendance.astro) branches the check-in button on `ev.i_attended`,
 * but the RPC never returned that column, so it was always undefined -> the button
 * stayed active even after the member checked in. This test locks the contract on
 * BOTH sides so the silent drift cannot come back.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const read = (p) => readFileSync(join(REPO_ROOT, p), 'utf8');

function latestRpcMigration() {
  const dir = 'supabase/migrations';
  return readdirSync(join(REPO_ROOT, dir))
    .filter((f) => f.endsWith('.sql'))
    .map((f) => read(join(dir, f)))
    .filter((s) => s.includes('FUNCTION public.get_events_with_attendance'))
    .pop();
}

test('a migration defines get_events_with_attendance with an i_attended column', () => {
  const src = latestRpcMigration();
  assert.ok(src, 'a migration must define get_events_with_attendance');
  assert.match(src, /i_attended boolean/, 'RETURNS TABLE must include i_attended boolean');
  assert.match(src, /EXISTS\s*\(/, 'i_attended must be derived from an EXISTS over attendance');
  assert.match(src, /a\.member_id\s*=\s*\(SELECT\s+m\.id\s+FROM\s+public\.members\s+m\s+WHERE\s+m\.auth_id\s*=\s*auth\.uid\(\)\)/,
    'i_attended must scope to the CURRENT caller (auth.uid -> members.id)');
});

test('attendance.astro shows a confirmed state when i_attended is true (not an empty branch)', () => {
  const src = read('src/pages/attendance.astro');
  assert.match(src, /ev\.i_attended !== true/, 'button gate must branch on ev.i_attended');
  assert.match(src, /I18N\.attendanceConfirmed/, 'the i_attended===true branch must render the confirmed pill');
  // the old dead `)) : ''}` empty branch must be gone
  assert.doesNotMatch(src, /\)\)\s*:\s*''\}/, 'the empty i_attended===true branch must be replaced by the confirmed pill');
});

test("i18n key 'attendance.confirmed' exists in all three dictionaries", () => {
  for (const d of ['pt-BR', 'en-US', 'es-LATAM']) {
    const src = read(`src/i18n/${d}.ts`);
    assert.match(src, /'attendance\.confirmed':/, `${d} must define 'attendance.confirmed'`);
  }
});

test('DB: get_events_with_attendance returns an i_attended field (skipped without creds)', async (t) => {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return t.skip('SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set');
  const res = await fetch(`${url}/rest/v1/rpc/get_events_with_attendance`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_limit: 1, p_offset: 0 }),
  });
  if (!res.ok) assert.fail(`RPC call failed: ${res.status} ${await res.text()}`);
  const rows = await res.json();
  if (rows.length === 0) return t.skip('no events to inspect');
  assert.ok(Object.prototype.hasOwnProperty.call(rows[0], 'i_attended'),
    'RPC response rows must include the i_attended field');
});
