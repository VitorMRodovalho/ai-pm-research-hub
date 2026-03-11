#!/usr/bin/env node
/**
 * Pre-build verification: ensures critical Astro page files exist.
 * Fails fast with a clear error if any are missing (e.g. ENOENT on Cloudflare).
 */
import { existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');

const CRITICAL_PAGES = [
  'src/pages/admin/board-governance.astro',
  'src/pages/admin/comms-ops.astro',
  'src/pages/admin/portfolio.astro',
  'src/pages/index.astro',
];

for (const rel of CRITICAL_PAGES) {
  const path = resolve(ROOT, rel);
  if (!existsSync(path)) {
    console.error(`[verify-build-pages] ENOENT: ${rel} not found at ${path}`);
    process.exit(1);
  }
}
console.log('[verify-build-pages] All critical pages present.');
