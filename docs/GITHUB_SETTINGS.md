# GitHub Repository Settings — Branch Protection

Status: **ACTIVE** — applied 2026-03-12 via GitHub API

## Current Branch Protection Rules for `main`

| Setting | Value | Why |
|---------|-------|-----|
| Require status checks to pass | Yes | CI must be green before merge |
| Required status checks | `validate`, `browser_guards` | Core CI jobs (build + unit tests + browser tests) |
| Require branches to be up to date | Yes | Branch must be rebased on latest main |
| Require PR before merging | **No** | Bus factor = 1 (Vitor is sole committer); direct push allowed |
| Required approvals | N/A | No PR requirement currently |
| Do not allow force pushes | Yes | Prevents history rewriting on main |
| Do not allow deletions | Yes | Prevents accidental branch deletion |
| Enforce for admins | No | Admin can bypass in emergencies |

## CI Workflow Jobs (`.github/workflows/ci.yml`)

| Job | What it does |
|-----|-------------|
| `validate` | npm ci → lint:i18n → unit tests → astro build → smoke:routes |
| `browser_guards` | Playwright browser integration tests |
| `visual_dark_mode` | Dark mode visual snapshot tests |
| `quality_gate` | Passes only when all 3 above pass |

> `validate` and `browser_guards` are required checks. `visual_dark_mode` runs but is not blocking (can be added later).

## How to Modify via GitHub CLI

```bash
# View current protection
gh api repos/VitorMRodovalho/ai-pm-research-hub/branches/main/protection

# Add PR requirement later (when team grows)
gh api repos/VitorMRodovalho/ai-pm-research-hub/branches/main/protection \
  --method PUT \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["validate", "browser_guards"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

## What This Means for Workflow

- Direct pushes to `main` still work (no PR required)
- But CI must pass — if `validate` or `browser_guards` fail, push is blocked
- Force push to main is blocked
- Cloudflare Workers autodeploys on every successful push
