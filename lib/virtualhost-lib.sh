#!/usr/bin/env bash
# virtualhost-lib.sh — Shared Library for VirtualHost Manager v3.0.0
# Version: 3.0.0
# Author: Shuvo Halder
# License: MIT
#
# Shared functions used by both Apache and Nginx virtual host managers.

# ============================================================================
# CONFIGURATION DEFAULTS
# ============================================================================
readonly LIB_VERSION="3.0.0"

# Feature flags (overridable)
DRY_RUN=${DRY_RUN:-0}
VERBOSE=${VERBOSE:-0}
SKIP_RELOAD=${SKIP_RELOAD:-0}
FORCE=${FORCE:-0}
SKIP_INDEX=${SKIP_INDEX:-0}
SKIP_HOSTS=${SKIP_HOSTS:-0}
ENABLE_SSL=${ENABLE_SSL:-0}
SELF_SIGNED=${SELF_SIGNED:-0}
FORCE_HTTPS=${FORCE_HTTPS:-0}
WITH_WWW=${WITH_WWW:-0}
JSON_OUTPUT=${JSON_OUTPUT:-0}
NO_COLOR=${NO_COLOR:-0}

# Color codes
if [[ $NO_COLOR -eq 0 ]] && [[ -t 1 ]]; then
    readonly C_RED='\033[0;31m'
    readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[1;33m'
    readonly C_BLUE='\033[0;34m'
    readonly C_CYAN='\033[0;36m'
    readonly C_BOLD='\033[1m'
    readonly C_RESET='\033[0m'
else
    readonly C_RED=''
    readonly C_GREEN=''
    readonly C_YELLOW=''
    readonly C_BLUE=''
    readonly C_CYAN=''
    readonly C_BOLD=''
    readonly C_RESET=''
fi

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Print error message to stderr and log file
err() {
    echo -e "${C_RED}ERROR:${C_RESET} $*" >&2
    log "ERROR: $*"
}

# Print info message to stdout and log file
info() {
    echo -e "${C_BLUE}INFO:${C_RESET} $*"
    log "INFO: $*"
}

# Print warning message to stderr and log file
warn() {
    echo -e "${C_YELLOW}WARNING:${C_RESET} $*" >&2
    log "WARNING: $*"
}

# Print success message
success() {
    echo -e "${C_GREEN}✓${C_RESET} $*"
    log "SUCCESS: $*"
}

# Verbose output (only if -v flag is set)
verbose() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo -e "  ${C_CYAN}→${C_RESET} $*"
    fi
    log "VERBOSE: $*"
}

# Log to file
log() {
    local log_dir="${LOG_DIR:-/var/log/virtualhost}"
    local log_file="$log_dir/virtualhost-$(date +%Y%m%d).log"
    if [[ -d "$log_dir" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$log_file"
    fi
}

# Print JSON formatted output
json_output() {
    local status="$1"
    local message="$2"
    local data="${3:-}"
    if [[ $JSON_OUTPUT -eq 1 ]]; then
        if [[ -n "$data" ]]; then
            echo "{\"status\":\"$status\",\"message\":\"$message\",\"data\":$data}"
        else
            echo "{\"status\":\"$status\",\"message\":\"$message\"}"
        fi
    fi
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

# Ensure script runs as root
check_root() {
    if [[ $(id -u) -ne 0 ]]; then
        err "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Validate domain name format
validate_domain() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        err "Domain cannot be empty"
        return 1
    fi

    if ! [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]]; then
        err "Invalid domain: '$domain' (use only alphanumeric, dots, and hyphens)"
        return 1
    fi

    # Check minimum length
    if [[ ${#domain} -lt 3 ]]; then
        err "Domain must be at least 3 characters long"
        return 1
    fi

    verbose "Domain validation passed: $domain"
    return 0
}

# ============================================================================
# COMMON OPERATIONS
# ============================================================================

# Get the owner from sudo or current user
get_owner() {
    local owner="${SUDO_USER:-}"
    if [[ -z "$owner" ]]; then
        owner=$(logname 2>/dev/null || echo "root")
    fi
    echo "$owner"
}

# Determine the web root directory
get_webroot() {
    local user_root="$1"
    local domain="$2"
    local default_webroot="${3:-/var/www}"
    local webroot

    if [[ -n "$user_root" ]]; then
        if [[ "$user_root" == /* ]]; then
            webroot="$user_root"
        else
            webroot="$default_webroot/$user_root"
        fi
    else
        local safe_name="${domain//./}"
        webroot="$default_webroot/$safe_name"
    fi

    echo "$webroot"
}

# Create web root directory and set permissions
create_webroot() {
    local webroot="$1"
    local owner="$2"
    local web_group="${3:-www-data}"

    verbose "Creating web root: $webroot"

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would create directory: $webroot"
        info "[DRY-RUN] Would set owner: $owner:$web_group"
        return 0
    fi

    if [[ -d "$webroot" ]]; then
        info "Directory already exists: $webroot"
    else
        mkdir -p -- "$webroot"
        chmod 755 -- "$webroot"
        success "Created directory: $webroot"
    fi

    # Set permissions — try sudo user first, fall back to web user
    if chown -R "$owner:$web_group" -- "$webroot" 2>/dev/null; then
        success "Set owner to $owner:$web_group"
    else
        warn "Could not set owner to $owner (using $web_user)"
        chown -R "$web_group:$web_group" -- "$webroot" 2>/dev/null || true
    fi
}

# Add sample phpinfo file
add_phpinfo() {
    local webroot="$1"
    local phpinfo_file="$webroot/phpinfo.php"

    if [[ $SKIP_INDEX -eq 1 ]]; then
        verbose "Skipping phpinfo.php (--no-index flag set)"
        return 0
    fi

    verbose "Adding phpinfo.php to: $webroot"

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would create: $phpinfo_file"
        return 0
    fi

    if [[ -e "$phpinfo_file" ]]; then
        verbose "phpinfo.php already exists"
        return 0
    fi

    cat > "$phpinfo_file" <<'PHP'
<?php
// Temporary phpinfo for verification
// Remove this file in production
phpinfo();
PHP

    success "Added phpinfo.php"
}

# Add sample index.html file
add_index_html() {
    local webroot="$1"
    local domain="$2"
    local index_file="$webroot/index.html"

    if [[ $SKIP_INDEX -eq 1 ]]; then
        verbose "Skipping index.html (--no-index flag set)"
        return 0
    fi

    verbose "Adding index.html to: $webroot"

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would create: $index_file"
        return 0
    fi

    if [[ -e "$index_file" ]]; then
        verbose "index.html already exists"
        return 0
    fi

    cat > "$index_file" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$domain</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: #333; }
        .container { background: white; border-radius: 16px; padding: 48px; max-width: 520px; width: 90%; box-shadow: 0 20px 60px rgba(0,0,0,0.3); text-align: center; }
        h1 { font-size: 28px; margin-bottom: 8px; color: #333; }
        .domain { color: #667eea; font-weight: 600; }
        .success-badge { display: inline-block; background: #28a745; color: white; padding: 4px 16px; border-radius: 20px; font-size: 14px; margin: 16px 0; }
        p { color: #666; line-height: 1.6; margin: 12px 0; }
        .links { margin-top: 24px; }
        .links a { display: inline-block; padding: 10px 24px; background: #667eea; color: white; text-decoration: none; border-radius: 8px; font-weight: 500; transition: background 0.2s; }
        .links a:hover { background: #5a67d8; }
        .meta { margin-top: 24px; font-size: 12px; color: #999; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Virtual Host Active</h1>
        <p>Your virtual host for <span class="domain">$domain</span> is now running.</p>
        <div class="success-badge">✓ Setup Complete</div>
        <div class="links">
            <a href="phpinfo.php">View PHP Info</a>
        </div>
        <div class="meta">Powered by virtualhost-automation v3.0.0</div>
    </div>
</body>
</html>
HTML

    success "Added index.html"
}

# ============================================================================
# HOSTS FILE FUNCTIONS
# ============================================================================

# Add entry to /etc/hosts
add_hosts_entry() {
    local domain="$1"
    local ip="127.0.0.1"
    local hosts_file="/etc/hosts"

    if [[ $SKIP_HOSTS -eq 1 ]]; then
        verbose "Skipping /etc/hosts modification (--no-hosts flag set)"
        return 0
    fi

    verbose "Adding entry to /etc/hosts: $ip $domain"

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would add to /etc/hosts: $ip $domain"
        return 0
    fi

    if grep -Eq "^[[:space:]]*$ip[[:space:]]+$domain[[:space:]]*$" "$hosts_file"; then
        info "Entry already exists in /etc/hosts"
    else
        echo -e "$ip\t$domain" >> "$hosts_file"
        success "Added to /etc/hosts: $ip $domain"

        # Also add www. alias if --with-www was used
        if [[ $WITH_WWW -eq 1 ]]; then
            if ! grep -Eq "^[[:space:]]*$ip[[:space:]]+www\.$domain[[:space:]]*$" "$hosts_file"; then
                echo -e "$ip\twww.$domain" >> "$hosts_file"
                success "Added to /etc/hosts: $ip www.$domain"
            fi
        fi
    fi
}

# Remove entry from /etc/hosts
remove_hosts_entry() {
    local domain="$1"
    local hosts_file="/etc/hosts"

    if [[ $SKIP_HOSTS -eq 1 ]]; then
        verbose "Skipping /etc/hosts modification (--no-hosts flag set)"
        return 0
    fi

    verbose "Removing entry from /etc/hosts: $domain"

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would remove from /etc/hosts: $domain"
        return 0
    fi

    if sed -i.bak -E "/(^|\s)${domain}(\s|$)/d" "$hosts_file" 2>/dev/null; then
        success "Removed from /etc/hosts: $domain"
        success "Backup saved to: ${hosts_file}.bak"
    else
        warn "Could not remove from /etc/hosts"
    fi
}

# ============================================================================
# SSL FUNCTIONS
# ============================================================================

# Generate a self-signed SSL certificate
generate_self_signed_ssl() {
    local domain="$1"
    local ssl_dir="/etc/ssl/$domain"
    local key_file="$ssl_dir/privkey.pem"
    local cert_file="$ssl_dir/fullchain.pem"

    verbose "Generating self-signed SSL certificate for: $domain"

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would generate self-signed cert in: $ssl_dir"
        return 0
    fi

    mkdir -p "$ssl_dir"

    # Only generate if cert doesn't already exist
    if [[ -f "$cert_file" ]] && [[ -f "$key_file" ]]; then
        verbose "SSL certificate already exists for: $domain"
        return 0
    fi

    if command -v openssl &>/dev/null; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$key_file" \
            -out "$cert_file" \
            -subj "/CN=$domain/O=VirtualHost Automation/C=XX" \
            2>/dev/null

        if [[ -f "$cert_file" ]]; then
            chmod 600 "$key_file"
            chmod 644 "$cert_file"
            success "Generated self-signed SSL certificate: $cert_file"
        else
            err "Failed to generate SSL certificate"
            return 1
        fi
    else
        err "openssl is not installed. Cannot generate self-signed certificate."
        return 1
    fi
}

# Obtain Let's Encrypt certificate via certbot
obtain_letsencrypt_cert() {
    local domain="$1"
    local webroot="$2"

    if ! command -v certbot &>/dev/null; then
        err "certbot is not installed. Install it with: sudo apt install certbot"
        return 1
    fi

    verbose "Obtaining Let's Encrypt certificate for: $domain"

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would run: certbot certonly --webroot -w $webroot -d $domain"
        return 0
    fi

    if certbot certonly --webroot -w "$webroot" -d "$domain" --non-interactive --agree-tos --email "${EMAIL:-webmaster@localhost}" 2>/dev/null; then
        success "Obtained Let's Encrypt certificate for: $domain"
    else
        warn "Let's Encrypt certificate acquisition failed (may need port 80 accessible)"
        return 1
    fi
}

# ============================================================================
# TRAP / CLEANUP
# ============================================================================

# Cleanup function for rollback on failure
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]] && [[ $DRY_RUN -eq 0 ]]; then
        warn "Script failed with exit code $exit_code"
        warn "Check logs for details"
    fi
}

trap cleanup EXIT