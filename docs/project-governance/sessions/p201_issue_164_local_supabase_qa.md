---
issue: 164
title: infra - restore local Supabase QA stack or document remote-only workflow
lane: Infra/Security + QA
priority: P1
effort: M (decide + implement + document)
status: ready
opened: 2026-05-19
github: https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/164
---

# p201 Session Brief - Issue #164: Local Supabase QA Stack

## Why this matters

`supabase start` currently fails when applying the local baseline:
`00000000_baseline_rpcs.sql` creates `get_member_by_auth()` returning
`SETOF public.members` before the `members` table exists in the local
migration order. `deno` is also not in the local PATH, blocking
`supabase functions serve` as a fallback. Result: local Edge Function
debugging is impossible, and QA happens only against production /
remote-linked DB. This is what made p201 MCP debugging slow.

## Evidence (collected during p201 audit)

- `supabase start` log: `ERROR: type "public.members" does not exist
  (SQLSTATE 42704)` at `00000000_baseline_rpcs.sql`.
- Local Deno fallback: `deno: command not found` on the dev environment.
- `supabase db push` is blocked by older remote-only migration history
  drift; p201 worked around this by applying SQL via
  `mcp__supabase__apply_migration` + `supabase migration repair --status
  applied <ts>`.

## Lane and gates

- Lane: Infra/Security + QA composite (`supabase/migrations/` baseline
  ordering is Infra/Security per roadmap §3; runbook + workflow
  documentation is QA per §3)
- Can touch: migration ordering for baseline, new bootstrap migration,
  `supabase/` config, `docs/` runbooks, CI workflow if needed
- Can't touch: business logic; do not rewrite RPCs to satisfy local
  bootstrap if the fix is just reorder
- Gates: `npm test` baselines preserved (1449/0/46 offline, 1501/0/5
  with-env); `check_schema_invariants()` 16/16; no remote-DB-only
  features broken by the local ordering fix

## Decision options

| Path | What changes | Effort | Risk |
|---|---|---|---|
| A | Document remote-linked as official QA workflow; freeze local stack | XS | Low - status quo |
| B | Reorder baseline so `members` table exists before RPCs that reference it | M | Medium - need full local reapply test |
| C | Split baseline RPCs into a second migration that runs after schema | M | Low - additive only |
| D | Both: ship B or C, AND document remote-linked as the supported path | M+ | Low |

Recommended path is C (additive, low blast radius) + documentation that
remote-linked is supported for everyday QA, with local being optional.

## In scope

1. PM picks path A/B/C/D.
2. If B/C: ship migration ordering fix + reapply locally + verify
   `supabase start` succeeds from a fresh database.
3. Document the chosen QA strategy in:
   - `docs/RUNBOOK.md` or `docs/operations/LOCAL_QA.md` (new)
   - `.claude/rules/deploy.md` (link to runbook)
   - `AGENTS.md` (one-line reference)
4. Address `supabase db push` drift: write a small section on how to
   diagnose drift + use `migration repair --status applied <ts>` (with
   SQL evidence) instead of mass repair.
5. Optional: install `deno` instructions for contributors who want EF
   local debug.

## Out of scope

- Migrating to a different local-stack tool (e.g., pglite, neon-local).
- Rewriting any RPC body; only ordering or splitting is acceptable.
- CI parity for local QA (separate issue if desired).

## Files likely to touch

- `supabase/migrations/00000000_baseline_rpcs.sql` (if path B) OR
  `supabase/migrations/00000001_baseline_rpcs_after_schema.sql` (if
  path C, new)
- `docs/operations/LOCAL_QA.md` (new) or extension of `docs/RUNBOOK.md`
- `.claude/rules/deploy.md`
- `AGENTS.md`
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` (close item #39)

## Validation

- Path B/C: `rm -rf supabase/.branches && supabase start` succeeds with
  full migration order applied; `supabase db dump --linked
  --schema=public` matches remote shape for `get_member_by_auth`
  signature.
- All paths: `npm test` PASS at baseline; `check_schema_invariants()`
  16/16; no MCP tool regressions in `mcp_usage_log`.
- Runbook readable: a new contributor can follow it from clean checkout
  to a working QA environment.

## Rollback

- Path B: revert the reorder migration; baseline returns to current
  broken state but production unaffected.
- Path C: revert the new additive migration; baseline returns to
  current state.
- Path A: no rollback needed.

## Cross-references

- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` item #39
- `docs/audit/P201_MCP_ARCHITECTURE_AUDIT.md` §6 Onda D
- `.claude/rules/database.md` (DDL via apply_migration policy)
- `.claude/rules/deploy.md` (current deploy checklist)

## Handoff (fill on completion)

```md
## Handoff
Issue: #164
Branch:
Path picked:
Local supabase start status:
Runbook path:
Validacao:
Riscos:
Rollback:
Docs:
Proximo passo:
```
