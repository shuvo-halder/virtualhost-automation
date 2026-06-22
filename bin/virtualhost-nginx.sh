#!/usr/bin/env bash
# virtualhost-nginx.sh — Production-Grade Nginx VirtualHost Manager v3.0.0
# Version: 3.0.0
# Author: Shuvo Halder
# License: MIT
#
# A clean, safe, and feature-rich script to create/delete Nginx virtual hosts.
# Includes SSL, Let's Encrypt, dry-run, logging, JSON output, and more.

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

# ============================================================================
# NGINX-SPECIFIC FUNCTIONS
# ============================================================================

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

# Auto-detect PHP-FPM version
detect_php_fpm() {
    if [[ $PHP_FPM_SOCKET != "127.0.0.1:9000" ]]; then
        echo "$PHP_FPM_SOCKET"
        return
    fi

    # Try to detect installed PHP-FPM versions
    for version in "8.4" "8.3" "8.2" "8.1" "8.0" "7.4" "7.3" "7.2" "7.1" "7.0"; do
        local sock="/run/php/php${version}-fpm.sock"
        if [[ -S "$sock" ]]; then
            verbose "Auto-detected PHP-FPM $version at: unix:$sock"
            echo "unix:$sock"
            return
        fi
    done

    # Fallback to default TCP
    echo "$PHP_FPM_SOCKET"
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

    # Build server_name
    local server_name="$domain"
    if [[ $WITH_WWW -eq 1 ]]; then
        server_name="$domain www.$domain"
    fi

    cat > "$conf_file" <<EOF
server {
    listen 80;
    server_name $server_name;
    root $webroot;

    index index.php index.html index.htm;

    # Security: Deny access to hidden files
    location ~ /\.|^\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Serve static files directly with caching
    location ~* \.(jpg|jpeg|gif|css|png|js|ico|html|svg|woff|woff2|ttf|eot)$ {
        access_log off;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Try files, fallback to index.php
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # PHP-FPM handling
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
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

    # If SSL is enabled, create HTTPS server block
    if [[ $ENABLE_SSL -eq 1 ]]; then
        local ssl_cert="/etc/letsencrypt/live/$domain/fullchain.pem"
        local ssl_key="/etc/letsencrypt/live/$domain/privkey.pem"

        # Use self-signed paths if not using Let's Encrypt
        if [[ $SELF_SIGNED -eq 1 ]]; then
            ssl_cert="/etc/ssl/$domain/fullchain.pem"
            ssl_key="/etc/ssl/$domain/privkey.pem"
        fi

        cat >> "$conf_file" <<EOF

server {
    listen 443 ssl http2;
    server_name $server_name;
    root $webroot;

    index index.php index.html index.htm;

    # SSL Configuration
    ssl_certificate $ssl_cert;
    ssl_certificate_key $ssl_key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;

    # Security: Deny access to hidden files
    location ~ /\.|^\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Static file caching
    location ~* \.(jpg|jpeg|gif|css|png|js|ico|html|svg|woff|woff2|ttf|eot)$ {
        access_log off;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_pass $php_socket;
        fastcgi_index index.php;
        include snippets/fastcgi-php.conf;
    }

    error_log /var/log/nginx/${domain}_error.log warn;
    access_log /var/log/nginx/${domain}_access.log combined;
}
EOF

        # Add HTTP→HTTPS redirect if --force-https was used
        if [[ $FORCE_HTTPS -eq 1 ]]; then
            cat >> "$conf_file" <<EOF

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name $server_name;
    return 301 https://\$server_name\$request_uri;
}
EOF
        fi
    fi

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
# LIST FUNCTION
# ============================================================================

# List all existing virtual hosts
list_hosts() {
    if [[ $JSON_OUTPUT -eq 1 ]]; then
        local json_entries="["
        local first=true
        for site in "$SITES_ENABLED"/*; do
            if [[ -L "$site" ]]; then
                local domain_name=$(basename "$site")
                local target=$(readlink "$site")
                if [[ "$first" == true ]]; then
                    first=false
                else
                    json_entries+=","
                fi
                json_entries+="{\"domain\":\"$domain_name\",\"target\":\"$target\",\"type\":\"nginx\"}"
            fi
        done
        json_entries+="]"
        json_output "success" "Virtual hosts listed" "$json_entries"
        return 0
    fi

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
    local webroot=$(get_webroot "$custom_root" "$domain" "$DEFAULT_WEBROOT")
    local php_socket=$(detect_php_fpm)

    info "Creating virtual host for: $domain"
    verbose "Web root: $webroot"
    verbose "Owner: $owner"
    verbose "PHP-FPM socket: $php_socket"

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
    add_phpinfo "$webroot"
    create_nginx_conf "$domain" "$webroot" "$php_socket" || return 1
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

    # Ask about removing webroot (skip if --force is set)
    if [[ $DRY_RUN -eq 0 ]]; then
        local webroot=""
        if [[ -e "$SITES_AVAILABLE/$domain" ]]; then
            webroot=$(grep "root " "$SITES_AVAILABLE/$domain" | grep -v "# " | head -1 | awk '{print $2}' | sed 's/;$//')
        fi

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
  Production-grade Nginx virtual host creator and remover v$SCRIPT_VERSION.
  Safely manages Nginx server blocks, DNS entries, directories, and SSL.

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
  -l, --letsencrypt        Obtain Let's Encrypt SSL certificate
  --self-signed            Generate a self-signed SSL certificate
  --force-https            Redirect all HTTP traffic to HTTPS
  --with-www               Create server_name with www. prefix
  --force                  Skip confirmation prompts (non-interactive)
  --no-index               Skip creation of test files (phpinfo.php)
  --no-hosts               Skip /etc/hosts modification
  --json                   Output in JSON format (for list command)
  --no-color               Disable colored output

EXAMPLES:
  # Create a new virtual host
  sudo $SCRIPT_NAME create example.dev

  # Create with custom directory
  sudo $SCRIPT_NAME create example.dev /var/www/mysite

  # Create with Let's Encrypt SSL
  sudo $SCRIPT_NAME -l create example.dev

  # Create with self-signed SSL and HTTPS redirect
  sudo $SCRIPT_NAME --self-signed --force-https create example.dev

  # Delete a virtual host (non-interactive)
  sudo $SCRIPT_NAME --force delete example.dev

  # Dry-run mode (show what would happen)
  sudo $SCRIPT_NAME -d create example.dev

  # Use Unix socket for PHP-FPM
  sudo $SCRIPT_NAME -p unix:/run/php/php8.1-fpm.sock create example.dev

  # List all virtual hosts (JSON format)
  sudo $SCRIPT_NAME list --json

NOTES:
  - Must be run with sudo (root privileges required)
  - Domain names must contain only alphanumeric characters, dots, and hyphens
  - Logs are stored in: $LOG_DIR/
  - /etc/hosts entries use 127.0.0.1
  - Default PHP-FPM socket: $PHP_FPM_SOCKET

EOF
    exit "${1:-0}"
}

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