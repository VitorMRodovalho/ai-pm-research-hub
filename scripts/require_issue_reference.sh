#!/usr/bin/env bash
set -euo pipefail

# Enforce issue linkage for critical-path changes.
# Usage:
#   scripts/require_issue_reference.sh <base_sha> <head_sha>
# Env (optional):
#   PR_TITLE, PR_BODY

BASE_SHA="${1:-}"
HEAD_SHA="${2:-}"

if [[ -z "$BASE_SHA" || -z "$HEAD_SHA" ]]; then
  echo "Usage: $0 <base_sha> <head_sha>"
  exit 2
fi

if [[ "$BASE_SHA" == "0000000000000000000000000000000000000000" ]]; then
  BASE_SHA="$(git rev-list --max-parents=0 HEAD | tail -n 1)"
fi

if ! git rev-parse --verify "$BASE_SHA" >/dev/null 2>&1; then
  echo "Base SHA not found locally: $BASE_SHA"
  exit 2
fi

if ! git rev-parse --verify "$HEAD_SHA" >/dev/null 2>&1; then
  echo "Head SHA not found locally: $HEAD_SHA"
  exit 2
fi

changed_files="$(git diff --name-only "$BASE_SHA" "$HEAD_SHA" || true)"

if [[ -z "$changed_files" ]]; then
  echo "No changed files in range."
  exit 0
fi

# Critical paths by governance policy.
critical_files="$(printf '%s\n' "$changed_files" | rg '^(src/|supabase/|scripts/|\.github/workflows/|package\.json|astro\.config\.)' || true)"

if [[ -z "$critical_files" ]]; then
  echo "No critical-path files changed; issue reference gate skipped."
  exit 0
fi

echo "Critical files changed:"
printf '%s\n' "$critical_files"

log_text="$(git log --format=%B "$BASE_SHA..$HEAD_SHA" || true)"
joined="${log_text}
${PR_TITLE:-}
${PR_BODY:-}"

# Accept #123, GH-123 or full issue URL.
if printf '%s' "$joined" | rg -q '(#\d+|GH-\d+|github\.com/.+/issues/\d+)'; then
  echo "Issue reference found in commits/PR metadata."
  exit 0
fi

echo "ERROR: Critical-path changes require linked issue reference (#123, GH-123 or issue URL)."
exit 1
