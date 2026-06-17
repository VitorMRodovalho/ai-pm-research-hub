#!/bin/bash
# check-doc-metrics.sh — Warns when documentation metrics drift from codebase reality.
# Run manually: ./scripts/check-doc-metrics.sh
# Or add to pre-commit / CI to prevent stale docs.
#
# Scope note (2026-06-17): this script asserts ONLY on the public-facing README
# numbers (the reader-facing contract). It deliberately does NOT check CLAUDE.md
# or .claude/rules/mcp.md: both files explicitly decided NOT to pin volatile
# counts (CLAUDE.md "Current state … NOT pinned per Anthropic guidance";
# rules/mcp.md "## Current State (do NOT pin counts here) … never pin it here").
# Demanding a pinned number there was a permanent false-positive. Get the live
# MCP tool count from the running server (see .claude/rules/mcp.md), not from docs.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ERRORS=0

# ── Extract actual metrics ──
MCP_TOOLS=$(grep -c 'mcp\.tool(' "$ROOT/supabase/functions/nucleo-mcp/index.ts" 2>/dev/null || echo 0)
EF_COUNT=$(find "$ROOT/supabase/functions" -mindepth 1 -maxdepth 1 -type d ! -name '_shared' | wc -l | tr -d ' ')
I18N_KEYS=$(grep -c "'" "$ROOT/src/i18n/pt-BR.ts" 2>/dev/null || echo 0)

echo "=== Doc Metrics Check ==="
echo "  MCP tools (actual): $MCP_TOOLS"
echo "  Edge Functions (actual): $EF_COUNT"
echo "  i18n keys (actual): ~$I18N_KEYS"
echo ""

# ── Check README.md Key Numbers table (public-facing contract) ──
# The "320+" soft-growth form is fine: we only compare the leading integer.
README_MCP=$(grep -P '^\| MCP tools \| \d+' "$ROOT/README.md" | grep -oP '\d+' | head -1 || echo "?")
if [ "$README_MCP" != "$MCP_TOOLS" ]; then
  echo "DRIFT: README.md Key Numbers says $README_MCP MCP tools, actual is $MCP_TOOLS"
  ERRORS=$((ERRORS + 1))
fi

README_EF=$(grep -P '^\| Edge Functions \| \d+' "$ROOT/README.md" | grep -oP '\d+' | head -1 || echo "?")
if [ "$README_EF" != "$EF_COUNT" ]; then
  echo "DRIFT: README.md Key Numbers says $README_EF Edge Functions, actual is $EF_COUNT"
  ERRORS=$((ERRORS + 1))
fi

# i18n keys in the README are an approximate ("6,200+") and the live count is a
# fuzzy quote-grep, so it is reported above for reference but not asserted.

# ── Summary ──
echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo "All public docs in sync."
else
  echo "$ERRORS drift(s) found. Update docs to match codebase."
  echo "Tip: search for the old number and replace with the actual value."
  exit 1
fi
