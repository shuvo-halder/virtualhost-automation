#!/usr/bin/env bash
# virtualhost.sh — Production-Grade Apache VirtualHost Manager v3.0.0
# Version: 3.0.0
# Author: Shuvo Halder
# License: MIT
#
# A clean, safe, and feature-rich script to create/delete Apache virtual hosts.
# Includes SSL, Let's Encrypt, dry-run, logging, JSON output, proxy pass, and more.

set -o errexit
set -o nounset
set -o pipefail
IFS=$'\n\t'

# ============================================================================
# SOURCE SHARED LIBRARY
# ============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../lib/virtualhost-lib.sh" ]]; then
    source "$SCRIPT_DIR/../lib/virtualhost-lib.sh"
elif [[ -f "/usr/local/lib/virtualhost-lib.sh" ]]; then
    source "/usr/local/lib/virtualhost-lib.sh"
else
    echo "ERROR: virtualhost-lib.sh not found" >&2
    exit 1
fi

# ============================================================================
# CONFIGURATION
# ============================================================================
readonly SCRIPT_VERSION="3.0.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Apache paths
readonly SITES_AVAILABLE="/etc/apache2/sites-available"
readonly SITES_ENABLED="/etc/apache2/sites-enabled"
readonly DEFAULT_WEBROOT="/var/www"
readonly APACHE_MODS_ENABLED="/etc/apache2/mods-enabled"
readonly WEB_USER="www-data"
readonly WEB_GROUP="www-data"

# Email for Apache configuration
EMAIL="${EMAIL:-webmaster@localhost}"

# Logging
readonly LOG_DIR="${LOG_DIR:-/var/log/virtualhost}"
readonly LOG_FILE="$LOG_DIR/virtualhost-apache-$(date +%Y%m%d).log"

# ============================================================================
# APACHE-SPECIFIC FUNCTIONS
# ============================================================================

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
    verbose "Checking Apache modules..."

    if [[ ! -d "$APACHE_MODS_ENABLED" ]]; then
        warn "Could not verify Apache modules"
        return 0
    fi

    if [[ ! -e "$APACHE_MODS_ENABLED/rewrite.load" ]]; then
        warn "mod_rewrite may not be enabled. Run: sudo a2enmod rewrite"
    fi

    if [[ $ENABLE_SSL -eq 1 ]] && [[ ! -e "$APACHE_MODS_ENABLED/ssl.load" ]]; then
        warn "mod_ssl is not enabled. Run: sudo a2enmod ssl"
    fi

    if [[ -n "$PROXY_PASS" ]]; then
        if [[ ! -e "$APACHE_MODS_ENABLED/proxy.load" ]]; then
            warn "mod_proxy is not enabled. Run: sudo a2enmod proxy proxy_http"
        fi
        if [[ ! -e "$APACHE_MODS_ENABLED/proxy_http.load" ]]; then
            warn "mod_proxy_http is not enabled. Run: sudo a2enmod proxy_http"
        fi
        if [[ $PROXY_WEBSOCKET -eq 1 ]] && [[ ! -e "$APACHE_MODS_ENABLED/proxy_wstunnel.load" ]]; then
            warn "mod_proxy_wstunnel is not enabled. Run: sudo a2enmod proxy_wstunnel"
        fi
    fi
}

# Create Apache VirtualHost configuration (standard document root)
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

    # Build ServerAlias
    local server_alias=""
    if [[ $WITH_WWW -eq 1 ]]; then
        server_alias="ServerAlias www.$domain"
    fi

    # Only write full HTTP block when NOT force-redirecting to HTTPS
    if [[ $FORCE_HTTPS -eq 0 ]]; then
        cat > "$conf_file" <<EOF
<VirtualHost *:80>
    ServerAdmin $email
    ServerName $domain
    ${server_alias}

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
    fi

    # If SSL is enabled, create HTTPS virtual host
    if [[ $ENABLE_SSL -eq 1 ]]; then
        local ssl_cert="/etc/letsencrypt/live/$domain/fullchain.pem"
        local ssl_key="/etc/letsencrypt/live/$domain/privkey.pem"

        # Use self-signed paths if not using Let's Encrypt
        if [[ $SELF_SIGNED -eq 1 ]]; then
            ssl_cert="/etc/ssl/$domain/fullchain.pem"
            ssl_key="/etc/ssl/$domain/privkey.pem"
        fi

        cat >> "$conf_file" <<EOF

<VirtualHost *:443>
    ServerAdmin $email
    ServerName $domain
    ${server_alias}

    DocumentRoot $webroot

    # SSL Configuration
    SSLEngine on
    SSLCertificateFile $ssl_cert
    SSLCertificateKeyFile $ssl_key

    # Security headers
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"

    <Directory $webroot>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
        RewriteEngine On
        RewriteBase /
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule ^ index.php [L]
    </Directory>

    <FilesMatch "^\\.">
        Require all denied
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/${domain}_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_access.log combined

    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/plain text/html text/xml text/css
        AddOutputFilterByType DEFLATE application/xml application/xhtml+xml
        AddOutputFilterByType DEFLATE application/rss+xml application/javascript
        AddOutputFilterByType DEFLATE application/x-javascript
    </IfModule>
</VirtualHost>
EOF

        # Add HTTP→HTTPS redirect if --force-https was used
        if [[ $FORCE_HTTPS -eq 1 ]]; then
            cat >> "$conf_file" <<EOF

# Redirect HTTP to HTTPS
<VirtualHost *:80>
    ServerName $domain
    ${server_alias}
    Redirect permanent / https://$domain/
</VirtualHost>
EOF
        fi
    fi

    success "Created Apache configuration: $conf_file"
    return 0
}

# Create Apache reverse proxy configuration
create_apache_proxy_conf() {
    local domain="$1"
    local proxy_url="$2"
    local email="$3"
    local conf_file="$SITES_AVAILABLE/${domain}.conf"

    if [[ -e "$conf_file" ]]; then
        err "Configuration already exists: $conf_file"
        return 1
    fi

    verbose "Creating Apache reverse proxy configuration: $conf_file"

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY-RUN] Would create proxy config at: $conf_file"
        return 0
    fi

    # Build ServerAlias
    local server_alias=""
    if [[ $WITH_WWW -eq 1 ]]; then
        server_alias="ServerAlias www.$domain"
    fi

    # Build WebSocket proxy config if requested
    local ws_proxy=""
    if [[ $PROXY_WEBSOCKET -eq 1 ]]; then
        local ws_url
        ws_url=$(echo "$proxy_url" | sed 's|^http://|ws://|' | sed 's|^https://|wss://|')
        ws_proxy=$(cat <<WSEOF
    # WebSocket reverse proxy
    <Location /ws>
        ProxyPass $ws_url
        ProxyPassReverse $ws_url
    </Location>

    # WebSocket upgrade support (alternative method)
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteRule /(.*) $ws_url/\$1 [P,L]

WSEOF
)
    fi

    # Only write full HTTP proxy block when NOT force-redirecting to HTTPS
    if [[ $FORCE_HTTPS -eq 0 ]]; then
        cat > "$conf_file" <<EOF
<VirtualHost *:80>
    ServerAdmin $email
    ServerName $domain
    ${server_alias}

    # Reverse Proxy Configuration
    # Proxying all requests to: $proxy_url

    # Enable proxy
    ProxyPreserveHost On
    ProxyRequests Off

    # Main proxy pass
    ProxyPass / $proxy_url/
    ProxyPassReverse / $proxy_url/

    # Security headers
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"

    # Pass real IP to backend
    RequestHeader set X-Forwarded-Proto "http"
    RequestHeader set X-Forwarded-Port "80"

${ws_proxy}
    # Logging
    ErrorLog \${APACHE_LOG_DIR}/${domain}_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_access.log combined
</VirtualHost>
EOF
    fi

    # If SSL is enabled, create HTTPS proxy virtual host
    if [[ $ENABLE_SSL -eq 1 ]]; then
        local ssl_cert="/etc/letsencrypt/live/$domain/fullchain.pem"
        local ssl_key="/etc/letsencrypt/live/$domain/privkey.pem"

        # Use self-signed paths if not using Let's Encrypt
        if [[ $SELF_SIGNED -eq 1 ]]; then
            ssl_cert="/etc/ssl/$domain/fullchain.pem"
            ssl_key="/etc/ssl/$domain/privkey.pem"
        fi

        cat >> "$conf_file" <<EOF

<VirtualHost *:443>
    ServerAdmin $email
    ServerName $domain
    ${server_alias}

    # SSL Configuration
    SSLEngine on
    SSLCertificateFile $ssl_cert
    SSLCertificateKeyFile $ssl_key

    # Security headers
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"

    # Reverse Proxy Configuration
    ProxyPreserveHost On
    ProxyRequests Off

    # Main proxy pass
    ProxyPass / $proxy_url/
    ProxyPassReverse / $proxy_url/

    # Pass real IP to backend
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port "443"

${ws_proxy}
    ErrorLog \${APACHE_LOG_DIR}/${domain}_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_access.log combined
</VirtualHost>
EOF

        # Add HTTP→HTTPS redirect if --force-https was used
        if [[ $FORCE_HTTPS -eq 1 ]]; then
            cat >> "$conf_file" <<EOF

# Redirect HTTP to HTTPS
<VirtualHost *:80>
    ServerName $domain
    ${server_alias}
    Redirect permanent / https://$domain/
</VirtualHost>
EOF
        fi
    fi

    success "Created Apache reverse proxy configuration: $conf_file"
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
# LIST FUNCTION
# ============================================================================

# List all existing virtual hosts
list_hosts() {
    if [[ $JSON_OUTPUT -eq 1 ]]; then
        local json_entries="["
        local first=true
        for conf in "$SITES_ENABLED"/*.conf; do
            if [[ -e "$conf" ]]; then
                local domain_name=$(basename "$conf" .conf)
                if [[ "$first" == true ]]; then
                    first=false
                else
                    json_entries+=","
                fi
                json_entries+="{\"domain\":\"$domain_name\",\"type\":\"apache\"}"
            fi
        done
        json_entries+="]"
        json_output "success" "Virtual hosts listed" "$json_entries"
        return 0
    fi

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
    local webroot=$(get_webroot "$custom_root" "$domain" "$DEFAULT_WEBROOT")

    info "Creating virtual host for: $domain"
    verbose "Web root: $webroot"
    verbose "Owner: $owner"
    verbose "Email: $EMAIL"

    # Normalize proxy pass (accept port number like 3000, or full URL)
    if [[ -n "$PROXY_PASS" ]]; then
        PROXY_PASS=$(normalize_proxy_pass "$PROXY_PASS")
        verbose "Proxy pass: $PROXY_PASS"
        if [[ $PROXY_WEBSOCKET -eq 1 ]]; then
            verbose "WebSocket proxy: enabled"
        fi
    fi

    # SSL setup (if requested)
    if [[ $ENABLE_SSL -eq 1 ]]; then
        if [[ $SELF_SIGNED -eq 1 ]]; then
            generate_self_signed_ssl "$domain" || return 1
        else
            # Create webroot first for Let's Encrypt verification
            create_webroot "$webroot" "$owner" "$WEB_GROUP"
            obtain_letsencrypt_cert "$domain" "$webroot" || return 1
        fi
    fi

    # Create operations
    create_webroot "$webroot" "$owner" "$WEB_GROUP"

    if [[ -n "$PROXY_PASS" ]]; then
        # Proxy pass mode: skip test files, create proxy config
        validate_proxy_pass "$PROXY_PASS" || return 1
        check_proxy_backend "$PROXY_PASS"
        create_apache_proxy_conf "$domain" "$PROXY_PASS" "$EMAIL" || return 1
    else
        # Standard mode: create test files and document root config
        add_phpinfo "$webroot"
        add_index_html "$webroot" "$domain"
        create_apache_conf "$domain" "$webroot" "$EMAIL" || return 1
    fi

    enable_site "$domain" || return 1
    add_hosts_entry "$domain"
    reload_apache || return 1

    echo ""
    if [[ $DRY_RUN -eq 0 ]]; then
        success "Virtual host created successfully!"
        echo ""
        echo "  Domain: $domain"
        if [[ -n "$PROXY_PASS" ]]; then
            echo "  Proxy:  $PROXY_PASS"
            echo "  Type:   Reverse Proxy"
        else
            echo "  Root:   $webroot"
        fi
        echo "  Visit:  http://$domain"
        if [[ $ENABLE_SSL -eq 1 ]]; then
            echo "  HTTPS:  https://$domain"
        fi
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

    # Capture webroot NOW, before the config file is deleted
    local webroot=""
    if [[ -e "$conf_file" ]]; then
        webroot=$(grep -m1 "^[[:space:]]*DocumentRoot" "$conf_file" | awk '{print $2}')
    fi

    # Delete operations
    disable_site "$domain"
    remove_conf "$domain" || return 1
    remove_hosts_entry "$domain"
    reload_apache || return 1

    # Ask about removing webroot (skip if --force is set)
    if [[ $DRY_RUN -eq 0 ]]; then

        if [[ -n "$webroot" && -d "$webroot" ]]; then
            if [[ $FORCE -eq 1 ]]; then
                rm -rf -- "$webroot"
                success "Removed directory: $webroot"
            else
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
    fi

    echo ""
    if [[ $DRY_RUN -eq 0 ]]; then
        success "Virtual host deleted successfully!"
    fi
}

# ============================================================================
# USAGE / HELP
# ============================================================================

usage() {
    cat <<EOF
Usage: sudo $SCRIPT_NAME [OPTIONS] COMMAND DOMAIN [ROOTDIR]

DESCRIPTION:
  Production-grade Apache virtual host creator and remover v$SCRIPT_VERSION.
  Safely manages Apache server blocks, DNS entries, directories, SSL, and reverse proxy.

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
  -l, --letsencrypt        Obtain Let's Encrypt SSL certificate
  --self-signed            Generate a self-signed SSL certificate
  --force-https            Redirect all HTTP traffic to HTTPS
  --with-www               Create ServerAlias with www. prefix
  --force                  Skip confirmation prompts (non-interactive)
  --no-index               Skip creation of test files (phpinfo.php, index.html)
  --no-hosts               Skip /etc/hosts modification
  --json                   Output in JSON format (for list command)
  --no-color               Disable colored output
  --proxy-pass URL         Reverse proxy to a backend server (e.g., http://localhost:3000)
                           Supports Node.js, React, Next.js, Vue, or any HTTP server
  --proxy-websocket        Enable WebSocket proxy support (use with --proxy-pass)

EXAMPLES:
  # Create a new virtual host
  sudo $SCRIPT_NAME create example.dev

  # Create with custom directory
  sudo $SCRIPT_NAME create example.dev /var/www/mysite

  # Create with Let's Encrypt SSL
  sudo $SCRIPT_NAME -l create example.dev

  # Create with self-signed SSL and HTTPS redirect
  sudo $SCRIPT_NAME --self-signed --force-https create example.dev

  # Reverse proxy to Node.js app (e.g., Express, Next.js, React dev server)
  sudo $SCRIPT_NAME --proxy-pass http://localhost:3000 create myapp.dev

  # Reverse proxy to Node.js with WebSocket support (e.g., Nuxt, Socket.io)
  sudo $SCRIPT_NAME --proxy-pass http://localhost:3000 --proxy-websocket create myapp.dev

  # Reverse proxy with SSL
  sudo $SCRIPT_NAME --self-signed --proxy-pass http://localhost:3000 create myapp.dev

  # Delete a virtual host (non-interactive)
  sudo $SCRIPT_NAME --force delete example.dev

  # Dry-run mode (show what would happen)
  sudo $SCRIPT_NAME -d create example.dev

  # List all virtual hosts (JSON format)
  sudo $SCRIPT_NAME list --json

  # Set custom admin email
  sudo $SCRIPT_NAME -e admin@example.com create example.dev

NOTES:
  - Must be run with sudo (root privileges required)
  - Domain names must contain only alphanumeric characters, dots, and hyphens
  - Logs are stored in: $LOG_DIR/
  - /etc/hosts entries use 127.0.0.1
  - Requires Apache2 with mod_rewrite enabled
  - For proxy pass: requires mod_proxy and mod_proxy_http (auto-warned)
  - For WebSocket proxy: requires mod_proxy_wstunnel (auto-warned)
  - Default admin email: $EMAIL

EOF
    exit "${1:-0}"
}

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
            -l|--letsencrypt)
                ENABLE_SSL=1
                shift
                ;;
            --self-signed)
                ENABLE_SSL=1
                SELF_SIGNED=1
                shift
                ;;
            --force-https)
                FORCE_HTTPS=1
                shift
                ;;
            --with-www)
                WITH_WWW=1
                shift
                ;;
            --force)
                FORCE=1
                shift
                ;;
            --no-index)
                SKIP_INDEX=1
                shift
                ;;
            --no-hosts)
                SKIP_HOSTS=1
                shift
                ;;
            --json)
                JSON_OUTPUT=1
                shift
                ;;
            --no-color)
                NO_COLOR=1
                shift
                ;;
            --proxy-pass)
                PROXY_PASS="$2"
                shift 2
                ;;
            --proxy-websocket)
                PROXY_WEBSOCKET=1
                shift
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

    # Initialize colors after arg parsing (so --no-color is respected)
    init_colors

    # Guard: --force-https requires SSL to be enabled
    if [[ $FORCE_HTTPS -eq 1 ]] && [[ $ENABLE_SSL -eq 0 ]]; then
        err "--force-https requires --self-signed or --letsencrypt"
        exit 1
    fi

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