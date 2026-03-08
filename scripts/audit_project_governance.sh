#!/usr/bin/env bash
set -euo pipefail
OWNER="${1:-VitorMRodovalho}"
PROJECT_NUM="${2:-1}"
OUT="${3:-/tmp/project_items_audit.json}"

gh project item-list "$PROJECT_NUM" --owner "$OWNER" --limit 200 --format json > "$OUT"

echo "== Active Drafts (must be 0) =="
jq -r '.items[] | select((.status=="In progress" or .status=="In review") and .content.type=="DraftIssue") | [.id,.sprint,.title,.status] | @tsv' "$OUT"

echo "\n== Sprint Coverage =="
jq -r '.items[] | .sprint // "<none>"' "$OUT" | sort | uniq -c | sort -k2

echo "\n== Repository Split =="
jq -r '.items[] | .repository // "<draft/no-repo>"' "$OUT" | sort | uniq -c
