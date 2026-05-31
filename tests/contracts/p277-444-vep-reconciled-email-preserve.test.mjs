/**
 * #444 — VEP worker must NOT clobber a manually-reconciled email — p277.
 *
 * Root cause (triaged p277, corrected layer): the live clobber is NOT in the
 * `import_vep_applications` RPC (named in the issue) — that RPC only INSERTs new
 * apps or dedup-skips existing ones, never touching an existing app's email. The
 * real refresh path is the Cloudflare worker `pmi-vep-sync/src/db.ts`
 * `upsertSelectionApplication()`, which matches an existing row by COMPOUND KEY
 * (vep_application_id, vep_opportunity_id) — NOT by email — and applied
 * `commonRefresh.email = payload.email` (the raw PMI email) on every re-sync.
 *
 * For an admin-reconciled approved candidate whose member primary email differs
 * from the PMI email, that overwrite breaks the app↔member link and trips
 * `R_approved_application_has_member`, red-lighting CI for unrelated PRs every
 * cycle import. Live case: Paulo Alves (app 6259ced2) — the 2026-05-30 sync reset
 * email from the reconciled `paulo-junior@outlook.com` back to `pejota81@gmail.com`.
 *
 * Fix (db.ts): freeze email when `existing.vep_reconciled_at` is set, by writing
 * back the existing stored value (a deliberate no-op) — non-reconciled rows keep
 * refreshing from PMI as before.
 *
 * This is a STATIC SOURCE-PARSE test (mirrors worker-mapper-db-update-coverage):
 * the worker runs on Cloudflare and is not exercised by main CI's runtime, so we
 * lock the regression class at the source level — CI catches a revert to the
 * unconditional overwrite before the next deploy. No DB or network calls.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const DB_PATH = join(REPO_ROOT, 'cloudflare-workers/pmi-vep-sync/src/db.ts');

function readDb() {
  return readFileSync(DB_PATH, 'utf8');
}

/** Extract the `const commonRefresh = { ... };` object-literal body from db.ts. */
function extractCommonRefreshBlock(src) {
  const m = src.match(/const\s+commonRefresh\s*=\s*\{([\s\S]*?)\};/);
  assert.ok(m, 'commonRefresh object literal not found in db.ts');
  return m[1];
}

/** Extract the `existing` SELECT column string from upsertSelectionApplication. */
function extractExistingSelect(src) {
  // Anchor on the COMPOUND-KEY probe specifically (db.ts has several
  // .from('selection_applications').select(...) queries): the upsert existing-row
  // lookup is the .select() immediately chained to .eq('vep_application_id', ...).
  const m = src.match(
    /\.select\(\s*'([^']*)'\s*\)\s*\.eq\('vep_application_id',\s*payload\.vep_application_id\)/
  );
  assert.ok(m, 'upsert existing-row .select(...).eq(vep_application_id) probe not found in db.ts');
  return m[1];
}

test('#444 — existing-row SELECT loads vep_reconciled_at + email (needed for the freeze)', () => {
  const select = extractExistingSelect(readDb());
  assert.ok(
    /\bvep_reconciled_at\b/.test(select),
    `existing-row SELECT must include vep_reconciled_at — got: "${select}"`
  );
  assert.ok(
    /\bemail\b/.test(select),
    `existing-row SELECT must include email (written back as a no-op on reconciled rows) — got: "${select}"`
  );
});

test('#444 — commonRefresh.email is GATED by vep_reconciled_at (no unconditional PMI overwrite)', () => {
  const block = extractCommonRefreshBlock(readDb());

  // The email line must exist and reference existing.vep_reconciled_at.
  const emailLine = block.split('\n').find(l => /^\s*email\s*:/.test(l));
  assert.ok(emailLine, 'commonRefresh must still declare an `email:` key (kept for update-coverage test)');
  assert.ok(
    /existing\.vep_reconciled_at/.test(emailLine),
    `commonRefresh.email must be gated by existing.vep_reconciled_at — got: "${emailLine.trim()}"`
  );

  // Forward defense: the exact pre-fix bug shape must NOT reappear.
  assert.ok(
    !/^\s*email\s*:\s*payload\.email\s*,?\s*$/.test(emailLine),
    'REGRESSION: commonRefresh.email reverted to the unconditional `email: payload.email` overwrite (#444)'
  );

  // Reconciled branch must preserve the stored value (existing.email), not null/PMI.
  assert.ok(
    /existing\.email/.test(emailLine),
    `the reconciled branch must write back existing.email (no-op preserve) — got: "${emailLine.trim()}"`
  );
});
