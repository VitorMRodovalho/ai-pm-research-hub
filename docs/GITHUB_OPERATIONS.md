# GitHub Operations Baseline

## Objective
Standardize sprint visibility, issue flow, CI, and release tagging for this repository.

## Sprint View Standard
Use `backlog-wave-planning-updated.md` as source of truth for IDs (for example `S-HF1`, `S-RM3`).

Every issue and PR must include a Sprint/Wave ID.

## Issue Types
- `Bug Report` for regressions and defects.
- `Sprint Task` for planned execution with acceptance criteria.
- `Feature Request` for product enhancements.

## PR Flow
1. Link PR to one issue and one Sprint/Wave ID.
2. Pass CI build.
3. Update release log when user-visible behavior changes.
4. Merge to `main` only after checklist completion.

## CI/CD Pipeline
- `CI` workflow runs build for pushes and PRs to `main`.
- `CodeQL` workflow scans JavaScript/TypeScript.
- `Dependabot` keeps npm and GitHub Actions dependencies updated.
- `Release on Tag` auto-creates GitHub release when pushing `v*` tags.

## Tagging Strategy
- Use semantic tags for release snapshots:
  - `vMAJOR.MINOR.PATCH`
- Recommended examples:
  - `v0.1.0` initial governance baseline
  - `v0.1.1` hotfix-only delivery

## Suggested GitHub Project (Board) Columns
- `Backlog`
- `Ready`
- `In Progress`
- `In Review`
- `Blocked`
- `Done`

## Suggested Label Set
- `type:bug`
- `type:feature`
- `type:task`
- `status:triage`
- `status:ready`
- `status:blocked`
- `priority:critical`
- `priority:high`
- `priority:medium`
- `priority:low`
