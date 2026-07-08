/**
 * Contract: canonical public host is centralized in ONE module (Rider — Ciclo 4).
 *
 * Before this, the host `nucleoia.vitormr.dev` was hardcoded as a literal across ~20 spots in
 * `src/` (middleware redirect target, OAuth issuer/resource identifiers, MCP base, certificate
 * verification URL crava'd into the PDF, og:url/RSS, i18n footers). The domain flip to
 * `nucleoia.pmigo.org.br` would have meant editing all of them in lockstep — error-prone, and a
 * missed OAuth `.well-known` issuer would break MCP auth silently.
 *
 * Now `src/lib/canonical.ts` is the SINGLE source of truth (CANONICAL_HOST / CANONICAL_ORIGIN). The
 * flip = change one line there. This test is the RATCHET: it fails the build if any other file under
 * `src/` reintroduces the host literal, so the SSOT cannot drift.
 *
 * Scope note: Edge Functions (Deno, separate runtime — cannot import from src/) and historical
 * migration bodies still carry the literal; they are intentionally OUT of scope while vitormr.dev is
 * co-hosted forever (already-issued cert PDFs + live MCP clients reference it). This test guards
 * `src/` only — the deploy artifact whose host the flip actually moves.
 *
 * Offline-only (static source assertions); no DB gating.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const HOST = 'nucleoia.vitormr.dev';
const MODULE_PATH = 'src/lib/canonical.ts';

// ── The SSOT module exists and exports both names ────────────────────────────────
test('canonical.ts: exists and exports CANONICAL_HOST + CANONICAL_ORIGIN', () => {
  const src = read(MODULE_PATH);
  assert.ok(src, 'src/lib/canonical.ts exists');
  assert.match(src, /export const CANONICAL_HOST\s*=/, 'exports CANONICAL_HOST');
  assert.match(src, /export const CANONICAL_ORIGIN\s*=/, 'exports CANONICAL_ORIGIN');
  // ORIGIN is derived from HOST (so a flip needs to touch only HOST)
  assert.match(src, /CANONICAL_ORIGIN\s*=\s*`https:\/\/\$\{CANONICAL_HOST\}`/, 'ORIGIN derives from HOST');
});

// ── RATCHET: the host literal lives ONLY in canonical.ts across all of src/ ───────
test('canonical-host: no other file under src/ hardcodes the host literal', () => {
  const offenders = [];
  const SKIP_DIRS = new Set(['node_modules', '.git', 'dist']);
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      if (SKIP_DIRS.has(name)) continue;
      const full = join(dir, name);
      const st = statSync(full);
      if (st.isDirectory()) { walk(full); continue; }
      if (!/\.(ts|tsx|astro|mjs|js|jsx)$/.test(name)) continue;
      const rel = full.slice(ROOT.length + 1);
      if (rel === MODULE_PATH) continue; // the SSOT is the one allowed home
      const body = readFileSync(full, 'utf8');
      if (body.includes(HOST)) offenders.push(rel);
    }
  };
  walk(resolve(ROOT, 'src'));
  assert.deepEqual(
    offenders,
    [],
    `host literal "${HOST}" must come from src/lib/canonical.ts, not hardcoded. Offenders:\n  ${offenders.join('\n  ')}`,
  );
});

// ── Critical-path files actually import from the SSOT (not a stale copy) ──────────
// #1210: the two .well-known OAuth discovery routes intentionally left this
// list — they derive issuer/resource from the REQUEST origin (url.origin) so
// the same metadata serves the canonical host and the institutional alias.
// The host-literal ratchet above still covers them (no hardcoded hosts).
const CRITICAL = [
  ['src/middleware.ts', /from ["']\.\/lib\/canonical["']/],
  ['src/pages/mcp.ts', /from ["']\.\.\/lib\/canonical["']/],
  ['src/pages/mcp/semantic.ts', /from ["']\.\.\/\.\.\/lib\/canonical["']/],
  ['src/lib/certificates/pdf.ts', /from ["']\.\.\/canonical["']/],
];

for (const [file, importRe] of CRITICAL) {
  test(`canonical-host: ${file} imports from the SSOT module`, () => {
    const src = read(file);
    assert.ok(src, `${file} exists`);
    assert.match(src, importRe, `${file} imports from canonical module`);
  });
}

// ── astro.config.mjs (root, outside src/) also sources site from the SSOT ─────────
test('astro.config.mjs: site comes from CANONICAL_ORIGIN, not a literal', () => {
  const src = read('astro.config.mjs');
  assert.ok(src, 'astro.config.mjs exists');
  assert.ok(!src.includes(HOST), 'no host literal in astro.config.mjs');
  assert.match(src, /from ['"]\.\/src\/lib\/canonical['"]/, 'imports canonical module');
  assert.match(src, /site:\s*CANONICAL_ORIGIN/, 'site uses CANONICAL_ORIGIN');
});

// ── The OAuth issuer/resource identifiers stay absolute (origin, not bare host) ───
// #1210: identifiers now derive from the request origin (alias-ready) instead of
// the pinned canonical constant. RFC 8414 §3.3 still holds: the issuer equals the
// origin the metadata is fetched from.
test('canonical-host: OAuth metadata derives issuer/resource from the request origin', () => {
  const as = read('src/pages/.well-known/oauth-authorization-server.ts');
  const pr = read('src/pages/.well-known/oauth-protected-resource.ts');
  assert.match(as, /url\.origin/, 'authz-server derives from url.origin');
  assert.match(pr, /url\.origin/, 'protected-resource derives from url.origin');
});
