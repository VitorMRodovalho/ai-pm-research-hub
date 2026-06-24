import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();

/**
 * #856 — the SSR auth-gate was RETIRED (ADR-0106). The dead `src/middleware/index.ts`
 * had been shadowed by `src/middleware.ts` for ~3 months (Astro loads ONE middleware
 * module; the `.ts` wins over `index.ts`), so it never ran in prod. The real boundary
 * is RLS + SECURITY DEFINER RPCs + the client-side capability gate (canFor(), ADR-0011).
 *
 * These guards keep the retirement honest:
 *  1. anti-shadow — fail if `src/middleware/index.ts` ever reappears while
 *     `src/middleware.ts` exists (root cause of #855 AND #856).
 *  2. backstop — no admin `.astro` may establish an AUTHENTICATED Supabase context in
 *     its SSR frontmatter (no service-role key, no reading the `sb-access-token` cookie
 *     into a client). Anon fetch of PUBLIC data (the analytics.astro pattern) is allowed.
 *     This preserves "the SSR shell carries no sensitive data" without a runtime gate;
 *     if it ever fails, ADR-0106 must be revisited (a gate would then have real value).
 */

// ── 1) Anti-shadow guard ──────────────────────────────────────────────────
test('#856 only one middleware module exists — src/middleware/index.ts must NOT shadow src/middleware.ts', () => {
  const liveExists = existsSync(resolve(ROOT, 'src/middleware.ts'));
  const shadowExists = existsSync(resolve(ROOT, 'src/middleware/index.ts'));

  assert.ok(liveExists, 'src/middleware.ts (the loaded middleware) must exist');
  assert.equal(
    shadowExists,
    false,
    'src/middleware/index.ts must NOT exist: Astro loads ONE middleware module and the ' +
      '.ts silently shadows index.ts — reintroducing it would silently kill src/middleware.ts ' +
      '(canonical redirect + CSRF + SSR security headers). See ADR-0106, #855, #856.',
  );
});

test('#856 the live middleware does not silently resurrect a redirect-based auth gate', () => {
  // Belt-and-suspenders: if someone re-adds an auth redirect to the live middleware,
  // they must do it deliberately (and revisit ADR-0106), not by pasting the dead code.
  const live = readFileSync(resolve(ROOT, 'src/middleware.ts'), 'utf8');
  assert.equal(
    /auth=required/.test(live),
    false,
    'src/middleware.ts contains an `auth=required` redirect — the SSR auth gate was retired ' +
      '(ADR-0106). If reintroducing a gate, update ADR-0106 and this guard intentionally.',
  );
});

// ── 2) Frontmatter backstop ───────────────────────────────────────────────
// Recursively collect every .astro page under src/pages/admin/**.
function collectAstro(dir) {
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...collectAstro(full));
    else if (entry.name.endsWith('.astro')) out.push(full);
  }
  return out;
}

// Extract the frontmatter (the code fence between the first two `---` lines), which
// runs SERVER-SIDE in the Worker during SSR, before any client JS.
function frontmatter(src) {
  const m = src.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  return m ? m[1] : '';
}

const ADMIN_PAGES_DIR = resolve(ROOT, 'src/pages/admin');

test('#856 backstop: no admin .astro establishes an authenticated Supabase context in SSR frontmatter', () => {
  const pages = collectAstro(ADMIN_PAGES_DIR);
  assert.ok(pages.length > 0, 'expected to find admin pages');

  const offenders = [];
  for (const page of pages) {
    const fm = frontmatter(readFileSync(page, 'utf8'));
    const rel = page.replace(ROOT + '/', '');

    // Forbidden: a service-role client in SSR (would bypass RLS server-side).
    if (/service_role|SERVICE_ROLE/.test(fm)) {
      offenders.push(`${rel}: references service_role in SSR frontmatter`);
    }
    // Forbidden: reading the user's auth token cookie to build an authed SSR client —
    // via Astro.cookies, the raw Cookie header, or the token name directly.
    if (
      /sb-access-token/.test(fm) ||
      /Astro\.cookies/.test(fm) ||
      /headers\.get\(\s*['"]cookie['"]\s*\)/i.test(fm)
    ) {
      offenders.push(`${rel}: reads auth cookie (sb-access-token / Astro.cookies / Cookie header) in SSR frontmatter`);
    }
    // Forbidden: pulling the user's session/JWT server-side.
    if (/\.auth\.(getUser|getSession|setSession)\s*\(/.test(fm)) {
      offenders.push(`${rel}: calls supabase.auth.getUser/getSession/setSession in SSR frontmatter`);
    }
  }

  assert.deepEqual(
    offenders,
    [],
    'Admin pages must not fetch authenticated/PII data in SSR frontmatter (ADR-0106 — there is no ' +
      'SSR auth gate; the shell must stay data-free, RLS is the boundary). Offenders:\n  ' +
      offenders.join('\n  '),
  );
});
