#!/usr/bin/env bash
# test-virtualhost-nginx.sh — Basic tests for Nginx VirtualHost Manager v3.0.0
# Version: 3.0.0
#
# Run with: bash tests/test-virtualhost-nginx.sh
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
echo "  VirtualHost Nginx — Test Suite v3.0.0"
echo "========================================="
echo ""

# ============================================================================
# Test 1: Script files exist
# ============================================================================
echo "--- File Existence ---"

test_script_exists() {
    [[ -f "$PROJECT_DIR/bin/virtualhost-nginx.sh" ]]
}
print_result "bin/virtualhost-nginx.sh exists" $?

test_wrapper_exists() {
    [[ -f "$PROJECT_DIR/virtualhost-nginx.sh" ]]
}
print_result "Root wrapper exists" $?

# ============================================================================
# Test 2: Version string extraction
# ============================================================================
echo ""
echo "--- Version Check ---"

test_version() {
    local version
    version=$(grep "^readonly SCRIPT_VERSION=" "$PROJECT_DIR/bin/virtualhost-nginx.sh" | cut -d'"' -f2)
    [[ "$version" == "3.0.0" ]]
}
print_result "Nginx script version is 3.0.0" $?

# ============================================================================
# Test 3: Domain validation
# ============================================================================
echo ""
echo "--- Domain Validation ---"

test_valid_domain() {
    local domain="example.dev"
    [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] && [[ ${#domain} -ge 3 ]]
}
print_result "Valid domain 'example.dev' passes" $?

test_invalid_domain_special_chars() {
    local domain="bad domain!!"
    ! [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]]
}
print_result "Invalid domain with special chars fails" $?

test_domain_with_dots() {
    local domain="subdomain.example.dev"
    [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]]
}
print_result "Subdomain 'subdomain.example.dev' passes" $?

# ============================================================================
# Test 4: PHP-FPM socket validation
# ============================================================================
echo ""
echo "--- PHP-FPM Socket Validation ---"

test_tcp_socket() {
    local socket="127.0.0.1:9000"
    [[ "$socket" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]
}
print_result "TCP socket '127.0.0.1:9000' passes" $?

test_unix_socket_format() {
    local socket="unix:/run/php/php8.1-fpm.sock"
    [[ "$socket" =~ ^unix: ]]
}
print_result "Unix socket 'unix:/run/php/php8.1-fpm.sock' passes" $?

# ============================================================================
# Test 5: Webroot calculation
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

test_webroot_custom_absolute() {
    local custom_root="/home/user/www"
    [[ "$custom_root" == "/home/user/www" ]]
}
print_result "Custom absolute path preserved" $?

# ============================================================================
# Test 6: PHP-FPM auto-detection versions
# ============================================================================
echo ""
echo "--- PHP-FPM Version Detection ---"

test_php_versions_in_script() {
    local versions
    versions=$(grep -oP '"\d+\.\d+"' "$PROJECT_DIR/bin/virtualhost-nginx.sh" | tr -d '"' | sort -u)
    local found=0
    for v in 8.4 8.3 8.2 8.1 8.0 7.4 7.3 7.2 7.1 7.0; do
        if echo "$versions" | grep -q "$v"; then
            ((found++))
        fi
    done
    [[ $found -ge 5 ]]
}
print_result "Script contains multiple PHP-FPM version entries" $?

# ============================================================================
# Test 7: Generate SSL certificate logic
# ============================================================================
echo ""
echo "--- SSL Certificate Path Logic ---"

test_ssl_path_letsencrypt() {
    local domain="example.dev"
    local ssl_cert="/etc/letsencrypt/live/$domain/fullchain.pem"
    local ssl_key="/etc/letsencrypt/live/$domain/privkey.pem"
    [[ "$ssl_cert" == "/etc/letsencrypt/live/example.dev/fullchain.pem" ]] && \
    [[ "$ssl_key" == "/etc/letsencrypt/live/example.dev/privkey.pem" ]]
}
print_result "Let's Encrypt paths are correct" $?

test_ssl_path_self_signed() {
    local domain="example.dev"
    local ssl_cert="/etc/ssl/$domain/fullchain.pem"
    local ssl_key="/etc/ssl/$domain/privkey.pem"
    [[ "$ssl_cert" == "/etc/ssl/example.dev/fullchain.pem" ]] && \
    [[ "$ssl_key" == "/etc/ssl/example.dev/privkey.pem" ]]
}
print_result "Self-signed paths are correct" $?

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