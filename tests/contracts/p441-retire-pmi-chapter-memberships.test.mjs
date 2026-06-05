/**
 * #441 (A1 retire) contract test — the dead pmi_chapter_memberships path stays gone.
 *
 * The `pmi_chapter_memberships` table was NEVER created (the whole p125-E1 migration
 * series is unapplied), so the pmi-vep-sync worker's upsert/map path was dead code
 * calling a non-existent relation. PM decision 2026-06-05 = A1 (retire). This
 * forward-defense asserts the worker source no longer references the dead table/types/
 * functions, so the path cannot be silently reintroduced while the table still doesn't
 * exist.
 *
 * RETAINED (intentionally not removed): findPersonIdByEmail + insertServiceHistory +
 * mapServiceHistory + the engagement end_date fallback — the selection_application_service_history
 * table DOES exist; only its external feed (extract_pmi_volunteer.js) stalled, which is a
 * PMI-side issue, not a dead local path.
 *
 * Cross-ref: #441. The entangled UNAPPLIED p125-E1 migration files (which still cross-
 * reference the table) are a separate cleanup flagged on the issue — not touched here.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const WORKER = resolve(ROOT, 'cloudflare-workers/pmi-vep-sync/src');
const FILES = ['index.ts', 'db.ts', 'script-mapper.ts', 'types.ts'];
// strip // line comments and /* */ block comments (the retire leaves explanatory comments
// that intentionally mention the retired name)
const stripComments = (s) => s.replace(/\/\/[^\n]*/g, '').replace(/\/\*[\s\S]*?\*\//g, '');

test('#441: pmi-vep-sync worker no longer references the dead pmi_chapter_memberships path', () => {
  for (const f of FILES) {
    const code = stripComments(readFileSync(resolve(WORKER, f), 'utf8'));
    assert.ok(!/pmi_chapter_memberships/.test(code),
      `${f} must not reference the pmi_chapter_memberships table (never created)`);
    assert.ok(!/PmiChapterMembershipUpsert/.test(code),
      `${f} must not reference the PmiChapterMembershipUpsert type`);
    assert.ok(!/(upsert|map)PmiChapterMemberships/.test(code),
      `${f} must not reference the chapter-membership upsert/map functions`);
  }
});

test('#441: service_history + person-resolution paths are RETAINED', () => {
  const db = readFileSync(resolve(WORKER, 'db.ts'), 'utf8');
  const mapper = readFileSync(resolve(WORKER, 'script-mapper.ts'), 'utf8');
  assert.match(db, /function insertServiceHistory/, 'insertServiceHistory must be retained');
  assert.match(db, /function findPersonIdByEmail/, 'findPersonIdByEmail must be retained');
  assert.match(mapper, /function mapServiceHistory/, 'mapServiceHistory must be retained');
});
