# GitHub Project Governance (Waves & Sprints)

## Canonical Source of Truth
- Official sprint pipeline lives in **GitHub Projects** (board view + iteration fields).
- Repository files remain mandatory mirrors:
  - `backlog-wave-planning-updated.md` = roadmap and wave status.
  - `docs/RELEASE_LOG.md` = shipped increments and evidence.
  - `docs/migrations/*` = SQL governance artifacts when applicable.

## Minimum Project Fields
- `Wave` (e.g. Wave 4)
- `Sprint` (e.g. S-COM10)
- `Type` (`Feature`, `Hotfix`, `SQL`, `Ops`)
- `Priority` (`Critical`, `High`, `Medium`, `Low`)
- `Status` (`Backlog`, `Ready`, `In Progress`, `Review`, `Done`)
- `SQL Required` (`Yes`, `No`)
- `Owner`
- `Target Deploy Date`

## Governance Cadence
1. Sprint planning: create/update Project items first.
2. During execution: update Project item status at each handoff.
3. At deploy: add release evidence in `docs/RELEASE_LOG.md`.
4. End of sprint: reconcile `backlog-wave-planning-updated.md` with Project board.

## CLI Access Requirement
To audit/sync Project items with GitHub CLI, token must include project scopes:

```bash
gh auth refresh -s read:project -s project
```

## Automation
- Workflow: `.github/workflows/project-governance-sync.yml`
- Script: `scripts/sync-project-metadata.sh`
- Trigger:
  - every push to `main`
  - manual dispatch with optional `issue_link`
- Required secret in GitHub repo:
  - `PROJECT_AUTOMATION_TOKEN` (PAT with `project` + `repo`)
- Auto-updated fields:
  - `Last Commit`
  - `Commit Timestamp`
  - `Last Update`
  - `Delivery Mode` (heuristic: `fix:` => `Review Loop`, else `Advancing`)
  - `Work Origin` (heuristic: `fix:` => `Issue-Driven`, else `Sprint Planned`)
  - `Issue Link` (when provided on manual dispatch)

## Board Views (manual setup in UI)
GitHub CLI/API currently does not reliably manage Project view layout/grouping. Keep these views in the Project UI:

1. `Execution Board`
- Layout: Board
- Group by: `Status`
- Sort by: `Priority` desc, then `Last Update` desc

2. `By Wave`
- Layout: Table
- Group by: `Wave`
- Sort by: `Sprint` asc

3. `By Module`
- Layout: Table
- Group by: `Module`
- Sort by: `Last Update` desc

4. `Review Loop`
- Filter: `Delivery Mode = Review Loop`
- Sort by: `Last Update` desc

5. `Done Timeline`
- Filter: `Status = Done`
- Sort by: `Commit Timestamp` desc

## Definition of Done (Governance)
- Project item marked `Done`.
- Release log entry created with validation evidence.
- Backlog row status reconciled.
- SQL pack attached when `SQL Required = Yes`.
