/**
 * Contract test for #1011 (#987 follow-up) — curation_review_log must not grant `anon` any
 * object-level privilege. RLS already denies the reachable writes (deny-all SELECT + the
 * authenticated-only INSERT policy); this is the defense-in-depth REVOKE flagged at the #987
 * close. anon held {DELETE, INSERT, REFERENCES, TRIGGER, TRUNCATE, UPDATE} before the fix.
 *
 * Static migration guard (offline). Non-no-op: without the REVOKE migration the assertion
 * fails. (A live grant assertion is not run in CI — table grants aren't exposed via a
 * PostgREST-reachable RPC; the applied state was verified out-of-band: anon → 0 privileges.)
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION = join(__dirname, '../../supabase/migrations/20260805000312_1011_revoke_anon_dml_curation_review_log.sql');
const sql = existsSync(MIGRATION) ? readFileSync(MIGRATION, 'utf8') : '';

test('#1011 migration REVOKEs ALL on curation_review_log FROM anon', () => {
  assert.ok(sql, `migration missing at expected path: ${MIGRATION}`);
  assert.ok(
    /REVOKE\s+ALL\s+ON\s+public\.curation_review_log\s+FROM\s+anon/i.test(sql),
    'must contain: REVOKE ALL ON public.curation_review_log FROM anon',
  );
});

test('#1011 the REVOKE targets ONLY anon (authenticated + service_role keep their grants)', () => {
  assert.ok(sql);
  // Anchor on the actual statement (not a comment mention of "REVOKE") and capture its
  // grantee list — must be exactly `anon`.
  const m = sql.match(/REVOKE\s+ALL\s+ON\s+public\.curation_review_log\s+FROM\s+([^;]*);/i);
  assert.ok(m, 'REVOKE ALL ON public.curation_review_log FROM ... statement present');
  const grantees = m[1];
  assert.ok(
    !/\bauthenticated\b/i.test(grantees) && !/\bservice_role\b/i.test(grantees),
    `the REVOKE grantee list must be only anon, got: ${grantees.trim()}`,
  );
});
