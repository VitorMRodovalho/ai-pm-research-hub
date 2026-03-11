#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATRIX="$ROOT_DIR/docs/PERMISSIONS_MATRIX.md"
NAV="$ROOT_DIR/src/lib/navigation.config.ts"

echo "[permissions-sync] validating matrix vs navigation keys..."

required_keys=(
  "webinars"
  "publications"
  "admin-comms"
  "admin-comms-ops"
  "admin-portfolio"
  "admin-governance-v2"
)

for key in "${required_keys[@]}"; do
  if ! grep -F "key: '$key'" "$NAV" >/dev/null 2>&1; then
    echo "FAIL: missing nav key $key in navigation config"
    exit 1
  fi
  if ! grep -F "$key" "$MATRIX" >/dev/null 2>&1; then
    echo "FAIL: missing key reference $key in permissions matrix"
    exit 1
  fi
done

echo "[permissions-sync] PASS"
