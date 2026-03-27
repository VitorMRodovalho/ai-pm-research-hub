# ASTRO 6 UPGRADE RUNBOOK
## AI & PM Research Hub — Fact-Based Migration Plan

**Version:** 1.0 (definitive)
**Date:** 28 March 2026
**Sources:** Official Astro 6 upgrade guide, @astrojs/cloudflare v13 docs, Astro 6.0 blog post, GitHub issues, codebase pre-check (13 verifications)
**Current state:** Astro 5.17.1, @astrojs/cloudflare 12.6.12, @astrojs/react 5.0.0

---

## 1. FACT-CHECKED RISK MATRIX

| Breaking Change | Applies to us? | Evidence | Action required |
|----------------|---------------|----------|-----------------|
| Zod 3→4 | **NO** | Pre-check #1: zero Zod imports, not in package.json | None |
| Content Collections removed | **NO** | Pre-check #2: no `src/content/`, no `getCollection`/`defineCollection` | None |
| `Astro.glob()` removed | **NO** | Pre-check #3: zero matches | None |
| `<ViewTransitions />` deprecated | **NO** | Pre-check #4: zero matches | None |
| `Astro.locals.runtime` **REMOVED** | **YES** | Pre-check #5: `Nav.astro:124` uses `(Astro.locals as any)?.runtime?.env` | **MUST FIX** |
| Node 22+ required | **Already met** | Pre-check #12: .nvmrc=22, running v24.14.0 | None |
| Vite 6→7 | **Auto** | Bundled with Astro 6, no direct Vite config in project | Monitor build |
| `i18n.redirectToDefaultLocale` changed | **NO** | Pre-check #9: no Astro i18n config (manual dictionaries) | None |
| `preserveScriptOrder` now default | **Maybe** | Script/style ordering in `.astro` files changes | Verify visual output |
| Shiki 3→4 (code highlighting) | **NO** | We don't use `<Code />` component or MD/MDX | None |
| `getImage()` throws on client | **Unlikely** | Need to verify if called client-side anywhere | Quick grep |
| Responsive image style emission changed | **Unlikely** | Need to verify if using Astro's image optimization | Quick grep |
| Cloudflare adapter v12→v13 | **YES** | Major breaking changes (see section 2) | **MUST UPGRADE** |
| Wrangler config entrypoint | **YES** | New `main` field required (see section 2) | **MUST UPDATE** |

**Summary: 3 mandatory changes, rest is zero-impact.**

---

## 2. THE CRITICAL CHANGE: @astrojs/cloudflare v12→v13

This is the single most impactful breaking change for our project. From official docs:

### 2.1 `Astro.locals.runtime` is REMOVED

**Official doc (astro.build/docs/guides/integrations-guide/cloudflare):**
> "The Astro.locals.runtime object has been removed in favor of direct access to Cloudflare Workers APIs."

**Our code (Nav.astro:124):**
```javascript
// CURRENT (Astro 5 + @astrojs/cloudflare v12)
(Astro.locals as any)?.runtime?.env
```

**Required change (Astro 6 + @astrojs/cloudflare v13):**
```javascript
// NEW — direct import from cloudflare:workers
import { env } from 'cloudflare:workers';
// Use env.MY_VARIABLE directly
```

**Migration steps from official docs:**

| Old pattern (v12) | New pattern (v13) |
|-------------------|-------------------|
| `Astro.locals.runtime.env.MY_VAR` | `import { env } from 'cloudflare:workers'` then `env.MY_VAR` |
| `Astro.locals.runtime.cf` | `import { cf } from 'cloudflare:workers'` |
| `Astro.locals.runtime.caches` | `import { caches } from 'cloudflare:workers'` |
| `Astro.locals.runtime.ctx` | `import { ctx } from 'cloudflare:workers'` |

**Impact assessment:** Our Nav.astro:124 accesses env variables via `Astro.locals.runtime.env`. This is the ONLY usage in the entire codebase (verified by pre-check #5). The fix is surgical: 1 file, ~3 lines changed.

### 2.2 Wrangler config: new entrypoint

**Official doc:**
> "The main field in your Wrangler configuration now points to `@astrojs/cloudflare/entrypoints/server`."

**Required:** Check if we have a `wrangler.toml` or `wrangler.jsonc` file. If yes, update the `main` field.

```jsonc
// wrangler.jsonc — NEW
{
  "main": "@astrojs/cloudflare/entrypoints/server"
}
```

**If we DON'T have a wrangler config:** The adapter handles it automatically. No action needed.

### 2.3 Dev server now uses workerd

**Official doc:**
> "`astro dev` and `astro preview` now use the Cloudflare Vite plugin to run your site using the real Workers runtime (workerd) instead of Node.js."

**Impact for us:** This is the BENEFIT, not a risk. Our 14 Sentry TDZ errors (`Cannot access before initialization`) are likely caused by the dev/prod mismatch that Astro 6 eliminates. The unified runtime means what works in dev works in prod.

**New adapter config:**
```javascript
// astro.config.mjs — NEW
import cloudflare from '@astrojs/cloudflare';

export default defineConfig({
  adapter: cloudflare({
    platformProxy: {
      enabled: true,  // enables workerd in dev
    },
  }),
});
```

**Verify:** Check if our current `astro.config.mjs` already has adapter options that may conflict.

### 2.4 `cloudflareModules` option removed

**Official doc:** "The `cloudflareModules` adapter option has been removed because it is no longer necessary."

**Impact:** Only if we use this option. Verify in `astro.config.mjs`.

---

## 3. MIDDLEWARE ANALYSIS

**File:** `src/middleware/index.ts` (90 lines)

**Risk level:** LOW-MEDIUM

The middleware uses `defineMiddleware` from `astro:middleware`. This API is NOT listed in Astro 6 breaking changes. However:

**Things to verify:**
1. Does our middleware access `context.locals` in a way that depends on the Cloudflare runtime shape?
2. Does it set properties on `context.locals` that other components read?
3. The Supabase auth session handling — does it depend on any Cloudflare-specific context?

**Action:** The Code team should read the full middleware file and cross-reference with the new `context.locals` shape in Astro 6 + Cloudflare v13.

---

## 4. env.d.ts ANALYSIS

**File:** `src/env.d.ts`

**Current content:** Standard `astro/client` reference + `ImportMetaEnv` typing.

**Astro 6 change:** Astro 6 introduces `astro:env` as a new way to handle environment variables (experimental→stable). However, the old `ImportMetaEnv` pattern still works.

**Action:** No immediate change needed. Can optionally migrate to `astro:env` later for better type safety.

---

## 5. SENTRY ANALYSIS

**Our setup:** Custom Sentry integration (NOT `@sentry/astro` plugin). Used in 6 files:
- `src/lib/sentry.ts`
- `src/components/ErrorBoundary.tsx`
- `src/layouts/BaseLayout.astro`
- 3 i18n dictionary files

**Risk level:** LOW

Since we don't use `@sentry/astro` as an Astro integration, the Vite 7 upgrade won't affect our Sentry config. Our Sentry is initialized manually in client-side scripts.

**Action:** Verify that `@sentry/browser` (or whichever Sentry package we use) is compatible with Vite 7. Check `package.json` for exact Sentry package.

---

## 6. PLAYWRIGHT ANALYSIS

**File:** `playwright.config.ts`

**Config:** Uses `npm run dev` as webServer.

**Risk level:** LOW-MEDIUM

The Astro 6 dev server (Vite 7 + workerd) may have different startup timing. Playwright's `webServer.reuseExistingServer` and timeout settings may need adjustment.

**Known issue:** GitHub issue #15310 reported Vitest breaking with Cloudflare adapter in v6 beta. This was for `vitest --browser`, not Playwright. However, the underlying cause (Cloudflare Vite plugin's `resolve.external` setting) could theoretically affect Playwright if it runs through Vite.

**Action:**
1. After upgrade, run `npx playwright test` immediately
2. If timeout errors: increase `webServer.timeout` in config
3. If `resolve.external` errors: may need to exclude Playwright from Cloudflare plugin scope
4. Check if issue #15310 was resolved in stable (6.0.8)

---

## 7. VERSION COMPATIBILITY MATRIX

| Package | Current | Target (Astro 6) | Notes |
|---------|---------|-------------------|-------|
| `astro` | ^5.17.1 | 6.0.8 (latest stable) | Core upgrade |
| `@astrojs/cloudflare` | ^12.6.12 | 13.x (latest) | **Major breaking changes** (section 2) |
| `@astrojs/react` | ^5.0.0 | 5.x or 6.x | Check Astro 6 compatibility |
| `vite` | (bundled) | 7.x (bundled with Astro 6) | Auto-upgraded |
| `react` | 19.x | 19.x | No change needed |
| `tailwindcss` | 4.x | 4.x | No change needed |
| `@sentry/*` | (check) | (check) | Verify Vite 7 compat |
| `playwright` | (check) | (check) | Verify with new dev server |
| `vitest` | (check) | ≥3.2 or ≥4.1-beta.5 | Required for `getViteConfig()` |
| Node.js | 22 (.nvmrc) | 22.12.0+ | Already met |

---

## 8. PRE-MIGRATION CHECKLIST (run via Code BEFORE upgrading)

```bash
# A. Verify all Astro.locals usages (beyond Nav.astro)
grep -rn "Astro\.locals\|context\.locals" src/ --include="*.ts" --include="*.astro"

# B. Check for wrangler config
ls -la wrangler.* 2>/dev/null

# C. Check astro.config.mjs adapter options
cat astro.config.mjs

# D. Check Sentry package version
grep -E '"@sentry' package.json

# E. Check Vitest version (needed ≥3.2 for Astro 6)
grep '"vitest"' package.json

# F. Check for getImage() client-side usage
grep -rn "getImage" src/ --include="*.tsx" --include="*.ts" --include="*.astro"

# G. Check for responsive image usage
grep -rn "widths\|densities\|layout=" src/ --include="*.astro" | grep -i "image\|img\|Picture"

# H. Check middleware full content
cat src/middleware/index.ts

# I. Check for cloudflareModules in config
grep -r "cloudflareModules" astro.config.* wrangler.* 2>/dev/null

# J. Full dependency tree check
npm ls astro @astrojs/cloudflare @astrojs/react vite vitest @sentry/browser @sentry/node 2>/dev/null
```

---

## 9. UPGRADE EXECUTION PLAN

### Step 0: Branch (5 min)
```bash
git checkout -b chore/upgrade-astro-6
```

### Step 1: Upgrade packages (10 min)
```bash
# Astro's official upgrade CLI handles dependency resolution
npx @astrojs/upgrade
# This upgrades: astro, @astrojs/cloudflare, @astrojs/react, and related deps
```

### Step 2: Fix Nav.astro — `Astro.locals.runtime` removal (15 min)
```javascript
// Nav.astro:124 — OLD
const envValue = (Astro.locals as any)?.runtime?.env?.SOME_VAR;

// Nav.astro:124 — NEW
// If in .astro frontmatter (server-side):
import { env } from 'cloudflare:workers';
const envValue = env.SOME_VAR;

// If in inline <script> (client-side):
// This was never available client-side anyway.
// Check what the env var is used for and use import.meta.env instead.
```

**IMPORTANT:** Understand what env var Nav.astro is reading and why. If it's a public env var (like `PUBLIC_SUPABASE_URL`), it should use `import.meta.env.PUBLIC_SUPABASE_URL` instead. The `Astro.locals.runtime.env` pattern was for Cloudflare-specific bindings (KV, D1, R2), not standard env vars.

### Step 3: Update astro.config.mjs (10 min)
```javascript
// Add platformProxy for workerd dev
adapter: cloudflare({
  platformProxy: {
    enabled: true,
  },
}),
```

Remove `cloudflareModules` option if present.

### Step 4: Update wrangler config (if exists) (5 min)
```jsonc
{
  "main": "@astrojs/cloudflare/entrypoints/server"
}
```

### Step 5: Build test (15 min)
```bash
npm run build
# Watch for:
# - TypeScript errors (env.d.ts, middleware)
# - Vite 7 plugin compatibility
# - Cloudflare adapter warnings
```

### Step 6: Dev server test (15 min)
```bash
npm run dev
# Verify:
# - Server starts without errors
# - workerd runtime message appears in console
# - Homepage loads
# - Login works
# - Dashboard loads data
```

### Step 7: Unit tests (10 min)
```bash
npm test
# All 779+ tests should pass
# If vitest version issue: upgrade vitest to ≥3.2
```

### Step 8: E2E tests (15 min)
```bash
npx playwright test
# All 8 tests should pass
# If timeout: increase webServer.timeout
```

### Step 9: Role-based smoke test (20 min)
Test as each persona:
- [ ] Logged out → homepage, blog, about
- [ ] Observer (Sarah) → limited access, no errors
- [ ] Researcher → workspace, tribe dashboard, BoardEngine
- [ ] Tribe Leader → tribe management, attendance
- [ ] Superadmin (Vitor) → admin panel, all dashboards

### Step 10: Deploy + monitor (30 min)
```bash
git add -A
git commit -m "chore: upgrade Astro 5→6, @astrojs/cloudflare 12→13, Vite 7"
git push origin chore/upgrade-astro-6
# → PR to main
# → Cloudflare Pages preview deploy
# → Test preview URL
# → Merge to main
# → Monitor Sentry for 24h
```

---

## 10. POST-MIGRATION MONITORING

### First 24 hours
- [ ] Sentry: 0 new issues
- [ ] Sentry: TDZ errors (#1-3, #9, etc.) — did they STOP?
- [ ] PostHog: pageviews normal
- [ ] Cloudflare Pages: build succeeds, deploy time normal
- [ ] Performance: TTFB same or better

### First week
- [ ] pg_cron jobs still running (not affected by frontend, but verify)
- [ ] Blog posts rendering correctly in all 3 locales
- [ ] Attendance system working (time window, check-in)
- [ ] Certificate PDF generation working
- [ ] BoardEngine cards draggable

### Optional future enhancements (enabled by Astro 6)
- [ ] Enable CSP (`csp: true` in astro.config.mjs) — free XSS protection
- [ ] Try experimental Rust compiler (`experimental: { rustCompiler: true }`)
- [ ] Explore Live Content Collections for real-time tribe data
- [ ] Explore experimental queued rendering for 2x faster SSR

---

## 11. ROLLBACK PLAN

If critical issues found post-deploy:

```bash
# Option A: Git revert
git revert HEAD  # reverts the upgrade commit
git push origin main

# Option B: Cloudflare rollback
# Dashboard → Pages → Deployments → previous deploy → "Rollback"

# Option C: Pin versions
# In package.json, revert to:
# "astro": "^5.17.1"
# "@astrojs/cloudflare": "^12.6.12"
# npm install
```

Time to rollback: <5 minutes.

---

## 12. ESTIMATED TOTAL EFFORT

| Step | Time |
|------|------|
| Pre-migration checks | 15 min |
| Package upgrade | 10 min |
| Code changes (Nav.astro + config) | 30 min |
| Build + dev test | 30 min |
| Unit + E2E tests | 25 min |
| Smoke testing (5 personas) | 20 min |
| Deploy + PR | 10 min |
| **Total** | **~2.5 hours** |

Buffer for unexpected issues: +1 hour = **3.5 hours max.**

---

## 13. GC ENTRY

```
GC-133: W-ASTRO6 — Astro 5→6 migration runbook (fact-based).
Pre-check verified: zero usage of Zod, Content Collections, Astro.glob(), ViewTransitions, Astro i18n.
3 mandatory changes: (1) Nav.astro Astro.locals.runtime→cloudflare:workers import,
(2) @astrojs/cloudflare 12→13 with platformProxy config,
(3) wrangler entrypoint update (if applicable).
Estimated effort: 2.5-3.5 hours in single session.
Target: week 7-11 April 2026.
```
