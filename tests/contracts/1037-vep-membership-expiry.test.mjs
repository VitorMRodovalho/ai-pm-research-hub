/**
 * #1037 — VEP mapper must persist the PMI membership expiryDate (VENCIMENTO) that
 * /admin/filiacao surfaces.
 *
 * Root cause: the enriched PMI export carries per-chapter expiry in `profileMemberships`
 * ([{chapterName, expiryDate}]), but the worker mapped `profileMembershipChapters`
 * (chapter NAMES only, no expiry). So selection_applications.pmi_memberships stored plain
 * strings and the affiliation modal's expiry field could never pre-fill.
 *
 * Static source-parse (no DB / network) — mirrors 902-vep-deadline-capture + the
 * worker-mapper-db-update-coverage approach. Behavioural coverage lives in the worker's
 * own vitest (cloudflare-workers/pmi-vep-sync/src/script-mapper.test.ts).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const read = (p) => readFileSync(join(REPO_ROOT, p), 'utf8');

test('#1037: script-mapper prefers profileMemberships (with expiry) over profileMembershipChapters', () => {
  const src = read('cloudflare-workers/pmi-vep-sync/src/script-mapper.ts');
  // The mapped pmi_memberships must be derived from profileMemberships FIRST, chapters as fallback.
  assert.match(
    src,
    /normalizeMemberships\(parseMaybeJsonArray\(app\.profileMemberships\)\)\s*\n?\s*\?\?\s*normalizeMemberships\(parseMaybeJsonArray\(app\.profileMembershipChapters\)\)/,
    'phaseBMemberships must read profileMemberships first, then fall back to profileMembershipChapters',
  );
  // The old bug shape (mapping profileMembershipChapters directly with a lying cast) must be gone.
  assert.doesNotMatch(
    src,
    /parseMaybeJsonArray\(app\.profileMembershipChapters\)\s+as\s+Array<\{\s*chapterName/,
    'the old direct profileMembershipChapters cast (drops expiry) must be removed',
  );
  assert.match(src, /export function normalizeMemberships\b/, 'normalizeMemberships must exist + be exported (testable)');
});

test('#1037: normalizeMemberships keeps object-form expiry and null-fills the names-only form', () => {
  const src = read('cloudflare-workers/pmi-vep-sync/src/script-mapper.ts');
  // string entry → { chapterName, expiryDate: null }
  assert.match(src, /typeof m === 'string'[\s\S]*?expiryDate:\s*null/, 'names-only entries must map to expiryDate null');
  // object entry → carries the source expiryDate when present
  assert.match(src, /expiryDate:\s*typeof exp === 'string'/, 'object entries must preserve the source expiryDate string');
});

test('#1037: types reflect reality — profileMemberships declared + pmi_memberships expiry nullable', () => {
  const types = read('cloudflare-workers/pmi-vep-sync/src/types.ts');
  assert.match(types, /profileMemberships\?:\s*Array<\{\s*chapterName:\s*string;\s*expiryDate:\s*string\s*\}>\s*\|\s*string\s*\|\s*null/,
    'ScriptApplication must declare the enriched profileMemberships field');
  assert.match(types, /pmi_memberships\?:\s*Array<\{\s*chapterName:\s*string;\s*expiryDate:\s*string\s*\|\s*null\s*\}>\s*\|\s*null/,
    'SelectionApplicationUpsert.pmi_memberships expiryDate must be nullable (names-only fallback)');
});
