// tests/contracts/1109-contract-whitelist-completeness.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json
// (SEDIMENT-186.C) before running. This file is SELF-REFERENTIAL: it asserts
// its own membership too, so it must be wired into both lists.
/**
 * Guard 2 (#1109, wave-9 harvest from LL #588) — contract-file whitelist completeness.
 *
 * CLASS: `package.json`'s `test` and `test:contracts` scripts are explicit,
 * space-separated whitelists (NOT globs). A new `tests/contracts/*.test.mjs`
 * forgotten from either list is SILENTLY SKIPPED — its ratchet never runs, and
 * the miss is caught only by adversarial review. This recurred (SEDIMENT-186.C)
 * and was the lesson hand-applied in #938 ([[reference-guard-test-never-wired-into-ci]]).
 *
 * GUARD: every `tests/contracts/*.test.mjs` on disk MUST be referenced in BOTH
 * whitelist strings. A deterministic CI failure replaces the review-dependent miss.
 *
 * QUARANTINE: a file may be temporarily excused via SKIP_LIST below — but ONLY
 * with a documented reason + tracking issue (same allowlist mechanics as #938;
 * never silence). The guard still fails if ANY non-skip-listed file is missing.
 * SKIP_LIST is itself validated: every entry must exist on disk AND actually be
 * absent from both whitelists (a stale excuse for an already-wired file fails).
 *
 * Offline-only (static source + package.json assertions); no DB gating.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const CONTRACT_DIR = 'tests/contracts';

// ── Documented quarantine (allowlist) ─────────────────────────────────────────
// Each entry: a contract test intentionally excused from the whitelists, with a
// reason and a tracking issue. Removing the root cause = wire the file + delete
// the entry here. NEVER add without a live issue — that is silencing, not skipping.
const SKIP_LIST = [
  {
    file: 'ip-gate-templates.test.mjs',
    reason:
      'Deterministic policy-drift: resolve_default_gates diverged from the test ' +
      '(first gate committee_majority != curator; executive_summary returns gates ' +
      "!= NULL; threshold 'majority' not number/'all') since ADR-0016 C9 (9d2eea3c). " +
      'Never wired into either whitelist; not running in CI. Reconcile test-vs-policy.',
    issue: 1340,
  },
];

const skipSet = new Set(SKIP_LIST.map((e) => e.file));

const pkg = JSON.parse(readFileSync(resolve(ROOT, 'package.json'), 'utf8'));
const testScript = pkg.scripts?.test ?? '';
const contractsScript = pkg.scripts?.['test:contracts'] ?? '';

// A file is "referenced" if its whitelist path token appears verbatim in the
// script string — exactly how `node --test` tokenizes the space-separated list.
const isReferenced = (script, basename) =>
  script.includes(`${CONTRACT_DIR}/${basename}`);

const diskFiles = readdirSync(resolve(ROOT, CONTRACT_DIR))
  .filter((f) => f.endsWith('.test.mjs'))
  .sort();

test('every tests/contracts/*.test.mjs is in BOTH package.json whitelists (or documented SKIP_LIST)', () => {
  const missingFromTest = [];
  const missingFromContracts = [];

  for (const f of diskFiles) {
    if (skipSet.has(f)) continue;
    if (!isReferenced(testScript, f)) missingFromTest.push(f);
    if (!isReferenced(contractsScript, f)) missingFromContracts.push(f);
  }

  const hint =
    ' -> add the path to the whitelist, OR (if broken/flaky) add a documented ' +
    'SKIP_LIST entry with a reason + tracking issue.';

  assert.deepEqual(
    missingFromTest,
    [],
    `Contract test(s) missing from the "test" whitelist:\n  ${missingFromTest.join(
      '\n  ',
    )}${hint}`,
  );
  assert.deepEqual(
    missingFromContracts,
    [],
    `Contract test(s) missing from the "test:contracts" whitelist:\n  ${missingFromContracts.join(
      '\n  ',
    )}${hint}`,
  );
});

test('this meta-test is itself wired into BOTH whitelists (self-reference)', () => {
  const self = '1109-contract-whitelist-completeness.test.mjs';
  assert.ok(
    isReferenced(testScript, self),
    `${self} must be in the "test" whitelist`,
  );
  assert.ok(
    isReferenced(contractsScript, self),
    `${self} must be in the "test:contracts" whitelist`,
  );
});

test('SKIP_LIST entries are valid (exist on disk, genuinely unwired, carry an issue)', () => {
  const diskSet = new Set(diskFiles);
  for (const entry of SKIP_LIST) {
    assert.ok(
      diskSet.has(entry.file),
      `SKIP_LIST references ${entry.file} which is not on disk — remove the stale entry`,
    );
    assert.ok(
      Number.isInteger(entry.issue) && entry.issue > 0,
      `SKIP_LIST entry for ${entry.file} needs a tracking issue number`,
    );
    assert.ok(
      typeof entry.reason === 'string' && entry.reason.trim().length > 0,
      `SKIP_LIST entry for ${entry.file} needs a documented reason`,
    );
    // A skip-listed file must be genuinely absent from BOTH lists; if it is
    // already wired, the excuse is stale and should be deleted.
    const wiredSomewhere =
      isReferenced(testScript, entry.file) ||
      isReferenced(contractsScript, entry.file);
    assert.ok(
      !wiredSomewhere,
      `SKIP_LIST excuses ${entry.file} but it is already wired into a whitelist — delete the entry`,
    );
  }
});
