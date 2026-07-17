/**
 * Guard: every ADR file under docs/adr/ has an index line in docs/adr/README.md.
 *
 * The ADR index silently drifted to 18 unindexed ADRs (ADR-0099..0103 + ADR-0111..0124)
 * before it was caught by a Platform Guardian audit (#1404). This static check fails the
 * moment a new `ADR-XXXX-*.md` file is added without a matching `` `ADR-XXXX-...md` `` entry
 * in the index, so the drift cannot re-accumulate.
 *
 * Pure static (no network / no DB) — runs in every offline baseline.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const ADR_DIR = resolve(ROOT, 'docs/adr');
const README = readFileSync(resolve(ADR_DIR, 'README.md'), 'utf8');

const adrFiles = readdirSync(ADR_DIR)
  .filter((f) => /^ADR-\d{4}-.*\.md$/.test(f))
  .sort();

test('every ADR file has a backticked index line in docs/adr/README.md', () => {
  const missing = adrFiles.filter((f) => !README.includes('`' + f + '`'));
  assert.deepEqual(
    missing,
    [],
    `ADR files missing an index entry in docs/adr/README.md: ${missing.join(', ')}. ` +
      `Add a line under "## ADRs ativos": - \`<file>\` — <one-line decision summary>.`,
  );
});

test('docs/adr contains at least the known ADR baseline (no accidental deletion)', () => {
  assert.ok(adrFiles.length >= 123, `expected >= 123 ADR files, found ${adrFiles.length}`);
});
