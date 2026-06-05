/**
 * Contract: #201 — the curation review modal must show the submitted artifact link(s)
 * and source context.
 *
 * ReviewRubricDialog rendered title/tribe/SLA/assignee/description but DROPPED
 * item.attachments (delivered by get_curation_dashboard), so a curator could not
 * reach the peça being reviewed. This adds an artifact section (links + empty-state)
 * + source context (board_name, tags). Core-only (PM default a) — Drive-folder links
 * and access-state deferred to #301/#190.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const ISLAND = resolve(ROOT, 'src/components/boards/CuratorshipBoardIsland.tsx');
const island = existsSync(ISLAND) ? readFileSync(ISLAND, 'utf8') : '';
const DICTS = {
  'pt-BR': readFileSync(resolve(ROOT, 'src/i18n/pt-BR.ts'), 'utf8'),
  'en-US': readFileSync(resolve(ROOT, 'src/i18n/en-US.ts'), 'utf8'),
  'es-LATAM': readFileSync(resolve(ROOT, 'src/i18n/es-LATAM.ts'), 'utf8'),
};

test('#201: review modal renders artifact links + empty-state', () => {
  assert.ok(island, 'CuratorshipBoardIsland.tsx readable');
  assert.match(island, /normalizeAttachments\(item\.attachments\)/, 'attachments are read in the dialog');
  assert.match(island, /curation\.artifact\.title/, 'artifact section title key');
  assert.match(island, /curation\.artifact\.empty/, 'empty-state key');
  assert.match(island, /<Paperclip/, 'artifact section icon');
});

test('#201: artifact links open safely (target=_blank + noopener noreferrer)', () => {
  assert.match(island, /href=\{a\.url\}\s+target="_blank"\s+rel="noopener noreferrer"/,
    'artifact links must be safe external links');
});

test('#201: normalizeAttachments handles array, bare string, and null shapes', () => {
  assert.match(island, /function normalizeAttachments/, 'normalizer exists');
  assert.match(island, /typeof a === 'string'/, 'handles bare-string attachment');
  assert.match(island, /Array\.isArray\(a\)/, 'handles array attachment');
});

test('#201: source context (board_name + tags) surfaced + attachments type widened', () => {
  assert.match(island, /item\.board_name/, 'board_name surfaced');
  assert.match(island, /item\.tags/, 'tags surfaced');
  assert.match(island, /attachments\?: Array<\{ url: string; name\?: string/, 'attachments type widened beyond {url}[]');
});

test('#201 i18n: artifact keys exist in all 3 locale dicts (parity)', () => {
  for (const [loc, raw] of Object.entries(DICTS)) {
    assert.match(raw, /'curation\.artifact\.title':/, `${loc} must define curation.artifact.title`);
    assert.match(raw, /'curation\.artifact\.empty':/, `${loc} must define curation.artifact.empty`);
  }
});
