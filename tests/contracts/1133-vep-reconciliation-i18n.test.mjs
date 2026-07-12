// #1133 — VepReconciliation i18n migration guard (static source scan).
//
// VepReconciliationIsland + VepReconciliationWidget held their own local `L`
// translation tables (already diverged between the two). This locks the fix:
//   - strings live in the 3 shared dictionaries under comp.vepReconciliation.*
//     (so the i18n parity tooling covers them);
//   - both components consume via usePageI18n() with t('comp.vepReconciliation.*');
//   - the hosting pages inject the bundle via buildPageI18n.
//
// Pure source scan (runs under both `test` and `test:contracts`).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(root, p), 'utf8');

const ISLAND = read('src/components/admin/VepReconciliationIsland.tsx');
const WIDGET = read('src/components/admin/VepReconciliationWidget.tsx');
const PAGE = read('src/pages/admin/vep-reconciliation.astro');
const INDEX = read('src/pages/admin/index.astro');
const DICTS = {
  'pt-BR': read('src/i18n/pt-BR.ts'),
  'en-US': read('src/i18n/en-US.ts'),
  'es-LATAM': read('src/i18n/es-LATAM.ts'),
};

const keysIn = (src) => {
  const re = /'comp\.vepReconciliation\.([a-zA-Z_]+)'/g;
  const set = new Set();
  let m;
  while ((m = re.exec(src)) !== null) set.add(m[1]);
  return set;
};

// ── P1 — no local L translation table survived ───────────────────────────────
test('P1: neither component keeps a local L translation table', () => {
  for (const [name, src] of [['Island', ISLAND], ['Widget', WIDGET]]) {
    assert.ok(!/const L:\s*Record<string,\s*Record<string,\s*string>>/.test(src),
      `${name} must not keep a local L translation table`);
    assert.match(src, /usePageI18n\(\)/, `${name} must consume usePageI18n()`);
    assert.match(src, /t\('comp\.vepReconciliation\./, `${name} must use comp.vepReconciliation.* keys`);
  }
});

// ── P2 — 3-dictionary parity for every used key ──────────────────────────────
test('P2: every comp.vepReconciliation key has parity across the 3 dictionaries', () => {
  const pt = keysIn(DICTS['pt-BR']);
  assert.ok(pt.size >= 70, `expected the full key set in pt-BR, got ${pt.size}`);
  for (const [lang, src] of Object.entries(DICTS)) {
    const k = keysIn(src);
    const missing = [...pt].filter((x) => !k.has(x));
    const extra = [...k].filter((x) => !pt.has(x));
    assert.equal(missing.length, 0, `${lang} missing keys: ${missing.join(', ')}`);
    assert.equal(extra.length, 0, `${lang} has extra keys not in pt-BR: ${extra.join(', ')}`);
  }
});

// ── P3 — every key the components reference actually exists in the dictionaries
test('P3: keys referenced by the components exist in the dictionaries (no orphan t() calls)', () => {
  const used = new Set([...keysIn(ISLAND), ...keysIn(WIDGET)]);
  const pt = keysIn(DICTS['pt-BR']);
  const orphan = [...used].filter((k) => !pt.has(k));
  assert.equal(orphan.length, 0, `component keys with no dictionary entry: ${orphan.join(', ')}`);
});

// ── P4 — the hosting pages inject the bundle ─────────────────────────────────
test('P4: both hosting pages inject the comp.vepReconciliation bundle', () => {
  assert.match(PAGE, /buildPageI18n\(\[\s*'comp\.vepReconciliation'\s*\]/,
    'vep-reconciliation.astro must build the comp.vepReconciliation bundle');
  assert.match(PAGE, /id="page-i18n"[^>]*set:html=\{i18nBundle\}/,
    'vep-reconciliation.astro must emit the page-i18n script');
  assert.match(INDEX, /buildPageI18n\(\[[^\]]*'comp\.vepReconciliation'[^\]]*\]/,
    'admin/index.astro (hosts the widget) must include comp.vepReconciliation in its bundle');
});

// ── P5 — dedup: the diverged subtitle is now two explicit keys, one source ────
test('P5: island subtitle and widget subtitle are distinct keys in the shared namespace', () => {
  assert.match(ISLAND, /t\('comp\.vepReconciliation\.subtitle'\)/, 'island uses .subtitle');
  assert.match(WIDGET, /t\('comp\.vepReconciliation\.widgetSubtitle'\)/, 'widget uses .widgetSubtitle');
  for (const key of ['subtitle', 'widgetSubtitle']) {
    assert.ok(keysIn(DICTS['pt-BR']).has(key), `pt-BR must define ${key}`);
  }
});
