// tests/contracts/889-comms-thumbnail-cache.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json before running.
/**
 * Contract: #889 — Instagram media thumbnails are cached to Supabase Storage during
 * the comms sync, and the dashboard prefers the cached URL over the raw (expiring,
 * often-null) Instagram CDN URL.
 *
 * WHY: Instagram Graph API only returns `thumbnail_url` for VIDEO posts, and the
 * cdninstagram URLs it returns are signed + short-lived. So `/admin/comms` "Top Content"
 * showed broken/placeholder images. The fix downloads the source image in the sync EF
 * and stores it in the public `comms-media` bucket, exposing a stable `cached_image_url`.
 *
 * Static-source ratchet (EF runs in Deno, frontend logic is inline) guarding the three
 * load-bearing pieces from a silent revert. Offline-only; no DB gating.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');

const COMMS = read('src/pages/admin/comms.astro');
const EF = read('supabase/functions/sync-comms-metrics/index.ts');

test('#889: Top Content prefers cached_image_url over the raw thumbnail_url', () => {
  assert.match(
    COMMS,
    /m\.cached_image_url \|\| m\.thumbnail_url/,
    'comms.astro <img src> must fall back cached_image_url -> thumbnail_url',
  );
});

test('#889: sync EF requests media_url (IMAGE posts) and caches to the comms-media bucket', () => {
  assert.match(EF, /fields=[^`'"]*media_url/, 'IG Graph fetch must include media_url (image posts lack thumbnail_url)');
  assert.match(EF, /storage\.from\('comms-media'\)\.upload/, 'EF uploads the cached image to the comms-media bucket');
  assert.match(EF, /cached_image_url:/, 'EF writes cached_image_url back onto the media item row');
});

test('#889: the migration creates the public comms-media bucket + cached_image_url column', () => {
  const dir = 'supabase/migrations';
  const file = readdirSync(resolve(ROOT, dir)).find((f) => f.includes('889_comms_media_thumbnail_cache'));
  assert.ok(file, 'migration 889_comms_media_thumbnail_cache exists');
  const mig = read(`${dir}/${file}`);
  assert.match(mig, /storage\.buckets[\s\S]*'comms-media'[\s\S]*true/, 'creates a PUBLIC comms-media bucket');
  assert.match(mig, /ADD COLUMN IF NOT EXISTS cached_image_url text/, 'adds comms_media_items.cached_image_url');
});
