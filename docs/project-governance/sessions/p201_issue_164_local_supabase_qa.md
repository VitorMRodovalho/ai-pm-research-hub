---
issue: 164
title: infra - restore local Supabase QA stack or document remote-only workflow
lane: Infra/Security + QA
priority: P1
effort: M (decide + implement + document)
status: done
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
Branch: agent/issue-164 (worktree em /home/vitormrodovalho/projects/ai-pm-issue-164)
Path picked: C (split baseline RPCs into post-schema migration) + remote-linked documentado como default
Local supabase start status: 00000000 baseline não falha mais (reduzido a marker/deprecation); local stack funciona APÓS one-time `supabase db pull --linked` bootstrap
Runbook path: docs/operations/LOCAL_QA.md (NOVO)
Files:
  - supabase/migrations/20260723000000_baseline_rpcs_after_schema.sql (NOVO) — 14 RPCs idempotent CREATE OR REPLACE, timestamp pós-schema
  - supabase/migrations/00000000_baseline_rpcs.sql — reduzido a marker (DDL removido)
  - docs/operations/LOCAL_QA.md (NOVO) — runbook A/B + bootstrap + drift troubleshooting + CI config
  - .claude/rules/deploy.md — item 4 link LOCAL_QA.md
  - AGENTS.md — paragrafo em "Local workflow" link LOCAL_QA.md
  - docs/audit/P162_GAP_OPPORTUNITY_LOG.md — #39 RESOLVED
Validação:
  - Production effect = zero (idempotent CREATE OR REPLACE + RPCs já vivem em prod)
  - Timestamp 20260723000000 > último existente (20260722020000)
  - Build/test não executados (mudanças SQL+docs only); production sem impacto
Riscos:
  - Baixo. Produção zero risk (idempotent reapply). Local: precisa db pull --linked bootstrap, documentado.
Rollback:
  - Revert PR; 00000000 volta com DDL; new file removido. Production zero impact.
Docs:
  - Runbook LOCAL_QA.md cobre Workflow A default + Workflow B opcional + bootstrap + drift troubleshooting + CI config secrets.
  - Audit log #39 RESOLVED.
Próximo passo:
  - Pós-merge: próximo deploy session valida via `supabase db push` (esperado no-op idempotente).
  - Backlog opcional: rodar `supabase db pull --linked` e commit baseline schema (one-time, não-bloqueante).
  - Pós-1 sprint QA window: confirmar zero regression em CI + verificar contributor reproduce Workflow B.
```
