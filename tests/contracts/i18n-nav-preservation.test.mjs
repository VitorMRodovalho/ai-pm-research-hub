/**
 * p123 — Internal navigation must preserve language context.
 *
 * Why this exists
 * ----------------
 * The platform is trilingual (pt-BR canonical, /en wrapper, /es wrapper).
 * SSR pages detect lang from `?lang=en-US` or `/en/` prefix; wrappers
 * meta-refresh /en/route → /route?lang=en-US. But hardcoded internal
 * `<a href="/route">` links (without `langPrefix` or `lp` interpolation)
 * drop the user back to PT-BR after navigation.
 *
 * Before p123 the platform had 89 such hardcoded links across 50 files.
 * Top offender: tribe/[id].astro with 9 hits — exactly the case the user
 * reported when presenting the platform in English. Sweep + fix happened
 * in p123 commits 65ad84b … (this test guards against regression).
 *
 * Allowed patterns:
 *   <a href={`${langPrefix}/route`}>      ← Astro frontmatter HTML (JSX)
 *   <a href="${langPrefix}/route">         ← Astro script template literal
 *   <a href="${lp}/route">                 ← Astro script (lp = window.__LANG_PREFIX)
 *   <a href={`${lp}/route`}>               ← TSX component (lp = lang === ... ? '/en' : ...)
 *   <a href="/api/...">                    ← API endpoints (no lang concept)
 *   <a href="/oauth/...">                  ← OAuth flow (no lang)
 *   <a href="/cdn-cgi/...">                ← Cloudflare internals
 *   <a href="/?lang=...">                  ← Explicit lang override (rare)
 *
 * Forbidden:
 *   <a href="/route">  ← drops the user's language context
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';

const ROOTS = ['src/pages', 'src/components', 'src/layouts'];
const EXCLUDE_DIRS = ['en', 'es']; // wrapper routes — they ARE the redirects
const EXCLUDE_FILES = new Set(['database.gen.ts']);

// Hardcoded internal href without lang interpolation
const FORBIDDEN_HREF = /<a\s+[^>]*href=["'](\/(?!api|oauth|cdn-cgi|en\/|es\/|\?)[a-zA-Z][^"'?\s]*)["'`]/g;

async function* walk(dir) {
  let entries;
  try { entries = await fs.readdir(dir, { withFileTypes: true }); }
  catch { return; }
  for (const e of entries) {
    if (EXCLUDE_FILES.has(e.name)) continue;
    if (e.isDirectory()) {
      // Skip /en/ and /es/ wrapper trees (those redirect by design)
      if (EXCLUDE_DIRS.includes(e.name)) continue;
      yield* walk(path.join(dir, e.name));
    } else if (e.isFile()) {
      if (e.name.endsWith('.astro') || e.name.endsWith('.tsx')) {
        yield path.join(dir, e.name);
      }
    }
  }
}

test('p123: no hardcoded internal `<a href="/route">` (must use ${langPrefix}/${lp})', async () => {
  const offenders = [];

  for (const root of ROOTS) {
    const abs = path.resolve(root);
    for await (const file of walk(abs)) {
      const src = await fs.readFile(file, 'utf-8');
      FORBIDDEN_HREF.lastIndex = 0;
      let m;
      while ((m = FORBIDDEN_HREF.exec(src)) !== null) {
        const lineNum = src.slice(0, m.index).split('\n').length;
        const rel = path.relative(path.resolve('.'), file);
        offenders.push({ file: rel, line: lineNum, route: m[1] });
      }
    }
  }

  if (offenders.length > 0) {
    const lines = offenders.map(o =>
      `  ${o.file}:${o.line}  href="${o.route}"`
    ).join('\n');
    assert.fail(
      `Found ${offenders.length} hardcoded internal <a href> without lang preservation:\n${lines}\n\n` +
      `Fix patterns:\n` +
      `  Astro frontmatter: <a href={\`\${langPrefix}/route\`}>\n` +
      `  Astro script:      <a href="\${(window).__LANG_PREFIX || ''}/route">\n` +
      `                  or <a href="\${lp}/route"> (with const lp = window.__LANG_PREFIX)\n` +
      `  TSX component:     <a href={\`\${lp}/route\`}> (with const lp from lang prop)\n\n` +
      `See p123 issue log entry for the canonical patterns + commit history.`
    );
  }
});

test('p123: every PT-BR public page has /en/ and /es/ wrappers', async () => {
  const ptPages = new Set();
  for await (const f of walk(path.resolve('src/pages'))) {
    if (!f.endsWith('.astro')) continue;
    const rel = path.relative(path.resolve('src/pages'), f);
    // Skip 404 (Astro fallback page; not a navigable route)
    if (rel === '404.astro') continue;
    // Skip api/oauth/.well-known
    if (rel.startsWith('api/') || rel.startsWith('oauth/') || rel.startsWith('.well-known/')) continue;
    ptPages.add(rel.replace('.astro', ''));
  }

  const enPages = new Set();
  try {
    for await (const f of fsWalk(path.resolve('src/pages/en'))) {
      if (!f.endsWith('.astro')) continue;
      const rel = path.relative(path.resolve('src/pages/en'), f);
      enPages.add(rel.replace('.astro', ''));
    }
  } catch {}

  const esPages = new Set();
  try {
    for await (const f of fsWalk(path.resolve('src/pages/es'))) {
      if (!f.endsWith('.astro')) continue;
      const rel = path.relative(path.resolve('src/pages/es'), f);
      esPages.add(rel.replace('.astro', ''));
    }
  } catch {}

  const missingEn = [...ptPages].filter(p => !enPages.has(p));
  const missingEs = [...ptPages].filter(p => !esPages.has(p));

  assert.deepEqual(
    missingEn, [],
    `PT-BR pages without /en/ wrapper:\n${missingEn.map(p => `  /${p}`).join('\n')}\n\nCreate src/pages/en/${missingEn[0] || 'X'}.astro with the canonical meta-refresh / Astro.redirect pattern (see src/pages/en/about.astro or src/pages/en/tribe/[id].astro).`
  );
  assert.deepEqual(
    missingEs, [],
    `PT-BR pages without /es/ wrapper:\n${missingEs.map(p => `  /${p}`).join('\n')}\n\nSame as EN but with lang=es-LATAM.`
  );
});

async function* fsWalk(dir) {
  let entries;
  try { entries = await fs.readdir(dir, { withFileTypes: true }); }
  catch { return; }
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) yield* fsWalk(full);
    else if (e.isFile()) yield full;
  }
}
