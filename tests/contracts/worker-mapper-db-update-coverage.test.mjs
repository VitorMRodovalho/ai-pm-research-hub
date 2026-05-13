/**
 * Worker mapper ↔ db.ts UPDATE SET coverage contract — p152 W4 OPP-152.1.
 *
 * Prevents silent-drop bug class that burned us 2x in p151:
 *   - hotfix5 profileCertifications (mapper had it, db.ts UPDATE didn't propagate
 *     it to selection_applications text[] column — direct CSV assignment failed)
 *   - hotfix6 vep_status_raw + vep_last_seen_at (mapper had them, db.ts UPDATE
 *     SET clause never included them — silently dropped on every re-ingest;
 *     worker reported success but DB stayed NULL in all 97 apps)
 *
 * Invariant: every key returned by `script-mapper.ts → return { ... }` MUST
 * appear in `db.ts → .update({ ... })` SET clause, OR be in the allowed-skip
 * list (immutable fields like cycle_id, vep_application_id, vep_opportunity_id,
 * organization_id — set once at INSERT, preserved on UPDATE).
 *
 * Why static parse (vs runtime check): worker runs on Cloudflare; we want CI
 * to catch drift before deploy, not at runtime after silent drop. Test reads
 * source files directly, no DB or network calls. Safe to run anywhere.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const MAPPER_PATH = join(REPO_ROOT, 'cloudflare-workers/pmi-vep-sync/src/script-mapper.ts');
const DB_PATH = join(REPO_ROOT, 'cloudflare-workers/pmi-vep-sync/src/db.ts');

// Fields intentionally absent from UPDATE SET (immutable post-INSERT).
// Kept synced with comment in db.ts ("cycle_id intentionally NOT updated").
const ALLOWED_SKIP_FROM_UPDATE = new Set([
  'cycle_id',                  // history preservation per cycle-aware behavior
  'vep_application_id',        // compound key — unique identifier from PMI VEP
  'vep_opportunity_id',        // compound key
  'organization_id',           // set once at INSERT, immutable scoping
]);

function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')  // block comments
    .replace(/\/\/[^\n]*/g, '');        // line comments
}

function extractObjectKeys(blockContent) {
  // Match identifiers followed by ':' at the start of a (possibly indented) line.
  // Excludes nested-object keys by requiring 2-4 space indent (top level of the block).
  const KEY_RE = /^\s*([a-z_][a-z0-9_]*)\s*:/gm;
  const keys = new Set();
  let m;
  while ((m = KEY_RE.exec(blockContent)) !== null) {
    keys.add(m[1]);
  }
  return keys;
}

function extractMapperReturnKeys() {
  const src = readFileSync(MAPPER_PATH, 'utf8');
  const cleaned = stripComments(src);
  // The mapper's main return is the one inside function `mapToSelectionApplication`.
  // Heuristic: find the LAST `return {` that's preceded by reasonable function context.
  // Simpler: find return blocks that have many keys (>10) — the helper functions like
  // parsePmiLocation return small objects (3 keys).
  const RETURN_BLOCK = /return\s*\{([\s\S]*?)\};\s*\n}/g;
  let bestBlock = '';
  let bestKeyCount = 0;
  let m;
  while ((m = RETURN_BLOCK.exec(cleaned)) !== null) {
    const block = m[1];
    const keys = extractObjectKeys(block);
    if (keys.size > bestKeyCount) {
      bestKeyCount = keys.size;
      bestBlock = block;
    }
  }
  assert.ok(bestBlock, 'Mapper main return block not found');
  return extractObjectKeys(bestBlock);
}

function extractUpdateSetKeys() {
  const src = readFileSync(DB_PATH, 'utf8');
  const cleaned = stripComments(src);
  // p153 hotfix7: db.ts now uses `const commonRefresh = { ... }` shared between
  // cross-cycle (partial) + same-cycle (full) UPDATE paths. Collect keys from
  // the commonRefresh decl AND every inline .update({...}).eq block — the union
  // is the actual set of mapper fields propagated to UPDATE on re-ingest.
  const keys = new Set();
  const COMMON_REFRESH = /const\s+commonRefresh\s*=\s*\{([\s\S]*?)\};/;
  const cr = cleaned.match(COMMON_REFRESH);
  if (cr) {
    extractObjectKeys(cr[1]).forEach(k => keys.add(k));
  }
  const UPDATE_BLOCK = /\.update\(\s*\{([\s\S]*?)\}\s*\)\s*\.eq/g;
  let m;
  while ((m = UPDATE_BLOCK.exec(cleaned)) !== null) {
    extractObjectKeys(m[1]).forEach(k => keys.add(k));
  }
  assert.ok(keys.size > 0, 'db.ts UPDATE keys + commonRefresh extraction returned empty');
  return keys;
}

test('worker mapper return keys are all covered by db.ts UPDATE SET (or in allowed-skip list)', () => {
  const mapperKeys = extractMapperReturnKeys();
  const updateKeys = extractUpdateSetKeys();

  // Sanity floor: confirm we extracted reasonable counts (test self-check)
  assert.ok(mapperKeys.size >= 30, `Mapper key count too low (${mapperKeys.size}) — regex likely broken`);
  assert.ok(updateKeys.size >= 30, `Update key count too low (${updateKeys.size}) — regex likely broken`);

  // Compute mapper keys missing from UPDATE that are NOT in allowed-skip
  const missingFromUpdate = [...mapperKeys]
    .filter(k => !updateKeys.has(k))
    .filter(k => !ALLOWED_SKIP_FROM_UPDATE.has(k));

  if (missingFromUpdate.length > 0) {
    assert.fail(
      `Worker drift detected — these mapper fields are SILENTLY DROPPED in db.ts UPDATE SET:\n` +
      missingFromUpdate.map(k => `  - ${k}`).join('\n') +
      `\n\nLikely root cause: someone added a field to script-mapper.ts return object but ` +
      `forgot to wire it into db.ts UPDATE clause. This pattern caused hotfix5+6 (profile_certifications, ` +
      `vep_status_raw, vep_last_seen_at silent drops in p151).\n\nFix: add each field to db.ts .update({...}) ` +
      `OR if intentionally immutable on re-import, add to ALLOWED_SKIP_FROM_UPDATE in this test.`
    );
  }
});

test('allowed-skip list is not stale (every entry is actually in mapper output)', () => {
  const mapperKeys = extractMapperReturnKeys();
  const stale = [...ALLOWED_SKIP_FROM_UPDATE].filter(k => !mapperKeys.has(k));
  if (stale.length > 0) {
    assert.fail(
      `Allowed-skip list contains keys not in mapper output (stale): ${stale.join(', ')}\n` +
      `Remove these from ALLOWED_SKIP_FROM_UPDATE in this test.`
    );
  }
});

test('db.ts UPDATE SET contains updated_at (sanity)', () => {
  const updateKeys = extractUpdateSetKeys();
  assert.ok(updateKeys.has('updated_at'), 'db.ts UPDATE SET must include updated_at for auditing');
});
