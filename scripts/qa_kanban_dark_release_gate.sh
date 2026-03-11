#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "== QA Kanban/Dark release gate =="
./scripts/audit_dark_mode_a11y.sh
npm test
npm run build
npm run smoke:routes
echo "PASS: QA Kanban/Dark release gate"
