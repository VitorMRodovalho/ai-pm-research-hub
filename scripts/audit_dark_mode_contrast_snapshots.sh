#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[dark-contrast] running baseline checks..."
./scripts/audit_dark_mode_a11y.sh
./scripts/audit_dark_mode_visual_baseline.sh

echo "[dark-contrast] generating multilingual screenshot baseline..."
npm run screenshots:multilang

echo "[dark-contrast] PASS"
