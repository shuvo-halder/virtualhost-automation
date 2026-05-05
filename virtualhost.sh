#!/usr/bin/env bash
# virtualhost.sh — Production-Grade Apache VirtualHost Manager
# Version: 2.0.0
# Author: Shuvo Halder
# License: MIT
#
# A clean, safe, and feature-rich script to create/delete Apache virtual hosts.
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

# Apache paths
readonly SITES_AVAILABLE="/etc/apache2/sites-available"
readonly SITES_ENABLED="/etc/apache2/sites-enabled"
readonly DEFAULT_WEBROOT="/var/www"
readonly APACHE_MODS_ENABLED="/etc/apache2/mods-enabled"

# Email for Apache configuration
EMAIL="${EMAIL:-webmaster@localhost}"

# Logging
readonly LOG_DIR="${LOG_DIR:-/var/log/virtualhost}"
readonly LOG_FILE="$LOG_DIR/virtualhost-apache-$(date +%Y%m%d).log"

# Feature flags
DRY_RUN=0
VERBOSE=0
SKIP_RELOAD=0
ENABLE_SSL=0

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
  Production-grade Apache virtual host creator and remover. Safely manages
  Apache server blocks, DNS entries, and directories with mod_rewrite support.

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
  -s, --skip-reload        Skip Apache reload after changes
  -V, --version            Show version information
  -e, --email EMAIL        Set admin email (default: webmaster@localhost)

EXAMPLES:
  # Create a new virtual host
  sudo $SCRIPT_NAME create example.dev

  # Create with custom directory
  sudo $SCRIPT_NAME create example.dev /var/www/mysite

  # Delete a virtual host
  sudo $SCRIPT_NAME delete example.dev

  # Dry-run mode (show what would happen)
  sudo $SCRIPT_NAME -d create example.dev

  # Set custom admin email
  sudo $SCRIPT_NAME -e admin@example.com create example.dev

  # List all virtual hosts
  sudo $SCRIPT_NAME list

NOTES:
  - Must be run with sudo (root privileges required)
  - Domain names must contain only alphanumeric characters, dots, and hyphens
  - Logs are stored in: $LOG_DIR/
  - /etc/hosts entries use 127.0.0.1
  - Requires Apache2 with mod_rewrite enabled
  - Default admin email: $EMAIL

EOF
    exit "${1:-0}"
}

# Show version information
show_version() {
    cat <<EOF
$SCRIPT_NAME version $SCRIPT_VERSION

A production-grade Apache VirtualHost manager.
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

# Ensure Apache is installed
check_apache() {
    if ! command -v apache2ctl &>/dev/null; then
        err "Apache2 is not installed"
        exit 1
    fi
    verbose "Apache2 is installed"
}

# Check if required Apache modules are enabled
check_apache_mods() {
    local required_mods=("rewrite.load" "ssl.load" "php.*\.load")
    verbose "Checking Apache modules..."
    
    if [[ ! -d "$APACHE_MODS_ENABLED" ]]; then
        warn "Could not verify Apache modules"
        return 0
    fi
    
    if [[ ! -e "$APACHE_MODS_ENABLED/rewrite.load" ]]; then
        warn "mod_rewrite may not be enabled. Run: sudo a2enmod rewrite"
    fi
}

# ============================================================================
# APACHE CONFIGURATION FUNCTIONS
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

# Create Apache VirtualHost configuration
create_apache_conf() {
    local domain="$1"
    local webroot="$2"
    local email="$3"
    local conf_file="$SITES_AVAILABLE/${domain}.conf"
    
    if [[ -e "$conf_file" ]]; then
        err "Configuration already exists: $conf_file"
        return 1
    fi
    
    verbose "Creating Apache configuration: $conf_file"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would create config at: $conf_file"
        return 0
    fi
    
    cat > "$conf_file" <<EOF
<VirtualHost *:80>
    ServerAdmin $email
    ServerName $domain
    ServerAlias www.$domain

    DocumentRoot $webroot

    # Enable mod_rewrite
    <Directory $webroot>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted

        # Common framework rewrites
        RewriteEngine On
        RewriteBase /
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule ^ index.php [L]
    </Directory>

    # Security: Deny access to hidden files
    <FilesMatch "^\\.">
        Require all denied
    </FilesMatch>

    # Logging
    ErrorLog \${APACHE_LOG_DIR}/${domain}_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_access.log combined

    # Performance: Enable gzip compression
    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/plain
        AddOutputFilterByType DEFLATE text/html
        AddOutputFilterByType DEFLATE text/xml
        AddOutputFilterByType DEFLATE text/css
        AddOutputFilterByType DEFLATE application/xml
        AddOutputFilterByType DEFLATE application/xhtml+xml
        AddOutputFilterByType DEFLATE application/rss+xml
        AddOutputFilterByType DEFLATE application/javascript
        AddOutputFilterByType DEFLATE application/x-javascript
    </IfModule>
</VirtualHost>
EOF

    success "Created Apache configuration: $conf_file"
    return 0
}

# Remove Apache configuration
remove_conf() {
    local domain="$1"
    local conf_file="$SITES_AVAILABLE/${domain}.conf"
    
    if [[ ! -e "$conf_file" ]]; then
        warn "Configuration not found: $conf_file"
        return 0
    fi
    
    verbose "Removing Apache configuration: $conf_file"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would remove config: $conf_file"
        return 0
    fi
    
    rm -f "$conf_file"
    success "Removed Apache configuration: $conf_file"
    return 0
}

# Enable Apache site
enable_site() {
    local domain="$1"
    
    verbose "Enabling site: $domain"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would enable site: $domain"
        return 0
    fi
    
    if a2ensite "${domain}.conf" >/dev/null 2>&1; then
        success "Enabled site: $domain"
    else
        err "Failed to enable site: $domain"
        return 1
    fi
}

# Disable Apache site
disable_site() {
    local domain="$1"
    
    verbose "Disabling site: $domain"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would disable site: $domain"
        return 0
    fi
    
    if a2dissite "${domain}.conf" >/dev/null 2>&1; then
        success "Disabled site: $domain"
    else
        verbose "Site was not enabled: $domain"
    fi
}

# Test and reload Apache safely
reload_apache() {
    if [[ $SKIP_RELOAD -eq 1 ]]; then
        warn "Skipping Apache reload (--skip-reload flag set)"
        return 0
    fi
    
    verbose "Testing Apache configuration"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would test and reload Apache"
        return 0
    fi
    
    if ! apache2ctl configtest >/dev/null 2>&1; then
        err "Apache configuration test failed"
        err "Please check your configuration and try again"
        apache2ctl configtest
        return 1
    fi
    
    if systemctl reload apache2 >/dev/null 2>&1; then
        success "Apache configuration reloaded"
    else
        warn "Reload failed, attempting restart..."
        if systemctl restart apache2 >/dev/null 2>&1; then
            success "Apache restarted"
        else
            err "Failed to reload Apache"
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
    if chown -R "$owner:$owner" -- "$webroot" 2>/dev/null; then
        success "Set owner to $owner"
    else
        warn "Could not set owner to $owner"
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

# Add sample index.html file
add_index_html() {
    local webroot="$1"
    local domain="$2"
    local index_file="$webroot/index.html"
    
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
<html>
<head>
    <title>$domain</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 600px; margin: 0 auto; }
        h1 { color: #333; }
        .success { color: #28a745; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Virtual Host Setup <span class="success">✓</span></h1>
        <p>Virtual host for <strong>$domain</strong> is now active.</p>
        <p><a href="phpinfo.php">View PHP Info</a></p>
    </div>
</body>
</html>
HTML
    
    success "Added index.html"
}

# ============================================================================
# LIST FUNCTION
# ============================================================================

# List all existing virtual hosts
list_hosts() {
    info "Listing enabled Apache virtual hosts:"
    echo ""
    
    if [[ ! -d "$SITES_ENABLED" ]]; then
        err "Sites-enabled directory not found: $SITES_ENABLED"
        return 1
    fi
    
    local count=0
    for conf in "$SITES_ENABLED"/*.conf; do
        if [[ -e "$conf" ]]; then
            local domain_name=$(basename "$conf" .conf)
            echo "  ✓ $domain_name"
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
    
    local owner=$(get_owner)
    local webroot=$(get_webroot "$custom_root" "$domain")
    
    info "Creating virtual host for: $domain"
    verbose "Web root: $webroot"
    verbose "Owner: $owner"
    verbose "Email: $EMAIL"
    
    # Create operations
    create_webroot "$webroot" "$owner"
    add_phpinfo "$webroot"
    add_index_html "$webroot" "$domain"
    create_apache_conf "$domain" "$webroot" "$EMAIL" || return 1
    enable_site "$domain" || return 1
    add_hosts_entry "$domain"
    reload_apache || return 1
    
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
    
    local conf_file="$SITES_AVAILABLE/${domain}.conf"
    
    if [[ ! -e "$conf_file" ]] && [[ $DRY_RUN -eq 0 ]]; then
        err "Virtual host does not exist: $domain"
        return 1
    fi
    
    info "Deleting virtual host: $domain"
    
    # Delete operations
    disable_site "$domain"
    remove_conf "$domain" || return 1
    remove_hosts_entry "$domain"
    reload_apache || return 1
    
    # Ask about removing webroot
    if [[ $DRY_RUN -eq 0 ]]; then
        local webroot
        if [[ -e "$SITES_AVAILABLE/${domain}.conf" ]]; then
            webroot=$(grep "DocumentRoot" "$SITES_AVAILABLE/${domain}.conf" | head -1 | awk '{print $2}')
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
            -e|--email)
                EMAIL="$2"
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
    
    # Check Apache installation
    check_apache
    check_apache_mods
    
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
