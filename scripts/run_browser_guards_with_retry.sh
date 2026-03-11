#!/usr/bin/env bash
set -euo pipefail

attempt=1
max_attempts=2

while [ "$attempt" -le "$max_attempts" ]; do
  echo "[browser-guards] attempt ${attempt}/${max_attempts}"
  if npm run test:browser:guards; then
    echo "[browser-guards] success on attempt ${attempt}"
    exit 0
  fi
  if [ "$attempt" -lt "$max_attempts" ]; then
    echo "[browser-guards] failed attempt ${attempt}; retrying after short cooldown..."
    sleep 5
  fi
  attempt=$((attempt + 1))
done

echo "[browser-guards] failed after ${max_attempts} attempts"
exit 1
