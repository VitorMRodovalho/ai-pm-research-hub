# AI & PM Research Hub — Agent Context

This file orients the AI assistant on the project so it can work effectively without re-explaining the repo each time. **Read this before making changes.**

## Quick reference

| Need to…              | Go to / Use |
|-----------------------|-------------|
| Understand project    | This file + README.md |
| Check governance      | docs/GOVERNANCE_CHANGELOG.md |
| Migration / legacy    | docs/MIGRATION.md |
| Log a release         | docs/RELEASE_LOG.md |
| Member fields         | `operational_role`, `designations` (`role`/`roles` dropped in Wave 8) |
| History               | `member_cycle_history` |
| Edge functions        | supabase/functions/ (19 deployed, 4 with --no-verify-jwt) |
| DB schema / types     | `src/lib/database.gen.ts` (run `npm run db:types` to refresh) |
| Data import scripts   | `scripts/` (trello, calendar, volunteer CSV, miro importers) |
| Pre-push              | `npm test` + `npm run build` |
| Pre-commit QA rules   | CLAUDE.md (GC-097) |
| Debug / troubleshoot  | `DEBUG_HOLISTIC_PLAYBOOK.md` |
| Project board / sprints | [GitHub Project](https://github.com/users/VitorMRodovalho/projects/1/) |
| Sprint implementation  | docs/project-governance/SPRINT_IMPLEMENTATION_PRACTICES.md |
| QA/QC release         | docs/QA_RELEASE_VALIDATION.md |
| MCP server            | docs/MCP_SETUP_GUIDE.md |

---

## What this project is

- **Product**: Operational hub for the *Núcleo de Estudos e Pesquisa em IA e GP* — PMI Brazilian chapters joint initiative (PMI-GO, PMI-CE, PMI-DF, PMI-MG, PMI-RS).
- **Scale**: ~50 active members, 7 tribes, 5 chapters.
- **Repo**: Both the product codebase and a knowledge/operational asset. Not a generic starter.
- **Principles**: Zero-cost stack, Hub as single source of truth for members/gamification/cycles, cycle-aware data model, legacy deprecation discipline.

## Tech stack

| Layer      | Tech                           |
|-----------|--------------------------------|
| Frontend  | Astro 6 + React 19 + Tailwind 4 |
| Charts    | Chart.js v4 (native)           |
| Hosting   | Cloudflare Workers SSR         |
| Database  | Supabase (PostgreSQL, auth, RLS) |
| Backend   | Supabase Edge Functions (20 deployed) |
| Auth      | Google + LinkedIn (OIDC) + Microsoft (Azure) |
| Env access | `import { env } from 'cloudflare:workers'` (NOT `locals.runtime.env`) |
| MCP       | 64 tools (51R + 13W), OAuth 2.1, Streamable HTTP SSE, `nucleoia.vitormr.dev/mcp` |
| Observability | PostHog (custom events) + Sentry (global handlers) |
| i18n      | PT-BR, EN, ES (keys in `src/i18n/`) |

## Documentation map (authoritative)

- **README.md** — Entry point, product scope, stack, status, doc map.
- **docs/GOVERNANCE_CHANGELOG.md** — Governance and product/engineering decisions.
- **docs/MIGRATION.md** — Technical transitions (roles, Credly, analytics, etc.).
- **docs/RELEASE_LOG.md** — Release and hotfix history; update on every production change.
- **docs/project-governance/** — Runbooks, roadmap, sprint practices, sprint closure routine.
- **docs/REPLICATION_GUIDE.md** — How to replicate the Hub for another chapter/project.
- **docs/PERMISSIONS_MATRIX.md** — RBAC tier model, designations, route access matrix.
- **docs/MCP_SETUP_GUIDE.md** — MCP server setup and tool reference.
- **docs/ARCHITECTURE.md** — System architecture, layers, and constraints.
- **docs/DEPLOY_CHECKLIST.md** — Deploy configuration for Workers via GitHub Actions.

Before changing behavior or schema, check these for constraints and current state.

## Conventions and rules

1. **Role model v3 (finalized)**
   Use `operational_role` and `designations`. Legacy `role`/`roles` columns were **dropped** in Wave 8 (migration `20260312020000`). No code should reference them.

2. **Members vs history**
   `members` = current snapshot. Historical roles, tribes, cycles live in `member_cycle_history` and related fact tables. Timeline and reporting must read from history tables.

3. **SSR safety**
   No server-rendered page or section may assume optional arrays/objects exist; always guard or default (e.g. `TribesSection.astro` and `deliverables`).

4. **Route compatibility**
   Legacy routes `/teams`, `/rank`, `/ranks` are kept by policy. Do not remove without product decision.

5. **SQL and releases**
   DB-impacting work must have migrations in `supabase/migrations/` and, when non-trivial, a docs pack (apply/audit/rollback/runbook). Document in `docs/RELEASE_LOG.md` what changed and how it was validated.

6. **Analytics**
   No PII in analytics identity; mask inputs; restrict admin analytics by tier. Use **native Chart.js dashboards** powered by Supabase RPCs. PostHog/Looker iframes have been superseded.

7. **i18n**
   User-facing strings belong in `src/i18n/` (pt-BR, en-US, es-LATAM). Prefer locale keys over hardcoded text.

8. **Navigation & access control**
   All route visibility is governed by `src/lib/navigation.config.ts`. Items use `minTier` and `allowedDesignations`. LGPD-sensitive items use `lgpdSensitive: true` to remain fully hidden. Other restricted items show as disabled with lock icon (progressive disclosure).

9. **Pre-commit QA (GC-097)**
   See CLAUDE.md for mandatory validation rules before any commit (SQL/RPC, i18n, routes, RPC signatures).

10. **Database patterns**
    ~189+ SECURITY DEFINER functions, RLS recursion pattern (queries via RPCs, not `.from()`). 12 tables have `rpc_only_deny_all` policies. 4 pg_cron jobs active.

## Local workflow

```bash
npm install
npm run build
npm run dev -- --host 0.0.0.0 --port 4321
npm test
npm run smoke:routes
```

Validate with `npm test` and `npm run build` before pushing. For production-impact changes, add or update an entry in `docs/RELEASE_LOG.md`.

## Sprint closure routine (5-phase)

Every sprint ends with this mandatory sequence:

1. **Execute** — All code changes complete
2. **Audit** — `supabase db push` + `npm run build` + `npm test` + lint check on edited files + route smoke test
3. **Fix** — Address any issues found in audit
4. **Docs** — Update `docs/RELEASE_LOG.md` (new version entry), `docs/GOVERNANCE_CHANGELOG.md` (decisions and lessons)
5. **Deploy** — `git add -A && git commit && git push && git tag vX.Y.Z` + verify production deployment

See `docs/project-governance/SPRINT_IMPLEMENTATION_PRACTICES.md` for the full Definition of Done.

## Where key things live

- **Pages**: `src/pages/` (including `en/`, `es/`, `admin/`).
- **Components**: `src/components/` (sections, UI, nav, attendance).
- **Data / lib**: `src/data/`, `src/lib/` (routing, Supabase, credly, gamification, trail, admin constants, navigation config).
- **Edge functions**: `supabase/functions/` — 17 deployed (verify-credly, sync-comms-metrics, sync-knowledge-insights, sync-credly-all, sync-attendance-points, send-campaign, send-global-onboarding, send-allocation-notify, nucleo-mcp, etc.); 4 with `--no-verify-jwt`.
- **Migrations**: `supabase/migrations/` (tracked in repo / linked project schema refreshed), with supporting SQL in `docs/migrations/` (archived).
- **Scripts**: `scripts/` — data importers (Trello boards, Google Calendar ICS, PMI volunteer CSVs, Miro links), knowledge file detective, WhatsApp NLP analysis.
- **Data staging**: `data/` — staging area for knowledge assets and ETL pipeline.

When adding features, respect the existing structure and the governance/release discipline above.

## Agent team structure

Specialized agents operate within strict boundaries. An agent must NOT work outside its lane.

| Agent | Scope | Can modify | Cannot touch |
|-------|-------|------------|-------------|
| **Foundation** | DB schema, RPCs, migrations, RLS, triggers | `supabase/`, `database.gen.ts`, `docs/migrations/` | Frontend pages, styling |
| **Frontend** | Pages, components, i18n, Tailwind | `src/pages/`, `src/components/`, `src/i18n/`, `src/data/` | DB schema, RPCs, migrations |
| **Integration** | Edge functions, API calls, sync logic | `supabase/functions/`, API fetch calls in `src/lib/` | Pages, components, DB schema |
| **Governance** | Docs, backlog, release log, runbooks | `docs/`, `AGENTS.md`, `README.md` | Code files |
| **DevOps** | CI/CD, workflows, deploy config | `.github/`, `wrangler.toml`, `package.json` scripts | Application code, DB |

### Agent rules

1. **No frontend without backend:** A frontend change that calls a new RPC/table MUST have the corresponding migration merged first.
2. **No orphan code:** If an edge function is invoked, it must exist in `supabase/functions/` or be explicitly documented as externally deployed.
3. **Break the build = revert:** If CI fails after merge, revert before doing anything else.
4. **One concern per commit:** Don't mix DB migrations with UI changes in the same commit.
5. **Gate checks before merge:** `npm test` + `npm run build` + `npm run smoke:routes` must pass.
6. **Sprint closure is mandatory:** Every sprint must complete the 5-phase closure routine before the next sprint begins.

## Interação com agentes (obrigatório)

### Ao iniciar trabalho
1. Se adicionar rota/nav: garantir que `navigation.config.ts` + página em `src/pages/` + `AdminNav.astro` (se admin) estejam alinhados; atualizar `PERMISSIONS_MATRIX.md` e `constants.ts` (AdminRouteKey, ROUTE_MIN_TIER).
2. Respeitar visibilidade e grupos de acesso: `minTier`, `allowedDesignations`, `lgpdSensitive` conforme matriz.

### Ao encerrar sprint (5-phase — não pular)
1. **Execute** — código completo.
2. **Audit** — `supabase db push`, `npm run build`, `npm test`, lint, smoke routes, **site hierarchy**.
3. **Fix** — corrigir problemas encontrados.
4. **Docs** — RELEASE_LOG (vX.Y.Z), GOVERNANCE_CHANGELOG.
5. **Deploy** — commit + push + tag + verificar produção.

Detalhes em `docs/project-governance/SPRINT_IMPLEMENTATION_PRACTICES.md`.

## Context & continuity (harness engineering)

This project adopts Anthropic's harness engineering framework — see [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents), [Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents), [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents). The audit in CR-052 found 5 of 7 principles already covered by the existing rules in this file; the two sections below close the remaining gaps (context engineering and mid-wave handoff).

### Context strategy (principle 2: context is finite)

The repo surfaces 64 MCP tools (51R + 13W) plus dense governance docs. Loading everything upfront burns 30–50k tokens of schema before useful work begins. Agents MUST follow this strategy:

1. **MCP tools — route, don't preload.** Classify intent first ("board?", "governance?", "selection?", "gamification?"), then load only the relevant subset. Generic ops (search, profile) stay available; domain ops load on-demand.
2. **Docs JIT, not upfront.** `GOVERNANCE_CHANGELOG.md`, `MIGRATION.md`, `RELEASE_LOG.md`, and ADRs in `docs/project-governance/` load **only when referenced** by the current task. The quick-reference table at the top of this file is the index.
3. **Schema by symbol, not by file.** Don't load `src/lib/database.gen.ts` wholesale — `grep` for the specific table/RPC, read the local region. Same for `src/lib/navigation.config.ts` and `src/components/admin/constants.ts`.
4. **Catalogs via RPC, not `SELECT *`.** Members, cycles, tribes, board cards — always via existing RPCs (`get_*`, `list_*`, `search_*`). Never `.from('table').select('*')` patterns that pull dataset-sized payloads into context.
5. **Sub-agent isolation when the lane is clear.** If the task is wholly within one lane (Foundation / Frontend / Integration / Governance / DevOps), invoke the lane-specific sub-agent with its scoped context. The orchestrator does not need to load everything just to delegate.

### Mid-wave handoff (principle 5: plan for context reset)

The 5-phase sprint closure (Execute → Audit → Fix → Docs → Deploy) covers **end of sprint**. It does NOT cover **end of session within a wave in flight**. When work straddles sessions, agents MUST produce a handoff artifact so the next session opens cold and picks up cleanly.

**When to write a handoff:**
- Session ending without completing the current feature/wave.
- More than ~1h of identifiable residual work.
- Any blocker that requires human decision before the next session resumes.

**Where it lives:**
- Default: `docs/handoff/HANDOFF-YYYY-MM-DD-session-end.md` (same pattern Panorama uses in `docs/audits/HANDOFF-*`).
- Alternative: draft PR description, extended with the same fields, when work is committable-as-draft.

**Minimum content:**
1. **State**: feature/wave, current phase of the 5-phase closure, last commit SHA on the working branch.
2. **Decisions made this session**: bullet list, with link to any ADR opened or amended.
3. **Blockers**: human decisions pending, external waits (Cloudflare deploys, Supabase migrations), or known broken state.
4. **Next concrete step**: one sentence describing exactly what the next session opens with.
5. **Related**: links to relevant ADRs, issues, RELEASE_LOG entries, GOVERNANCE_CHANGELOG entries.

**Opening sequence for the next session:**
1. Read the latest `docs/handoff/HANDOFF-*.md`.
2. Verify state (run smoke tests if the handoff says environment may be dirty).
3. Address blockers first if any; otherwise pick up the next concrete step.
4. Append a marker to the handoff confirming pickup (or open a new handoff if you'll close the wave this session).

**Anti-patterns explicitly forbidden:**
- Declaring "complete" without a handoff when work is incomplete — leads to next session re-doing or contradicting decisions.
- Editing/deleting handoffs from previous sessions to "tidy up". Archive to `docs/handoff/archive/` instead.
- Skipping the handoff because "the next session will figure it out" — this section exists to prevent that failure mode.
