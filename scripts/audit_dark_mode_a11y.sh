#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

FAIL=0

check_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Fq "${pattern}" "${file}"; then
    echo "OK: ${label}"
  else
    echo "FAIL: ${label} (${pattern})"
    FAIL=1
  fi
}

echo "== Dark mode A11y quick audit =="
check_contains "src/layouts/BaseLayout.astro" "data-theme" "layout applies runtime theme attribute"
check_contains "src/components/nav/Nav.astro" "pd-theme-toggle" "profile drawer exposes theme toggle"
check_contains "src/styles/global.css" "@custom-variant dark" "tailwind dark variant configured"
check_contains "src/pages/tribe/[id].astro" "id=\"board-item-modal\"" "tribe card modal exists"
check_contains "src/pages/tribe/[id].astro" "dark:bg-slate-900" "tribe modals include dark background"
check_contains "src/pages/publications.astro" "dark:bg-slate-900" "publications surface includes dark styles"
check_contains "src/pages/admin/webinars.astro" "dark:bg-slate-900" "webinars panel includes dark styles"
check_contains "src/pages/teams.astro" "dark:bg-slate-900" "teams surface includes dark styles"

if [[ "${FAIL}" -ne 0 ]]; then
  echo "FAIL: dark mode audit detected missing coverage."
  exit 1
fi

echo "PASS: dark mode audit passed."
