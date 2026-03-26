#!/usr/bin/env node
/**
 * Post-build patch for @astrojs/cloudflare v13 + Cloudflare Pages.
 *
 * The adapter generates dist/server/wrangler.json designed for Workers.
 * Many fields are incompatible with Pages deployments. Instead of
 * stripping them one by one, we use an allowlist of Pages-supported fields.
 *
 * Reference: https://developers.cloudflare.com/pages/functions/wrangler-configuration/
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const WRANGLER_JSON = 'dist/server/wrangler.json';

if (!existsSync(WRANGLER_JSON)) {
  console.log('[patch-wrangler] No dist/server/wrangler.json found, skipping.');
  process.exit(0);
}

// Fields that Cloudflare Pages accepts in wrangler config
const PAGES_ALLOWED_FIELDS = new Set([
  'name',
  'main',
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

// Also strip kv_namespaces entries without an id (auto-generated Sessions)
if (config.kv_namespaces) {
  const valid = config.kv_namespaces.filter(kv => kv.id);
  if (valid.length === 0) {
    delete config.kv_namespaces;
    removed.push('kv_namespaces (no valid ids)');
  } else {
    config.kv_namespaces = valid;
  }
}

if (removed.length > 0) {
  writeFileSync(WRANGLER_JSON, JSON.stringify(config, null, 2) + '\n');
  console.log(`[patch-wrangler] Removed non-Pages fields: ${removed.join(', ')}`);
} else {
  console.log('[patch-wrangler] No incompatible fields found.');
}
