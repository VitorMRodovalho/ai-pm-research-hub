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
| Edge functions        | supabase/functions/ (17 deployed, 4 with --no-verify-jwt) |
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
| Backend   | Supabase Edge Functions (17 deployed) |
| Auth      | Google + LinkedIn (OIDC) + Microsoft (Azure) |
| Env access | `import { env } from 'cloudflare:workers'` (NOT `locals.runtime.env`) |
| MCP       | 15 tools, OAuth 2.1, URL `platform.ai-pm-research-hub.workers.dev/mcp` |
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
