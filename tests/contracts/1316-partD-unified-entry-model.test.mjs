/**
 * #1316 Part D — Unified entry model (Cycle 1/2 Goiás+Ceará → PMI-GO sede).
 *
 * Governance decision (owner 2026-07-11): origin and the contracting sede are INDEPENDENT axes.
 *   - `members.entry_chapter_code` = chapter of ORIGIN (varied; never overwritten to 'GO').
 *   - The contracting sede is a single constant: `chapter_registry.is_contracting_chapter = PMI-GO`
 *     (the only contracting chapter; the volunteer term always contracts with PMI-GO).
 * This test locks the single-sede invariant and the legacy-cohort provenance-tag semantics.
 * See ADR-0104 (Amendment: #1316 Part D) + ADR-0076 (Princípio 1 corrected) + migration
 * 20260805000424_1316_partD_unified_entry_legacy_cohort_tag.sql.
 *
 * Data-driven, no absolute-count coupling (per memory reference-roster-tests-data-driven-single-source).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const read = (p) => readFileSync(join(REPO_ROOT, p), 'utf8');

const MIGRATION = 'supabase/migrations/20260805000424_1316_partD_unified_entry_legacy_cohort_tag.sql';

// ---------- static (offline) ----------

test('Part D migration is data-only, additive, idempotent, and derived from the legacy mirror', () => {
  const src = read(MIGRATION);
  // additive merge, never a bare assignment that clobbers metadata
  assert.match(src, /metadata\s*=\s*COALESCE\(e\.metadata,'\{\}'::jsonb\)\s*\|\|/,
    'must merge (||) into existing metadata, not overwrite it');
  assert.match(src, /'legacy_cohort'/, 'must stamp the legacy_cohort key');
  assert.match(src, /'sede',\s*'PMI-GO'/, 'the tag must record PMI-GO as the sede');
  // idempotent guard
  assert.match(src, /NOT\s*\(COALESCE\(e\.metadata,'\{\}'::jsonb\)\s*\?\s*'legacy_cohort'\)/,
    'must be idempotent (skip already-tagged engagements)');
  // scope: legacy mirror + null modern link, volunteer/researcher kinds
  assert.match(src, /FROM\s+public\.volunteer_applications/, 'cohort derives from the legacy mirror');
  assert.match(src, /selection_application_id\s+IS\s+NULL/, 'only engagements without a modern link');
  // DDL-free (no schema objects created in this data migration)
  assert.doesNotMatch(src, /CREATE\s+(OR\s+REPLACE\s+)?(FUNCTION|TABLE|VIEW|TRIGGER|POLICY|TYPE|INDEX)/i,
    'Part D is data-only; no DDL');
  // no hardcoded UUIDs (ids are derived from the mirror)
  assert.doesNotMatch(src, /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i,
    'no hardcoded engagement/member ids — derive from the mirror');
});

test('ADR-0104 documents the unified entry model (Part D); ADR-0076 Princípio 1 is corrected', () => {
  const adr104 = read('docs/adr/ADR-0104-chapter-affiliations-ssot.md');
  assert.match(adr104, /Amendment:\s*#1316 Part D/, 'ADR-0104 must carry the Part D amendment');
  assert.match(adr104, /origin and sede are independent axes/i,
    'ADR-0104 must state origin/sede are independent');

  const adr76 = read('docs/adr/ADR-0076-pmi-3d-volunteer-model-and-phase-b-base-legal.md');
  // the stale entry pointer must be struck through / corrected toward entry_chapter_code
  assert.match(adr76, /members\.entry_chapter_code/,
    'ADR-0076 must point entry to members.entry_chapter_code');
  assert.match(adr76, /#1316 Parte D/, 'ADR-0076 must carry the correction note');
});

// ---------- DB-aware (skipped without creds) ----------

async function rest(path) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const res = await fetch(`${url}/rest/v1/${path}`, {
    headers: { apikey: key, Authorization: `Bearer ${key}` },
  });
  if (!res.ok) assert.fail(`REST ${path} failed: ${res.status} ${await res.text()}`);
  return res.json();
}

test('DB: exactly one contracting sede, and it is PMI-GO (skipped without creds)', async (t) => {
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return t.skip('SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set');
  }
  const rows = await rest('chapter_registry?select=chapter_code&is_contracting_chapter=eq.true');
  assert.equal(rows.length, 1, 'there must be exactly one contracting chapter (single sede)');
  assert.equal(rows[0].chapter_code, 'GO', 'the sole contracting sede must be GO (PMI-GO)');
});

test('DB: every legacy_cohort-tagged engagement is a null-link Cycle 1/2 entry under PMI-GO (skipped without creds)', async (t) => {
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return t.skip('SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set');
  }
  const rows = await rest(
    'engagements?select=id,selection_application_id,metadata&metadata->legacy_cohort=not.is.null',
  );
  assert.ok(rows.length >= 1, 'the Part D stamp must be present on at least one engagement');
  for (const e of rows) {
    const lc = e.metadata?.legacy_cohort;
    assert.ok(lc, `engagement ${e.id} has a legacy_cohort object`);
    assert.equal(e.selection_application_id, null,
      `tagged engagement ${e.id} must have no modern selection_application link`);
    assert.equal(lc.sede, 'PMI-GO', `engagement ${e.id} sede must be PMI-GO`);
    assert.ok([1, 2].includes(Number(lc.cycle)),
      `engagement ${e.id} cycle must be a legacy entry cycle (1 or 2), got ${lc.cycle}`);
    assert.equal(lc.source, 'volunteer_applications_mirror',
      `engagement ${e.id} provenance must cite the legacy mirror`);
  }
});
