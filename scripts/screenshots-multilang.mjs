#!/usr/bin/env node
/**
 * S-SC1: Multilingual Screenshots — captura páginas chave em PT, EN, ES.
 * Uso:
 *   npm run build && npm run preview &
 *   npm run screenshots:multilang
 * Ou: PORT=4321 node scripts/screenshots-multilang.mjs (com preview já rodando)
 */
import { chromium } from 'playwright';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const OUT_DIR = join(ROOT, 'docs', 'screenshots');
const PORT = Number(process.env.PORT || 4321);
const BASE = `http://127.0.0.1:${PORT}`;

const PAGES = [
  { path: '/', label: 'index' },
  { path: '/en', label: 'en-index' },
  { path: '/es', label: 'es-index' },
  { path: '/workspace', label: 'workspace-pt' },
  { path: '/en/workspace', label: 'workspace-en' },
  { path: '/es/workspace', label: 'workspace-es' },
  { path: '/artifacts', label: 'artifacts-pt' },
  { path: '/en/artifacts', label: 'artifacts-en' },
  { path: '/gamification', label: 'gamification-pt' },
];

async function main() {
  await mkdir(OUT_DIR, { recursive: true });
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 720 },
    deviceScaleFactor: 2,
  });

  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const results = [];

  for (const { path, label } of PAGES) {
    try {
      const page = await context.newPage();
      const url = `${BASE}${path}`;
      await page.goto(url, { waitUntil: 'networkidle', timeout: 15_000 });
      await page.waitForTimeout(500);
      const fn = `screenshot-${label}-${ts}.png`;
      const outPath = join(OUT_DIR, fn);
      await page.screenshot({ path: outPath, fullPage: false });
      results.push({ path, label, file: fn, ok: true });
      await page.close();
    } catch (err) {
      results.push({ path, label, error: err.message, ok: false });
    }
  }

  await browser.close();

  const manifest = { timestamp: new Date().toISOString(), results };
  await writeFile(
    join(OUT_DIR, `manifest-${ts}.json`),
    JSON.stringify(manifest, null, 2)
  );

  const fails = results.filter((r) => !r.ok);
  if (fails.length) {
    console.error('Failures:', fails);
    process.exit(1);
  }
  console.log(`Screenshots: ${results.filter((r) => r.ok).length}/${PAGES.length} → ${OUT_DIR}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
