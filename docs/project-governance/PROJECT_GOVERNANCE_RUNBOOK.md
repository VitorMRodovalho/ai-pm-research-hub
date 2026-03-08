# Project Governance Runbook

## Objective
Keep GitHub Project (`AI PM Hub - Wave Sprint Pipeline`) synchronized with real delivery state and avoid draft-only work items for active execution.

## Mandatory rules
- Every active sprint (`In progress` or `In review`) must be a real GitHub Issue in `VitorMRodovalho/ai-pm-hub-v2`.
- Draft cards are allowed only for long-horizon backlog ideation.
- Critical commits must reference a sprint/issue id in the commit message/body.
- SQL-impact sprints must include migration pack (`apply/audit/rollback`) before `Done`.

## Weekly cadence
1. `Backlog sync`: compare `backlog-wave-planning-updated.md` with project Sprint field.
2. `Issue sync`: convert active DraftIssue cards into repository issues.
3. `Field sync`: normalize `Wave`, `Sprint`, `Module`, `Type`, `Priority`, `SQL Required`, `Work Origin`, `Status`.
4. `Evidence sync`: update `Last Commit`, `Last Update`, and release evidence (`docs/RELEASE_LOG.md`).

## Commands
- Inventory project items:
  - `gh project item-list 1 --owner VitorMRodovalho --limit 200 --format json`
- Find active drafts (must be converted):
  - `jq -r '.items[] | select((.status=="In progress" or .status=="In review") and .content.type=="DraftIssue") | [.id,.sprint,.title] | @tsv'`
- Coverage by sprint id:
  - `jq -r '.items[] | .sprint' | sort | uniq -c`

## Current baseline (2026-03-08)
- Active drafts in progress/review: `0`
- Backlog sprint coverage from v4 plan: complete for listed sprint IDs.
- Snapshot evidence:
  - `docs/project-governance/project-snapshot-2026-03-08.json`
  - `docs/project-governance/project-snapshot-2026-03-08.tsv`

## Workflows (GitHub Actions)
- `Project Governance Sync`:
  - file: `.github/workflows/project-governance-sync.yml`
  - trigger: `workflow_dispatch`, schedule each 6h, and push on governance files
- `Knowledge Insights Auto Sync`:
  - file: `.github/workflows/knowledge-insights-auto-sync.yml`
  - trigger: `workflow_dispatch`, schedule Monday/Thursday
  - required secrets:
    - `SUPABASE_URL`
    - `SUPABASE_ANON_KEY`
    - `SYNC_KNOWLEDGE_INSIGHTS_SECRET`
    - optional: `KNOWLEDGE_INSIGHTS_FUNCTION_NAME` (default `sync-knowledge-insights`)
