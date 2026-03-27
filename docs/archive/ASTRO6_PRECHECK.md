# Astro 6 Migration Pre-Check — Run against ai-pm-research-hub repo
# Purpose: Verify actual usage of Astro APIs that have breaking changes in v6
# This replaces assumptions with facts.

## Run ALL of these and report results:

```bash
echo "=== 1. ZOD USAGE ==="
grep -r "from 'zod'\|from \"zod\"" src/ --include="*.ts" --include="*.tsx" --include="*.astro" -l 2>/dev/null || echo "NO ZOD IMPORTS FOUND"
grep -E '"zod"' package.json || echo "ZOD NOT IN PACKAGE.JSON"

echo ""
echo "=== 2. ASTRO CONTENT COLLECTIONS ==="
ls -la src/content/ 2>/dev/null || echo "NO src/content/ DIRECTORY"
grep -r "getCollection\|getEntry\|defineCollection\|content/config" src/ --include="*.ts" --include="*.tsx" --include="*.astro" -l 2>/dev/null || echo "NO CONTENT COLLECTION USAGE"

echo ""
echo "=== 3. ASTRO.GLOB() ==="
grep -rn "Astro\.glob" src/ --include="*.ts" --include="*.tsx" --include="*.astro" 2>/dev/null || echo "NO Astro.glob() USAGE"

echo ""
echo "=== 4. VIEW TRANSITIONS ==="
grep -rn "ViewTransitions\|astro:transitions\|ClientRouter" src/ --include="*.ts" --include="*.tsx" --include="*.astro" 2>/dev/null || echo "NO ViewTransitions USAGE"

echo ""
echo "=== 5. ASTRO.LOCALS USAGE ==="
grep -rn "Astro\.locals\|locals\.runtime\|context\.locals" src/ --include="*.ts" --include="*.tsx" --include="*.astro" 2>/dev/null || echo "NO Astro.locals USAGE"

echo ""
echo "=== 6. CURRENT VERSIONS ==="
echo "--- package.json versions ---"
grep -E '"astro"|"@astrojs/cloudflare"|"@astrojs/react"|"vite"|"zod"|"@sentry/astro"' package.json

echo ""
echo "=== 7. MIDDLEWARE ==="
ls -la src/middleware/ 2>/dev/null || echo "NO middleware/ DIRECTORY"
cat src/middleware/index.ts 2>/dev/null || cat src/middleware.ts 2>/dev/null || echo "NO MIDDLEWARE FILE FOUND"

echo ""
echo "=== 8. ENV.D.TS (App.Locals typing) ==="
cat src/env.d.ts 2>/dev/null || echo "NO env.d.ts"

echo ""
echo "=== 9. ASTRO CONFIG (i18n section) ==="
grep -A 20 "i18n" astro.config.mjs 2>/dev/null || grep -A 20 "i18n" astro.config.ts 2>/dev/null || echo "NO i18n CONFIG FOUND"

echo ""
echo "=== 10. SENTRY INTEGRATION ==="
grep -rn "@sentry/astro\|sentry" astro.config.mjs astro.config.ts 2>/dev/null || echo "NO SENTRY IN ASTRO CONFIG"
grep -rn "Sentry\|@sentry" src/ --include="*.ts" --include="*.tsx" --include="*.astro" -l 2>/dev/null || echo "NO SENTRY USAGE IN SRC"

echo ""
echo "=== 11. PLAYWRIGHT CONFIG ==="
grep -A 5 "webServer" playwright.config.ts 2>/dev/null || echo "NO PLAYWRIGHT WEBSERVER CONFIG"

echo ""
echo "=== 12. NODE VERSION ==="
cat .nvmrc 2>/dev/null || echo "NO .nvmrc"
node --version 2>/dev/null

echo ""
echo "=== 13. DEPENDABOT ASTRO 6 PR ==="
# Check if there's a pending Astro upgrade
grep -E '"astro":\s*"\^?[56]' package.json
```

## After running, report:
1. Which of the 13 checks found actual usage vs "NOT FOUND"
2. The exact current versions from package.json
3. Full content of middleware file (if exists)
4. Full content of env.d.ts (if exists)
5. The i18n config block from astro.config
6. The Playwright webServer config
