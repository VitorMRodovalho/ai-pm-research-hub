/**
 * #1224 (PR 1) — entry chapter is DERIVED from the PMI enrichment snapshot, not free text.
 *
 * Migration 20260805000386 adds:
 *   - classify_entry_chapter(pmi_memberships, community_profile_private, pmi_data_fetched_at)
 *     -> {bucket, active_br_codes}. Buckets: resolved | ambiguous | profile_private |
 *     no_fetch | not_affiliated. "PMI-active" = expiryDate >= today (membership_status is a
 *     null-trap). resolve_br_chapter_code maps "<State>, Brazil Chapter"/aliases to the code.
 *   - get_entry_chapter_diagnosis(cycle) — admin/service diagnosis over the approved cohort.
 *     Retired by #3170 (no caller left after the affiliation consolidation): the guard now asserts
 *     that the newest migration touching it DROPS it, and the bucket/codes consistency it used to
 *     check over the cohort is asserted on the classifier itself.
 *   - approve_selection_application — derives entry_chapter_code from a single active BR chapter
 *     and upserts every active BR affiliation (source='pmi_vep'); >1 active is left for
 *     self-declaration; 0 leaves the honest 'Outro'.
 *
 * Source-contract assertions run offline; the classifier + diagnosis + invariant U checks are
 * DB-aware (need SUPABASE_URL + SERVICE_ROLE_KEY; skip offline).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { unexpectedViolations, violationsMessage } from '../helpers/invariant-exceptions.mjs';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const MIG = readFileSync(
  fileURLToPath(new URL('../../supabase/migrations/20260805000386_1224_derive_entry_chapter_from_pmi_memberships.sql', import.meta.url)),
  'utf8',
);
// Comment-stripped view — executable SQL only.
const CODE = MIG.replace(/--.*$/gm, '');
// #1932/#3169: o classificador e afirmado contra a captura VIGENTE, nao contra o arquivo de origem.
const ROOT = process.cwd();
const CLS = latestFunctionCapture(ROOT, 'classify_entry_chapter');
const CLS_CODE = CLS.block.replace(/--.*$/gm, '');
// #3170: with the diagnosis retired, approval is the classifier's consumer. Current capture.
const APPROVE_CODE = latestFunctionCapture(ROOT, 'approve_selection_application').block.replace(/--.*$/gm, '');

/**
 * #3170: the newest migration whose EXECUTABLE SQL (line comments masked) names the function.
 * latestFunctionCapture only sees CREATE, so it keeps returning a dropped function's last body;
 * the retirement has to be read from the migration stream itself.
 */
function newestExecutableMention(name) {
  const dir = join(ROOT, 'supabase/migrations');
  const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
  for (let i = files.length - 1; i >= 0; i--) {
    const sql = maskLineComments(readFileSync(join(dir, files[i]), 'utf8'));
    if (sql.includes(name)) return { file: files[i], sql };
  }
  return null;
}
const DIAG = newestExecutableMention('get_entry_chapter_diagnosis');

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
test('1224: the pure classifier is defined; the admin diagnosis is retired (#3170)', () => {
  assert.match(CLS_CODE, /CREATE OR REPLACE FUNCTION public\.classify_entry_chapter\(/, 'classifier defined');
  assert.ok(DIAG, 'some migration must name get_entry_chapter_diagnosis (else this assertion reads the void)');
  // assert.ok, not match: a failing match would print the whole migration.
  assert.ok(
    /^\s*DROP\s+FUNCTION\s+public\.get_entry_chapter_diagnosis\(\s*uuid\s*\)\s*;/m.test(DIAG.sql),
    `the newest migration naming the diagnosis (${DIAG.file}) must DROP it`,
  );
  assert.ok(
    !/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.get_entry_chapter_diagnosis\s*\(/i.test(DIAG.sql),
    `${DIAG.file} must not recreate the diagnosis it retires`,
  );
});

test('1224: the classifier binds the bucket to the number of active codes', () => {
  // The invariant the diagnosis used to check over the cohort, read where it is decided.
  assert.match(
    CLS_CODE,
    /IF v_codes IS NOT NULL AND array_length\(v_codes, 1\) >= 1 THEN\s+RETURN jsonb_build_object\(\s*'bucket', CASE WHEN array_length\(v_codes, 1\) > 1 THEN 'ambiguous' ELSE 'resolved' END,\s*'active_br_codes', to_jsonb\(v_codes\)/,
    'one active code => resolved, more than one => ambiguous, codes returned with the bucket',
  );
  assert.match(
    CLS_CODE,
    /WHEN COALESCE\(p_community_profile_private, false\) THEN 'profile_private'\s+WHEN p_pmi_data_fetched_at IS NULL\s+THEN 'no_fetch'\s+ELSE 'not_affiliated'\s+END,\s+'active_br_codes', '\[\]'::jsonb/,
    'the three no-code buckets return an empty code list',
  );
});

test('1224: approve derives the entry chapter from pmi_memberships (not free text)', () => {
  assert.match(CODE, /classify_entry_chapter\(\s*v_app\.pmi_memberships/, 'approve classifies the applicant enrichment');
  assert.match(CODE, /upsert_chapter_affiliation\(v_person_id, v_code, 'pmi_vep', false\)/, 'active BR chapters upserted as pmi_vep facts');
  assert.match(CODE, /array_length\(v_br_codes, 1\) = 1/, 'exactly-one-active gate for the governance entry');
  assert.match(CODE, /SET entry_chapter_code = v_entry_derived/, 'unambiguous single chapter sets entry_chapter_code');
});

test('1224: classifier is STABLE (never a data-mutating derivation)', () => {
  assert.match(CLS_CODE, /FUNCTION public\.classify_entry_chapter\([^)]*\)\s+RETURNS jsonb\s+LANGUAGE plpgsql\s+STABLE\b/, 'classify_entry_chapter is STABLE');
});

test('1224: approval classifies the applicant and reads the codes the classifier returned (#3170)', () => {
  assert.match(
    APPROVE_CODE,
    /v_classify := public\.classify_entry_chapter\(\s*v_app\.pmi_memberships, v_app\.community_profile_private, v_app\.pmi_data_fetched_at\s*\);\s*v_br_codes := ARRAY\(SELECT jsonb_array_elements_text\(v_classify->'active_br_codes'\)\);/,
    'approve_selection_application must classify the applicant enrichment and take active_br_codes from that result',
  );
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

// ── DB-aware: classifier consistency + invariant ─────────────────────────────
// #3170: was asserted over get_entry_chapter_diagnosis (retired). Same rule, on the live
// classifier, over one synthetic input per bucket, so every bucket is reached.
const MATRIX = [
  { want: 'resolved', p_pmi_memberships: [{ chapterName: 'Goiás, Brazil Chapter', expiryDate: FUTURE }], p_community_profile_private: false, fetched: true },
  { want: 'ambiguous', p_pmi_memberships: [{ chapterName: 'Goiás, Brazil Chapter', expiryDate: FUTURE }, { chapterName: 'Espírito Santo, Brazil Chapter', expiryDate: FUTURE }], p_community_profile_private: false, fetched: true },
  { want: 'profile_private', p_pmi_memberships: null, p_community_profile_private: true, fetched: false },
  { want: 'no_fetch', p_pmi_memberships: null, p_community_profile_private: false, fetched: false },
  { want: 'not_affiliated', p_pmi_memberships: [{ chapterName: 'PMI Global', expiryDate: FUTURE }], p_community_profile_private: false, fetched: true },
];

test('1224: classifier returns only known buckets and stays code-consistent', { skip: canRun ? false : skipMsg }, async () => {
  const rows = [];
  for (const m of MATRIX) {
    const r = await rpc('classify_entry_chapter', {
      p_pmi_memberships: m.p_pmi_memberships,
      p_community_profile_private: m.p_community_profile_private,
      p_pmi_data_fetched_at: m.fetched ? new Date().toISOString() : null,
    });
    assert.equal(r.bucket, m.want);
    rows.push(r);
  }
  assert.deepEqual(new Set(rows.map((r) => r.bucket)), BUCKETS, 'every bucket is reached');
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
  assert.equal(unexpectedViolations([u]).length, 0, violationsMessage([u]));
});
