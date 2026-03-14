# W139C — Technical Debt Inventory (Pre-Beta)

**Data:** 2026-03-14
**Metodo:** npm audit, TypeScript strict, grep de hardcoded values, TODO scan, security check
**Branch:** `fix/w139-pre-beta-all`

---

## 1. Dependencies — npm audit

| Severity | Count | Packages |
|----------|-------|----------|
| High | 3 | `undici` (via wrangler/miniflare/@astrojs/cloudflare) |
| Moderate | 7 | `devalue` (prototype pollution), `lodash` (via @astrojs/check) |
| Low | 0 | — |

**Fix disponivel:** `npm audit fix` resolve `devalue` e `undici`. Para `lodash`, fix requer `--force` (breaking change em @astrojs/check).

**Risco para Beta:** BAIXO. Todas as vulnerabilities sao em dependencias de dev/build (wrangler, astro check). Nenhuma vulnerabilidade em dependencias de runtime que chegam ao usuario.

---

## 2. Dependencies — Outdated

| Package | Current | Wanted | Latest | Risk |
|---------|---------|--------|--------|------|
| `@astrojs/check` | 0.9.6 | 0.9.7 | 0.9.7 | LOW — patch |
| `@astrojs/cloudflare` | 12.6.12 | 12.6.13 | 13.1.1 | MEDIUM — major 13.x available |
| `@eslint/js` | 9.39.4 | 9.39.4 | 10.0.1 | LOW — major, defer |
| `astro` | 5.18.0 | 5.18.1 | 6.0.4 | HIGH — Astro 6 is major, defer |
| `eslint` | 9.39.4 | 9.39.4 | 10.0.3 | LOW — major, defer |
| `recharts` | 2.15.4 | 2.15.4 | 3.8.0 | MEDIUM — major 3.x, defer |

**Recomendacao:** Apply patch updates (`@astrojs/check`, `@astrojs/cloudflare` minor) pos-Beta. Major upgrades (Astro 6, recharts 3, eslint 10) em sprint dedicada.

---

## 3. TypeScript Strict Check

**Total errors:** 18 (across 5 files)

| File | Errors | Category |
|------|--------|----------|
| `src/components/board/BoardKanban.tsx` | 7 | Type narrowing — enum comparisons with status strings that don't overlap |
| `src/components/board/CardDetail.tsx` | 2 | Missing `curationPipeline` key in BoardI18n type |
| `src/components/boards/TribeKanbanIsland.tsx` | 1 | Null in attachment array |
| `src/components/ui/GlobalSearchIsland.tsx` | 1 | Window type cast |
| `src/lib/schedule.ts` | 6 | Properties on `never` type (generic config parsing) |

**Risco para Beta:** NENHUM. Build passa sem errors (Astro/Vite nao usa `--strict`). Esses erros sao em `noEmit` strict mode e nao bloqueiam deploy.

---

## 4. TODOs / FIXMEs / HACKs

**Total encontrados:** 0

Nenhum `TODO`, `FIXME`, `HACK`, `XXX`, `WORKAROUND`, ou `PLACEHOLDER` encontrado em `src/**/*.{ts,tsx,astro}`.

---

## 5. Hardcoded Values

### 5.1 Anon Key (hardcoded fallback)

| File | Line | Value | Risk |
|------|------|-------|------|
| `src/lib/supabase.ts` | 22 | `FALLBACK_SUPABASE_ANON_KEY = 'eyJ...'` | LOW — anon key is public by design. Env var is preferred but fallback is safe. |

**Recomendacao:** Manter como fallback. Anon key e publico e seguro.

### 5.2 Localhost References

**ZERO** referencias a `localhost` em `src/**/*.{ts,tsx,astro}`.

### 5.3 Hardcoded Secrets

**ZERO** service_role keys, passwords, ou secrets hardcoded no codigo fonte.

---

## 6. Security Check

| Check | Status |
|-------|--------|
| `.env` in `.gitignore` | OK |
| `.env.example` exists | OK |
| No `service_role` key in source | OK |
| No hardcoded passwords | OK (profile.astro uses `type="password"` for PII fields — correct pattern) |
| `apikey` references | OK — all use runtime `sb.supabaseKey` (anon key from client) |
| Admin page API key instructions | OK — `/admin/selection` shows CLI usage pattern, not actual key |
| Comms API key input | OK — `type="password"` for OAuth tokens, stored in DB not code |

**Conclusao:** Nenhuma vulnerabilidade de seguranca encontrada no codigo fonte.

---

## 7. Build Warnings

**Build output:** Clean. `npm run build` completa sem warnings ou errors.

```
14:21:23 [build] Server built in 14.60s
14:21:23 [build] Complete!
```

---

## 8. Summary por Prioridade

### Acao Imediata (antes do Beta): NENHUMA

Todas as issues encontradas sao de baixo risco e nao bloqueiam o Beta.

### Pos-Beta (Sprint de Limpeza)

| # | Item | Esforco | Risco |
|---|------|---------|-------|
| 1 | `npm audit fix` — resolve devalue + undici | 5 min | Baixo |
| 2 | Update @astrojs/check 0.9.6 → 0.9.7 | 5 min | Baixo |
| 3 | Update @astrojs/cloudflare 12.6.12 → 12.6.13 | 10 min + teste | Baixo |
| 4 | Fix 18 TypeScript strict errors (5 files) | 1-2h | Baixo |

### Backlog (Sprint Dedicada)

| # | Item | Esforco | Risco |
|---|------|---------|-------|
| 5 | Upgrade Astro 5 → 6 (major) | 1 sprint | Alto |
| 6 | Upgrade recharts 2 → 3 (major) | 1/2 sprint | Medio |
| 7 | Upgrade eslint 9 → 10 (major) | 1/2 sprint | Baixo |

---

*W139C Technical Debt Audit — 10 npm vulnerabilities (all dev-time), 18 TypeScript strict errors (all non-blocking), 0 TODOs, 0 security issues, 0 hardcoded secrets. Platform is clean for Beta.*
