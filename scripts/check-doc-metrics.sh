#!/bin/bash
# check-doc-metrics.sh — Warns when documentation metrics drift from codebase reality.
# Run manually: ./scripts/check-doc-metrics.sh
# Or add to pre-commit / CI to prevent stale docs.

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

# ── Check CLAUDE.md ──
CLAUDE_MCP=$(grep -oP '\d+ MCP tools' "$ROOT/CLAUDE.md" | grep -oP '^\d+' || echo "?")
CLAUDE_EF=$(grep -oP '\d+ Edge Functions' "$ROOT/CLAUDE.md" | grep -oP '^\d+' || echo "?")

if [ "$CLAUDE_MCP" != "$MCP_TOOLS" ]; then
  echo "DRIFT: CLAUDE.md says $CLAUDE_MCP MCP tools, actual is $MCP_TOOLS"
  ERRORS=$((ERRORS + 1))
fi
if [ "$CLAUDE_EF" != "$EF_COUNT" ]; then
  echo "DRIFT: CLAUDE.md says $CLAUDE_EF Edge Functions, actual is $EF_COUNT"
  ERRORS=$((ERRORS + 1))
fi

# ── Check README.md Key Numbers table ──
README_MCP=$(grep -P 'MCP tools.*\d+' "$ROOT/README.md" | grep -oP '^\| MCP tools \| (\d+)' | grep -oP '\d+$' || echo "?")
if [ "$README_MCP" != "$MCP_TOOLS" ]; then
  echo "DRIFT: README.md Key Numbers says $README_MCP MCP tools, actual is $MCP_TOOLS"
  ERRORS=$((ERRORS + 1))
fi

# ── Check .claude/rules/mcp.md ──
RULES_MCP=$(grep -oP '^\- \d+ tools' "$ROOT/.claude/rules/mcp.md" | grep -oP '\d+' || echo "?")
if [ "$RULES_MCP" != "$MCP_TOOLS" ]; then
  echo "DRIFT: .claude/rules/mcp.md says $RULES_MCP tools, actual is $MCP_TOOLS"
  ERRORS=$((ERRORS + 1))
fi

# ── Summary ──
echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo "All docs in sync."
else
  echo "$ERRORS drift(s) found. Update docs to match codebase."
  echo "Tip: search for the old number and replace with the actual value."
  exit 1
fi
