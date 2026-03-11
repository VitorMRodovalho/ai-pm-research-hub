#!/usr/bin/env bash
set -euo pipefail

OWNER_REPO="${1:-VitorMRodovalho/ai-pm-research-hub}"
BRANCHES=("main" "dev")

for branch in "${BRANCHES[@]}"; do
  echo "== Branch protection: ${OWNER_REPO}:${branch} =="
  gh api "repos/${OWNER_REPO}/branches/${branch}/protection" 2>/dev/null \
    | jq '{required_status_checks, enforce_admins, required_pull_request_reviews, restrictions}' \
    || echo "No protection config or insufficient permissions for ${branch}."
  echo
done
