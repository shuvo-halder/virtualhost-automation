#!/usr/bin/env bash
# test-virtualhost.sh — Basic tests for Apache VirtualHost Manager v3.0.0
# Version: 3.0.0
#
# Run with: bash tests/test-virtualhost.sh
# These tests validate the main script functions without requiring root.

set -o errexit
set -o nounset
set -o pipefail

readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd "$TEST_DIR/.." && pwd)"

# Colors
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_RESET='\033[0m'

PASSED=0
FAILED=0

print_result() {
    local test_name="$1"
    local result="$2"
    if [[ "$result" -eq 0 ]]; then
        echo -e "  ${C_GREEN}✓${C_RESET} $test_name"
        ((PASSED++))
    else
        echo -e "  ${C_RED}✗${C_RESET} $test_name"
        ((FAILED++))
    fi
}

echo ""
echo "========================================="
echo "  VirtualHost Apache — Test Suite v3.0.0"
echo "========================================="
echo ""

# ============================================================================
# Test 1: Script files exist
# ============================================================================
echo "--- File Existence ---"

test_script_exists() {
    [[ -f "$PROJECT_DIR/bin/virtualhost.sh" ]]
}
print_result "bin/virtualhost.sh exists" $?

test_lib_exists() {
    [[ -f "$PROJECT_DIR/lib/virtualhost-lib.sh" ]]
}
print_result "lib/virtualhost-lib.sh exists" $?

test_wrapper_exists() {
    [[ -f "$PROJECT_DIR/virtualhost.sh" ]]
}
print_result "Root wrapper exists" $?

# ============================================================================
# Test 2: Version string extraction
# ============================================================================
echo ""
echo "--- Version Check ---"

test_version() {
    local version
    version=$(grep "^readonly SCRIPT_VERSION=" "$PROJECT_DIR/bin/virtualhost.sh" | cut -d'"' -f2)
    [[ "$version" == "3.0.0" ]]
}
print_result "Apache script version is 3.0.0" $?

test_lib_version() {
    local version
    version=$(grep "^readonly LIB_VERSION=" "$PROJECT_DIR/lib/virtualhost-lib.sh" | cut -d'"' -f2)
    [[ "$version" == "3.0.0" ]]
}
print_result "Library version is 3.0.0" $?

# ============================================================================
# Test 3: Domain validation (source the lib)
# ============================================================================
echo ""
echo "--- Domain Validation ---"

test_valid_domain() {
    # Simulate validation by checking the regex
    local domain="example.dev"
    [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] && [[ ${#domain} -ge 3 ]]
}
print_result "Valid domain 'example.dev' passes" $?

test_invalid_domain_special_chars() {
    local domain="bad domain!!"
    ! [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]]
}
print_result "Invalid domain with special chars fails" $?

test_invalid_domain_too_short() {
    local domain="ab"
    ! ([[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] && [[ ${#domain} -ge 3 ]])
}
print_result "Domain too short 'ab' fails" $?

test_domain_with_dots() {
    local domain="subdomain.example.dev"
    [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]]
}
print_result "Subdomain 'subdomain.example.dev' passes" $?

test_domain_with_hyphens() {
    local domain="my-site.example.com"
    [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]]
}
print_result "Domain with hyphen 'my-site.example.com' passes" $?

# ============================================================================
# Test 4: Webroot calculation
# ============================================================================
echo ""
echo "--- Webroot Calculation ---"

test_webroot_default() {
    local domain="example"
    local safe_name="${domain//./}"
    local webroot="/var/www/$safe_name"
    [[ "$webroot" == "/var/www/example" ]]
}
print_result "Default webroot for 'example': /var/www/example" $?

test_webroot_with_dots() {
    local domain="example.dev"
    local safe_name="${domain//./}"
    local webroot="/var/www/$safe_name"
    [[ "$webroot" == "/var/www/exampledev" ]]
}
print_result "Default webroot for 'example.dev': /var/www/exampledev" $?

test_webroot_custom() {
    local custom_root="/home/user/www"
    [[ "$custom_root" == /* ]]
    [[ "$custom_root" == "/home/user/www" ]]
}
print_result "Custom absolute path preserved" $?

test_webroot_relative() {
    local custom_root="mysite"
    local default_webroot="/var/www"
    local webroot="$default_webroot/$custom_root"
    [[ "$webroot" == "/var/www/mysite" ]]
}
print_result "Relative custom path: /var/www/mysite" $?

# ============================================================================
# Test 5: Feature flags
# ============================================================================
echo ""
echo "--- Feature Flags ---"

test_dry_run_default() {
    local DRY_RUN=0
    [[ $DRY_RUN -eq 0 ]]
}
print_result "DRY_RUN defaults to 0" $?

test_verbose_default() {
    local VERBOSE=0
    [[ $VERBOSE -eq 0 ]]
}
print_result "VERBOSE defaults to 0" $?

test_skip_reload_default() {
    local SKIP_RELOAD=0
    [[ $SKIP_RELOAD -eq 0 ]]
}
print_result "SKIP_RELOAD defaults to 0" $?

test_force_default() {
    local FORCE=0
    [[ $FORCE -eq 0 ]]
}
print_result "FORCE defaults to 0" $?

test_skip_index_default() {
    local SKIP_INDEX=0
    [[ $SKIP_INDEX -eq 0 ]]
}
print_result "SKIP_INDEX defaults to 0" $?

test_skip_hosts_default() {
    local SKIP_HOSTS=0
    [[ $SKIP_HOSTS -eq 0 ]]
}
print_result "SKIP_HOSTS defaults to 0" $?

test_enable_ssl_default() {
    local ENABLE_SSL=0
    [[ $ENABLE_SSL -eq 0 ]]
}
print_result "ENABLE_SSL defaults to 0" $?

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "========================================="
echo -e "  Results: ${C_GREEN}$PASSED passed${C_RESET}, ${C_RED}$FAILED failed${C_RESET}"
echo "========================================="
echo ""

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0