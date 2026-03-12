# GitHub Repository Settings — Branch Protection

Status: **Documentation for GP to configure**

## Recommended Branch Protection Rules for `main`

Go to **Settings → Branches → Add branch protection rule** and set:

| Setting | Value | Why |
|---------|-------|-----|
| Branch name pattern | `main` | Protects the production branch |
| Require a pull request before merging | Yes | Prevents direct pushes to main |
| Required approvals | 1 | At least one reviewer must approve |
| Require status checks to pass | Yes | CI must be green before merge |
| Required status checks | `quality_gate` | Final gate job that depends on all others |
| Require branches to be up to date | Yes | PR must be rebased on latest main |
| Do not allow force pushes | Yes | Prevents history rewriting on main |
| Do not allow deletions | Yes | Prevents accidental branch deletion |

## How to Configure via GitHub UI

1. Navigate to the repo on GitHub
2. **Settings** → **Branches** (left sidebar)
3. Click **Add branch protection rule**
4. Enter `main` as the branch name pattern
5. Check the boxes per the table above
6. For "Require status checks", search for the job names from `.github/workflows/`
7. Click **Create** / **Save changes**

## How to Configure via GitHub CLI

```bash
# Requires gh CLI authenticated with admin access
gh api repos/{owner}/{repo}/branches/main/protection \
  --method PUT \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["quality_gate"]
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

> **Note:** Replace `{owner}/{repo}` with the actual values. `enforce_admins: false` allows admins to bypass in emergencies — set to `true` for stricter enforcement.

## Current CI Workflow Jobs (`.github/workflows/ci.yml`)

| Job | What it does |
|-----|-------------|
| `validate` | npm ci → lint:i18n → unit tests → astro build → smoke:routes |
| `browser_guards` | Playwright browser integration tests |
| `visual_dark_mode` | Dark mode visual snapshot tests |
| `quality_gate` | Passes only when all 3 above pass (use this as required check) |

## Transition Plan

Until branch protection is enabled:
- Developers push directly to `main` (current workflow)
- Cloudflare Pages autodeploys on every push
- After enabling protection, all changes go through PRs
