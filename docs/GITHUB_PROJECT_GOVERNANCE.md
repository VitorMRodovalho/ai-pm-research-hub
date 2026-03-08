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

## Definition of Done (Governance)
- Project item marked `Done`.
- Release log entry created with validation evidence.
- Backlog row status reconciled.
- SQL pack attached when `SQL Required = Yes`.
