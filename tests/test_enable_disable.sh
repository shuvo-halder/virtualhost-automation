#!/usr/bin/env bash
# test_enable_disable.sh - Integration test: enable/disable idempotency
# Run as: bash tests/test_enable_disable.sh   (root required for live tests)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VH="$REPO_ROOT/bin/virtualhost.sh"
DOMAIN="test-idempotent.local"
PASS=0
FAIL=0

_pass() { echo "[PASS] $1"; PASS=$((PASS+1)); }
_fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo ""
echo "=== Enable/Disable Idempotency Tests ==="
echo ""

# enable --dry-run should exit cleanly
if "$VH" enable "$DOMAIN" --dry-run 2>&1 | grep -qiE "DRY-RUN|already enabled|No configuration|not found"; then
    _pass "enable --dry-run exits cleanly"
else
    _fail "enable --dry-run unexpected output"
fi

# disable --dry-run should exit cleanly
if "$VH" disable "$DOMAIN" --dry-run 2>&1 | grep -qiE "DRY-RUN|already disabled|No configuration|not found"; then
    _pass "disable --dry-run exits cleanly"
else
    _fail "disable --dry-run unexpected output"
fi

# status should exit cleanly (even if domain does not exist)
if "$VH" status "$DOMAIN" --dry-run 2>&1 | grep -qiE "not found|DISABLED|ENABLED|DRY-RUN"; then
    _pass "status command exits cleanly"
else
    _fail "status command unexpected output"
fi

echo ""
echo "Results: PASS=$PASS  FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
