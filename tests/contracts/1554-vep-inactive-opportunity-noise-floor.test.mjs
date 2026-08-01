/**
 * Contract: #1554 — a closed VEP cohort must not sit in the import's error block.
 *
 * Grounded 2026-08-01 (live query, project ldrfrvwhxsmgaabwmaik): opportunity 62106
 * is is_active=false with an empty essay_mapping, and all 8 applications pointing at
 * it are the whole cycle2-2025 cohort, in a CLOSED cycle, with final decisions already
 * recorded. The VEP keeps exporting them on every run, so the import used to report
 * 8 errors every single time. A permanent floor of expected errors is worse than no
 * error block at all: it is exactly what teaches an operator to skim past the 9th
 * line, the one with a different cause.
 *
 * Three invariants, each of which was a real bug or a near-miss:
 *
 *  1. SPLIT — "not registered" and "registered but closed" ask for opposite actions
 *     and must not share a scope. The lookup therefore must NOT pre-filter is_active;
 *     filtering it is what made the two indistinguishable in the first place.
 *
 *  2. ORDER — the inactive branch must come BEFORE the essay_mapping test. Closed
 *     opportunities tend to have an empty mapping too (62106 does), so testing the
 *     mapping first would relabel the same 8 skips as `essay_mapping_missing`: same
 *     noise floor, worse name, and it points the operator at a mapping they must not
 *     fill in. This is the correction that the issue's own proposed fix got wrong.
 *
 *  3. SEPARATION — expected outcomes travel in `notices`, never in `errors`. A UI that
 *     renders notices into the error block would rebuild the noise floor one layer up,
 *     so the admin renderer is guarded too.
 *
 * Layer B (DB-aware, skipped without credentials) re-measures the premise rather than
 * trusting this comment: if 62106 ever goes active, or the 8 stop being terminal, the
 * reasoning above expires and this test should fail loudly instead of passing stale.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const WORKER_DIR = resolve(ROOT, 'cloudflare-workers/pmi-vep-sync');
const indexSrc = readFileSync(resolve(WORKER_DIR, 'src/index.ts'), 'utf8');
const dbSrc = readFileSync(resolve(WORKER_DIR, 'src/db.ts'), 'utf8');
const typesSrc = readFileSync(resolve(WORKER_DIR, 'src/types.ts'), 'utf8');
const selectionSrc = readFileSync(resolve(ROOT, 'src/pages/admin/selection.astro'), 'utf8');

// ── Layer A1: the split ────────────────────────────────────────────────────────

test('#1554: the opportunity lookup loads inactive rows too', () => {
  assert.match(dbSrc, /export async function getAllOpportunities/,
    'the loader must be the all-opportunities one');
  const fn = dbSrc.match(/export async function getAllOpportunities[\s\S]*?\n\}/);
  assert.ok(fn, 'getAllOpportunities body must be findable');
  assert.ok(!/\.eq\('is_active'/.test(fn[0]),
    'getAllOpportunities must NOT filter is_active — that filter is what collapsed ' +
    '"never registered" and "cycle closed" into one indistinguishable miss');
  assert.match(fn[0], /is_active/,
    'the selected columns must still include is_active so the caller can branch on it');
});

test('#1554: the retired single scope is gone from the worker', () => {
  assert.ok(!/opportunity_not_active/.test(indexSrc),
    "the ambiguous 'opportunity_not_active' scope must not survive anywhere in the worker");
  assert.match(indexSrc, /scope:\s*'opportunity_not_found'/, 'real-gap scope must exist');
  assert.match(indexSrc, /scope:\s*'opportunity_inactive'/, 'expected-outcome scope must exist');
});

// ── Layer A2: the order ────────────────────────────────────────────────────────

test('#1554: the inactive branch is evaluated BEFORE the essay_mapping test', () => {
  // Guard the APPLY loop specifically: slice from the last `for (const app of
  // body.applications)` (the apply path; the earlier one is the dry-run preview)
  // so a matching pair of anchors in the preview cannot satisfy this by accident.
  const applyStart = indexSrc.lastIndexOf('for (const app of body.applications)');
  assert.ok(applyStart > 0, 'apply loop must be findable');
  const applyLoop = indexSrc.slice(applyStart);

  const inactiveAt = applyLoop.indexOf('!opp.is_active');
  const mappingAt = applyLoop.indexOf('!opp.essay_mapping');
  assert.ok(inactiveAt > 0, 'apply loop must test !opp.is_active');
  assert.ok(mappingAt > 0, 'apply loop must test !opp.essay_mapping');
  assert.ok(inactiveAt < mappingAt,
    'the inactive branch must precede the essay_mapping branch — otherwise a closed ' +
    'opportunity with an empty mapping (62106) is relabelled essay_mapping_missing, ' +
    'trading one permanent noise floor for a worse-named one');
});

test('#1554: the dry-run preview branches in the same order as Apply', () => {
  const previewStart = indexSrc.indexOf('for (const app of body.applications)');
  const applyStart = indexSrc.lastIndexOf('for (const app of body.applications)');
  assert.ok(previewStart > 0 && previewStart < applyStart,
    'dry-run loop must exist and precede the apply loop');
  const preview = indexSrc.slice(previewStart, applyStart);

  const notFoundAt = preview.indexOf("reason: 'opportunity_not_found'");
  const inactiveAt = preview.indexOf("reason: 'opportunity_inactive'");
  const mappingAt = preview.indexOf("reason: 'essay_mapping_missing'");
  assert.ok(notFoundAt > 0 && inactiveAt > 0 && mappingAt > 0,
    'preview must carry all three distinct reasons');
  assert.ok(inactiveAt < mappingAt,
    'preview order must match Apply order, or the preview promises one reason and ' +
    'Apply reports another');
});

// ── Layer A3: the separation ───────────────────────────────────────────────────

test('#1554: expected outcomes go to notices, not errors', () => {
  assert.match(typesSrc, /notices:\s*Array<\{\s*scope:\s*string;\s*ref\?:\s*string;\s*message:\s*string\s*\}>/,
    'IngestSummary must declare a notices array distinct from errors');

  // The inactive branch must push to notices and must NOT push to errors. Anchor on
  // the APPLY loop first: the dry-run preview has its own !opp.is_active branch, and
  // an unanchored match would grab that one and pass while the apply path regressed.
  const applyStart = indexSrc.lastIndexOf('for (const app of body.applications)');
  assert.ok(applyStart > 0, 'apply loop must be findable');
  const branch = indexSrc.slice(applyStart).match(/if\s*\(!opp\.is_active\)\s*\{[\s\S]*?continue;/);
  assert.ok(branch, 'inactive branch must be findable in the apply loop');
  assert.match(branch[0], /summary\.notices\.push/,
    'the inactive skip must be reported as a notice');
  assert.ok(!/summary\.errors\.push/.test(branch[0]),
    'the inactive skip must NOT push to errors — that is the noise floor this closes');
  assert.match(branch[0], /applications_skipped_inactive_opportunity\+\+/,
    'the inactive skip must be counted separately so the summary stays auditable');
});

test('#1554: an ACTIVE opportunity with empty essay_mapping is warned about at load time', () => {
  // 66470 is live in this state right now: the mine only goes off when the first
  // candidate applies, and then it goes off once per candidate. Warn while it has
  // no victims.
  assert.match(indexSrc, /scope:\s*'opportunity_active_without_essay_mapping'/,
    'load-time warning scope must exist');
  const warn = indexSrc.match(/for\s*\(const o of opps\)\s*\{[\s\S]*?opportunity_active_without_essay_mapping[\s\S]*?\n\s*\}\n\s*\}/);
  assert.ok(warn, 'the load-time scan over opps must be findable');
  assert.match(warn[0], /o\.is_active\s*&&/,
    'the warning must be scoped to ACTIVE opportunities (a closed one with no mapping is fine)');
});

test('#1554: the admin renderer keeps notices out of the error block', () => {
  assert.match(selectionSrc, /function\s+renderWorkerNoticesBlock\s*\(/,
    'a dedicated notices renderer must exist');
  assert.match(selectionSrc, /renderWorkerNoticesBlock\s*\(\s*d\.notices/,
    'the apply result must render d.notices');
  // The error renderer must stay fed by errors alone, or the split dies at the UI.
  assert.match(selectionSrc, /renderWorkerErrorsBlock\s*\(\s*d\.errors/,
    'the error block must be fed by d.errors only');
  const errRenderer = selectionSrc.match(/function\s+renderWorkerErrorsBlock[\s\S]*?\n  \}/);
  assert.ok(errRenderer, 'renderWorkerErrorsBlock body must be findable');
  assert.ok(!/notices/.test(errRenderer[0]),
    'renderWorkerErrorsBlock must not consume notices — that would rebuild the noise floor in the UI');
});

test('#1554: the skip path stamps vep_last_seen_at', () => {
  assert.match(dbSrc, /export async function touchVepLastSeen/,
    'the stamp helper must exist');
  assert.match(indexSrc, /touchVepLastSeen\(/,
    'the worker must call it for the rows it deliberately skipped');
  // A bookkeeping failure must not fail the ingest, but must not vanish either.
  assert.match(indexSrc, /scope:\s*'vep_last_seen_stamp_failed'/,
    'a stamp failure must surface with its own scope instead of being swallowed');
});

// ── Layer B: the premise, re-measured ──────────────────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1554: stamping vep_last_seen_at on the closed cohort still wakes no reconciliation bucket',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { createClient } = await import('@supabase/supabase-js');
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

    const { data: opp, error: oppErr } = await sb
      .from('vep_opportunities')
      .select('opportunity_id, is_active')
      .eq('opportunity_id', '62106')
      .maybeSingle();
    assert.ifError(oppErr);
    assert.ok(opp, '62106 must still be registered');
    assert.equal(opp.is_active, false, '62106 must still be inactive — else the premise expired');

    const { data: apps, error: appErr } = await sb
      .from('selection_applications')
      .select('vep_application_id, status, vep_status_raw, cycle_id, selection_cycles!inner(status)')
      .eq('vep_opportunity_id', '62106');
    assert.ifError(appErr);
    // #1525/#1532 lesson: a probe failure must not be reported as a domain violation.
    // An EMPTY result here means the cohort moved, not that the invariant holds.
    assert.ok(Array.isArray(apps) && apps.length > 0,
      'the 62106 cohort must be non-empty — an empty read is a probe problem, not a pass');

    // The two reconciliation buckets in 20260805000354_1130_...sql:
    //   selection      → requires selection_cycles.status = 'open'
    //   pre-onboarding → requires vep_status_raw IN ('Submitted','OfferExtended')
    // Stamping vep_last_seen_at only matters for rows that pass one of these gates.
    const PRE_ONBOARDING_RAW = ['Submitted', 'OfferExtended'];
    for (const a of apps) {
      const cycleStatus = a.selection_cycles?.status;
      assert.notEqual(cycleStatus, 'open',
        `app ${a.vep_application_id} sits in an OPEN cycle — stamping it would surface the ` +
        'closed cohort in the selection reconciliation bucket');
      assert.ok(!PRE_ONBOARDING_RAW.includes(a.vep_status_raw),
        `app ${a.vep_application_id} has vep_status_raw=${a.vep_status_raw} — stamping it would ` +
        'surface it in the pre-onboarding bucket');
    }
  });
