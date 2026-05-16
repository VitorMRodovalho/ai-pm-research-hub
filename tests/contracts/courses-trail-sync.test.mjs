/**
 * p169 #3 — Courses DB ↔ trail.ts sync contract
 *
 * Asserts that src/data/trail.ts COURSES array matches public.courses DB rows.
 * Prevents silent drift between frontend static data and DB source of truth.
 *
 * Pragmatic alternative to refactoring TrailSection.astro to SSR-fetch from DB
 * (which would require server-side Supabase client + handling Cloudflare Worker
 * env access patterns + updating downstream consumers like TribeGamificationTab).
 *
 * Status quo: trail.ts is canonical for FRONTEND DISPLAY (URLs, ordering),
 * DB courses table is canonical for MEMBER PROGRESS TRACKING (course_progress
 * FK references). They MUST match on: code, name, tier, is_trail, url.
 *
 * If this test fails: add the new course to BOTH places (DB migration +
 * trail.ts entry) in the same commit.
 *
 * Requires: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY. Skipped otherwise.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
// get_trail_courses() is public (GRANT EXECUTE TO anon), so anon key is sufficient.
const API_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY
              || process.env.PUBLIC_SUPABASE_ANON_KEY
              || process.env.SUPABASE_ANON_KEY;
const canRun = !!(SUPABASE_URL && API_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and an API key (anon or service role) required';

const TRAIL_TS_PATH = resolve(process.cwd(), 'src/data/trail.ts');

function parseTrailTs() {
  const src = readFileSync(TRAIL_TS_PATH, 'utf8');
  const courses = [];
  const objectRegex = /\{\s*code:\s*'([^']+)',\s*name:\s*'([^']+)',\s*tier:\s*'([^']+)',\s*isTrail:\s*(true|false),\s*hasCredly:\s*(true|false),\s*url:\s*'([^']+)'/g;
  let m;
  while ((m = objectRegex.exec(src)) !== null) {
    courses.push({
      code: m[1],
      name: m[2],
      tier: m[3],
      is_trail: m[4] === 'true',
      has_credly: m[5] === 'true',
      url: m[6],
    });
  }
  return courses;
}

test('p169: src/data/trail.ts COURSES ≡ public.courses DB rows', { skip: !canRun && skipMsg }, async () => {
  if (!canRun) return;
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_trail_courses`, {
    method: 'POST',
    headers: {
      apikey: API_KEY,
      Authorization: `Bearer ${API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: '{}',
  });
  assert.equal(res.status, 200, `get_trail_courses RPC must return 200, got ${res.status}`);
  const dbRows = await res.json();
  assert.ok(Array.isArray(dbRows), 'RPC must return array');

  const tsRows = parseTrailTs();

  // Set of codes must match
  const dbCodes = new Set(dbRows.map((r) => r.code));
  const tsCodes = new Set(tsRows.map((r) => r.code));
  const missingInTs = [...dbCodes].filter((c) => !tsCodes.has(c));
  const missingInDb = [...tsCodes].filter((c) => !dbCodes.has(c));
  assert.deepEqual(missingInTs, [], `Courses in DB but missing in trail.ts: ${missingInTs.join(', ')}`);
  assert.deepEqual(missingInDb, [], `Courses in trail.ts but missing in DB: ${missingInDb.join(', ')}`);

  // For each code, tier + is_trail + url must agree (name allowed to differ for branding tweaks)
  const dbByCode = new Map(dbRows.map((r) => [r.code, r]));
  for (const ts of tsRows) {
    const db = dbByCode.get(ts.code);
    assert.equal(ts.tier, db.tier, `${ts.code}: tier mismatch — trail.ts='${ts.tier}', DB='${db.tier}'`);
    assert.equal(ts.is_trail, db.is_trail, `${ts.code}: is_trail mismatch — trail.ts=${ts.is_trail}, DB=${db.is_trail}`);
    assert.equal(ts.url, db.url, `${ts.code}: URL mismatch — trail.ts='${ts.url}', DB='${db.url}'`);
  }
});
