#!/usr/bin/env bash
# install.sh — Installer/Uninstaller for VirtualHost Automation v4.0.0
# Usage:
#   sudo ./install.sh           Install (default)
#   sudo ./install.sh install   Install
#   sudo ./install.sh uninstall Uninstall

set -o errexit
set -o nounset
set -o pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================
readonly INSTALL_VERSION="4.0.0"
readonly INSTALL_DIR="/usr/local/bin"
readonly LIB_DIR="/usr/local/lib"
readonly LOG_DIR="/var/log/virtualhost"
readonly BACKUP_DIR="/var/backups/virtualhost"
readonly COMPLETION_DIR="/etc/bash_completion.d"
readonly MAN_DIR="/usr/share/man/man1"
readonly LOGROTATE_DIR="/etc/logrotate.d"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[0;34m'
C_BOLD='\033[1m'
C_RESET='\033[0m'

# ============================================================================
# HELPERS
# ============================================================================

err()     { echo -e "${C_RED}ERROR:${C_RESET} $*" >&2; }
info()    { echo -e "${C_BLUE}INFO:${C_RESET} $*"; }
success() { echo -e "${C_GREEN}✓${C_RESET} $*"; }
warn()    { echo -e "${C_YELLOW}WARNING:${C_RESET} $*" >&2; }

check_root() {
    if [[ $(id -u) -ne 0 ]]; then
        err "This script must be run as root (use sudo)"
        exit 1
    fi
}

# ============================================================================
# INSTALL
# ============================================================================

do_install() {
    echo ""
    echo -e "${C_BOLD}Installing VirtualHost Automation v${INSTALL_VERSION}${C_RESET}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # ── Shared library ───────────────────────────────────────────────
    if [[ -f "$SCRIPT_DIR/lib/virtualhost-lib.sh" ]]; then
        install -m 644 "$SCRIPT_DIR/lib/virtualhost-lib.sh" "$LIB_DIR/virtualhost-lib.sh"
        success "Installed library: $LIB_DIR/virtualhost-lib.sh"
    else
        err "lib/virtualhost-lib.sh not found in $SCRIPT_DIR"
        exit 1
    fi

    # ── Apache manager ───────────────────────────────────────────────
    if [[ -f "$SCRIPT_DIR/bin/virtualhost.sh" ]]; then
        install -m 755 "$SCRIPT_DIR/bin/virtualhost.sh" "$INSTALL_DIR/virtualhost"
        success "Installed: $INSTALL_DIR/virtualhost"
    else
        warn "bin/virtualhost.sh not found — Apache manager not installed"
    fi

    # ── Nginx manager ────────────────────────────────────────────────
    if [[ -f "$SCRIPT_DIR/bin/virtualhost-nginx.sh" ]]; then
        install -m 755 "$SCRIPT_DIR/bin/virtualhost-nginx.sh" "$INSTALL_DIR/virtualhost-nginx"
        success "Installed: $INSTALL_DIR/virtualhost-nginx"
    else
        warn "bin/virtualhost-nginx.sh not found — Nginx manager not installed"
    fi

    # ── Directories ──────────────────────────────────────────────────
    mkdir -p "$LOG_DIR" "$BACKUP_DIR"
    chmod 750 "$LOG_DIR" "$BACKUP_DIR"
    success "Created directories: $LOG_DIR, $BACKUP_DIR"

    # ── Bash completion ──────────────────────────────────────────────
    if [[ -d "$COMPLETION_DIR" ]]; then
        install_bash_completion
    else
        info "Bash completion directory not found ($COMPLETION_DIR) — skipping"
    fi

    echo ""
    echo -e "${C_GREEN}${C_BOLD}Installation complete!${C_RESET}"
    echo ""
    echo "  Apache:  sudo virtualhost [OPTIONS] COMMAND DOMAIN"
    echo "  Nginx:   sudo virtualhost-nginx [OPTIONS] COMMAND DOMAIN"
    echo ""
    echo "  Run 'virtualhost --help' or 'virtualhost-nginx --help' for usage."
    echo ""
}

install_bash_completion() {
    cat > "$COMPLETION_DIR/virtualhost" <<'COMPLETION'
# Bash completion for virtualhost and virtualhost-nginx

_virtualhost_complete() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local commands="create delete enable disable status clone backup restore ssl-renew list help version"
    local options="-h --help -v --verbose -d --dry-run -s --skip-reload -V --version -e --email -l --letsencrypt --self-signed --force-https --with-www --force --no-index --no-hosts --json --no-color --proxy-pass --proxy-websocket --aliases"

    case "$prev" in
        create|delete|enable|disable|status|backup|restore|clone)
            # Complete with known virtual hosts (apache)
            if command -v apache2ctl &>/dev/null 2>&1; then
                local hosts
                hosts=$(ls /etc/apache2/sites-available/*.conf 2>/dev/null | xargs -I{} basename {} .conf)
                COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
            fi
            return 0
            ;;
        --email|-e)
            return 0
            ;;
        --proxy-pass|--aliases)
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "$options" -- "$cur"))
    else
        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
    fi
}

_virtualhost_nginx_complete() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local commands="create delete enable disable status clone backup restore ssl-renew list help version"
    local options="-h --help -v --verbose -d --dry-run -s --skip-reload -V --version -e --email -p --php-socket --php-version -l --letsencrypt --self-signed --force-https --with-www --force --no-index --no-hosts --json --no-color --proxy-pass --proxy-websocket --aliases"

    case "$prev" in
        create|delete|enable|disable|status|backup|restore|clone)
            if command -v nginx &>/dev/null 2>&1; then
                local hosts
                hosts=$(ls /etc/nginx/sites-available/*.conf 2>/dev/null | xargs -I{} basename {} .conf)
                COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
            fi
            return 0
            ;;
        --php-version)
            COMPREPLY=($(compgen -W "8.4 8.3 8.2 8.1 8.0 7.4" -- "$cur"))
            return 0
            ;;
        --email|-e|--proxy-pass|--aliases|-p|--php-socket)
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "$options" -- "$cur"))
    else
        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
    fi
}

complete -F _virtualhost_complete virtualhost
complete -F _virtualhost_nginx_complete virtualhost-nginx
COMPLETION
    success "Installed bash completion: $COMPLETION_DIR/virtualhost"
    info "Reload your shell or run: source $COMPLETION_DIR/virtualhost"
}

# ============================================================================
# UNINSTALL
# ============================================================================

do_uninstall() {
    echo ""
    echo -e "${C_BOLD}Uninstalling VirtualHost Automation${C_RESET}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local removed=0

    for target in \
        "$INSTALL_DIR/virtualhost" \
        "$INSTALL_DIR/virtualhost-nginx" \
        "$LIB_DIR/virtualhost-lib.sh" \
        "$COMPLETION_DIR/virtualhost"
    do
        if [[ -f "$target" ]]; then
            rm -f "$target"
            success "Removed: $target"
            ((removed++))
        fi
    done

    echo ""
    warn "Log directory kept: $LOG_DIR (remove manually if desired)"
    warn "Backup directory kept: $BACKUP_DIR (remove manually if desired)"
    echo ""

    if [[ $removed -eq 0 ]]; then
        info "Nothing to uninstall — not currently installed."
    else
        success "Uninstall complete ($removed file(s) removed)."
    fi
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    check_root

    local action="${1:-install}"

    case "$action" in
        install)
            do_install
            ;;
        uninstall)
            do_uninstall
            ;;
        *)
            err "Unknown action: $action"
            echo "Usage: sudo $0 [install|uninstall]"
            exit 1
            ;;
    esac
}

main "$@"
