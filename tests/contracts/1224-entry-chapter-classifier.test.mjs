/**
 * #1224 (PR 1) — entry chapter is DERIVED from the PMI enrichment snapshot, not free text.
 *
 * Migration 20260805000386 adds:
 *   - classify_entry_chapter(pmi_memberships, community_profile_private, pmi_data_fetched_at)
 *     -> {bucket, active_br_codes}. Buckets: resolved | ambiguous | profile_private |
 *     no_fetch | not_affiliated. "PMI-active" = expiryDate >= today (membership_status is a
 *     null-trap). resolve_br_chapter_code maps "<State>, Brazil Chapter"/aliases to the code.
 *   - get_entry_chapter_diagnosis(cycle) — admin/service diagnosis over the approved cohort.
 *   - approve_selection_application — derives entry_chapter_code from a single active BR chapter
 *     and upserts every active BR affiliation (source='pmi_vep'); >1 active is left for
 *     self-declaration; 0 leaves the honest 'Outro'.
 *
 * Source-contract assertions run offline; the classifier + diagnosis + invariant U checks are
 * DB-aware (need SUPABASE_URL + SERVICE_ROLE_KEY; skip offline).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const MIG = readFileSync(
  fileURLToPath(new URL('../../supabase/migrations/20260805000386_1224_derive_entry_chapter_from_pmi_memberships.sql', import.meta.url)),
  'utf8',
);
// Comment-stripped view — executable SQL only.
const CODE = MIG.replace(/--.*$/gm, '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function rpc(fn, body) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body || {}),
  });
  if (!res.ok) throw new Error(`POST rpc/${fn} HTTP ${res.status}: ${await res.text()}`);
  return res.json();
}

const BUCKETS = new Set(['resolved', 'ambiguous', 'profile_private', 'no_fetch', 'not_affiliated']);
// Far-future date keeps "active" deterministic regardless of when the suite runs.
const FUTURE = '31 Dec 2099';

// ── Source contract (offline) ───────────────────────────────────────────────
test('1224: migration defines the pure classifier and admin diagnosis', () => {
  assert.match(CODE, /CREATE OR REPLACE FUNCTION public\.classify_entry_chapter\(/, 'classifier defined');
  assert.match(CODE, /CREATE OR REPLACE FUNCTION public\.get_entry_chapter_diagnosis\(/, 'diagnosis defined');
});

test('1224: approve derives the entry chapter from pmi_memberships (not free text)', () => {
  assert.match(CODE, /classify_entry_chapter\(\s*v_app\.pmi_memberships/, 'approve classifies the applicant enrichment');
  assert.match(CODE, /upsert_chapter_affiliation\(v_person_id, v_code, 'pmi_vep', false\)/, 'active BR chapters upserted as pmi_vep facts');
  assert.match(CODE, /array_length\(v_br_codes, 1\) = 1/, 'exactly-one-active gate for the governance entry');
  assert.match(CODE, /SET entry_chapter_code = v_entry_derived/, 'unambiguous single chapter sets entry_chapter_code');
});

test('1224: classifier is STABLE (never a data-mutating derivation)', () => {
  assert.match(CODE, /FUNCTION public\.classify_entry_chapter[\s\S]*?\bSTABLE\b/, 'classify_entry_chapter is STABLE');
});

// ── DB-aware: classifier buckets (deterministic synthetic inputs) ────────────
test('1224: classifier — single active BR chapter is resolved', { skip: canRun ? false : skipMsg }, async () => {
  const r = await rpc('classify_entry_chapter', {
    p_pmi_memberships: [{ chapterName: 'Goiás, Brazil Chapter', expiryDate: FUTURE }],
    p_community_profile_private: false,
    p_pmi_data_fetched_at: new Date().toISOString(),
  });
  assert.equal(r.bucket, 'resolved');
  assert.deepEqual(r.active_br_codes, ['GO']);
});

test('1224: classifier — two active BR chapters are ambiguous', { skip: canRun ? false : skipMsg }, async () => {
  const r = await rpc('classify_entry_chapter', {
    p_pmi_memberships: [
      { chapterName: 'Goiás, Brazil Chapter', expiryDate: FUTURE },
      { chapterName: 'Espírito Santo, Brazil Chapter', expiryDate: FUTURE },
    ],
    p_community_profile_private: false,
    p_pmi_data_fetched_at: new Date().toISOString(),
  });
  assert.equal(r.bucket, 'ambiguous');
  assert.equal(r.active_br_codes.length, 2);
});

test('1224: classifier — expired / PMI-Global-only fall through to not_affiliated', { skip: canRun ? false : skipMsg }, async () => {
  const expired = await rpc('classify_entry_chapter', {
    p_pmi_memberships: [{ chapterName: 'Goiás, Brazil Chapter', expiryDate: '30 Jun 2020' }],
    p_community_profile_private: false,
    p_pmi_data_fetched_at: new Date().toISOString(),
  });
  assert.equal(expired.bucket, 'not_affiliated');

  const globalOnly = await rpc('classify_entry_chapter', {
    p_pmi_memberships: [{ chapterName: 'PMI Global', expiryDate: FUTURE }],
    p_community_profile_private: false,
    p_pmi_data_fetched_at: new Date().toISOString(),
  });
  assert.equal(globalOnly.bucket, 'not_affiliated');
});

test('1224: classifier — missing-enrichment precedence: private > no_fetch', { skip: canRun ? false : skipMsg }, async () => {
  const priv = await rpc('classify_entry_chapter', {
    p_pmi_memberships: null, p_community_profile_private: true, p_pmi_data_fetched_at: null,
  });
  assert.equal(priv.bucket, 'profile_private', 'private wins even when fetch is also null');

  const noFetch = await rpc('classify_entry_chapter', {
    p_pmi_memberships: null, p_community_profile_private: false, p_pmi_data_fetched_at: null,
  });
  assert.equal(noFetch.bucket, 'no_fetch');
});

// ── DB-aware: diagnosis surface + invariant ──────────────────────────────────
test('1224: diagnosis returns only known buckets and stays classifier-consistent', { skip: canRun ? false : skipMsg }, async () => {
  const rows = await rpc('get_entry_chapter_diagnosis', {});
  assert.ok(Array.isArray(rows) && rows.length > 0, 'diagnosis returns the current cohort');
  for (const r of rows) {
    assert.ok(BUCKETS.has(r.bucket), `unknown bucket ${r.bucket}`);
    if (r.bucket === 'resolved') assert.equal((r.active_br_codes || []).length, 1, 'resolved => exactly one active code');
    if (r.bucket === 'ambiguous') assert.ok((r.active_br_codes || []).length > 1, 'ambiguous => more than one active code');
    if (r.bucket === 'profile_private' || r.bucket === 'no_fetch' || r.bucket === 'not_affiliated') {
      assert.equal((r.active_br_codes || []).length, 0, `${r.bucket} => no active codes`);
    }
  }
});

test('1224: derivation keeps invariant U (one primary affiliation) green', { skip: canRun ? false : skipMsg }, async () => {
  const rows = await rpc('check_schema_invariants', {});
  const u = (Array.isArray(rows) ? rows : []).find(
    (r) => r.invariant_name === 'U_active_person_has_primary_chapter_affiliation',
  );
  assert.ok(u, 'invariant U present');
  assert.equal(Number(u.violation_count), 0, 'invariant U must have 0 violations');
});
