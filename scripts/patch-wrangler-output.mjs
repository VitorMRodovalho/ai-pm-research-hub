#!/usr/bin/env node
/**
 * Post-build patch for @astrojs/cloudflare v13 + Cloudflare Pages.
 *
 * The adapter generates dist/server/wrangler.json with bindings that are
 * incompatible with Pages deployments:
 *   - "assets" binding (reserved by Pages internally)
 *   - "kv_namespaces" without an ID (Sessions auto-enabled)
 *   - "main" field (Workers-only, conflicts with pages_build_output_dir)
 *
 * This script strips those fields so `wrangler pages deploy` succeeds.
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const WRANGLER_JSON = 'dist/server/wrangler.json';

if (!existsSync(WRANGLER_JSON)) {
  console.log('[patch-wrangler] No dist/server/wrangler.json found, skipping.');
  process.exit(0);
}

const raw = readFileSync(WRANGLER_JSON, 'utf-8');
const config = JSON.parse(raw);

const removed = [];

if (config.main) {
  delete config.main;
  removed.push('main');
}

if (config.assets) {
  delete config.assets;
  removed.push('assets');
}

if (config.images) {
  delete config.images;
  removed.push('images');
}

if (config.kv_namespaces) {
  delete config.kv_namespaces;
  removed.push('kv_namespaces');
}

if (config.triggers && (!config.triggers.crons || config.triggers.crons.length === 0)) {
  delete config.triggers;
  removed.push('triggers (empty)');
}

if (removed.length > 0) {
  writeFileSync(WRANGLER_JSON, JSON.stringify(config, null, 2) + '\n');
  console.log(`[patch-wrangler] Removed incompatible fields: ${removed.join(', ')}`);
} else {
  console.log('[patch-wrangler] No incompatible fields found.');
}
