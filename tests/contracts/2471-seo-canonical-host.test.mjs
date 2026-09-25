/**
 * #2471: every public page declares ONE address to search engines and link previews.
 *
 * The same app answers 200 on several hosts (the OAuth/MCP host, the chapter-seat
 * entrance and the initiative's own domain). Without a declared canonical, search engines
 * index them as duplicate sites. The GP chose SEO_CANONICAL_HOST (src/lib/canonical.ts) as
 * the one address; this guard keeps every SEO surface pointed at it:
 *   - BaseLayout derives ONE url from SEO_CANONICAL_ORIGIN + the request path, and BOTH
 *     `<link rel="canonical">` and `og:url` use it (condition bound to result);
 *   - no page emits its own og:url or canonical (5 pages used to add a SECOND og:url
 *     pointing at the OAuth host);
 *   - the app does NOT serve its own robots.txt (see the last test for why).
 * astro.config `site` (sitemap + feeds) is guarded in canonical-host-centralization.
 *
 * Offline-only (static source assertions); no DB gating.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const LAYOUT = 'src/layouts/BaseLayout.astro';

// Drop `//` line comments and `<!-- -->` so a comment that NAMES the pattern cannot satisfy it.
// Repeat until stable: one pass over `<!<!---->--` would leave a new `<!--` behind.
const stripComments = (s) => {
  let prev;
  do {
    prev = s;
    s = s.replace(/<!--[\s\S]*?-->/g, '');
  } while (s !== prev);
  return s.replace(/^\s*\/\/.*$/gm, '');
};

test('BaseLayout: one SEO url, derived from SEO_CANONICAL_ORIGIN + request path, feeds BOTH canonical and og:url', () => {
  const src = stripComments(read(LAYOUT));
  assert.match(src, /import \{[^}]*\bSEO_CANONICAL_ORIGIN\b[^}]*\} from ['"]\.\.\/lib\/canonical['"]/,
    'BaseLayout imports SEO_CANONICAL_ORIGIN from the SSOT');
  assert.match(src, /const seoCanonicalUrl = new URL\(Astro\.url\.pathname, SEO_CANONICAL_ORIGIN\)\.href;/,
    'seoCanonicalUrl = SEO origin + request PATH (no query string, never the request host)');
  assert.match(src, /<link rel="canonical" href=\{seoCanonicalUrl\} \/>/, 'canonical link uses seoCanonicalUrl');
  const ogUrls = [...src.matchAll(/<meta property="og:url" content=\{([^}]+)\} \/>/g)].map((m) => m[1]);
  assert.deepEqual(ogUrls, ['seoCanonicalUrl'], 'exactly one og:url, and it is seoCanonicalUrl');
});

test('no page under src/ emits its own og:url or rel=canonical (BaseLayout is the one owner)', () => {
  const offenders = [];
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      const full = join(dir, name);
      if (statSync(full).isDirectory()) { walk(full); continue; }
      if (!/\.(astro|tsx|ts|jsx|js)$/.test(name)) continue;
      const rel = full.slice(ROOT.length + 1);
      if (rel === LAYOUT) continue;
      const body = stripComments(readFileSync(full, 'utf8'));
      if (/property=["']og:url["']/.test(body) || /rel=["']canonical["']/.test(body)) offenders.push(rel);
    }
  };
  walk(resolve(ROOT, 'src'));
  assert.deepEqual(offenders, [], `og:url/canonical must come only from ${LAYOUT}. Offenders:\n  ${offenders.join('\n  ')}`);
});

// #2471 (regression measured live on 2026-09-25): an app-served robots.txt REPLACED the
// Cloudflare-managed one that the hosts served while the app had none (it carried the
// "content signals" about AI use). Cloudflare only prepends its settings when the zone's
// "Bot Preference Sync" is on, and it was off. GP decision: keep the managed file and give
// the sitemap to Search Console. Re-adding a robots route is a policy change: decide it
// first (turn Bot Preference Sync on, or declare the signals), then drop this guard.
test('robots.txt: the app does NOT serve one, so the Cloudflare-managed file stays in effect', () => {
  const offenders = readdirSync(resolve(ROOT, 'src/pages')).filter((n) => /^robots\.txt(\.|$)/.test(n));
  assert.deepEqual(offenders, [], `src/pages must not define robots.txt: ${offenders.join(', ')}`);
  assert.ok(!existsSync(resolve(ROOT, 'public/robots.txt')), 'public/robots.txt must not exist either');
});
