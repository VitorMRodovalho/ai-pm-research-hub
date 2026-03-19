#!/bin/bash
# ============================================================
# GC-097: Pre-Deploy Smoke Test
# Run before merging to main. Checks critical routes and i18n.
# Usage: bash scripts/smoke-test.sh [BASE_URL]
# ============================================================

BASE_URL="${1:-https://ai-pm-research-hub.pages.dev}"
ERRORS=0

echo "🔍 Smoke Test — $BASE_URL"
echo "================================"

# Layer 1: Route status checks (3 locales)
echo ""
echo "📡 Route checks..."

check_route() {
  local path="$1"
  local expected="$2"
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" -L "$BASE_URL$path" 2>/dev/null)
  if [ "$status" = "$expected" ]; then
    echo "  ✅ $path → $status"
  else
    echo "  ❌ $path → $status (expected $expected)"
    ERRORS=$((ERRORS + 1))
  fi
}

# Public pages (PT-BR)
check_route "/" "200"
check_route "/library" "200"
check_route "/gamification" "200"
check_route "/blog" "200"
check_route "/privacy" "200"

# EN locale
check_route "/en/" "200"
check_route "/en/library" "200"
check_route "/en/blog" "200"
check_route "/en/privacy" "200"

# ES locale
check_route "/es/" "200"
check_route "/es/library" "200"
check_route "/es/blog" "200"
check_route "/es/privacy" "200"

# Auth redirects (should redirect to /?auth=required)
check_route "/workspace" "200"  # redirects then 200
check_route "/en/workspace" "200"

echo ""
echo "🌐 Security headers..."
HEADERS=$(curl -s -I "$BASE_URL/" 2>/dev/null)
for header in "x-frame-options" "x-content-type-options" "referrer-policy"; do
  if echo "$HEADERS" | grep -qi "$header"; then
    echo "  ✅ $header present"
  else
    echo "  ⚠️  $header missing"
  fi
done

echo ""
echo "🔤 i18n key leak check..."
# Check build output for raw i18n keys (pattern: word.word.word without being in a JS string definition)
BUILD_DIR="dist"
if [ -d "$BUILD_DIR" ]; then
  RAW_KEYS=$(grep -roh "'[a-z]\+\.[a-z]\+\.[a-z]\+'" "$BUILD_DIR" --include="*.html" 2>/dev/null | sort -u | head -20)
  if [ -n "$RAW_KEYS" ]; then
    echo "  ⚠️  Possible raw i18n keys in HTML output:"
    echo "$RAW_KEYS" | sed 's/^/    /'
  else
    echo "  ✅ No raw i18n keys detected in HTML"
  fi
else
  echo "  ⏭️  No dist/ directory — run 'npm run build' first"
fi

echo ""
echo "================================"
if [ $ERRORS -eq 0 ]; then
  echo "✅ All checks passed!"
  exit 0
else
  echo "❌ $ERRORS check(s) failed!"
  exit 1
fi
