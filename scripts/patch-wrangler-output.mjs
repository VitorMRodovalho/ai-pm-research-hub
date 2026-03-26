#!/usr/bin/env node
/**
 * Post-build patch for @astrojs/cloudflare v13 + Cloudflare Pages.
 *
 * The adapter generates dist/server/wrangler.json designed for Workers.
 * Many fields are incompatible with Pages deployments.
 *
 * Two-step fix:
 * 1. Strip non-Pages fields from wrangler.json (including "main")
 * 2. Copy dist/server/ contents into dist/_worker.js/ directory
 *    Pages convention: dist/_worker.js/ is auto-detected as the worker bundle
 *
 * Reference: https://developers.cloudflare.com/pages/functions/wrangler-configuration/
 */
import { readFileSync, writeFileSync, existsSync, cpSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const WRANGLER_JSON = 'dist/server/wrangler.json';
const WORKER_DIR = 'dist/_worker.js';

if (!existsSync(WRANGLER_JSON)) {
  console.log('[patch-wrangler] No dist/server/wrangler.json found, skipping.');
  process.exit(0);
}

// --- Step 1: Clean wrangler.json ---

// Fields that Cloudflare Pages accepts in wrangler config
const PAGES_ALLOWED_FIELDS = new Set([
  'name',
  'pages_build_output_dir',
  'compatibility_date',
  'compatibility_flags',
  'vars',
  'd1_databases',
  'durable_objects',
  'kv_namespaces',
  'r2_buckets',
  'services',
  'analytics_engine_datasets',
  'ai',
  'browser',
  'hyperdrive',
  'send_email',
  'vectorize',
  'queues',
  'mtls_certificates',
  'pipelines',
  // Internal / meta fields the CLI expects
  'configPath',
  'userConfigPath',
  'topLevelName',
  'definedEnvironments',
  'legacy_env',
  'dev',
]);

const raw = readFileSync(WRANGLER_JSON, 'utf-8');
const config = JSON.parse(raw);

const removed = [];
for (const key of Object.keys(config)) {
  if (!PAGES_ALLOWED_FIELDS.has(key)) {
    delete config[key];
    removed.push(key);
  }
}

// Strip kv_namespaces entries without an id (auto-generated Sessions)
if (config.kv_namespaces) {
  const valid = config.kv_namespaces.filter(kv => kv.id);
  if (valid.length === 0) {
    delete config.kv_namespaces;
    removed.push('kv_namespaces (no valid ids)');
  } else {
    config.kv_namespaces = valid;
  }
}

writeFileSync(WRANGLER_JSON, JSON.stringify(config, null, 2) + '\n');
if (removed.length > 0) {
  console.log(`[patch-wrangler] Removed non-Pages fields: ${removed.join(', ')}`);
}

// --- Step 2: Create _worker.js directory bundle ---
// Pages auto-detects dist/_worker.js/ as the advanced-mode worker.
// Copy the entire server output there so entry.mjs can resolve ./chunks/

mkdirSync(WORKER_DIR, { recursive: true });
cpSync('dist/server/chunks', join(WORKER_DIR, 'chunks'), { recursive: true });
cpSync('dist/server/entry.mjs', join(WORKER_DIR, 'index.js'));

console.log('[patch-wrangler] Created dist/_worker.js/ bundle (entry + chunks)');
