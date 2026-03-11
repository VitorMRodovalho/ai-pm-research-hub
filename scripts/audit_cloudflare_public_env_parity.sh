#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_EXAMPLE="${ROOT_DIR}/.env.example"
SUPABASE_TS="${ROOT_DIR}/src/lib/supabase.ts"
WRANGLER_TOML="${ROOT_DIR}/wrangler.toml"

required_public_vars=(
  "PUBLIC_SUPABASE_URL"
  "PUBLIC_SUPABASE_ANON_KEY"
)

echo "== Cloudflare Public Env Parity Audit =="
echo "repo: ${ROOT_DIR}"
echo

if [[ ! -f "${ENV_EXAMPLE}" ]]; then
  echo "FAIL: .env.example not found"
  exit 1
fi

if [[ ! -f "${SUPABASE_TS}" ]]; then
  echo "FAIL: src/lib/supabase.ts not found"
  exit 1
fi

if [[ ! -f "${WRANGLER_TOML}" ]]; then
  echo "FAIL: wrangler.toml not found"
  exit 1
fi

echo "-- Required public vars in .env.example --"
for var_name in "${required_public_vars[@]}"; do
  if grep -Eq "^${var_name}=" "${ENV_EXAMPLE}"; then
    echo "OK  ${var_name}"
  else
    echo "FAIL ${var_name} missing in .env.example"
    exit 1
  fi
done
echo

echo "-- Runtime/fallback safeguards in supabase.ts --"
if grep -Eq "DEFAULT_PUBLIC_SUPABASE_URL" "${SUPABASE_TS}"; then
  echo "OK  fallback default URL present"
else
  echo "FAIL fallback default URL missing"
  exit 1
fi

if grep -Eq "DEFAULT_PUBLIC_SUPABASE_ANON_KEY" "${SUPABASE_TS}"; then
  echo "OK  fallback default anon key present"
else
  echo "FAIL fallback default anon key missing"
  exit 1
fi

if grep -Eq "__PUBLIC_SUPABASE_URL" "${SUPABASE_TS}" && grep -Eq "__PUBLIC_SUPABASE_ANON_KEY" "${SUPABASE_TS}"; then
  echo "OK  runtime window public env hooks present"
else
  echo "FAIL runtime window public env hooks missing"
  exit 1
fi
echo

echo "-- Wrangler check (informational) --"
if grep -Eq "^[[:space:]]*\\[vars\\]" "${WRANGLER_TOML}"; then
  echo "INFO wrangler.toml has [vars] block (keep parity with dashboard envs)"
else
  echo "INFO wrangler.toml has no [vars] block (dashboard env injection is primary source)"
fi
echo

echo "-- Manual parity checklist (Cloudflare Pages) --"
echo "1) Settings -> Environment Variables -> Production:"
for var_name in "${required_public_vars[@]}"; do
  echo "   - ${var_name} configured"
done
echo "2) Settings -> Environment Variables -> Preview:"
for var_name in "${required_public_vars[@]}"; do
  echo "   - ${var_name} configured"
done
echo "3) Trigger redeploy after env updates."
echo
echo "PASS: local parity guards are in place; complete dashboard parity checklist above."
