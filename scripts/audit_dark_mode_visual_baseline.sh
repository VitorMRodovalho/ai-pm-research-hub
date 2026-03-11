#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[dark-baseline] checking visual baseline prerequisites..."

[[ -f "scripts/screenshots-multilang.mjs" ]] || { echo "FAIL: screenshots-multilang.mjs not found"; exit 1; }
[[ -f "scripts/audit_dark_mode_a11y.sh" ]] || { echo "FAIL: audit_dark_mode_a11y.sh not found"; exit 1; }

if ! grep -E -n "data-theme|ui_theme|pd-theme-toggle" src/components/nav/Nav.astro src/layouts/BaseLayout.astro src/styles/global.css >/dev/null 2>&1; then
  echo "FAIL: no dark-mode hooks found in expected surfaces"
  exit 1
fi

echo "[dark-baseline] running dark mode a11y quick audit..."
./scripts/audit_dark_mode_a11y.sh

echo "[dark-baseline] baseline prerequisites OK."
