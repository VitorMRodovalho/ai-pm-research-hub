#!/usr/bin/env bash
set -euo pipefail
REPO="${1:-VitorMRodovalho/ai-pm-research-hub}"

gh issue list --repo "$REPO" --state all --limit 300 --json number,title,state,url > /tmp/issues_seq.json

printf "# Roadmap Sequence Snapshot\n\n"

print_epic() {
  local epic_num="$1"
  local epic_title="$2"
  printf "## %s\n" "$epic_title"
  jq -r --arg num "$epic_num" '.[] | select(.number==($num|tonumber)) | "- EPIC: #\(.number) [\(.state)] \(.title)"' /tmp/issues_seq.json
  printf "\n"
}

print_epic 47 "P0 Foundation"
print_epic 48 "P1 Comms"
print_epic 49 "P2 Knowledge"
print_epic 50 "P3 Scale/Data/FinOps"

printf "## Open child issues (non-epic)\n"
jq -r '.[] | select(.state=="OPEN" and (.number<47 or .number>50)) | "- #\(.number) \(.title)"' /tmp/issues_seq.json | sort -V
