# AI & PM Research Hub — Agent Context

This file orients the AI assistant (Cursor) on the project so it can work effectively without re-explaining the repo each time. **Read this before making changes.**

## Quick reference

| Need to…              | Go to / Use |
|-----------------------|-------------|
| Understand project    | This file + README.md |
| Plan work             | backlog-wave-planning-updated.md |
| Check governance      | docs/GOVERNANCE_CHANGELOG.md |
| Migration / legacy    | docs/MIGRATION.md |
| Log a release         | docs/RELEASE_LOG.md |
| Member fields         | `operational_role`, `designations` (not `role`/`roles`) |
| History               | `member_cycle_history` |
| Edge functions        | supabase/functions/ (verify-credly, sync-comms-metrics, sync-knowledge-insights) |
| DB schema / types     | `src/lib/database.gen.ts` (run `npm run db:types` to refresh) |
| AI DB access setup   | docs/AI_DB_ACCESS_SETUP.md |
| Pre-push              | `npm test` + `npm run build` |
| Debug / troubleshoot  | `DEBUG_HOLISTIC_PLAYBOOK.md` |
| Project board / sprints | [GitHub Project](https://github.com/users/VitorMRodovalho/projects/1/) |
| Board ↔ docs sync      | docs/AGENT_BOARD_SYNC.md — checklist para manter board e documentação atrelados |
| Sprint implementation  | docs/project-governance/SPRINT_IMPLEMENTATION_PRACTICES.md — ordem de prioridade, gates, checklist |
| QA/QC release         | docs/QA_RELEASE_VALIDATION.md — console F12, cross-browser (Win/Mac/iPhone/Android) |

---

## What this project is

- **Product**: Operational hub for the *Núcleo de Estudos e Pesquisa em IA e GP* — PMI Brazilian chapters joint initiative (PMI-GO, PMI-CE, PMI-DF, PMI-MG, PMI-RS).
- **Repo**: Both the product codebase and a knowledge/operational asset. Not a generic starter.
- **Principles**: Zero-cost stack, Hub as single source of truth for members/gamification/cycles, cycle-aware data model, legacy deprecation discipline.

## Tech stack

| Layer      | Tech                  |
|-----------|------------------------|
| Frontend  | Astro + Tailwind CSS   |
| Hosting   | Cloudflare Pages       |
| Database  | Supabase (PostgreSQL, auth, RLS) |
| Backend   | Supabase Edge Functions |
| i18n      | PT-BR, EN, ES (keys in `src/i18n/`) |

## Documentation map (authoritative)

- **README.md** — Entry point, product scope, stack, status, doc map.
- **backlog-wave-planning-updated.md** — Wave planning, completed work, debt, next priorities, execution order.
- **docs/GOVERNANCE_CHANGELOG.md** — Governance and product/engineering decisions.
- **docs/MIGRATION.md** — Technical transitions (roles, Credly, analytics, etc.).
- **docs/RELEASE_LOG.md** — Release and hotfix history; update on every production change.
- **docs/project-governance/** — Runbooks, roadmap, snapshots.
- **docs/REPLICATION_GUIDE.md** — How to replicate the Hub for another chapter/project.

Before changing behavior or schema, check these for constraints and current state.

## Conventions and rules

1. **Role model v3**  
   Use `operational_role` and `designations`. Legacy `role`/`roles` are transitional only; new code must not rely on them for long-term behavior.

2. **Members vs history**  
   `members` = current snapshot. Historical roles, tribes, cycles live in `member_cycle_history` and related fact tables. Timeline and reporting must read from history tables.

3. **SSR safety**  
   No server-rendered page or section may assume optional arrays/objects exist; always guard or default (e.g. `TribesSection.astro` and `deliverables`).

4. **Route compatibility**  
   Legacy routes `/teams`, `/rank`, `/ranks` are kept by policy. Do not remove without product decision.

5. **SQL and releases**  
   DB-impacting work must have migrations in `supabase/migrations/` and, when non-trivial, a docs pack (apply/audit/rollback/runbook). Document in `docs/RELEASE_LOG.md` what changed and how it was validated.

6. **Analytics**  
   No PII in analytics identity; mask inputs; restrict admin analytics by tier; prefer iframe dashboards (PostHog, Looker) over custom charts in Astro.

7. **i18n**  
   User-facing strings belong in `src/i18n/` (pt-BR, en-US, es-LATAM). Prefer locale keys over hardcoded text.

## Local workflow

```bash
npm install
npm run build
npm run dev -- --host 0.0.0.0 --port 4321
npm test
npm run smoke:routes
```

Validate with `npm test` and `npm run build` before pushing. For production-impact changes, add or update an entry in `docs/RELEASE_LOG.md`.

## Where key things live

- **Pages**: `src/pages/` (including `en/`, `es/`, `admin/`).
- **Components**: `src/components/` (sections, UI, nav, attendance).
- **Data / lib**: `src/data/`, `src/lib/` (routing, Supabase, credly, gamification, trail, admin constants).
- **Edge functions**: `supabase/functions/` — `verify-credly`, `sync-comms-metrics`, `sync-knowledge-insights` presentes; `sync-credly-all` e `sync-attendance-points` invocados mas ausentes no repo (ver `docs/project-governance/PROJECT_ON_TRACK.md`).
- **Migrations**: `supabase/migrations/`, with supporting SQL/docs in `docs/migrations/`.

When adding features, respect the existing structure and the governance/release discipline above.
