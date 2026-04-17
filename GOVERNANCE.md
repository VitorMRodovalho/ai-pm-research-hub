# Governance

How decisions are made, how architecture evolves, and where different types of content live.

## Project scope

**Núcleo de Estudos e Pesquisa em IA e GP** — joint research program of 5 PMI Brazil chapters (GO, CE, DF, MG, RS). The platform in this repo is the operational backbone: member management, tribes, boards, events, gamification, LGPD compliance, and an AI-accessible MCP server.

- **URL:** https://nucleoia.vitormr.dev
- **Supabase:** `ldrfrvwhxsmgaabwmaik` (sa-east-1, free tier)
- **Infra cost:** R$ 0/month
- **License:** see `LICENSE`

## Decision authority

| Decision type | Who decides | How documented |
|---|---|---|
| Architecture (domain model, auth pattern, schema structure) | Vitor (GP) + architectural committee when convened | ADR in `docs/adr/` |
| Platform operational rules (permissions, cycles, workflows) | Vitor + tribe leaders | `.claude/rules/*`, RPC code + comments |
| Feature roadmap / prioritization | Vitor + Ivan (sponsor PMI-GO) | `memory/project_issue_gap_opportunity_log.md` + GitHub issues |
| Partnership agreements / external integrations | Ivan (sponsor) + Vitor | Private wiki `strategy/` + signed contracts |
| Chapter-level decisions | 5 chapter presidents (CR process) | Change Request docs + chapter assemblies |
| Member lifecycle (selection, offboarding) | Tribe leaders + Vitor (for escalations) | `admin_audit_log` entries + `.claude/rules/database.md` |

**Important:** This project is an open-source initiative of PMI chapters. External programs that Vitor or Fabrício participate in individually (e.g., **AIPM Ambassadors**) are **not institutional partnerships** unless there is a signed cooperation agreement between entities. Do not document external programs as stakeholders without formal agreement.

## ADR process

Architectural Decision Records live in `docs/adr/`. Status lifecycle:

1. **Proposed** — draft with rationale, alternatives, trade-offs. Can be edited.
2. **Accepted** — approved by decision authority above. **Immutable** — never edit body of an Accepted ADR. Edits only to metadata (date, references).
3. **Superseded** — replaced by a newer ADR. The superseded ADR points to its successor; the successor explains why.
4. **Deprecated** — the decision no longer applies but no direct successor exists.

### When to create a new ADR

Create one when:
- Changing the primitive of a domain concept (e.g., V3→V4 `initiatives` replacing `tribes` primitive → ADR-0005)
- Inverting where authority is computed (e.g., engagement-derived `can()` → ADR-0007)
- Adding a new consolidation principle that applies across tables (e.g., cache + trigger + invariant pattern → ADR-0012)
- Changing LGPD posture (new PII column, new anonymization flow)
- Changing the identity model (who can sign agreements, what engagement kind implies)

Do NOT create an ADR for:
- Bug fixes, even complex ones
- Schema changes covered by an existing ADR
- UI/UX tweaks
- Dependency upgrades
- Adding a new MCP tool (unless it changes the auth model)

### ADR template

Each file: `docs/adr/ADR-NNNN-short-slug.md`. Frontmatter + sections in the style of existing ADRs (see ADR-0011 and ADR-0012 for recent examples).

### Accepted ADRs (as of 2026-04-18)

| # | Title | Status |
|---|---|---|
| 0001-0003 | Pre-V4 baseline decisions | Accepted (some superseded partially) |
| 0004 | Multi-org isolation via `organization_id` | Accepted |
| 0005 | `initiatives` as domain primitive, `tribes` as bridge | Accepted |
| 0006 | `persons` + `engagements` identity model | Accepted |
| 0007 | Authority as derived grant from active engagements | Accepted |
| 0008 | LGPD posture per engagement kind | Accepted |
| 0009 | Config-driven initiative kinds | Accepted |
| 0010 | Wiki as narrative knowledge surface | Accepted |
| 0011 | V4 auth pattern in RPCs and MCP | Accepted (2026-04-17) |
| 0012 | Schema consolidation principles (cache + trigger + invariant) | Accepted (2026-04-17) |

## Where content lives — the trifold

Three distinct destinations. Each has different access, licensing, and purpose.

### 1. This repo (`VitorMRodovalho/ai-pm-research-hub`) — code + architectural knowledge

**Access:** Public.
**License:** See `LICENSE` (source code).
**Content:**
- Source code (frontend, Edge Functions, migrations)
- `.claude/` agents, skills, rules
- `docs/adr/` (architectural decisions)
- `docs/refactor/` (refactor tracking)
- `CLAUDE.md`, `CONTRIBUTING.md`, `SECURITY.md`, `GOVERNANCE.md`
- Operational how-tos that are safe to publish

**Never put here:** secrets, PII, sensitive strategy, unpublished research, internal stakeholder communications.

### 2. Private wiki (`nucleo-ia-gp/wiki`) — narrative knowledge with scope

**Access:** Private (org members only).
**Format:** Obsidian vault (plain markdown + `.obsidian/` config). Anyone clones the repo and opens the folder as an Obsidian vault (see "Obsidian workflow" below).
**Sync to platform:** `sync-wiki` Edge Function is triggered by GitHub push webhook — syncs changed markdown files into `wiki_pages` table (with FTS) within seconds of each push. Not a cron — real-time. Platform UI renders domain-scoped pages per user permissions.
**Content:**
- Governance narratives (process docs, decision log detail)
- Onboarding materials
- Partnership context (ongoing negotiations, stakeholder notes)
- Platform user guides
- Research drafts pre-publication
- Strategic planning
- Tribe-specific internal knowledge

**Domains (top-level folders):** `governance/`, `onboarding/`, `partnerships/`, `platform/`, `research/`, `strategy/`, `tribes/`

**Frontmatter required (for sync):**
```yaml
---
title: <page title>
domain: governance|onboarding|partnerships|platform|research|strategy|tribes
summary: <1-line summary>
tags: [<tag>, <tag>]
authors: [<name>]
license: CC-BY-4.0
ip_track: A|B|C  # governance track for IP classification
---
```

### 3. Public frameworks (`nucleo-ia-gp/frameworks`) — published intellectual output

**Access:** Public.
**License:** CC-BY-SA 4.0 for docs, MIT for code samples.
**Content:** Original frameworks, methodologies, published research. Polished outputs, not drafts.

### Decision matrix

When you have a new piece of content, ask:

1. Is it code that the platform executes? → this repo (`src/`, `supabase/`)
2. Is it an architectural decision affecting future work? → this repo (`docs/adr/`)
3. Is it documentation of public platform behavior? → this repo (`docs/`) or `nucleo-ia-gp/frameworks`
4. Is it narrative knowledge (process, strategy, context) that needs scope control? → `nucleo-ia-gp/wiki`
5. Is it a polished framework ready for external adoption? → `nucleo-ia-gp/frameworks`
6. Is it operational data (who did what, when)? → Supabase SQL (never file-based)
7. Does it contain PII, secrets, or stakeholder-sensitive info? → **never in any repo** (private wiki with scoped domain, OR nowhere if truly secret)

## Archive criteria

The platform has multiple archive destinations. When something stops being active:

### Tables with historical rows (no longer written to)

→ `ALTER TABLE public.<tname> SET SCHEMA z_archive`

**Criteria:**
- Zero writes in >30 days AND no frontend/MCP/EF reader
- OR superseded by a newer table (document the successor)
- OR post-migration cleanup after a consolidation (e.g., B8 in ADR-0012)

**Pattern:** reversible (can move back with `SET SCHEMA public`). Used by W132 (22 tables, 2026-03-19) and B8/B9 (2026-04-18).

**Do NOT drop tables.** Archive-first policy preserves rollback capability.

### Migrations and historical docs

→ `docs/archive/`

**Criteria:**
- Reference documents that captured a point-in-time audit
- Superseded specs or specifications
- Release notes from major pre-V4 versions

**Pattern:** keep readable, not deleted. If archived, update `docs/INDEX.md` to note the move.

### Unused RPCs

→ `DROP FUNCTION public.<name>(...)`

**Criteria:**
- Grep shows zero callers in `src/`, `supabase/functions/`, and tests
- Not documented as a public surface
- Not used by any published MCP tool

**Pattern:** drop is fine because RPC functions are pure logic, not state. Rollback = recreate from the original migration file. Example: B9 dropped `list_volunteer_applications` (2026-04-18).

### Code (components, utilities)

**Criteria:**
- Grep for all references shows no call site
- Not exported as a public API
- Tests pass after removal

**Pattern:** just delete. Git preserves history. Avoid `_deprecated` naming or `// TODO: remove` comments — either keep or delete cleanly.

### When in doubt

Archive, don't delete. The cost of a `SET SCHEMA z_archive` is nearly zero; the cost of losing data or context is high.

## Sanitation checklist before each commit

(Automated via `.githooks/pre-commit` when installed — see `CONTRIBUTING.md`.)

1. No file named `.env` (other than `.env.example`) being staged
2. No 40+ character tokens in staged diff (`eyJ...`, `sk_...`, `pat_...`)
3. No private keys (`-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----`)
4. No synthetic fixture with real member emails/PMI IDs
5. No large binary file (>10MB) being staged
6. No reference to archived/deprecated code as if it were live

## Review gates

(Enforced by CI + CODEOWNERS.)

| Change type | Reviewer(s) | CI gate |
|---|---|---|
| Migration in `supabase/migrations/` | Vitor | Tests pass, astro build passes, invariants check 0 violations |
| RPC signature change | Vitor | `NOTIFY pgrst` included in migration |
| MCP tool addition | Vitor | No duplicate tool names (pre-deploy check), 76 tools accounted for |
| LGPD-sensitive code | Vitor (as interim DPO) | `security-lgpd.test.mjs` + `privacy-sentry.test.mjs` pass |
| Deployment (Worker or EF) | Vitor | Smoke test after deploy |
| ADR | Decision authority (see table above) | ADR file format matches template |

## Quarterly hygiene (recurring)

Proposed cadence for catching drift:

- **Monthly:** run `audit` skill (includes `check_schema_invariants()`, docs drift check, CI status)
- **Per feature shipped:** run `code-reviewer` agent, update `project_issue_gap_opportunity_log.md`
- **End of cycle (every 6 months):** refresh ADR index, prune stale memory entries, review archive candidates, update CLAUDE.md metrics

## Obsidian workflow (for contributors to the private wiki)

The `nucleo-ia-gp/wiki` repo IS an Obsidian vault (has `.obsidian/` folder committed). To use it:

1. Install Obsidian (free): https://obsidian.md/
2. Clone the repo: `git clone git@github.com:nucleo-ia-gp/wiki.git` (suggested path: `~/Documents/nucleo-wiki/`)
3. Open Obsidian → "Open folder as vault" → select the cloned folder, OR launch with path: `flatpak run md.obsidian.Obsidian ~/Documents/nucleo-wiki` (Linux flatpak) / equivalent on macOS/Windows
4. Obsidian reads the shared `.obsidian/` config (themes, plugins) — including the **Obsidian Git plugin** (v2.38.2+) which auto-commits every 10min + auto-pushes on commit + auto-pulls on boot
5. Edit pages (with frontmatter per the template above) — plugin handles git automatically. Manual fallback: `git add -A && git commit && git push` in the cloned folder.
6. On push, GitHub fires a webhook to the `sync-wiki` Edge Function — wiki_pages table updates within seconds (real-time, not cron).

**From Claude Code:** The wiki is just markdown files in a folder. If you clone the wiki locally at e.g. `~/Documents/nucleo-wiki/`, Claude Code can read/write those files like any other project. Claude Code is not required to use Obsidian — the two are independent.

## References

- `SECURITY.md` — what must not be committed + vuln reporting
- `CONTRIBUTING.md` — developer workflow
- `CLAUDE.md` — operational rules for AI-assisted development
- `.claude/rules/*` — domain-specific rules
- `docs/adr/README.md` — ADR index
- `docs/refactor/DOMAIN_MODEL_V4_MASTER.md` — V4 refactor history
- Platform Guardian: `.claude/agents/platform-guardian.md` — ongoing integrity audit
