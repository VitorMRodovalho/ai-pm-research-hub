/**
 * #1319 — self check-in window is a single source of truth.
 *
 * The window (hours after an event during which a member may self check-in via
 * register_own_presence) must have ONE value shared by:
 *   - DB: platform_settings 'attendance.self_checkin_window_hours' (server gate, seeded by migration)
 *   - Frontend: SELF_CHECKIN_WINDOW_HOURS in src/lib/attendance-window.ts (button show/hide mirror)
 *
 * Before #1319 the value 48 was hardcoded in ~12 places (RPC + 4 FE mirrors + 6 i18n strings),
 * so any change was a multi-file hunt and the FE could silently drift from the server gate.
 *
 * Static locks (run anywhere): migration seed value === FE constant; the FE mirrors read the
 * constant and carry no residual hardcoded window. Optional DB-aware lock when creds are present.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const read = (p) => readFileSync(join(REPO_ROOT, p), 'utf8');

const SETTING_KEY = 'attendance.self_checkin_window_hours';

function feConstant() {
  const src = read('src/lib/attendance-window.ts');
  const m = src.match(/export const SELF_CHECKIN_WINDOW_HOURS\s*=\s*(\d+)/);
  assert.ok(m, 'SELF_CHECKIN_WINDOW_HOURS must be a numeric literal in src/lib/attendance-window.ts');
  return Number(m[1]);
}

function migrationSeed() {
  const dir = 'supabase/migrations';
  const files = readdirSync(join(REPO_ROOT, dir)).filter((f) => f.endsWith('.sql'));
  let seed = null;
  for (const f of files) {
    const src = read(join(dir, f));
    // Locate the literal key, then read the first '<digits>'::jsonb that follows it.
    // String search (not a dynamic RegExp) keeps the SSOT key out of a regex source.
    const idx = src.indexOf(`'${SETTING_KEY}'`);
    if (idx === -1) continue;
    const m = src.slice(idx).match(/'(\d+)'::jsonb/); // last migration touching the key wins
    if (m) seed = Number(m[1]);
  }
  return seed;
}

test('FE constant is a positive integer', () => {
  const hours = feConstant();
  assert.ok(Number.isInteger(hours) && hours > 0, `SELF_CHECKIN_WINDOW_HOURS must be a positive int, got ${hours}`);
});

test('migration seeds platform_settings with the SAME value as the FE constant', () => {
  const seed = migrationSeed();
  assert.ok(seed !== null, `a migration must seed platform_settings '${SETTING_KEY}' with a jsonb integer`);
  assert.equal(seed, feConstant(),
    `platform_settings seed (${seed}) must equal SELF_CHECKIN_WINDOW_HOURS (${feConstant()}) — SSOT drift`);
});

test('server gate reads the setting (register_own_presence uses get_platform_setting + make_interval)', () => {
  const dir = 'supabase/migrations';
  const files = readdirSync(join(REPO_ROOT, dir)).filter((f) => f.endsWith('.sql'));
  const rpc = files
    .map((f) => read(join(dir, f)))
    .filter((s) => s.includes('CREATE OR REPLACE FUNCTION public.register_own_presence'))
    .pop();
  assert.ok(rpc, 'a migration must (re)define register_own_presence');
  assert.ok(rpc.includes(`get_platform_setting('${SETTING_KEY}')`),
    'register_own_presence must read the window from platform_settings (not a hardcoded interval)');
  assert.match(rpc, /make_interval\(hours\s*=>\s*v_window_hours\)/,
    'register_own_presence must build the window from the setting value');
});

test('FE check-in mirrors read the shared constant, not a hardcoded window', () => {
  const mirrors = [
    'src/components/workspace/MyMeetingsIsland.tsx',
    'src/components/attendance/AttendanceGrid.tsx',
    'src/components/tribes/TribeAttendanceTab.tsx',
    'src/pages/attendance.astro',
  ];
  for (const f of mirrors) {
    const src = read(f);
    assert.match(src, /SELF_CHECKIN_WINDOW_HOURS/, `${f} must reference SELF_CHECKIN_WINDOW_HOURS`);
    assert.doesNotMatch(src, /\b48\s*\*\s*60\s*\*\s*60\s*\*\s*1000\b/,
      `${f} still has a hardcoded 48h check-in window`);
    assert.doesNotMatch(src, /CHECKIN_WINDOW_H\s*=\s*48/, `${f} still has a hardcoded CHECKIN_WINDOW_H`);
  }
});

test('DB platform_settings matches the FE constant (skipped without creds)', async (t) => {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return t.skip('SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set');
  const res = await fetch(`${url}/rest/v1/platform_settings?key=eq.${encodeURIComponent(SETTING_KEY)}&select=value`, {
    headers: { apikey: key, Authorization: `Bearer ${key}` },
  });
  assert.ok(res.ok, `platform_settings query failed: ${res.status}`);
  const rows = await res.json();
  assert.equal(rows.length, 1, `expected exactly one platform_settings row for '${SETTING_KEY}'`);
  assert.equal(Number(rows[0].value), feConstant(),
    `DB platform_settings (${rows[0].value}) must equal SELF_CHECKIN_WINDOW_HOURS (${feConstant()})`);
});
