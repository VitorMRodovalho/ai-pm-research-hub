# Contributing to AI & PM Research Hub

## Before you start

- Read **README.md** for project scope and stack.
- Read **AGENTS.md** for conventions, doc map, and where things live (recommended for contributors and AI-assisted workflows).
- Using **Cursor**? See **docs/CURSOR_SETUP.md** for first-use checklist.

## Quality gates

Before opening a PR or pushing to a shared branch:

1. **Tests**: `npm test`
2. **Build**: `npm run build`
3. **Smoke** (optional): `npm run smoke:routes`

## Documentation and releases

- **Production-impacting changes** (hotfixes, new features, schema changes): add or update an entry in **docs/RELEASE_LOG.md** (what changed, why, how it was validated, what remains).
- **SQL / migrations**: Put migrations in `supabase/migrations/`. For non-trivial changes, add a docs pack in `docs/migrations/` (apply, audit, rollback, runbook) and follow **docs/project-governance/PROJECT_GOVERNANCE_RUNBOOK.md** (e.g. no marking Done without migration pack when SQL is required).

## Conventions

- Use **operational_role** and **designations**; avoid relying on legacy **role** / **roles** for new logic.
- **members** = current snapshot; history in **member_cycle_history**.
- SSR: guard optional data; do not assume arrays/objects exist.
- User-facing strings: use i18n keys from `src/i18n/` (PT/EN/ES).
- Keep **docs/GOVERNANCE_CHANGELOG.md** and **docs/MIGRATION.md** in mind for governance and migration state.

## Repository docs

- **GitHub Project board** — [https://github.com/users/VitorMRodovalho/projects/1/](https://github.com/users/VitorMRodovalho/projects/1/) — Sprint status; use with `backlog-wave-planning-updated.md`.
- **backlog-wave-planning-updated.md** — Wave planning and execution order.
- **docs/GOVERNANCE_CHANGELOG.md** — Decisions and governance.
- **docs/MIGRATION.md** — Technical transitions and compatibility.
- **docs/RELEASE_LOG.md** — Release and hotfix log.
