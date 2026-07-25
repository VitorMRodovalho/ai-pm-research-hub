// tests/contracts/migration-drift-classifier.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json
// (SEDIMENT-186.C / #1109) — an unwired contract file is silently skipped.
/**
 * Guard — migration-drift classifier (tests/helpers/migration-drift-classifier.mjs).
 *
 * CLASS: the ADR-0097 / Phase-C gates in rpc-migration-coverage.test.mjs compare the
 * SHARED remote DB against the CHECKOUT. Three different situations produce the same
 * red and only one of them is authored drift:
 *   1. phantom tracking row from `apply_migration` via MCP (duplicate NAME, wall-clock version)
 *   2. prod-ahead / DDL-lag (version newer than the checkout head; .sql has not landed here)
 *   3. genuine missing file (the pre-GC-097 class the baselines were built for)
 * Measured 2026-07-24 over the last 200 CI runs: 12 of 21 non-Dependabot failures
 * involved this class, and the generic message pointed all of them at remedy (3).
 *
 * GUARD: the classifier is the thing that turns those reds into the right action, so its
 * discrimination is locked here. Offline (pure functions — no DB, no fs).
 *
 * Cross-ref: [[reference-gc097-phantom-row-delete-scope-care]],
 * [[reference-shared-db-drift-gate-serializes-ddl-prs]],
 * [[feedback-apply-migration-creates-tracking-row]].
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  checkoutHead,
  classifyMissingFileDrift,
  compareVersions,
  formatMissingFileDriftReport,
  prodAheadBanner,
  prodAheadVersions,
} from '../helpers/migration-drift-classifier.mjs';

// A checkout at head 20260805000489 (the repo's own zero-padded sequence scheme).
const LOCAL_VERSIONS = new Set([
  '20260319000001',
  '20260805000466',
  '20260805000488',
  '20260805000489',
]);
// name -> version of the local file carrying it (a Set is also accepted, without the
// colliding-file detail). The Map form is what rpc-migration-coverage passes.
const LOCAL_NAMES = new Map([
  ['legacy_seed', '20260319000001'],
  ['1437_v_operational_members_canonical_metric', '20260805000466'],
  ['1470_digest_rolling_window_occurred_at', '20260805000488'],
  ['1468_recompute_cutoff_researcher_scope', '20260805000489'],
]);

test('compareVersions orders by value, not by string length', () => {
  assert.equal(compareVersions('20260805', '20260805000489'), -1);
  assert.equal(compareVersions('20260805000489', '20260805000488'), 1);
  assert.equal(compareVersions('20260805000489', '20260805000489'), 0);
});

test('checkoutHead picks the highest local version (null when there are none)', () => {
  assert.equal(checkoutHead(LOCAL_VERSIONS), '20260805000489');
  assert.equal(checkoutHead(new Set()), null);
});

test('phantom: a tracked row whose NAME already has a local file, under a wall-clock version', () => {
  // Real shape from CI run 29788781971 (2026-07-21): apply_migration via MCP stamped
  // 20260720230931 while the repo file landed as 20260805000466 under the same name.
  const { phantom, prodAhead, genuine } = classifyMissingFileDrift({
    missingVersions: ['20260720230931'],
    trackedRows: [
      { version: '20260720230931', name: '1437_v_operational_members_canonical_metric' },
    ],
    localVersions: LOCAL_VERSIONS,
    localNames: LOCAL_NAMES,
  });
  assert.deepEqual(prodAhead, []);
  assert.deepEqual(genuine, []);
  assert.deepEqual(phantom, [
    {
      version: '20260720230931',
      name: '1437_v_operational_members_canonical_metric',
      localVersion: '20260805000466',
    },
  ]);
});

test('a Set of local names still classifies; the colliding file is just unknown', () => {
  const { phantom } = classifyMissingFileDrift({
    missingVersions: ['20260720230931'],
    trackedRows: [
      { version: '20260720230931', name: '1437_v_operational_members_canonical_metric' },
    ],
    localVersions: LOCAL_VERSIONS,
    localNames: new Set(LOCAL_NAMES.keys()),
  });
  assert.equal(phantom.length, 1);
  assert.equal(phantom[0].localVersion, null);
});

test('phantom wins over prod-ahead: name match classifies even above the checkout head', () => {
  // Belt: a duplicate-name row stamped ABOVE the head is still a phantom, and the remedy
  // (delete the row) differs from the prod-ahead remedy (land the file).
  const { phantom, prodAhead } = classifyMissingFileDrift({
    missingVersions: ['20260805000999'],
    trackedRows: [{ version: '20260805000999', name: '1470_digest_rolling_window_occurred_at' }],
    localVersions: LOCAL_VERSIONS,
    localNames: LOCAL_NAMES,
  });
  assert.equal(phantom.length, 1);
  assert.deepEqual(prodAhead, []);
});

test('prod-ahead: version newer than the checkout head, name unknown locally', () => {
  const { phantom, prodAhead, genuine } = classifyMissingFileDrift({
    missingVersions: ['20260805000490'],
    trackedRows: [{ version: '20260805000490', name: '1424_phase_c_digest_fanout' }],
    localVersions: LOCAL_VERSIONS,
    localNames: LOCAL_NAMES,
  });
  assert.deepEqual(phantom, []);
  assert.deepEqual(genuine, []);
  assert.deepEqual(prodAhead, ['20260805000490']);
});

test('genuine: older than the head and no local file claims the name', () => {
  const { phantom, prodAhead, genuine } = classifyMissingFileDrift({
    missingVersions: ['20260401120000'],
    trackedRows: [{ version: '20260401120000', name: 'pre_gc097_lost_body' }],
    localVersions: LOCAL_VERSIONS,
    localNames: LOCAL_NAMES,
  });
  assert.deepEqual(phantom, []);
  assert.deepEqual(prodAhead, []);
  assert.deepEqual(genuine, ['20260401120000']);
});

test('a mixed batch splits into all three classes (the CI 29788781971 shape)', () => {
  const { phantom, prodAhead, genuine } = classifyMissingFileDrift({
    missingVersions: ['20260805000490', '20260401120000', '20260720230931'],
    trackedRows: [
      { version: '20260720230931', name: '1437_v_operational_members_canonical_metric' },
      { version: '20260805000490', name: '1424_phase_c_digest_fanout' },
      { version: '20260401120000', name: 'pre_gc097_lost_body' },
    ],
    localVersions: LOCAL_VERSIONS,
    localNames: LOCAL_NAMES,
  });
  assert.equal(phantom.length, 1);
  assert.deepEqual(prodAhead, ['20260805000490']);
  assert.deepEqual(genuine, ['20260401120000']);
});

test('a tracked row with no name at all degrades to prod-ahead/genuine, never crashes', () => {
  const { phantom, prodAhead, genuine } = classifyMissingFileDrift({
    missingVersions: ['20260805000491', '20260101000000'],
    trackedRows: [{ version: '20260805000491' }, { version: '20260101000000', name: null }],
    localVersions: LOCAL_VERSIONS,
    localNames: LOCAL_NAMES,
  });
  assert.deepEqual(phantom, []);
  assert.deepEqual(prodAhead, ['20260805000491']);
  assert.deepEqual(genuine, ['20260101000000']);
});

test('report names the right remedy per class (delete row / land file / recover body)', () => {
  const report = formatMissingFileDriftReport(
    {
      phantom: [
        {
          version: '20260720230931',
          name: '1437_v_operational_members_canonical_metric',
          localVersion: '20260805000466',
        },
      ],
      prodAhead: ['20260805000490'],
      genuine: ['20260401120000'],
    },
    { baselinePath: 'docs/audit/BASELINE.txt', baselineConstant: 'BASE_SIZE' }
  );
  assert.match(report, /LIKELY PHANTOM tracking row\(s\) — 1/);
  assert.match(report, /DELETE FROM supabase_migrations\.schema_migrations WHERE version = '20260720230931';/);
  assert.match(report, /never LIKE/, 'the exact-version scope caveat must survive');
  assert.match(report, /CONFIRM FIRST/, 'name reuse is legitimate in the pre-GC-097 history');
  assert.match(
    report,
    /20260805000466_1437_v_operational_members_canonical_metric\.sql/,
    'the colliding local file must be named so the reader can confirm before deleting'
  );
  assert.match(report, /PROD-AHEAD \/ DDL-lag — 1/);
  assert.match(report, /land the \.sql in this PR, or rebase/);
  assert.match(report, /GENUINE missing file — 1/);
  assert.match(report, /docs\/audit\/BASELINE\.txt/);
  assert.match(report, /BASE_SIZE/);
});

test('report omits classes with no entries (no empty sections)', () => {
  const report = formatMissingFileDriftReport({ phantom: [], prodAhead: ['20260805000490'], genuine: [] });
  assert.match(report, /PROD-AHEAD/);
  assert.ok(!/PHANTOM/.test(report), 'no phantom section when none classified');
  assert.ok(!/GENUINE/.test(report), 'no genuine section when none classified');
});

test('prodAheadVersions is empty when the checkout is level with prod', () => {
  const ahead = prodAheadVersions({
    trackedVersions: ['20260805000488', '20260805000489'],
    localVersions: LOCAL_VERSIONS,
  });
  assert.deepEqual(ahead, []);
});

test('prodAheadVersions lists only what is newer than the head, sorted', () => {
  const ahead = prodAheadVersions({
    trackedVersions: ['20260805000491', '20260805000489', '20260805000490', '20260319000001'],
    localVersions: LOCAL_VERSIONS,
  });
  assert.deepEqual(ahead, ['20260805000490', '20260805000491']);
});

test('prodAheadBanner is empty when there is no lag, and actionable when there is', () => {
  assert.equal(prodAheadBanner([], '20260805000489'), '');
  const banner = prodAheadBanner(['20260805000490'], '20260805000489');
  assert.match(banner, /PROD-AHEAD/);
  assert.match(banner, /20260805000490/);
  assert.match(banner, /DDL-lag, not authored drift/);
});
