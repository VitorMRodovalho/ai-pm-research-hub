#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX_FILE="${ROOT_DIR}/docs/INDEX.md"

if [[ ! -f "${INDEX_FILE}" ]]; then
  echo "FAIL: docs/INDEX.md not found"
  exit 1
fi

echo "== Docs index link audit =="
echo "index: ${INDEX_FILE}"
echo

mapfile -t doc_refs < <(grep -oE '`[^`]+`' "${INDEX_FILE}" | tr -d '`' | sort -u)

if [[ ${#doc_refs[@]} -eq 0 ]]; then
  echo "FAIL: no backtick references found in docs/INDEX.md"
  exit 1
fi

missing=0
for rel in "${doc_refs[@]}"; do
  if [[ "${rel}" == *"*"* ]]; then
    if compgen -G "${ROOT_DIR}/${rel}" > /dev/null; then
      echo "OK   ${rel}"
    else
      echo "MISS ${rel}"
      missing=1
    fi
    continue
  fi

  # Ignore directory-only markers while still checking known docs and files.
  if [[ "${rel}" == */ ]]; then
    if [[ -d "${ROOT_DIR}/${rel}" ]]; then
      echo "OK   ${rel}"
    else
      echo "MISS ${rel}"
      missing=1
    fi
    continue
  fi

  if [[ -e "${ROOT_DIR}/${rel}" ]]; then
    echo "OK   ${rel}"
  else
    echo "MISS ${rel}"
    missing=1
  fi
done

if [[ ${missing} -ne 0 ]]; then
  echo
  echo "FAIL: docs index has broken references."
  exit 1
fi

echo
echo "PASS: docs index references are valid."
