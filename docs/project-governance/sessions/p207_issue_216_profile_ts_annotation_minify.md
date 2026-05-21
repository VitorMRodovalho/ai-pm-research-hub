---
issue: 216
title: profile.astro — strip module-level TS annotations from inline <script> (Vite minify trap, 3rd recurrence)
lane: Frontend
priority: P1
effort: S (profile.astro fix) + M (broader audit + forward defense)
status: RESOLVED p207 — DIAGNOSIS REVISED, PR #223 (bb95bb03) merged. See PR description + Issue #216 comment 4504200204 for real cause. **TL;DR: this spec was wrong about TS annotations; real fix was 1-line `import { t } from '../i18n/utils'` in the <script> block.**
opened: 2026-05-20
closed: 2026-05-20 (same day, p207 session)
github: https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/216
pr: https://github.com/VitorMRodovalho/ai-pm-research-hub/pull/223
---

> **⚠️ DIAGNOSTIC REVISION NOTE (p207 close)**
>
> This spec hypothesized that the bug was the 3rd recurrence of TS-annotation × Vite-minify trap (p158/p184 class on `lp`). **Empirical disproof during execution**: stripping all 22 module-level annotations produced bundle byte-identical to broken prod (same hash `v3Zqq7wC.js` + md5 `418784e95fc0830e2c749c305a109485`). Esbuild strips TS annotations BEFORE Vite minification, so source-level annotations are no-op for output bundle.
>
> **Real root cause**: inline `<script>` calls `t('profile.xp.howToEarn', lang)` ~25× at runtime but never imports `t` (frontmatter imports server-side only; script runs in browser).
>
> **Real fix (PR #223)**: 1-line `import { t } from '../i18n/utils';` at top of `<script>` block. Bundle hash CHANGED `v3Zqq7wC` → `CGuhpcmD`.
>
> **The body of this spec below is HISTORICAL — kept for archaeological reference. The fix that shipped is 1-line, not 22-line. Future agents reading this for context: see PR #223 description + Issue #216 comment for the actual diagnosis path.**

---

# p207 Session Brief — Profile /profile ReferenceError (TS annotation × Vite minify)

## Symptom (user-reported, 2026-05-20)

Live error on `https://nucleoia.vitormr.dev/profile` (and presumably `/en/profile`, `/es/profile`):

```
profile.astro_astro_type_script_index_0_lang.v3Zqq7wC.js:116
Uncaught (in promise) ReferenceError: t is not defined
    at pt (profile.astro_astro_type_script_index_0_lang.v3Zqq7wC.js:116:1585)
    at B (profile.astro_astro_type_script_index_0_lang.v3Zqq7wC.js:270:9)
    at he (profile.astro_astro_type_script_index_0_lang.v3Zqq7wC.js:1:3498)
```

Reproduces in current main HEAD (`741511ce`). User-facing on a member-critical page.

## Root cause class (high confidence, NOT speculation)

Module-level `const`/`let` declarations with TypeScript type annotations inside Astro `<script>` (processed, NOT `is:inline`) blocks cause Vite minification to drop the binding from module scope. The minifier emits a short identifier (e.g., `t`) and another callsite (e.g., `pt`) tries to reference it but it's not in scope.

The trap is invisible in dev (Vite doesn't minify) and only fires in prod.

## Prior occurrences (already documented in code + commit history)

| # | Session | Commit | Var fixed | Note |
|---|---|---|---|---|
| 1 | p158 hotfix#8 (2026-05-14) | `e098c398` | `lp` (locale prefix) | First diagnosis. `module-level so myWeekHtml + renderProfile can reference lp without TDZ ReferenceError` |
| 2 | p184 (2026-05-14) | inline in `profile.astro` (after p158) | `lp` again | Original p158 missed that `: 'pt-BR' \| 'en-US' \| ...` annotation was the trigger; p184 stripped annotation. Inline code comment at lines 248-252 documents this. |
| 3 | **p207 (2026-05-20)** | — | `?` (currently failing in minified `pt(t)` call) | This issue. p184 fix was scoped to `lp` only; the same trap exists on ~20+ other module-level annotated consts/lets. |

Memory entries:
- `[[feedback-astro-define-vars-no-ts]]` (p169) — adjacent class: `define:vars` + TS annotations cause SyntaxError at parse. Different mechanism (no Vite involved) but same operator-error category.

## Surface to fix in profile.astro

Greppable inventory (lines relative to `<script>` start at line 237):

```
const OPROLE_LABELS: Record<string, string>     (line 256)
const OPROLE_COLORS: Record<string, string>     (line 261)
const DESIG_LABELS: Record<string, string>      (line 266)
const DESIG_COLORS: Record<string, string>      (line 269)
const HISTORY_TYPE_LABELS: Record<string, string> (line 273)

let currentMember: any                          (line 280)
let attendanceHistory: any[]                    (line 281)
let cycleHistory: any[]                         (line 282)
let cycleStats: any                             (line 283)
let journeyStats: any                           (line 284)
let xpByCycle: Record<string, number>           (line 285)
let cycleXpData: any                            (line 286)
let xpPillarsLifetimeData: any                  (line 287)
let xpPillarsCycleData: any                     (line 288)
let championsHistoryData: any                   (line 289)
let allGamificationPoints: any[]                (line 290)
let currentXpScope: 'lifetime' | 'cycle'        (line 294)
let attendanceHoursData: { total_hours: ... }   (line 296)
let currentCycleCode: string                    (line 297)
let currentCycleLabel: string                   (line 298)
let cycleMeta: Record<string, { label: ... }>   (line 299)
let weekData: { meetingSlots: ... }             (line 300-303)
let credlyNormalizeTimer: ReturnType<typeof setTimeout> | null (line 304)
```

**~22 module-level annotations** to strip.

Note: function-scoped `let`/`const` with annotations (e.g., line 386 `const missing: string[]`) are NOT affected — only **module-level** identifiers are minifier candidates for hoisting/renaming with cross-chunk references.

## Fix pattern (established at p184)

Replace each annotation with bare declaration + value (the JS runtime doesn't need the type):

```ts
// BEFORE (broken in minified prod):
const OPROLE_LABELS: Record<string, string> = { ... };
let currentMember: any = null;

// AFTER (safe):
const OPROLE_LABELS = { ... };
let currentMember = null;
```

For complex shapes (e.g., `weekData`, `cycleMeta`, `attendanceHoursData`), the initial value already encodes the shape — no annotation needed at runtime.

## Lane and gates

- **Lane**: Frontend (`src/pages/profile.astro` primary; `src/pages/en/profile.astro` + `src/pages/es/profile.astro` likely just re-exports, but verify).
- **Can touch**: Only the inline `<script>` blocks of profile.astro variants.
- **Can't touch**: `src/lib/*`, components, types in `src/lib/types/*`. The trap is module-scope-of-script-only.
- **Gates**: `npx astro build` PASS; manual browser smoke on `/profile` for at least 1 member (signed in); verify no console errors. Server-render also still works.

## In scope (this PR)

1. **Strip the ~22 module-level annotations in `src/pages/profile.astro`** lines ~256-304. Keep value initialization unchanged.
2. **Verify `/en/profile.astro` and `/es/profile.astro` parity** — if they have their own scripts (not just re-exports), apply the same fix.
3. **Run `npx astro build`** — must pass clean.
4. **Manual browser smoke**: load `/profile` as a signed-in member, confirm `pt(...)`/`renderProfile(...)` runs without errors.
5. **Add inline comment** updating the p184 explanation comment block to note the p207 sweep covered all module-level annotations (not just `lp`).
6. **Backlog entry** in `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` for the broader audit (see "Forward defense" below).

## In scope (broader audit — can be split into separate PR or this one's discretion)

Run a project-wide audit to find all other `.astro` files with the same trap:

```bash
# Find all module-level annotated consts/lets in processed <script> blocks
# Heuristic — false positives possible but signal is strong:
grep -rnE '^\s{2}(const|let)\s+[a-zA-Z_][a-zA-Z0-9_]*\s*:\s' src/pages/ src/components/ \
  --include='*.astro' | grep -v 'is:inline' | grep -v 'frontmatter'
```

For each hit, file a sub-bullet under this issue OR a follow-up issue per file, depending on density.

## Forward defense (file as backlog, not required this PR)

Three options for preventing the 4th recurrence:

**Option A: ESLint rule (preferred)** — `eslint-plugin-astro` does not natively catch this. Custom rule on top of TS-ESLint AST: flag any module-level `VariableDeclaration` with `typeAnnotation` inside an `<script>` block of an `.astro` file. Effort: M (custom rule + CI integration).

**Option B: Audit script** — `scripts/audit-astro-script-annotations.mjs` that greps + reports. Run in pre-commit hook. Lighter than ESLint rule. Effort: S.

**Option C: Type-erasure transform** — Vite plugin that strips module-level type annotations from processed scripts before minification. Most invasive; not recommended. Effort: L.

**Recommended**: Option B for now; promote to Option A if 4th recurrence happens despite Option B.

## Out of scope

- Refactoring `<script>` → external `.ts` module imports. (Astro convention is fine; the bug is in the type annotation handling, not the embedding pattern.)
- Touching `<script is:inline define:vars>` blocks. Those have a DIFFERENT trap (`SyntaxError` at parse, documented in `[[feedback-astro-define-vars-no-ts]]`).
- Changing function-scoped annotations. Those are safe.
- Refactoring any logic in `boot()`, `renderProfile()`, `myWeekHtml()`, etc.

## Validation

- [ ] All ~22 module-level annotations removed from `src/pages/profile.astro`.
- [ ] `npx astro build` PASS (0 new errors).
- [ ] Manual browser smoke on `/profile` (signed-in member): no `ReferenceError: t is not defined`, full UI renders, pillar/champion sections visible.
- [ ] Spanish + English routes (if they have own scripts) similarly cleaned.
- [ ] P162 log entry added for forward-defense Option B.
- [ ] Inline comment at lines 248-252 of profile.astro updated to note p207 closure.
- [ ] Pre-existing `npm test` baselines preserved (1449/0/46 offline; 1499/0/50 with-env after p206).

## Rollback

`git revert <commit>` restores previous state. Risk is extremely low — annotations carry no runtime semantics. If the bug somehow persists after the strip, a stale Cloudflare Worker cache may be the cause (see `[[feedback-astro-define-vars-no-ts]]` p169 sediment); `wrangler deploy` invalidates.

## Cross-references

- p158 hotfix#8 commit `e098c398`
- p184 inline comment block in `profile.astro` (lines 248-252)
- `[[feedback-astro-define-vars-no-ts]]` (p169 sediment on adjacent inline+TS class)
- `[[feedback-handoff-invariants-verify-on-boot]]` (this bug was caught via verify-on-boot UX flow, not via tests — sediment indicator that test coverage is gap)
- p202 governance: `docs/project-governance/sessions/README.md`

## Handoff (fill on completion)

```md
## Handoff

Issue: #
Branch: agent/issue-XXX
Escopo: strip ~22 module-level TS annotations in profile.astro (+ en/es variants if applicable)
Arquivos: src/pages/profile.astro, src/pages/en/profile.astro, src/pages/es/profile.astro
Validação: npx astro build PASS + browser smoke /profile (signed-in member)
Riscos: nenhum runtime; revert é file-only
Rollback: git revert
Docs: P162 entry para forward defense; inline comment update
Próximo passo: PM signoff → merge → QA window
```

## Notes for the agent picking this up

- **DO NOT** add `// @ts-nocheck` at top of script — that hides legitimate type checking elsewhere in the file. Just strip the annotations.
- **DO NOT** convert `<script>` to `<script is:inline>` — that creates the OTHER trap from p169.
- **DO** read the existing comment block at lines 248-252 of profile.astro before starting — it explains the trap in prose.
- **DO** verify `agent/issue-180` and other QA-window branches don't already touch profile.astro (rebase awareness).
- **DO** run `gh pr list --state open` first to confirm no parallel work on profile.astro.
- **DO** put this fix's session brief into the PR description as anchor context.
