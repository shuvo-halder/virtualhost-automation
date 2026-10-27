#!/usr/bin/env bash
# virtualhost-lib.sh — Shared Library for VirtualHost Manager v4.0.0
# Version: 4.0.0
# Author: Shuvo Halder
# License: MIT
#
# Shared functions used by both Apache and Nginx virtual host managers.

# ============================================================================
# CONFIGURATION DEFAULTS
# ============================================================================
readonly LIB_VERSION="4.0.0"

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
PROXY_PASS=${PROXY_PASS:-""}
PROXY_WEBSOCKET=${PROXY_WEBSOCKET:-0}
ALIASES=${ALIASES:-""}
BACKUP_DIR=${BACKUP_DIR:-/var/backups/virtualhost}

# Color codes
# Color variables — populated by init_colors() after argument parsing.
# Not readonly so init_colors() can assign them after --no-color is parsed.
C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_BOLD='' C_RESET=''

# Initialize color codes.
# Must be called in each script's main() AFTER the argument-parsing loop,
# so that --no-color is respected before any output is emitted.
init_colors() {
    if [[ ${NO_COLOR:-0} -eq 0 ]] && [[ -t 1 ]]; then
        C_RED='\033[0;31m'
        C_GREEN='\033[0;32m'
        C_YELLOW='\033[1;33m'
        C_BLUE='\033[0;34m'
        C_CYAN='\033[0;36m'
        C_BOLD='\033[1m'
        C_RESET='\033[0m'
    else
        C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_BOLD='' C_RESET=''
    fi
}

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

# Validate email address format
validate_email() {
    local email="$1"

    if [[ -z "$email" ]]; then
        err "Email cannot be empty"
        return 1
    fi

    # RFC 5322 simplified: local@domain.tld
    if ! [[ "$email" =~ ^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$ ]]; then
        err "Invalid email address: '$email'"
        return 1
    fi

    verbose "Email validation passed: $email"
    return 0
}

# Normalize proxy pass value: if it's just a number (port), convert to full URL
# Also accepts full URLs like http://localhost:3000
normalize_proxy_pass() {
    local proxy_input="$1"

    if [[ -z "$proxy_input" ]]; then
        echo ""
        return 1
    fi

    # If input is just digits (port number), convert to full URL
    if [[ "$proxy_input" =~ ^[0-9]+$ ]]; then
        echo "http://127.0.0.1:$proxy_input"
        return 0
    fi

    # If already a full URL, return as-is
    if [[ "$proxy_input" =~ ^https?:// ]]; then
        echo "$proxy_input"
        return 0
    fi

    # If contains host:port pattern (e.g., localhost:3000, 0.0.0.0:8080)
    if [[ "$proxy_input" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
        echo "http://$proxy_input"
        return 0
    fi

    # Unrecognized format — return as-is; validate_proxy_pass() will catch errors
    echo "$proxy_input"
    return 0
}

# Validate proxy pass URL format
validate_proxy_pass() {
    local proxy_url="$1"

    if [[ -z "$proxy_url" ]]; then
        return 1
    fi

    # Must start with http:// or https://
    if ! [[ "$proxy_url" =~ ^https?:// ]]; then
        err "Proxy pass URL must start with http:// or https://"
        return 1
    fi

    # Must contain host:port or just host
    if ! [[ "$proxy_url" =~ ^https?://[^/]+ ]]; then
        err "Invalid proxy pass URL format: $proxy_url"
        return 1
    fi

    verbose "Proxy pass validation passed: $proxy_url"
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
        warn "Could not set owner to $owner (using $web_group)"
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
        <div class="meta">Powered by virtualhost-automation v4.0.0</div>
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

    if ! grep -Eq "^[[:space:]]*$ip[[:space:]]+$domain[[:space:]]*$" "$hosts_file"; then
        echo -e "$ip\t$domain" >> "$hosts_file"
        success "Added to /etc/hosts: $ip $domain"
    else
        info "Entry already exists in /etc/hosts: $domain"
    fi

    # Add www. alias independently — idempotent across re-runs
    if [[ $WITH_WWW -eq 1 ]]; then
        if ! grep -Eq "^[[:space:]]*$ip[[:space:]]+www\.$domain[[:space:]]*$" "$hosts_file"; then
            echo -e "$ip\twww.$domain" >> "$hosts_file"
            success "Added to /etc/hosts: $ip www.$domain"
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

    local escaped_domain
    escaped_domain=$(printf '%s' "$domain" | sed 's/[.[*^$\]/\\&/g')
    if sed -i.bak -E "/(^|[[:space:]])${escaped_domain}([[:space:]]|$)/d" "$hosts_file" 2>/dev/null; then
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
# PROXY PASS FUNCTIONS
# ============================================================================

# Validate that the proxy target backend is reachable (basic check)
check_proxy_backend() {
    local proxy_url="$1"

    if [[ $DRY_RUN -eq 1 ]]; then
        return 0
    fi

    # Determine correct default port from URL scheme
    local scheme
    scheme=$(echo "$proxy_url" | grep -oE '^https?')
    local default_port=80
    [[ "$scheme" == "https" ]] && default_port=443

    # Extract host and port from URL
    local host_port
    host_port=$(echo "$proxy_url" | sed -E 's|^https?://||' | sed -E 's|/.*$||')
    local host="${host_port%:*}"
    local port="${host_port##*:}"
    if [[ "$host" == "$port" ]]; then
        port=$default_port
    fi

    verbose "Checking proxy backend: $host:$port"

    if command -v nc &>/dev/null; then
        if nc -z -w 2 "$host" "$port" 2>/dev/null; then
            verbose "Backend is reachable: $host:$port"
        else
            warn "Backend $host:$port may not be reachable. Ensure your application is running."
        fi
    elif command -v curl &>/dev/null; then
        if curl -s -o /dev/null --connect-timeout 2 "$proxy_url" 2>/dev/null; then
            verbose "Backend is reachable: $host:$port"
        else
            warn "Backend $host:$port may not be reachable. Ensure your application is running."
        fi
    fi
}

# ============================================================================
# BACKUP / RESTORE / SSL-RENEW FUNCTIONS
# ============================================================================

# Create a tar.gz backup of a virtual host's config, webroot, and SSL certs
# Usage: perform_backup DOMAIN CONF_FILE WEBROOT OUTPUT_FILE
perform_backup() {
    local domain="$1"
    local conf_file="$2"
    local webroot="${3:-}"
    local output="$4"

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would backup $domain to $output"
        return 0
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    local backup_root="$tmp_dir/$domain"
    mkdir -p "$backup_root/config" "$backup_root/ssl"

    # Copy config file
    if [[ -f "$conf_file" ]]; then
        cp "$conf_file" "$backup_root/config/"
        verbose "Backed up config: $conf_file"
    fi

    # Copy webroot
    if [[ -n "$webroot" && -d "$webroot" ]]; then
        cp -a "$webroot" "$backup_root/webroot"
        verbose "Backed up webroot: $webroot"
    fi

    # Copy SSL certs (Let's Encrypt or self-signed)
    local le_dir="/etc/letsencrypt/live/$domain"
    local ss_dir="/etc/ssl/$domain"
    if [[ -d "$le_dir" ]]; then
        cp -a "$le_dir" "$backup_root/ssl/letsencrypt"
        verbose "Backed up LE certs: $le_dir"
    elif [[ -d "$ss_dir" ]]; then
        cp -a "$ss_dir" "$backup_root/ssl/selfsigned"
        verbose "Backed up self-signed certs: $ss_dir"
    fi

    # Create archive
    mkdir -p "$(dirname "$output")"
    tar -czf "$output" -C "$tmp_dir" "$domain"
    rm -rf "$tmp_dir"

    if [[ -f "$output" ]]; then
        success "Backup created: $output"
    else
        err "Backup failed: $output"
        return 1
    fi
}

# Restore a virtual host from a tar.gz backup
# Usage: perform_restore BACKUP_FILE
perform_restore() {
    local backup_file="$1"

    if [[ ! -f "$backup_file" ]]; then
        err "Backup file not found: $backup_file"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would restore from: $backup_file"
        return 0
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    tar -xzf "$backup_file" -C "$tmp_dir"

    # Find restored domain directory
    local domain_dir
    domain_dir=$(find "$tmp_dir" -maxdepth 1 -mindepth 1 -type d | head -1)
    if [[ -z "$domain_dir" ]]; then
        err "Could not find domain directory in backup"
        rm -rf "$tmp_dir"
        return 1
    fi

    local domain
    domain=$(basename "$domain_dir")

    # Restore config
    if [[ -d "$domain_dir/config" ]]; then
        for f in "$domain_dir/config/"*; do
            [[ -f "$f" ]] && cp "$f" /etc/apache2/sites-available/ 2>/dev/null ||                              cp "$f" /etc/nginx/sites-available/ 2>/dev/null || true
        done
        verbose "Restored config for: $domain"
    fi

    # Restore webroot
    if [[ -d "$domain_dir/webroot" ]]; then
        local target_webroot
        target_webroot=$(basename "$domain_dir/webroot")
        cp -a "$domain_dir/webroot" "/var/www/$target_webroot"
        verbose "Restored webroot to: /var/www/$target_webroot"
    fi

    # Restore SSL certs
    if [[ -d "$domain_dir/ssl/letsencrypt" ]]; then
        mkdir -p "/etc/letsencrypt/live"
        cp -a "$domain_dir/ssl/letsencrypt" "/etc/letsencrypt/live/$domain"
        verbose "Restored LE certs for: $domain"
    elif [[ -d "$domain_dir/ssl/selfsigned" ]]; then
        mkdir -p "/etc/ssl"
        cp -a "$domain_dir/ssl/selfsigned" "/etc/ssl/$domain"
        verbose "Restored self-signed certs for: $domain"
    fi

    rm -rf "$tmp_dir"
    success "Restored virtual host: $domain from $backup_file"
}

# Renew Let's Encrypt certificate for a domain (or all domains)
# Usage: perform_ssl_renew [DOMAIN]
perform_ssl_renew() {
    local domain="${1:-}"

    if ! command -v certbot &>/dev/null; then
        err "certbot is not installed. Install it with: sudo apt install certbot"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        if [[ -n "$domain" ]]; then
            info "[DRY-RUN] Would renew cert for: $domain"
        else
            info "[DRY-RUN] Would renew all certificates"
        fi
        return 0
    fi

    if [[ -n "$domain" ]]; then
        verbose "Renewing certificate for: $domain"
        if certbot renew --cert-name "$domain" --non-interactive 2>/dev/null; then
            success "Certificate renewed for: $domain"
        else
            err "Certificate renewal failed for: $domain"
            return 1
        fi
    else
        verbose "Renewing all certificates"
        if certbot renew --non-interactive 2>/dev/null; then
            success "All certificates renewed"
        else
            err "Certificate renewal failed"
            return 1
        fi
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