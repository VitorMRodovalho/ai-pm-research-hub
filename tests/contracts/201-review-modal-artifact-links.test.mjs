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
  // assert attributes independently — robust to JSX attribute reordering
  assert.match(island, /href=\{a\.url\}/, 'artifact link uses the url as href');
  assert.match(island, /target="_blank"/, 'opens in a new tab');
  assert.match(island, /rel="noopener noreferrer"/, 'safe external-link rel');
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

// ── #201 Drive layer (fed by #301 get_board_item_drive_access; deferred from the core PR) ──
test('#201 drive: the review modal fetches per-file Drive access state on open', () => {
  assert.match(island, /get_board_item_drive_access/, 'modal calls the item Drive-access RPC');
  assert.match(island, /p_board_item_id:\s*item\.id/, 'keyed on the open item id');
  assert.match(island, /drive_permission_status/, 'renders per-file permission status');
  assert.match(island, /function driveStatusMeta/, 'status -> label/style mapper exists');
});

test('#201 drive: per-file rows link to drive_file_url and carry a status badge', () => {
  assert.match(island, /drive\.files\.map/, 'iterates the Drive files array');
  assert.match(island, /href=\{f\.drive_file_url\}/, 'per-file link uses drive_file_url');
  // the 4-state vocabulary mirrors get_board_item_drive_access (ready|pending|error|missing)
  assert.match(island, /curation\.drive\.statusReady/, 'ready label key referenced');
  assert.match(island, /curation\.drive\.statusMissing/, 'missing label key referenced');
});

test('#201 drive i18n: curation.drive.* keys exist in all 3 locale dicts (parity)', () => {
  const keys = ['title', 'statusReady', 'statusPending', 'statusError', 'statusMissing', 'expiresOn', 'grantees', 'error'];
  for (const [loc, raw] of Object.entries(DICTS)) {
    for (const k of keys) {
      assert.match(raw, new RegExp(`'curation\\.drive\\.${k}':`), `${loc} must define curation.drive.${k}`);
    }
  }
});
