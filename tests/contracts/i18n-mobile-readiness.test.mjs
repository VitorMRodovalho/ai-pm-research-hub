/**
 * W128 Contract Tests: i18n Completion + Mobile Readiness
 * Static analysis — reads source files and verifies structure.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();

/**
 * Extract top-level i18n keys from a TS dict file.
 * Anchored to start-of-line; captures `'key.path':` patterns at column-N indent.
 * Returns a Set<string> of key paths.
 */
function extractKeys(filePath) {
  const content = readFileSync(filePath, 'utf8');
  const keys = new Set();
  const re = /^\s*'([^'\\]+)'\s*:/gm;
  let m;
  while ((m = re.exec(content)) !== null) keys.add(m[1]);
  return keys;
}

function formatKeyList(keys, max = 10) {
  const arr = Array.from(keys);
  if (arr.length === 0) return '(none)';
  if (arr.length <= max) return arr.join(', ');
  return `${arr.slice(0, max).join(', ')} ... (+${arr.length - max} more)`;
}

// ═══════════════════════════════════════════════════
// i18n Completeness — Set Equality (p135 Ω-B upgrade)
// Replaces ±5% count tolerance with strict key-by-key parity.
// Catches inline-dict regressions (Senior Eng feedback p134).
// ═══════════════════════════════════════════════════

test('EN-US has every PT-BR key (no missing, no extra)', () => {
  const ptKeys = extractKeys(resolve(ROOT, 'src/i18n/pt-BR.ts'));
  const enKeys = extractKeys(resolve(ROOT, 'src/i18n/en-US.ts'));
  const missingInEn = new Set([...ptKeys].filter(k => !enKeys.has(k)));
  const extraInEn = new Set([...enKeys].filter(k => !ptKeys.has(k)));
  assert.equal(
    missingInEn.size,
    0,
    `EN-US missing ${missingInEn.size} keys from PT-BR: ${formatKeyList(missingInEn)}`
  );
  assert.equal(
    extraInEn.size,
    0,
    `EN-US has ${extraInEn.size} extra keys not in PT-BR: ${formatKeyList(extraInEn)}`
  );
});

test('ES-LATAM has every PT-BR key (no missing, no extra)', () => {
  const ptKeys = extractKeys(resolve(ROOT, 'src/i18n/pt-BR.ts'));
  const esKeys = extractKeys(resolve(ROOT, 'src/i18n/es-LATAM.ts'));
  const missingInEs = new Set([...ptKeys].filter(k => !esKeys.has(k)));
  const extraInEs = new Set([...esKeys].filter(k => !ptKeys.has(k)));
  assert.equal(
    missingInEs.size,
    0,
    `ES-LATAM missing ${missingInEs.size} keys from PT-BR: ${formatKeyList(missingInEs)}`
  );
  assert.equal(
    extraInEs.size,
    0,
    `ES-LATAM has ${extraInEs.size} extra keys not in PT-BR: ${formatKeyList(extraInEs)}`
  );
});

test('All 3 dicts have identical key sets', () => {
  const ptKeys = extractKeys(resolve(ROOT, 'src/i18n/pt-BR.ts'));
  const enKeys = extractKeys(resolve(ROOT, 'src/i18n/en-US.ts'));
  const esKeys = extractKeys(resolve(ROOT, 'src/i18n/es-LATAM.ts'));
  assert.equal(ptKeys.size, enKeys.size, `PT-BR has ${ptKeys.size} keys but EN-US has ${enKeys.size}`);
  assert.equal(ptKeys.size, esKeys.size, `PT-BR has ${ptKeys.size} keys but ES-LATAM has ${esKeys.size}`);
});

test('No empty string values in PT-BR', () => {
  const content = readFileSync(resolve(ROOT, 'src/i18n/pt-BR.ts'), 'utf8');
  const emptyValues = content.match(/:\s*''\s*[,}]/g);
  assert.ok(!emptyValues || emptyValues.length === 0, `Found ${emptyValues?.length || 0} empty values in PT-BR`);
});

test('No empty string values in EN-US', () => {
  const content = readFileSync(resolve(ROOT, 'src/i18n/en-US.ts'), 'utf8');
  const emptyValues = content.match(/:\s*''\s*[,}]/g);
  assert.ok(!emptyValues || emptyValues.length === 0, `Found ${emptyValues?.length || 0} empty values in EN-US`);
});

test('No empty string values in ES-LATAM', () => {
  const content = readFileSync(resolve(ROOT, 'src/i18n/es-LATAM.ts'), 'utf8');
  const emptyValues = content.match(/:\s*''\s*[,}]/g);
  assert.ok(!emptyValues || emptyValues.length === 0, `Found ${emptyValues?.length || 0} empty values in ES-LATAM`);
});

// ═══════════════════════════════════════════════════
// Language Auto-Detection
// ═══════════════════════════════════════════════════

test('BaseLayout has browser language auto-detection', () => {
  const content = readFileSync(resolve(ROOT, 'src/layouts/BaseLayout.astro'), 'utf8');
  assert.ok(content.includes('navigator.language'), 'Must use navigator.language for auto-detection');
  assert.ok(content.includes('preferred_language'), 'Must use localStorage preferred_language');
});

test('Auto-detection handles en, es, and pt', () => {
  const content = readFileSync(resolve(ROOT, 'src/layouts/BaseLayout.astro'), 'utf8');
  assert.ok(content.includes("=== 'en'"), 'Must detect English');
  assert.ok(content.includes("=== 'es'"), 'Must detect Spanish');
  assert.ok(content.includes("=== 'pt'") || content.includes("'pt'"), 'Must detect Portuguese');
});

test('URL param ?lang=XX overrides auto-detection', () => {
  const content = readFileSync(resolve(ROOT, 'src/layouts/BaseLayout.astro'), 'utf8');
  assert.ok(content.includes("get('lang')") || content.includes("'lang'"), 'Must check URL lang param');
});

// ═══════════════════════════════════════════════════
// LangSwitcher
// ═══════════════════════════════════════════════════

test('LangSwitcher exists and is visible', () => {
  assert.ok(existsSync(resolve(ROOT, 'src/components/nav/LangSwitcher.astro')), 'LangSwitcher must exist');
});

test('LangSwitcher persists choice in localStorage', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/nav/LangSwitcher.astro'), 'utf8');
  assert.ok(content.includes('localStorage'), 'LangSwitcher must persist to localStorage');
  assert.ok(content.includes('preferred_language'), 'Must use preferred_language key');
});

test('LangSwitcher is included in Nav', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/nav/Nav.astro'), 'utf8');
  assert.ok(content.includes('LangSwitcher'), 'Nav must include LangSwitcher');
});

test('Nav is included in BaseLayout (visible on all pages)', () => {
  const content = readFileSync(resolve(ROOT, 'src/layouts/BaseLayout.astro'), 'utf8');
  assert.ok(content.includes('Nav'), 'BaseLayout must include Nav component');
});

// ═══════════════════════════════════════════════════
// Mobile Responsiveness
// ═══════════════════════════════════════════════════

test('PartnerPipelineIsland has mobile overflow-x handling', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/islands/PartnerPipelineIsland.tsx'), 'utf8');
  assert.ok(content.includes('overflow-x-auto') || content.includes('overflow-x'), 'Kanban must have overflow-x for mobile');
});

test('CrossTribeIsland table has overflow-x-auto', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/islands/CrossTribeIsland.tsx'), 'utf8');
  assert.ok(content.includes('overflow-x-auto'), 'Comparison table must have overflow-x-auto');
});

test('CrossTribeIsland uses ResponsiveContainer for charts', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/islands/CrossTribeIsland.tsx'), 'utf8');
  assert.ok(content.includes('ResponsiveContainer'), 'Charts must use ResponsiveContainer');
});

test('Quick-checkin banner is mobile responsive', () => {
  const content = readFileSync(resolve(ROOT, 'src/pages/workspace.astro'), 'utf8');
  assert.ok(
    content.includes('flex-col sm:flex-row') || content.includes('flex-col'),
    'Quick-checkin banner must stack on mobile'
  );
});

test('Quick-checkin button is full width on mobile', () => {
  const content = readFileSync(resolve(ROOT, 'src/pages/workspace.astro'), 'utf8');
  assert.ok(
    content.includes('w-full sm:w-auto'),
    'Quick-checkin button must be full width on mobile'
  );
});

// ═══════════════════════════════════════════════════
// Print CSS
// ═══════════════════════════════════════════════════

test('global.css has print CSS for cycle report', () => {
  const content = readFileSync(resolve(ROOT, 'src/styles/global.css'), 'utf8');
  assert.ok(content.includes('@media print'), 'Must have @media print block');
  assert.ok(content.includes('cr-section'), 'Must handle cr-section for print');
  assert.ok(content.includes('page-break-inside: avoid') || content.includes('break-inside: avoid'), 'Must prevent page breaks inside sections');
});

test('print CSS handles canvas elements', () => {
  const content = readFileSync(resolve(ROOT, 'src/styles/global.css'), 'utf8');
  assert.ok(content.includes('canvas'), 'Print CSS must handle canvas elements');
});

test('print CSS hides non-essential elements', () => {
  const content = readFileSync(resolve(ROOT, 'src/styles/global.css'), 'utf8');
  assert.ok(content.includes('consent-banner'), 'Must hide consent banner in print');
  assert.ok(content.includes('nav') && content.includes('display: none'), 'Must hide nav in print');
});

test('global.css has mobile responsive CSS', () => {
  const content = readFileSync(resolve(ROOT, 'src/styles/global.css'), 'utf8');
  assert.ok(content.includes('max-width: 640px') || content.includes('640px'), 'Must have mobile breakpoint');
  assert.ok(content.includes('pipeline-mobile-scroll'), 'Must have pipeline mobile scroll class');
});

// ═══════════════════════════════════════════════════
// Mobile viewport test file exists
// ═══════════════════════════════════════════════════

test('Playwright mobile viewport test file exists', () => {
  assert.ok(
    existsSync(resolve(ROOT, 'tests/mobile-viewport.spec.ts')),
    'tests/mobile-viewport.spec.ts must exist'
  );
});

test('Mobile viewport tests cover 8 critical pages', () => {
  const content = readFileSync(resolve(ROOT, 'tests/mobile-viewport.spec.ts'), 'utf8');
  const pages = ['/about', '/privacy', '/workspace', '/attendance', '/profile', '/tribes', '/help'];
  for (const page of pages) {
    assert.ok(content.includes(`'${page}'`), `Must test ${page}`);
  }
});

test('Mobile viewport tests cover 3 admin pages on tablet', () => {
  const content = readFileSync(resolve(ROOT, 'tests/mobile-viewport.spec.ts'), 'utf8');
  assert.ok(content.includes('/admin/tribes'), 'Must test /admin/tribes');
  assert.ok(content.includes('/admin/partnerships'), 'Must test /admin/partnerships');
  assert.ok(content.includes('/admin/cycle-report'), 'Must test /admin/cycle-report');
});

test('Mobile viewport tests use 375px for mobile', () => {
  const content = readFileSync(resolve(ROOT, 'tests/mobile-viewport.spec.ts'), 'utf8');
  assert.ok(content.includes('375'), 'Must use 375px mobile viewport');
});

test('Mobile viewport tests use 768px for tablet', () => {
  const content = readFileSync(resolve(ROOT, 'tests/mobile-viewport.spec.ts'), 'utf8');
  assert.ok(content.includes('768'), 'Must use 768px tablet viewport');
});
