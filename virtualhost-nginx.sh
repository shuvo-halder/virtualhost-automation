#!/usr/bin/env bash
# virtualhost-nginx.sh — Production-Grade Nginx VirtualHost Manager
# Version: 2.0.0
# Author: Shuvo Halder
# License: MIT
#
# A clean, safe, and feature-rich script to create/delete Nginx virtual hosts.
# Includes help, logging, validation, dry-run mode, and more.

set -o errexit
set -o nounset
set -o pipefail
IFS=$'\n\t'

# ============================================================================
# CONFIGURATION
# ============================================================================
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Nginx paths
readonly SITES_AVAILABLE="/etc/nginx/sites-available"
readonly SITES_ENABLED="/etc/nginx/sites-enabled"
readonly DEFAULT_WEBROOT="/var/www"
readonly WEB_USER="www-data"
readonly WEB_GROUP="www-data"

# PHP-FPM configuration (customize as needed)
PHP_FPM_SOCKET="${PHP_FPM_SOCKET:-127.0.0.1:9000}"
# Alternatives: unix:/run/php/php8.1-fpm.sock, unix:/var/run/php-fpm.sock

# Logging
readonly LOG_DIR="${LOG_DIR:-/var/log/virtualhost}"
readonly LOG_FILE="$LOG_DIR/virtualhost-nginx-$(date +%Y%m%d).log"

# Feature flags
DRY_RUN=0
VERBOSE=0
SKIP_RELOAD=0

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Print error message to stderr and log file
err() {
    echo "ERROR: $*" >&2
    log "ERROR: $*"
}

# Print info message to stdout and log file
info() {
    echo "INFO: $*"
    log "INFO: $*"
}

# Print warning message to stderr and log file
warn() {
    echo "WARNING: $*" >&2
    log "WARNING: $*"
}

# Print success message
success() {
    echo "✓ $*"
    log "SUCCESS: $*"
}

# Verbose output (only if -v flag is set)
verbose() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo "  → $*"
    fi
    log "VERBOSE: $*"
}

# Log to file
log() {
    if [[ -d "$LOG_DIR" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    fi
}

# Print usage/help information
usage() {
    cat <<EOF
Usage: sudo $SCRIPT_NAME [OPTIONS] COMMAND DOMAIN [ROOTDIR]

DESCRIPTION:
  Production-grade Nginx virtual host creator and remover. Safely manages
  Nginx server blocks, DNS entries, and directories with PHP-FPM support.

COMMANDS:
  create DOMAIN [ROOTDIR]   Create a new virtual host
  delete DOMAIN             Delete an existing virtual host
  list                      List all existing virtual hosts
  help                      Show this help message
  version                   Show version information

OPTIONS:
  -h, --help               Show this help message
  -v, --verbose            Enable verbose output
  -d, --dry-run            Show what would be done without making changes
  -s, --skip-reload        Skip Nginx reload after changes
  -V, --version            Show version information
  -p, --php-socket SOCKET  Specify PHP-FPM socket (default: 127.0.0.1:9000)

EXAMPLES:
  # Create a new virtual host
  sudo $SCRIPT_NAME create example.dev

  # Create with custom directory
  sudo $SCRIPT_NAME create example.dev /var/www/mysite

  # Delete a virtual host
  sudo $SCRIPT_NAME delete example.dev

  # Dry-run mode (show what would happen)
  sudo $SCRIPT_NAME -d create example.dev

  # Use Unix socket for PHP-FPM
  sudo $SCRIPT_NAME -p unix:/run/php/php8.1-fpm.sock create example.dev

  # List all virtual hosts
  sudo $SCRIPT_NAME list

NOTES:
  - Must be run with sudo (root privileges required)
  - Domain names must contain only alphanumeric characters, dots, and hyphens
  - Logs are stored in: $LOG_DIR/
  - /etc/hosts entries use 127.0.0.1
  - Default PHP-FPM socket: $PHP_FPM_SOCKET

EOF
    exit "${1:-0}"
}

# Show version information
show_version() {
    cat <<EOF
$SCRIPT_NAME version $SCRIPT_VERSION

A production-grade Nginx VirtualHost manager.
License: MIT
Homepage: https://github.com/shuvo-halder/virtualhost-automation

EOF
    exit 0
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

# Ensure Nginx is installed
check_nginx() {
    if ! command -v nginx &>/dev/null; then
        err "Nginx is not installed"
        exit 1
    fi
    verbose "Nginx is installed"
}

# Validate PHP-FPM socket
validate_php_socket() {
    local socket="$1"
    verbose "PHP-FPM socket: $socket"
    
    if [[ "$socket" =~ ^unix: ]]; then
        local socket_path="${socket#unix:}"
        verbose "Unix socket path: $socket_path"
    elif [[ "$socket" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
        verbose "TCP socket: $socket"
    else
        warn "PHP-FPM socket format may be incorrect: $socket"
    fi
}

# ============================================================================
# NGINX CONFIGURATION FUNCTIONS
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
    local webroot
    
    if [[ -n "$user_root" ]]; then
        if [[ "$user_root" == /* ]]; then
            webroot="$user_root"
        else
            webroot="$DEFAULT_WEBROOT/$user_root"
        fi
    else
        local safe_name="${domain//./}"
        webroot="$DEFAULT_WEBROOT/$safe_name"
    fi
    
    echo "$webroot"
}

# Create Nginx server block configuration
create_nginx_conf() {
    local domain="$1"
    local webroot="$2"
    local php_socket="$3"
    local conf_file="$SITES_AVAILABLE/$domain"
    
    if [[ -e "$conf_file" ]]; then
        err "Configuration already exists: $conf_file"
        return 1
    fi
    
    verbose "Creating Nginx configuration: $conf_file"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would create config at: $conf_file"
        return 0
    fi
    
    cat > "$conf_file" <<EOF
server {
    listen 80;
    server_name $domain;
    root $webroot;

    index index.php index.html index.htm;

    # Security: Deny access to hidden files
    location ~ /\.|^\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Serve static files directly with caching
    location ~* \\.
(jpg|jpeg|gif|css|png|js|ico|html|svg|woff|woff2|ttf|eot)$ {
        access_log off;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Try files, fallback to index.php
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # PHP-FPM handling
    location ~ \\.php$ {
        include fastcgi_params;
        fastcgi_split_path_info ^(.+\\.php)(/.+)$;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_pass $php_socket;
        fastcgi_index index.php;
        include snippets/fastcgi-php.conf;
    }

    # Logging
    error_log /var/log/nginx/${domain}_error.log warn;
    access_log /var/log/nginx/${domain}_access.log combined;
}
EOF

    success "Created Nginx configuration: $conf_file"
    return 0
}

# Remove Nginx configuration
remove_conf() {
    local domain="$1"
    local conf_file="$SITES_AVAILABLE/$domain"
    
    if [[ ! -e "$conf_file" ]]; then
        warn "Configuration not found: $conf_file"
        return 0
    fi
    
    verbose "Removing Nginx configuration: $conf_file"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would remove config: $conf_file"
        return 0
    fi
    
    rm -f "$conf_file"
    success "Removed Nginx configuration: $conf_file"
    return 0
}

# Enable Nginx site (create symlink)
enable_site() {
    local domain="$1"
    local conf_path="$SITES_AVAILABLE/$domain"
    local link_path="$SITES_ENABLED/$domain"
    
    if [[ -L "$link_path" || -e "$link_path" ]]; then
        verbose "Site already enabled: $link_path"
        return 0
    fi
    
    verbose "Enabling site: $domain"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would enable site: $domain"
        return 0
    fi
    
    if ln -s "$conf_path" "$link_path"; then
        success "Enabled site: $domain"
    else
        err "Failed to enable site: $domain"
        return 1
    fi
}

# Disable Nginx site (remove symlink)
disable_site() {
    local domain="$1"
    local link_path="$SITES_ENABLED/$domain"
    
    verbose "Disabling site: $domain"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would disable site: $domain"
        return 0
    fi
    
    if [[ -L "$link_path" || -e "$link_path" ]]; then
        rm -f "$link_path"
        success "Disabled site: $domain"
    else
        verbose "Site was not enabled: $domain"
    fi
}

# Test and reload Nginx safely
reload_nginx() {
    if [[ $SKIP_RELOAD -eq 1 ]]; then
        warn "Skipping Nginx reload (--skip-reload flag set)"
        return 0
    fi
    
    verbose "Testing Nginx configuration"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would test and reload Nginx"
        return 0
    fi
    
    if ! nginx -t >/dev/null 2>&1; then
        err "Nginx configuration test failed"
        err "Please check your configuration and try again"
        nginx -t
        return 1
    fi
    
    if systemctl reload nginx >/dev/null 2>&1; then
        success "Nginx configuration reloaded"
    else
        warn "Reload failed, attempting restart..."
        if systemctl restart nginx >/dev/null 2>&1; then
            success "Nginx restarted"
        else
            err "Failed to reload Nginx"
            return 1
        fi
    fi
}

# ============================================================================
# HOSTS FILE FUNCTIONS
# ============================================================================

# Add entry to /etc/hosts
add_hosts_entry() {
    local domain="$1"
    local ip="127.0.0.1"
    local hosts_file="/etc/hosts"
    
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
    fi
}

# Remove entry from /etc/hosts
remove_hosts_entry() {
    local domain="$1"
    local hosts_file="/etc/hosts"
    
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
# DIRECTORY FUNCTIONS
# ============================================================================

# Create web root directory and set permissions
create_webroot() {
    local webroot="$1"
    local owner="$2"
    
    verbose "Creating web root: $webroot"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would create directory: $webroot"
        info "[DRY-RUN] Would set owner: $owner"
        return 0
    fi
    
    if [[ -d "$webroot" ]]; then
        info "Directory already exists: $webroot"
    else
        mkdir -p -- "$webroot"
        chmod 755 -- "$webroot"
        success "Created directory: $webroot"
    fi
    
    # Set permissions
    if chown -R "$owner:$WEB_GROUP" -- "$webroot" 2>/dev/null; then
        success "Set owner to $owner:$WEB_GROUP"
    else
        warn "Could not set owner to $owner (using $WEB_USER)"
        chown -R "$WEB_USER:$WEB_GROUP" -- "$webroot" || true
    fi
}

# Add sample phpinfo file
add_phpinfo() {
    local webroot="$1"
    local phpinfo_file="$webroot/phpinfo.php"
    
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

# ============================================================================
# LIST FUNCTION
# ============================================================================

# List all existing virtual hosts
list_hosts() {
    info "Listing enabled Nginx virtual hosts:"
    echo ""
    
    if [[ ! -d "$SITES_ENABLED" ]]; then
        err "Sites-enabled directory not found: $SITES_ENABLED"
        return 1
    fi
    
    local count=0
    for site in "$SITES_ENABLED"/*; do
        if [[ -L "$site" ]]; then
            local domain_name=$(basename "$site")
            local target=$(readlink "$site")
            echo "  ✓ $domain_name -> $target"
            ((count++))
        fi
    done
    
    if [[ $count -eq 0 ]]; then
        echo "  (No virtual hosts found)"
    else
        echo ""
        success "Total: $count virtual host(s)"
    fi
}

# ============================================================================
# CREATE COMMAND
# ============================================================================

cmd_create() {
    local domain="$1"
    local custom_root="${2:-}"
    
    # Validation
    validate_domain "$domain" || return 1
    validate_php_socket "$PHP_FPM_SOCKET"
    
    local owner=$(get_owner)
    local webroot=$(get_webroot "$custom_root" "$domain")
    
    info "Creating virtual host for: $domain"
    verbose "Web root: $webroot"
    verbose "Owner: $owner"
    verbose "PHP-FPM socket: $PHP_FPM_SOCKET"
    
    # Create operations
    create_webroot "$webroot" "$owner"
    add_phpinfo "$webroot"
    create_nginx_conf "$domain" "$webroot" "$PHP_FPM_SOCKET" || return 1
    enable_site "$domain" || return 1
    add_hosts_entry "$domain"
    reload_nginx || return 1
    
    echo ""
    if [[ $DRY_RUN -eq 0 ]]; then
        success "Virtual host created successfully!"
        echo ""
        echo "  Domain: $domain"
        echo "  Root:   $webroot"
        echo "  Visit:  http://$domain"
    fi
}

# ============================================================================
# DELETE COMMAND
# ============================================================================

cmd_delete() {
    local domain="$1"
    
    # Validation
    validate_domain "$domain" || return 1
    
    local conf_file="$SITES_AVAILABLE/$domain"
    
    if [[ ! -e "$conf_file" ]] && [[ $DRY_RUN -eq 0 ]]; then
        err "Virtual host does not exist: $domain"
        return 1
    fi
    
    info "Deleting virtual host: $domain"
    
    # Delete operations
    disable_site "$domain"
    remove_conf "$domain" || return 1
    remove_hosts_entry "$domain"
    reload_nginx || return 1
    
    # Ask about removing webroot
    if [[ $DRY_RUN -eq 0 ]]; then
        local webroot
        if [[ -e "$SITES_AVAILABLE/$domain" ]]; then
            webroot=$(grep "root " "$SITES_AVAILABLE/$domain" | grep -v "# " | head -1 | awk '{print $2}' | sed 's/;$//')
        fi
        
        if [[ -n "$webroot" && -d "$webroot" ]]; then
            echo ""
            read -rp "Delete web root directory: $webroot? [y/N]: " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                rm -rf -- "$webroot"
                success "Removed directory: $webroot"
            else
                info "Kept web root directory: $webroot"
            fi
        fi
    fi
    
    echo ""
    if [[ $DRY_RUN -eq 0 ]]; then
        success "Virtual host deleted successfully!"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # Initialize logging
    mkdir -p "$LOG_DIR"
    log "=========================================="
    log "Script started by: ${SUDO_USER:-$(whoami)}"
    log "Arguments: $*"
    
    # Parse command line arguments
    local command=""
    local domain=""
    local rootdir=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage 0
                ;;
            -V|--version)
                show_version
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=1
                info "DRY-RUN MODE: No changes will be made"
                shift
                ;;
            -s|--skip-reload)
                SKIP_RELOAD=1
                shift
                ;;
            -p|--php-socket)
                PHP_FPM_SOCKET="$2"
                shift 2
                ;;
            create|delete|list|help|version)
                command="$1"
                shift
                break
                ;;
            *)
                err "Unknown option: $1"
                usage 1
                ;;
        esac
    done
    
    # Get remaining arguments
    domain="${1:-}"
    rootdir="${2:-}"
    
    # Check root privileges
    check_root
    
    # Check Nginx installation
    check_nginx
    
    # Execute command
    case "$command" in
        create)
            [[ -z "$domain" ]] && { err "Domain required for create"; usage 1; }
            cmd_create "$domain" "$rootdir"
            ;;
        delete)
            [[ -z "$domain" ]] && { err "Domain required for delete"; usage 1; }
            cmd_delete "$domain"
            ;;
        list)
            list_hosts
            ;;
        help)
            usage 0
            ;;
        version)
            show_version
            ;;
        *)
            if [[ -z "$command" ]]; then
                err "No command specified"
            else
                err "Unknown command: $command"
            fi
            usage 1
            ;;
    esac
    
    log "Script completed successfully"
}

# Run main function
main "$@"
