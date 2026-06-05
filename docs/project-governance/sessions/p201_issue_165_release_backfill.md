---
issue: 165
title: docs - complete governance and release backfill p40-p201
lane: Governance
priority: P1 (docs)
effort: L (richer backfill is large)
status: partial-done (minimal backfill shipped p201)
opened: 2026-05-19
github: https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/165
---

# p201 Session Brief - Issue #165: Release + Governance Backfill p40-p201

## Already shipped (do not redo)

- `docs/RELEASE_LOG.md` got 10 milestone backfill entries in commit
  `bc14694f` (p201).
- `docs/GOVERNANCE_CHANGELOG.md` got GC-142 through GC-146 in the same
  commit.
- Public-facing docs (READMEs, AGENTS.md, MCP_SETUP_GUIDE.md,
  platform-guardian) had count drift corrected.

## Why this is still open

The minimal backfill stitched together milestones but a full audit-grade
reconstruction of p40-p201 needs:

- Per-sprint scope, delivered, validation, rollback/follow-up.
- ADR cross-references for major decisions (ADR-0080 through ADR-0087
  in particular).
- Public-facing documents (`docs/SITE_MAP.md`, `docs/INDEX.md`, skill
  descriptions, i18n strings) still carry inherited count strings that
  may drift again.

External auditability and new-contributor onboarding both depend on this
deeper backfill.

## Lane and gates

- Lane: Governance (docs only)
- Can touch: `docs/`, skill `.md` files, i18n dictionaries (`src/i18n/`)
  only when removing static MCP/RPC counts; never the runtime
- Can't touch: source code, SQL, MCP, Worker
- Gates: `git diff` shows only doc/i18n strings; markdown lints if
  configured; consistency check against the canonical pins
  (293 tools, 16 invariants, 37 EF, 795 RPC, 34 pg_cron, 141+ governance)

## In scope

1. Expand `docs/RELEASE_LOG.md`:
   - Use `git log --oneline --reverse v0.4.0..v0.4.40` (or equivalent
     anchors) to identify per-sprint scope.
   - For each milestone, fill: scope, delivered, validation, rollback /
     follow-up.
   - Cite migrations + EF deploys + Worker versions + invariant
     verifications.
2. Expand `docs/GOVERNANCE_CHANGELOG.md`:
   - Add entries for ADR-0080 through ADR-0087 with one-line decision
     summaries + dates.
   - Add entries for semantic-layer decisions when issue #166 resolves
     them.
   - Add entry for Cloudflare MCP policy when issue #163 resolves.
   - Add entry for local QA policy when issue #164 resolves.
3. Update remaining stale docs:
   - `docs/SITE_MAP.md` - audit count strings, link to runtime sources
     where possible.
   - `docs/INDEX.md` - same.
   - Skill descriptions in `.claude/skills/` referencing tool counts.
   - i18n dictionaries (`src/i18n/pt-BR.ts`, `en-US.ts`, `es-LATAM.ts`)
     for any inherited MCP/RPC count strings.
4. Add a "Drift watch" section to one canonical doc that lists pinned
   counts and where they appear; future audits can grep this list.

## Out of scope

- Restructuring `docs/` directory hierarchy.
- Translating ADRs.
- Reauthoring older ADRs (they stay as-is; only summary entries are
  added to the changelog).

## Files likely to touch

- `docs/RELEASE_LOG.md` (expand)
- `docs/GOVERNANCE_CHANGELOG.md` (expand)
- `docs/SITE_MAP.md`, `docs/INDEX.md`
- `.claude/skills/*.md` (where they reference MCP/RPC counts)
- `src/i18n/pt-BR.ts`, `en-US.ts`, `es-LATAM.ts` (only count strings)
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` (close item #31, #35)

## Validation

- `grep -rn "284 tools\|68 tools\|94 tools\|29 tools\|266 tools\|64 tools" docs/ AGENTS.md README*.md src/i18n .claude/`
  returns empty.
- Same grep for stale EF/RPC/pg_cron counts: empty.
- All ADR-008X have a corresponding GC entry.
- `git diff` is docs/i18n only.

## Rollback

- Pure docs PR; revert if drift snuck back in.

## Cross-references

- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` items #31, #35
- `docs/audit/P201_MCP_ARCHITECTURE_AUDIT.md` §6 Onda C
- `docs/adr/README.md` (current ADR index)

## Handoff (fill on completion)

```md
## Handoff
Issue: #165
Branch:
Release entries added:
GC entries added:
Stale count grep:
Validacao:
Riscos:
Rollback:
Docs:
Proximo passo:
```
