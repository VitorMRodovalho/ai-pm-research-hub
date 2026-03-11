# Project Governance Runbook

## GitHub Project (em uso)

Sim, continuamos a usar o **GitHub Project** para gestão de sprints e backlog.

- **Board**: [GitHub Project — AI PM Hub](https://github.com/users/VitorMRodovalho/projects/1/)
- **Repositório**: `VitorMRodovalho/ai-pm-research-hub`
- **EPICs atuais**: #47 (P0 Foundation), #48 (P1 Comms), #49 (P2 Knowledge), #50 (P3 Scale)

---

## Para começar a trabalhar

1. Abra o [board](https://github.com/users/VitorMRodovalho/projects/1/) e veja itens em `Backlog` ou `Ready`.
2. Leia `backlog-wave-planning-updated.md` para contexto das waves e prioridades.
3. Leia `docs/project-governance/ROADMAP_SEQUENCIAL_AGRUPADO.md` para regras de pacote pai → filho.
4. Leia `docs/project-governance/PROJECT_ON_TRACK.md` para integridade DB↔Frontend↔API e roadmap por batch.
5. Leia `docs/project-governance/REPO_SYNC_STRATEGY.md` para o fluxo oficial de sincronização dev ↔ prod.
6. Para analytics partner-facing, usar o checklist em `docs/project-governance/ANALYTICS_V2_PARTNER_VALIDATION.md`.
7. Itens em `In progress` devem ser **GitHub Issues** no repositório (não Drafts). Crie a issue se ainda não existir.
8. Ao commitar, referencie o sprint/issue (ex.: `fix: S-HF5 data patch (#XX)`).

---

## Objective
Keep GitHub Project (`AI PM Hub - Wave Sprint Pipeline`) synchronized with real delivery state and avoid draft-only work items for active execution.

## Mandatory rules
- Every active sprint (`In progress` or `In review`) must be a real GitHub Issue in `VitorMRodovalho/ai-pm-research-hub`.
- Draft cards are allowed only for long-horizon backlog ideation.
- Critical commits must reference a sprint/issue id in the commit message/body.
- SQL-impact sprints must include migration pack (`apply/audit/rollback`) before `Done`.
- Delivery model: trunk-based on `main` with mandatory technical gate (`npm test`, `npm run build`, `npm run smoke:routes`) and explicit closure of stale dependency PRs.

## Weekly cadence
1. `Backlog sync`: compare `backlog-wave-planning-updated.md` with project Sprint field.
2. `Issue sync`: convert active DraftIssue cards into repository issues.
3. `Field sync`: normalize `Wave`, `Sprint`, `Module`, `Type`, `Priority`, `SQL Required`, `Work Origin`, `Status`.
4. `Evidence sync`: update `Last Commit`, `Last Update`, and release evidence (`docs/RELEASE_LOG.md`).

## Commands

Project number: `1` · Owner: `VitorMRodovalho` · URL: https://github.com/users/VitorMRodovalho/projects/1/

- **Sincronização Board ↔ Docs**: ver `docs/AGENT_BOARD_SYNC.md` (workflow do assistente para issues + status + RELEASE_LOG)
- **Boas práticas de sprints**: ver `docs/project-governance/SPRINT_IMPLEMENTATION_PRACTICES.md` (priorização, gates, checklist ao concluir)
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
