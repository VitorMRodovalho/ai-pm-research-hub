#!/usr/bin/env bash
set -euo pipefail

OWNER="${1:-VitorMRodovalho}"
PROJECT_NUM="${2:-1}"

# NOTE:
# This script depends on GitHub Project GraphQL quota.
# Run after rate limit recovers.

echo "Fetching project items..."
gh project item-list "$PROJECT_NUM" --owner "$OWNER" --limit 300 --format json > /tmp/project_items_sync_seq.json

echo "Suggested manual view configuration in GitHub Project UI:"
echo "1) Create view: 'Roadmap Sequential (Packages)'"
echo "2) Group by: Wave"
echo "3) Sort by: Priority desc, Start date asc"
echo "4) Filter: Status != Done (for execution), duplicate view with Status=Done (history)"
echo "5) Pin fields: Sprint, Module, Type, SQL Required, Work Origin, Last Commit, Last Update"

echo "API snapshot saved at /tmp/project_items_sync_seq.json"
