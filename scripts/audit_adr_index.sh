#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADR_INDEX="${ROOT_DIR}/docs/adr/README.md"

if [[ ! -f "${ADR_INDEX}" ]]; then
  echo "FAIL: docs/adr/README.md not found"
  exit 1
fi

echo "== ADR index audit =="
echo "index: ${ADR_INDEX}"
echo

mapfile -t adr_refs < <(awk -F'`' '/ADR-[0-9]{4}.*\.md/ { for (i=2; i<=NF; i+=2) if ($i ~ /^ADR-[0-9]{4}.*\.md$/) print $i }' "${ADR_INDEX}" | sort -u)

if [[ ${#adr_refs[@]} -eq 0 ]]; then
  echo "FAIL: no ADR references found in docs/adr/README.md"
  exit 1
fi

missing=0
for adr in "${adr_refs[@]}"; do
  if [[ -f "${ROOT_DIR}/docs/adr/${adr}" ]]; then
    echo "OK   docs/adr/${adr}"
  else
    echo "MISS docs/adr/${adr}"
    missing=1
  fi
done

if [[ ${missing} -ne 0 ]]; then
  echo
  echo "FAIL: ADR index has broken references."
  exit 1
fi

echo
echo "PASS: ADR index references are valid."
