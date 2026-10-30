#!/usr/bin/env bash
# test_backup.sh - Integration test: backup/restore dry-run behaviour
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VH="$REPO_ROOT/bin/virtualhost.sh"
DOMAIN="test-backup.local"
PASS=0
FAIL=0

_pass() { echo "[PASS] $1"; PASS=$((PASS+1)); }
_fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo ""
echo "=== Backup / Restore Tests ==="
echo ""

# backup --dry-run should mention DRY-RUN
if "$VH" backup "$DOMAIN" --dry-run 2>&1 | grep -qi "DRY-RUN\|dry"; then
    _pass "backup --dry-run exits cleanly"
else
    _fail "backup --dry-run unexpected output"
fi

# restore with a missing file should error
if ! "$VH" restore "/tmp/no-such-backup-xyz.tar.gz" 2>&1 | grep -qiE "not found|error"; then
    _fail "restore should error on missing backup file"
else
    _pass "restore rejects missing backup file"
fi

# ssl-renew --dry-run should mention DRY-RUN or certbot
if "$VH" ssl-renew "$DOMAIN" --dry-run 2>&1 | grep -qiE "DRY-RUN|certbot|not installed"; then
    _pass "ssl-renew --dry-run exits cleanly"
else
    _fail "ssl-renew --dry-run unexpected output"
fi

echo ""
echo "Results: PASS=$PASS  FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
