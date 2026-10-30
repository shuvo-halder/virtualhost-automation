#!/usr/bin/env bash
# run_integration_tests.sh - Run all Phase 3 integration tests
# Usage: bash tests/run_integration_tests.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
ALL_PASS=true

run_test() {
    local name="$1"
    local script="$2"
    echo ""
    echo "--- Running: $name ---"
    if bash "$script"; then
        TOTAL_PASS=$((TOTAL_PASS+1))
    else
        TOTAL_FAIL=$((TOTAL_FAIL+1))
        ALL_PASS=false
    fi
}

run_test "Enable/Disable Idempotency" "$SCRIPT_DIR/test_enable_disable.sh"
run_test "Clone Guard"                "$SCRIPT_DIR/test_clone.sh"
run_test "Backup/Restore"             "$SCRIPT_DIR/test_backup.sh"

echo ""
echo "======================================="
echo "  Integration Test Summary"
echo "  Tests passed: $TOTAL_PASS"
echo "  Tests failed: $TOTAL_FAIL"
echo "======================================="
echo ""

$ALL_PASS
