# GitHub Repository Settings: merge gate on `main`

Status: **ACTIVE**. The gate is the repository ruleset `21186263` ("main - portao de merge"), created 2026-08-22. The legacy branch protection no longer exists: `GET .../branches/main/protection` returns 404 (measured 2026-10-31).

## Ruleset `21186263` (measured 2026-10-31, after `pmi-vep-sync` was added)

| Setting | Value | Why |
|---------|-------|-----|
| Target | `~DEFAULT_BRANCH` (`main`) | |
| Enforcement | `active` | |
| Required status checks | `validate`, `browser_guards`, `deno`, `structural`, `pmi-vep-sync`, all with `integration_id` 15368 (GitHub Actions) | See the table below |
| Require branches to be up to date | Yes (`strict_required_status_checks_policy`) | Update a PR by merging `main` into it: no rule forbids a merge commit on the branch, and it needs no force-push |
| Block force pushes | Yes (`non_fast_forward`) | Prevents history rewriting on `main` |
| Block deletions | Yes (`deletion`) | |
| Pull request rule | None | Every change still goes through a PR by owner decision: see `.claude/rules/bypass-protocol.md` |
| Bypass | `RepositoryRole` 5, `bypass_mode: always` | A bypass (an `--admin` merge, or a push with no PR) counts in the weekly audit (ADR-0122) |

## Required checks and where they come from

| Context | Workflow | Job |
|---------|----------|-----|
| `validate` | `.github/workflows/ci.yml` | waits for the DB lane (`wait-for-db-lane`) → npm ci → i18n and client-script gates → unit tests, DB-aware included → astro build → route smoke |
| `browser_guards` | `.github/workflows/ci.yml` | Playwright (chromium) browser guards, via `scripts/run_browser_guards_with_retry.sh` |
| `structural` | `.github/workflows/ci.yml` | `npm run test:structural`, with no Supabase env and no DB lane wait |
| `deno` | `.github/workflows/deno-ef-check.yml` | `deno lint` + `deno check` on the Edge Functions |
| `pmi-vep-sync` | `.github/workflows/worker-pmi-vep-sync.yml` | typecheck, tests and lint of `cloudflare-workers/pmi-vep-sync` |

`ci.yml` also runs `visual_dark_mode` and `quality_gate`, which needs `validate`, `browser_guards` and `visual_dark_mode`. Neither is a required context.

**A required context must report on EVERY pull request.** None of these workflows filters by `paths`. A path-filtered required check never reports on a PR that does not touch the path, and that PR waits forever. The context is the job id, so renaming the job has the same effect: change the ruleset in the same step. Only `pmi-vep-sync` has a guard for both today: `tests/contracts/2217-worker-pmi-vep-sync-no-ci.test.mjs` fails on a `paths` filter and on a renamed job. For `deno` there is only the comment at the top of `deno-ef-check.yml`, and nothing checks the `ci.yml` triggers or job ids.

## How to read and change it

```bash
# Read the ruleset, and the rules GitHub actually applies to main
gh api repos/VitorMRodovalho/ai-pm-research-hub/rulesets/21186263
gh api repos/VitorMRodovalho/ai-pm-research-hub/rules/branches/main

# Change it: send the COMPLETE ruleset (name, target, enforcement, conditions, bypass_actors, rules).
# The REST reference for "Update a repository ruleset" does not say whether an omitted field is kept,
# so build the body from the GET and keep the GET as the rollback body.
gh api repos/VitorMRodovalho/ai-pm-research-hub/rulesets/21186263 \
  | jq -S '{name,target,enforcement,conditions,bypass_actors,rules}' > rollback-body.json
# ...edit a copy into put-body.json, then:
gh api -X PUT repos/VitorMRodovalho/ai-pm-research-hub/rulesets/21186263 --input put-body.json
```

To see the effect where it is consumed, ask GitHub whether a check is required for a given PR: the GraphQL field `isRequired(pullRequestNumber: N)` on each `CheckRun` of the PR head.

## What This Means for Workflow

- Merge only with every required context green on a branch that is up to date with `main`.
- Force push to `main` is blocked.
- Deploy: `.github/workflows/deploy.yml` runs on `workflow_run` of `CI Validate`, only on `main` and only when it concludes with success.
