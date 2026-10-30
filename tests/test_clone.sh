#!/usr/bin/env bash
# test_clone.sh - Integration test: clone source-missing guard + target-exists guard
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VH="$REPO_ROOT/bin/virtualhost.sh"
DST="test-clone-dst.local"
PASS=0
FAIL=0

_pass() { echo "[PASS] $1"; PASS=$((PASS+1)); }
_fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo ""
echo "=== Clone Guard Tests ==="
echo ""

# Clone from a non-existent source should fail (dry-run)
output=$("$VH" clone "no-such-host-xyz.local" "$DST" --dry-run 2>&1 || true)
if echo "$output" | grep -qiE "not found|does not exist|error"; then
    _pass "clone rejects missing source"
else
    _fail "clone should error on missing source (got: $output)"
fi

# clone to existing target should fail when the conf file actually exists (root only)
if [[ $(id -u) -eq 0 ]]; then
    SITES="/etc/apache2/sites-available"
    if [[ -d "$SITES" ]]; then
        touch "$SITES/${DST}.conf"
        out=$("$VH" clone "any-src.local" "$DST" 2>&1 || true)
        if echo "$out" | grep -qiE "already exists|error"; then
            _pass "clone rejects existing target"
        else
            _fail "clone should error on existing target (got: $out)"
        fi
        rm -f "$SITES/${DST}.conf"
    else
        echo "  SKIP clone-to-existing (Apache not installed)"
    fi
else
    echo "  SKIP clone-to-existing (not running as root)"
fi

echo ""
echo "Results: PASS=$PASS  FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
