import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// #1094 — the LinkedIn enqueue UI on-ramp. The RPC trio (schedule/list/cancel,
// mig 334) and its live behavior are covered by 1099-schedule-comms-post.test.mjs.
// This suite pins the FRONTEND surface that was the remaining gap: the island
// wiring, its mount in comms-ops, and i18n parity for the new keys.

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const island = readFileSync(join(root, 'src/components/admin/CommsSchedulerPanel.tsx'), 'utf8');
const page = readFileSync(join(root, 'src/pages/admin/comms-ops.astro'), 'utf8');

test('1094: the scheduler island calls the RPC trio', () => {
  assert.match(island, /sb\.rpc\(\s*['"]schedule_comms_post['"]/, 'must call schedule_comms_post');
  assert.match(island, /sb\.rpc\(\s*['"]list_scheduled_comms_posts['"]/, 'must call list_scheduled_comms_posts');
  assert.match(island, /sb\.rpc\(\s*['"]cancel_scheduled_comms_post['"]/, 'must call cancel_scheduled_comms_post');
});

test('1094: the island hardcodes channel=linkedin and the 3 supported media types', () => {
  assert.match(island, /p_channel:\s*['"]linkedin['"]/, 'schedule targets the linkedin channel');
  for (const mt of ['TEXT', 'IMAGE', 'DOCUMENT']) {
    assert.ok(island.includes(`'${mt}'`), `media type ${mt} offered`);
  }
});

test('1094: payload keys mirror publish-linkedin (text / image_url+alt_text / document_url+title)', () => {
  // TEXT commentary → text; IMAGE → image_url (+ optional alt_text); DOCUMENT → document_url + title
  assert.match(island, /\btext\b/, 'text (commentary) key present');
  assert.match(island, /image_url/, 'image_url key present');
  assert.match(island, /alt_text/, 'alt_text key present');
  assert.match(island, /document_url/, 'document_url key present');
  assert.match(island, /\btitle\b/, 'title key present');
});

test('1094: comms-ops mounts the scheduler island', () => {
  assert.match(page, /import CommsSchedulerPanel from ['"]\.\.\/\.\.\/components\/admin\/CommsSchedulerPanel['"]/, 'imports the island');
  assert.match(page, /<CommsSchedulerPanel\s+client:load\s*\/>/, 'renders it with client:load');
});

test('1094: new i18n keys have full 3-dictionary parity', () => {
  const dicts = ['pt-BR', 'en-US', 'es-LATAM'].map(l =>
    readFileSync(join(root, `src/i18n/${l}.ts`), 'utf8'));

  // extract comp.comms.sched.* + admin.commsOps.linkedinScheduler* keys per dict
  const extract = (src) => new Set(
    [...src.matchAll(/'((?:comp\.comms\.sched|admin\.commsOps\.linkedinScheduler)[^']*)'/g)].map(m => m[1]));

  const [pt, en, es] = dicts.map(extract);
  assert.ok(pt.size >= 30, `expected the scheduler key block in pt-BR (got ${pt.size})`);
  for (const key of pt) {
    assert.ok(en.has(key), `en-US missing ${key}`);
    assert.ok(es.has(key), `es-LATAM missing ${key}`);
  }
  assert.equal(en.size, pt.size, 'en-US key count matches pt-BR');
  assert.equal(es.size, pt.size, 'es-LATAM key count matches pt-BR');
});
