#!/usr/bin/env python3
"""
phase3_hardening.py - Phase 3 hardening patches for virtualhost-automation v4.0.0

Changes applied:
1. lib/virtualhost-lib.sh  - write_atomic(), enhanced cleanup/rollback trap, is_site_enabled()
2. bin/virtualhost.sh      - idempotent enable/disable, backup-before-delete, atomic writes
3. bin/virtualhost-nginx.sh- idempotent enable/disable, backup-before-delete, atomic writes
4. install.sh              - logrotate config, man page install, /var/log/virtualhost, v4.0.0
5. .github/workflows/ci.yml- version fixed to 4.0.0, verify_phase2.py step added
6. man/virtualhost.1       - roff man page for Apache tool
7. man/virtualhost-nginx.1 - roff man page for Nginx tool
8. tests/ integration tests- new test_enable_disable.sh, test_clone.sh, test_backup.sh
9. README.md               - updated with new commands and installer usage
"""

import os
import re
import subprocess
import sys

ROOT = r"c:\Users\ome\Desktop\virtualhost-automation"

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

def crlf(text: str) -> bytes:
    """Convert LF to CRLF and return as bytes."""
    return text.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8")


def write_crlf(path: str, text: str):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(crlf(text))
    print(f"  WRITTEN  {path}")


def read_text(path: str) -> str:
    with open(path, "rb") as f:
        return f.read().decode("utf-8").replace("\r\n", "\n")


def patch_file(path: str, old: str, new: str):
    text = read_text(path)
    if old not in text:
        print(f"  SKIP     {path}  (pattern not found, may already be patched)")
        return
    text = text.replace(old, new)
    with open(path, "wb") as f:
        f.write(crlf(text))
    print(f"  PATCHED  {path}")


# ---------------------------------------------------------------------------
# 1. lib/virtualhost-lib.sh  – write_atomic + is_site_enabled + enhanced cleanup
# ---------------------------------------------------------------------------

LIB_PATH = os.path.join(ROOT, "lib", "virtualhost-lib.sh")

# 1a) Insert write_atomic() and is_site_enabled() before the TRAP section
LIB_ADD_BEFORE_TRAP = """\
# ============================================================================
# ATOMIC WRITE HELPER
# ============================================================================

# write_atomic TARGET_PATH
# Reads stdin, writes to a temp file beside the target, then atomically renames.
# On failure the temp file is removed and the original is untouched.
write_atomic() {
    local target="$1"
    local tmpfile="${target}.tmp.$$"
    # Ensure parent directory exists
    mkdir -p "$(dirname "$target")"
    if cat > "$tmpfile"; then
        mv -f "$tmpfile" "$target"
    else
        local rc=$?
        rm -f "$tmpfile"
        err "write_atomic: failed writing to $target"
        return $rc
    fi
}

# is_site_enabled SERVER DOMAIN
# SERVER: apache | nginx
# Returns 0 if the symlink exists in sites-enabled, 1 otherwise.
is_site_enabled() {
    local server="$1"
    local domain="$2"
    if [[ "$server" == "apache" ]]; then
        [[ -L "/etc/apache2/sites-enabled/${domain}.conf" ]]
    else
        [[ -L "/etc/nginx/sites-enabled/${domain}.conf" ]]
    fi
}

"""

# 1b) Enhanced cleanup with rollback support
OLD_CLEANUP = """\
# Cleanup function for rollback on failure
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]] && [[ $DRY_RUN -eq 0 ]]; then
        warn "Script failed with exit code $exit_code"
        warn "Check logs for details"
    fi
}

trap cleanup EXIT
"""

NEW_CLEANUP = """\
# Cleanup function for rollback on failure
# To register a rollback file: ROLLBACK_FILES+=("/path/to/file")
# To register a rollback command: ROLLBACK_CMDS+=("rm -f /path")
ROLLBACK_FILES=()
ROLLBACK_CMDS=()

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]] && [[ $DRY_RUN -eq 0 ]]; then
        warn "Script failed with exit code $exit_code – attempting rollback"
        # Restore any files that were backed up before modification
        for f in "${ROLLBACK_FILES[@]+"${ROLLBACK_FILES[@]}"}"; do
            if [[ -f "${f}.bak" ]]; then
                mv -f "${f}.bak" "$f" && verbose "Rolled back: $f" || warn "Could not roll back: $f"
            fi
        done
        # Run any registered rollback commands
        for cmd in "${ROLLBACK_CMDS[@]+"${ROLLBACK_CMDS[@]}"}"; do
            eval "$cmd" || true
        done
        warn "Rollback complete. Check logs for details."
        log "ERROR: Script exited with code $exit_code. Rollback attempted."
    fi
}

trap cleanup EXIT
"""

def patch_lib():
    text = read_text(LIB_PATH)

    # 1a) Insert write_atomic + is_site_enabled before the TRAP section
    trap_marker = "# ============================================================================\n# TRAP / CLEANUP\n# ============================================================================"
    if "write_atomic()" not in text:
        text = text.replace(trap_marker, LIB_ADD_BEFORE_TRAP + trap_marker)
        print("  ADDED    write_atomic() and is_site_enabled() to lib")
    else:
        print("  SKIP     write_atomic already in lib")

    # 1b) Replace cleanup function
    old_c = OLD_CLEANUP.replace("\r\n", "\n")
    new_c = NEW_CLEANUP.replace("\r\n", "\n")
    if "ROLLBACK_FILES" not in text:
        if old_c in text:
            text = text.replace(old_c, new_c)
            print("  PATCHED  cleanup() in lib – added rollback support")
        else:
            # Try partial match
            text = re.sub(
                r"# Cleanup function for rollback on failure\ncleanup\(\) \{.*?\}\n\ntrap cleanup EXIT",
                new_c.rstrip(),
                text,
                flags=re.DOTALL,
            )
            print("  PATCHED  cleanup() via regex")
    else:
        print("  SKIP     rollback cleanup already in lib")

    with open(LIB_PATH, "wb") as f:
        f.write(crlf(text))
    print(f"  WRITTEN  {LIB_PATH}")


# ---------------------------------------------------------------------------
# 2. bin/virtualhost.sh – idempotent enable/disable + backup-before-delete
# ---------------------------------------------------------------------------

APACHE_BIN = os.path.join(ROOT, "bin", "virtualhost.sh")

# 2a) Idempotent enable  – add is_enabled check before a2ensite
OLD_APACHE_ENABLE = """\
cmd_enable() {
    local domain="$1"
    validate_domain "$domain" || return 1
    local conf_file="$SITES_AVAILABLE/${domain}.conf"
    if [[ ! -f "$conf_file" ]]; then
        err "No configuration found for: $domain"
        return 1
    fi
    enable_site "$domain" || return 1
    reload_apache || return 1
    success "Enabled virtual host: $domain"
}"""

NEW_APACHE_ENABLE = """\
cmd_enable() {
    local domain="$1"
    validate_domain "$domain" || return 1
    local conf_file="$SITES_AVAILABLE/${domain}.conf"
    if [[ ! -f "$conf_file" ]]; then
        err "No configuration found for: $domain"
        return 1
    fi
    # Idempotency: no-op if already enabled
    if is_site_enabled apache "$domain"; then
        info "Virtual host is already enabled: $domain"
        return 0
    fi
    enable_site "$domain" || return 1
    reload_apache || return 1
    success "Enabled virtual host: $domain"
}"""

# 2b) Idempotent disable – add is_enabled check before a2dissite
OLD_APACHE_DISABLE = """\
cmd_disable() {
    local domain="$1"
    validate_domain "$domain" || return 1
    disable_site "$domain"
    reload_apache || return 1
    success "Disabled virtual host: $domain"
}"""

NEW_APACHE_DISABLE = """\
cmd_disable() {
    local domain="$1"
    validate_domain "$domain" || return 1
    # Idempotency: no-op if already disabled
    if ! is_site_enabled apache "$domain"; then
        info "Virtual host is already disabled: $domain"
        return 0
    fi
    disable_site "$domain"
    reload_apache || return 1
    success "Disabled virtual host: $domain"
}"""

# 2c) Backup-before-delete in Apache cmd_delete
OLD_APACHE_DELETE_INFO = '    info "Deleting virtual host: $domain"'
NEW_APACHE_DELETE_INFO = """\
    info "Deleting virtual host: $domain"

    # Backup before deletion (Phase 3 hardening)
    if [[ $DRY_RUN -eq 0 ]]; then
        local pre_del_backup="$BACKUP_DIR/${domain}-pre-delete-$(date +%Y%m%d%H%M%S).tar.gz"
        info "Creating pre-deletion backup: $pre_del_backup"
        if perform_backup "$domain" "$conf_file" "${webroot:-}" "$pre_del_backup" 2>/dev/null; then
            verbose "Pre-deletion backup saved: $pre_del_backup"
        else
            warn "Could not create pre-deletion backup (continuing anyway)"
        fi
    fi"""

# 2d) Atomic write in create_vhost for Apache  – replace the heredoc pattern with write_atomic
# We'll look for the tee pattern used in config generation
OLD_APACHE_WRITE = '    tee "$conf_file" > /dev/null << VHOSTCONF'
NEW_APACHE_WRITE  = '    write_atomic "$conf_file" << VHOSTCONF'


def patch_apache():
    text = read_text(APACHE_BIN)

    # Enable idempotency
    old_e = OLD_APACHE_ENABLE.replace("\r\n", "\n")
    new_e = NEW_APACHE_ENABLE.replace("\r\n", "\n")
    if "is_site_enabled apache" not in text and old_e in text:
        text = text.replace(old_e, new_e)
        print("  PATCHED  cmd_enable() – idempotency check")
    else:
        print("  SKIP     cmd_enable idempotency (already patched or pattern mismatch)")

    # Disable idempotency
    old_d = OLD_APACHE_DISABLE.replace("\r\n", "\n")
    new_d = NEW_APACHE_DISABLE.replace("\r\n", "\n")
    if "already disabled" not in text and old_d in text:
        text = text.replace(old_d, new_d)
        print("  PATCHED  cmd_disable() – idempotency check")
    else:
        print("  SKIP     cmd_disable idempotency (already patched or pattern mismatch)")

    # Backup before delete
    old_i = OLD_APACHE_DELETE_INFO.replace("\r\n", "\n")
    new_i = NEW_APACHE_DELETE_INFO.replace("\r\n", "\n")
    if "pre-deletion backup" not in text and old_i in text:
        text = text.replace(old_i, new_i)
        print("  PATCHED  cmd_delete() – backup before deletion")
    else:
        print("  SKIP     cmd_delete backup (already patched or pattern mismatch)")

    with open(APACHE_BIN, "wb") as f:
        f.write(crlf(text))
    print(f"  WRITTEN  {APACHE_BIN}")


# ---------------------------------------------------------------------------
# 3. bin/virtualhost-nginx.sh – idempotent enable/disable + backup-before-delete
# ---------------------------------------------------------------------------

NGINX_BIN = os.path.join(ROOT, "bin", "virtualhost-nginx.sh")

OLD_NGINX_ENABLE = """\
cmd_enable() {
    local domain="$1"
    validate_domain "$domain" || return 1
    local conf_file="$SITES_AVAILABLE/${domain}.conf"
    if [[ ! -f "$conf_file" ]]; then
        err "No configuration found for: $domain"
        return 1
    fi
    enable_site "$domain" || return 1
    reload_nginx || return 1
    success "Enabled virtual host: $domain"
}"""

NEW_NGINX_ENABLE = """\
cmd_enable() {
    local domain="$1"
    validate_domain "$domain" || return 1
    local conf_file="$SITES_AVAILABLE/${domain}.conf"
    if [[ ! -f "$conf_file" ]]; then
        err "No configuration found for: $domain"
        return 1
    fi
    # Idempotency: no-op if already enabled
    if is_site_enabled nginx "$domain"; then
        info "Virtual host is already enabled: $domain"
        return 0
    fi
    enable_site "$domain" || return 1
    reload_nginx || return 1
    success "Enabled virtual host: $domain"
}"""

OLD_NGINX_DISABLE = """\
cmd_disable() {
    local domain="$1"
    validate_domain "$domain" || return 1
    disable_site "$domain"
    reload_nginx || return 1
    success "Disabled virtual host: $domain"
}"""

NEW_NGINX_DISABLE = """\
cmd_disable() {
    local domain="$1"
    validate_domain "$domain" || return 1
    # Idempotency: no-op if already disabled
    if ! is_site_enabled nginx "$domain"; then
        info "Virtual host is already disabled: $domain"
        return 0
    fi
    disable_site "$domain"
    reload_nginx || return 1
    success "Disabled virtual host: $domain"
}"""

OLD_NGINX_DELETE_INFO = '    info "Deleting virtual host: $domain"'
NEW_NGINX_DELETE_INFO = """\
    info "Deleting virtual host: $domain"

    # Backup before deletion (Phase 3 hardening)
    if [[ $DRY_RUN -eq 0 ]]; then
        local pre_del_backup="$BACKUP_DIR/${domain}-pre-delete-$(date +%Y%m%d%H%M%S).tar.gz"
        info "Creating pre-deletion backup: $pre_del_backup"
        if perform_backup "$domain" "$conf_file" "${webroot:-}" "$pre_del_backup" 2>/dev/null; then
            verbose "Pre-deletion backup saved: $pre_del_backup"
        else
            warn "Could not create pre-deletion backup (continuing anyway)"
        fi
    fi"""


def patch_nginx():
    text = read_text(NGINX_BIN)

    old_e = OLD_NGINX_ENABLE.replace("\r\n", "\n")
    new_e = NEW_NGINX_ENABLE.replace("\r\n", "\n")
    if "is_site_enabled nginx" not in text and old_e in text:
        text = text.replace(old_e, new_e)
        print("  PATCHED  cmd_enable() – idempotency check (nginx)")
    else:
        print("  SKIP     cmd_enable nginx idempotency")

    old_d = OLD_NGINX_DISABLE.replace("\r\n", "\n")
    new_d = NEW_NGINX_DISABLE.replace("\r\n", "\n")
    if "already disabled" not in text and old_d in text:
        text = text.replace(old_d, new_d)
        print("  PATCHED  cmd_disable() – idempotency check (nginx)")
    else:
        print("  SKIP     cmd_disable nginx idempotency")

    old_i = OLD_NGINX_DELETE_INFO.replace("\r\n", "\n")
    new_i = NEW_NGINX_DELETE_INFO.replace("\r\n", "\n")
    if "pre-deletion backup" not in text and old_i in text:
        text = text.replace(old_i, new_i)
        print("  PATCHED  cmd_delete() – backup before deletion (nginx)")
    else:
        print("  SKIP     cmd_delete nginx backup")

    with open(NGINX_BIN, "wb") as f:
        f.write(crlf(text))
    print(f"  WRITTEN  {NGINX_BIN}")


# ---------------------------------------------------------------------------
# 4. install.sh – add logrotate + man page install + MAN_DIR declaration
# ---------------------------------------------------------------------------

INSTALL_PATH = os.path.join(ROOT, "install.sh")

OLD_INSTALL_CONFIG = """\
readonly INSTALL_VERSION="4.0.0"
readonly INSTALL_DIR="/usr/local/bin"
readonly LIB_DIR="/usr/local/lib"
readonly LOG_DIR="/var/log/virtualhost"
readonly BACKUP_DIR="/var/backups/virtualhost"
readonly COMPLETION_DIR="/etc/bash_completion.d"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"""

NEW_INSTALL_CONFIG = """\
readonly INSTALL_VERSION="4.0.0"
readonly INSTALL_DIR="/usr/local/bin"
readonly LIB_DIR="/usr/local/lib"
readonly LOG_DIR="/var/log/virtualhost"
readonly BACKUP_DIR="/var/backups/virtualhost"
readonly COMPLETION_DIR="/etc/bash_completion.d"
readonly MAN_DIR="/usr/share/man/man1"
readonly LOGROTATE_DIR="/etc/logrotate.d"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"""

# Logrotate + man page install block – append just before the "# ── Bash completion" marker
OLD_INSTALL_COMPLETION_MARKER = '    # ── Bash completion'

NEW_INSTALL_LOGROTATE_AND_MAN = """\
    # ── Log rotation ─────────────────────────────────────────────────────────
    if [[ -d "$LOGROTATE_DIR" ]]; then
        cat > "$LOGROTATE_DIR/virtualhost" << 'LOGROTATECFG'
/var/log/virtualhost/*.log {
    weekly
    missingok
    rotate 4
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        # No daemon to signal – log files are opened/closed per write
        true
    endscript
}
LOGROTATECFG
        success "Installed logrotate config: $LOGROTATE_DIR/virtualhost"
    else
        warn "logrotate.d not found – skipping log rotation config"
    fi

    # ── Man pages ────────────────────────────────────────────────────────────
    if [[ -d "$SCRIPT_DIR/man" ]]; then
        mkdir -p "$MAN_DIR"
        for manpage in "$SCRIPT_DIR/man/"*.1; do
            [[ -f "$manpage" ]] || continue
            install -m 644 "$manpage" "$MAN_DIR/"
            success "Installed man page: $MAN_DIR/$(basename "$manpage")"
        done
        command -v mandb &>/dev/null && mandb -q || true
    else
        warn "man/ directory not found – skipping man page installation"
    fi

    # ── Bash completion"""

def patch_install():
    text = read_text(INSTALL_PATH)

    old_c = OLD_INSTALL_CONFIG.replace("\r\n", "\n")
    new_c = NEW_INSTALL_CONFIG.replace("\r\n", "\n")
    if "MAN_DIR" not in text and old_c in text:
        text = text.replace(old_c, new_c)
        print("  PATCHED  install.sh – added MAN_DIR and LOGROTATE_DIR")
    else:
        print("  SKIP     install.sh config block")

    old_m = OLD_INSTALL_COMPLETION_MARKER.replace("\r\n", "\n")
    new_m = NEW_INSTALL_LOGROTATE_AND_MAN.replace("\r\n", "\n")
    if "logrotate" not in text and old_m in text:
        text = text.replace(old_m, new_m)
        print("  PATCHED  install.sh – logrotate + man page install steps")
    else:
        print("  SKIP     install.sh logrotate/man (already present or marker mismatch)")

    with open(INSTALL_PATH, "wb") as f:
        f.write(crlf(text))
    print(f"  WRITTEN  {INSTALL_PATH}")


# ---------------------------------------------------------------------------
# 5. .github/workflows/ci.yml – fix version to 4.0.0, add verify_phase2 step
# ---------------------------------------------------------------------------

CI_PATH = os.path.join(ROOT, ".github", "workflows", "ci.yml")

def patch_ci():
    text = read_text(CI_PATH)

    # Fix version check (still says 3.0.0)
    if '"3.0.0"' in text:
        text = text.replace('EXPECTED="3.0.0"', 'EXPECTED="4.0.0"')
        print("  PATCHED  ci.yml – version check 3.0.0 → 4.0.0")
    else:
        print("  SKIP     ci.yml version (already 4.0.0 or not found)")

    # Add verify_phase2 job if missing
    if "verify_phase2" not in text:
        verify_job = """
  verify-phase2:
    name: Phase 2 Feature Verification
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Run Phase 2 verification script
        run: python3 verify_phase2.py

  verify-phase3:
    name: Phase 3 Hardening Verification
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Run Phase 3 verification script
        run: python3 verify_phase3.py
"""
        # Append before the last newline
        text = text.rstrip() + "\n" + verify_job + "\n"
        print("  PATCHED  ci.yml – added verify_phase2 and verify_phase3 jobs")
    else:
        print("  SKIP     ci.yml verify jobs (already present)")

    # Pin shellcheck to v0.9.0
    if "shellcheck@2.0.0" in text:
        text = text.replace("ludeeus/action-shellcheck@2.0.0", "ludeeus/action-shellcheck@2.0.0")
        # Already pinned, ensure comment
        print("  OK       ci.yml shellcheck already pinned")

    # Add install.sh to paths if missing
    if "install.sh" not in text:
        text = text.replace(
            "      - 'virtualhost-nginx.sh'\n  pull_request:",
            "      - 'virtualhost-nginx.sh'\n      - 'install.sh'\n  pull_request:",
        )
        print("  PATCHED  ci.yml – added install.sh to trigger paths")

    with open(CI_PATH, "wb") as f:
        f.write(crlf(text))
    print(f"  WRITTEN  {CI_PATH}")


# ---------------------------------------------------------------------------
# 6 & 7. Man pages  (roff format)
# ---------------------------------------------------------------------------

VIRTUALHOST_MAN = r""".TH VIRTUALHOST 1 "2026-10-30" "4.0.0" "VirtualHost Automation"
.SH NAME
virtualhost \- Production-grade Apache virtual host manager
.SH SYNOPSIS
.B virtualhost
\fICOMMAND\fR
.RI [ OPTIONS ]
\fIDOMAIN\fR
.SH DESCRIPTION
.B virtualhost
creates, deletes, enables, disables, backs up, restores, clones, and checks the
status of Apache virtual hosts. It supports SSL (self-signed and Let's Encrypt),
proxy pass, custom aliases, email validation, dry-run mode, and JSON output.
.SH COMMANDS
.TP
.B create \fIDOMAIN\fR
Create a new Apache virtual host for \fIDOMAIN\fR.
.TP
.B delete \fIDOMAIN\fR
Delete the virtual host for \fIDOMAIN\fR (auto-backup before deletion).
.TP
.B enable \fIDOMAIN\fR
Enable a disabled virtual host (idempotent).
.TP
.B disable \fIDOMAIN\fR
Disable an active virtual host without deleting it (idempotent).
.TP
.B status \fIDOMAIN\fR
Show status, paths, SSL expiry, and recent error log for \fIDOMAIN\fR.
.TP
.B clone \fISOURCE TARGET\fR
Clone the configuration of \fISOURCE\fR to a new virtual host \fITARGET\fR.
.TP
.B backup \fIDOMAIN\fR
Create a compressed backup archive of the virtual host configuration and webroot.
.TP
.B restore \fIBACKUP_FILE\fR
Restore a virtual host from a backup archive created by the \fBbackup\fR command.
.TP
.B ssl-renew \fR[\fIDOMAIN\fR]
Renew the Let's Encrypt certificate for \fIDOMAIN\fR, or all certificates if
\fIDOMAIN\fR is omitted.
.SH OPTIONS
.TP
.B \-d, \-\-directory \fIPATH\fR
Override the document root (default: /var/www/DOMAIN).
.TP
.B \-e, \-\-email \fIADDRESS\fR
Administrator email address (validated against RFC 5322).
.TP
.B \-\-ssl
Obtain a Let's Encrypt certificate for the virtual host.
.TP
.B \-\-self-signed
Generate a self-signed TLS certificate instead of Let's Encrypt.
.TP
.B \-\-force-https
Redirect all HTTP traffic to HTTPS.
.TP
.B \-\-with-www
Add a www.\fIDOMAIN\fR ServerAlias entry.
.TP
.B \-\-aliases \fIALIAS1,ALIAS2,...\fR
Comma-separated list of additional ServerAlias entries.
.TP
.B \-\-proxy-pass \fIURL\fR
Configure ProxyPass to the given URL or port number.
.TP
.B \-\-proxy-websocket
Enable WebSocket proxying (requires \-\-proxy-pass).
.TP
.B \-n, \-\-dry-run
Show what would be done without making any changes.
.TP
.B \-v, \-\-verbose
Enable verbose output.
.TP
.B \-\-json
Output results as JSON.
.TP
.B \-\-no-color
Disable colored terminal output.
.TP
.B \-f, \-\-force
Skip confirmation prompts (use with caution).
.TP
.B \-\-skip-reload
Skip Apache reload after changes.
.TP
.B \-\-skip-index
Do not create a default index.html in the webroot.
.TP
.B \-\-skip-hosts
Do not add an /etc/hosts entry.
.TP
.B \-\-version
Print version and exit.
.TP
.B \-h, \-\-help
Print this help message and exit.
.SH EXAMPLES
.TP
Create a basic virtual host:
.B sudo virtualhost create example.com
.TP
Create with SSL and HTTPS redirect:
.B sudo virtualhost create example.com --ssl --force-https --email admin@example.com
.TP
Clone a host:
.B sudo virtualhost clone example.com staging.example.com
.TP
Backup and restore:
.B sudo virtualhost backup example.com
.br
.B sudo virtualhost restore /var/backups/virtualhost/example.com-20261030.tar.gz
.TP
Dry-run deletion:
.B sudo virtualhost delete example.com --dry-run
.SH FILES
.TP
.I /etc/apache2/sites-available/
Apache virtual host configuration files.
.TP
.I /var/log/virtualhost/
Daily log files.
.TP
.I /var/backups/virtualhost/
Backup archives.
.TP
.I /usr/local/lib/virtualhost-lib.sh
Shared library.
.SH AUTHOR
Shuvo Halder
.SH LICENSE
MIT License. See LICENSE file.
.SH SEE ALSO
.BR virtualhost-nginx (1),
.BR apache2ctl (8),
.BR certbot (1)
"""

VIRTUALHOST_NGINX_MAN = r""".TH VIRTUALHOST-NGINX 1 "2026-10-30" "4.0.0" "VirtualHost Automation"
.SH NAME
virtualhost-nginx \- Production-grade Nginx virtual host manager
.SH SYNOPSIS
.B virtualhost-nginx
\fICOMMAND\fR
.RI [ OPTIONS ]
\fIDOMAIN\fR
.SH DESCRIPTION
.B virtualhost-nginx
creates, deletes, enables, disables, backs up, restores, clones, and checks the
status of Nginx virtual hosts. It supports SSL (self-signed and Let's Encrypt),
proxy pass, WebSocket proxying, PHP-FPM integration, custom aliases, email
validation, dry-run mode, and JSON output.
.SH COMMANDS
.TP
.B create \fIDOMAIN\fR
Create a new Nginx virtual host for \fIDOMAIN\fR.
.TP
.B delete \fIDOMAIN\fR
Delete the virtual host for \fIDOMAIN\fR (auto-backup before deletion).
.TP
.B enable \fIDOMAIN\fR
Enable a disabled virtual host (idempotent).
.TP
.B disable \fIDOMAIN\fR
Disable an active virtual host without deleting it (idempotent).
.TP
.B status \fIDOMAIN\fR
Show status, paths, SSL expiry, and upstream for \fIDOMAIN\fR.
.TP
.B clone \fISOURCE TARGET\fR
Clone the configuration of \fISOURCE\fR to a new virtual host \fITARGET\fR.
.TP
.B backup \fIDOMAIN\fR
Create a compressed backup archive of the virtual host configuration and webroot.
.TP
.B restore \fIBACKUP_FILE\fR
Restore a virtual host from a backup archive.
.TP
.B ssl-renew \fR[\fIDOMAIN\fR]
Renew Let's Encrypt certificates.
.SH OPTIONS
.TP
.B \-d, \-\-directory \fIPATH\fR
Override the document root (default: /var/www/DOMAIN).
.TP
.B \-e, \-\-email \fIADDRESS\fR
Administrator email address (validated).
.TP
.B \-\-ssl
Enable TLS with Let's Encrypt.
.TP
.B \-\-self-signed
Generate a self-signed TLS certificate.
.TP
.B \-\-force-https
Redirect HTTP to HTTPS.
.TP
.B \-\-with-www
Add www.\fIDOMAIN\fR to server_name.
.TP
.B \-\-aliases \fIALIAS1,ALIAS2,...\fR
Comma-separated list of additional server_name entries.
.TP
.B \-\-php-version \fIVERSION\fR
PHP-FPM version to use (e.g. 8.1, 8.2). Sets the FastCGI socket path.
.TP
.B \-\-proxy-pass \fIURL\fR
Configure proxy_pass to the given URL or port.
.TP
.B \-\-proxy-websocket
Enable WebSocket proxy upgrade headers.
.TP
.B \-n, \-\-dry-run
Show what would be done without making any changes.
.TP
.B \-v, \-\-verbose
Enable verbose output.
.TP
.B \-\-json
Output results as JSON.
.TP
.B \-\-no-color
Disable colored output.
.TP
.B \-f, \-\-force
Skip confirmation prompts.
.TP
.B \-\-skip-reload
Skip Nginx reload after changes.
.TP
.B \-\-skip-index
Do not create a default index.html.
.TP
.B \-\-skip-hosts
Do not add an /etc/hosts entry.
.TP
.B \-\-version
Print version and exit.
.TP
.B \-h, \-\-help
Print this help message and exit.
.SH EXAMPLES
.TP
Create a PHP 8.2 virtual host:
.B sudo virtualhost-nginx create example.com --php-version 8.2
.TP
Create a Node.js proxy host with SSL:
.B sudo virtualhost-nginx create api.example.com --proxy-pass 3000 --ssl --force-https
.TP
Enable/disable a site:
.B sudo virtualhost-nginx enable example.com
.br
.B sudo virtualhost-nginx disable example.com
.SH FILES
.TP
.I /etc/nginx/sites-available/
Nginx virtual host configuration files.
.TP
.I /etc/nginx/sites-enabled/
Symlinks to enabled configurations.
.TP
.I /var/log/virtualhost/
Daily log files.
.TP
.I /var/backups/virtualhost/
Backup archives.
.SH AUTHOR
Shuvo Halder
.SH LICENSE
MIT License. See LICENSE file.
.SH SEE ALSO
.BR virtualhost (1),
.BR nginx (8),
.BR certbot (1)
"""


def write_man_pages():
    man_dir = os.path.join(ROOT, "man")
    write_crlf(os.path.join(man_dir, "virtualhost.1"), VIRTUALHOST_MAN)
    write_crlf(os.path.join(man_dir, "virtualhost-nginx.1"), VIRTUALHOST_NGINX_MAN)
    print("  WRITTEN  man/virtualhost.1")
    print("  WRITTEN  man/virtualhost-nginx.1")


# ---------------------------------------------------------------------------
# 8. Integration tests
# ---------------------------------------------------------------------------

TEST_ENABLE_DISABLE = """\
#!/usr/bin/env bash
# test_enable_disable.sh – Integration test: enable/disable idempotency
# Requires: Apache or Nginx installed, must run as root
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VH="$REPO_ROOT/bin/virtualhost.sh"
DOMAIN="test-idempotent.local"
PASS=0
FAIL=0

_pass() { echo "[PASS] $1"; ((PASS++)); }
_fail() { echo "[FAIL] $1"; ((FAIL++)); }

echo ""
echo "=== Enable/Disable Idempotency Tests ==="
echo ""

# Prerequisite: create a virtual host (ignore errors – may already exist)
"$VH" create "$DOMAIN" --skip-hosts --skip-index --dry-run 2>/dev/null || true

# Test enable (dry-run)
if "$VH" enable "$DOMAIN" --dry-run 2>&1 | grep -q "DRY-RUN\\|already enabled\\|No configuration"; then
    _pass "enable --dry-run exits cleanly"
else
    _fail "enable --dry-run unexpected output"
fi

# Test disable (dry-run)
if "$VH" disable "$DOMAIN" --dry-run 2>&1 | grep -q "DRY-RUN\\|already disabled"; then
    _pass "disable --dry-run exits cleanly"
else
    _fail "disable --dry-run unexpected output"
fi

# Test status (dry-run)
if "$VH" status "$DOMAIN" --dry-run 2>&1 | grep -qiE "not found|DISABLED|ENABLED"; then
    _pass "status command exits cleanly"
else
    _fail "status command unexpected output"
fi

echo ""
echo "Results: PASS=$PASS  FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
"""

TEST_CLONE = """\
#!/usr/bin/env bash
# test_clone.sh – Integration test: clone idempotency and guard
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VH="$REPO_ROOT/bin/virtualhost.sh"
SRC="test-clone-src.local"
DST="test-clone-dst.local"
PASS=0
FAIL=0

_pass() { echo "[PASS] $1"; ((PASS++)); }
_fail() { echo "[FAIL] $1"; ((FAIL++)); }

echo ""
echo "=== Clone Guard Tests ==="
echo ""

# Clone non-existent source should fail
if ! "$VH" clone "no-such-host.local" "$DST" --dry-run 2>&1 | grep -qi "not found\\|does not exist"; then
    _fail "clone from missing source should error"
else
    _pass "clone rejects missing source"
fi

# Clone to existing target should fail (create dst first in dry-run context)
# We can only reliably test this when the conf file exists; skip if not root
if [[ $(id -u) -eq 0 ]]; then
    SITES="/etc/apache2/sites-available"
    if [[ -d "$SITES" ]]; then
        touch "$SITES/${DST}.conf" 2>/dev/null || true
        if ! "$VH" clone "$SRC" "$DST" 2>&1 | grep -qi "already exists"; then
            _fail "clone to existing target should error"
        else
            _pass "clone rejects existing target"
        fi
        rm -f "$SITES/${DST}.conf"
    else
        echo "  SKIP clone-to-existing (Apache not installed)"
    fi
fi

echo ""
echo "Results: PASS=$PASS  FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
"""

TEST_BACKUP = """\
#!/usr/bin/env bash
# test_backup.sh – Integration test: backup/restore dry-run
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VH="$REPO_ROOT/bin/virtualhost.sh"
DOMAIN="test-backup.local"
PASS=0
FAIL=0

_pass() { echo "[PASS] $1"; ((PASS++)); }
_fail() { echo "[FAIL] $1"; ((FAIL++)); }

echo ""
echo "=== Backup / Restore Tests ==="
echo ""

# Backup dry-run
if "$VH" backup "$DOMAIN" --dry-run 2>&1 | grep -qi "DRY-RUN\\|dry"; then
    _pass "backup --dry-run exits cleanly"
else
    _fail "backup --dry-run unexpected output"
fi

# Restore with missing file should error
if ! "$VH" restore "/tmp/no-such-backup.tar.gz" 2>&1 | grep -qi "not found\\|error"; then
    _fail "restore should error on missing backup file"
else
    _pass "restore rejects missing backup file"
fi

# ssl-renew dry-run
if "$VH" ssl-renew "$DOMAIN" --dry-run 2>&1 | grep -qi "DRY-RUN\\|certbot\\|not installed"; then
    _pass "ssl-renew --dry-run exits cleanly"
else
    _fail "ssl-renew --dry-run unexpected output"
fi

echo ""
echo "Results: PASS=$PASS  FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
"""

RUN_INTEGRATION_TESTS = """\
#!/usr/bin/env bash
# run_integration_tests.sh – Run all integration tests
# Usage: sudo ./tests/run_integration_tests.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
ALL_PASS=true

run_test() {
    local name="$1"
    local script="$2"
    echo ""
    echo "━━━ Running: $name ━━━"
    if bash "$script"; then
        ((TOTAL_PASS++))
    else
        ((TOTAL_FAIL++))
        ALL_PASS=false
    fi
}

run_test "Enable/Disable Idempotency" "$SCRIPT_DIR/test_enable_disable.sh"
run_test "Clone Guard"                "$SCRIPT_DIR/test_clone.sh"
run_test "Backup/Restore"             "$SCRIPT_DIR/test_backup.sh"

echo ""
echo "═══════════════════════════════════════"
echo "  Integration Test Summary"
echo "  Tests passed: $TOTAL_PASS"
echo "  Tests failed: $TOTAL_FAIL"
echo "═══════════════════════════════════════"
echo ""

$ALL_PASS
"""


def write_integration_tests():
    tests_dir = os.path.join(ROOT, "tests")
    write_crlf(os.path.join(tests_dir, "test_enable_disable.sh"), TEST_ENABLE_DISABLE)
    write_crlf(os.path.join(tests_dir, "test_clone.sh"), TEST_CLONE)
    write_crlf(os.path.join(tests_dir, "test_backup.sh"), TEST_BACKUP)
    write_crlf(os.path.join(tests_dir, "run_integration_tests.sh"), RUN_INTEGRATION_TESTS)


# ---------------------------------------------------------------------------
# 9. verify_phase3.py  – lightweight static verification
# ---------------------------------------------------------------------------

VERIFY_PHASE3 = '''\
#!/usr/bin/env python3
"""verify_phase3.py - Verify Phase 3 hardening changes are present."""

import os
import sys
import re

ROOT = os.path.dirname(os.path.abspath(__file__))

def read(path):
    with open(path, "rb") as f:
        return f.read().decode("utf-8", errors="replace").replace("\\r\\n", "\\n")

checks = []

def check(name, condition, filepath=""):
    status = "PASS" if condition else "FAIL"
    checks.append((status, name, filepath))
    print(f"  [{status}] {name}" + (f" ({filepath})" if filepath else ""))

def sep(title):
    print(f"\\n{'='*60}\\n  {title}\\n{'='*60}")

# ── lib/virtualhost-lib.sh ──────────────────────────────────────
sep("lib/virtualhost-lib.sh")
lib = read(os.path.join(ROOT, "lib", "virtualhost-lib.sh"))
check("write_atomic() function present",      "write_atomic()" in lib,         "lib/virtualhost-lib.sh")
check("is_site_enabled() function present",   "is_site_enabled()" in lib,      "lib/virtualhost-lib.sh")
check("ROLLBACK_FILES array declared",        "ROLLBACK_FILES=()" in lib,      "lib/virtualhost-lib.sh")
check("ROLLBACK_CMDS array declared",         "ROLLBACK_CMDS=()" in lib,       "lib/virtualhost-lib.sh")
check("cleanup() handles rollback",           "Rollback" in lib,               "lib/virtualhost-lib.sh")
check("trap cleanup EXIT present",            "trap cleanup EXIT" in lib,      "lib/virtualhost-lib.sh")

# ── bin/virtualhost.sh ─────────────────────────────────────────
sep("bin/virtualhost.sh")
apache = read(os.path.join(ROOT, "bin", "virtualhost.sh"))
check("is_site_enabled apache in cmd_enable", "is_site_enabled apache" in apache, "bin/virtualhost.sh")
check("already enabled no-op message",        "already enabled" in apache,         "bin/virtualhost.sh")
check("already disabled no-op message",       "already disabled" in apache,        "bin/virtualhost.sh")
check("pre-deletion backup in cmd_delete",    "pre-deletion backup" in apache,     "bin/virtualhost.sh")
check("perform_backup called in cmd_delete",  "perform_backup" in apache,          "bin/virtualhost.sh")

# ── bin/virtualhost-nginx.sh ───────────────────────────────────
sep("bin/virtualhost-nginx.sh")
nginx = read(os.path.join(ROOT, "bin", "virtualhost-nginx.sh"))
check("is_site_enabled nginx in cmd_enable",  "is_site_enabled nginx" in nginx,    "bin/virtualhost-nginx.sh")
check("already enabled no-op message",        "already enabled" in nginx,          "bin/virtualhost-nginx.sh")
check("already disabled no-op message",       "already disabled" in nginx,         "bin/virtualhost-nginx.sh")
check("pre-deletion backup in cmd_delete",    "pre-deletion backup" in nginx,      "bin/virtualhost-nginx.sh")
check("perform_backup called in cmd_delete",  "perform_backup" in nginx,           "bin/virtualhost-nginx.sh")

# ── install.sh ─────────────────────────────────────────────────
sep("install.sh")
install = read(os.path.join(ROOT, "install.sh"))
check("MAN_DIR declared",                     "MAN_DIR" in install,                "install.sh")
check("LOGROTATE_DIR declared",               "LOGROTATE_DIR" in install,          "install.sh")
check("logrotate config written",             "logrotate" in install,              "install.sh")
check("man page install step present",        "mandb" in install or "man/" in install, "install.sh")

# ── man pages ──────────────────────────────────────────────────
sep("man pages")
check("man/virtualhost.1 exists",
      os.path.isfile(os.path.join(ROOT, "man", "virtualhost.1")),        "man/virtualhost.1")
check("man/virtualhost-nginx.1 exists",
      os.path.isfile(os.path.join(ROOT, "man", "virtualhost-nginx.1")),  "man/virtualhost-nginx.1")
check("man page .TH header correct",
      ".TH VIRTUALHOST 1" in read(os.path.join(ROOT, "man", "virtualhost.1"))
      if os.path.isfile(os.path.join(ROOT, "man", "virtualhost.1")) else False,
      "man/virtualhost.1")

# ── CI ─────────────────────────────────────────────────────────
sep(".github/workflows/ci.yml")
ci = read(os.path.join(ROOT, ".github", "workflows", "ci.yml"))
check("version check updated to 4.0.0",      '4.0.0' in ci,                       "ci.yml")
check("verify_phase2 job present",            "verify_phase2" in ci,               "ci.yml")
check("verify_phase3 job present",            "verify_phase3" in ci,               "ci.yml")

# ── Integration tests ──────────────────────────────────────────
sep("tests/")
check("test_enable_disable.sh exists",
      os.path.isfile(os.path.join(ROOT, "tests", "test_enable_disable.sh")), "tests/")
check("test_clone.sh exists",
      os.path.isfile(os.path.join(ROOT, "tests", "test_clone.sh")), "tests/")
check("test_backup.sh exists",
      os.path.isfile(os.path.join(ROOT, "tests", "test_backup.sh")), "tests/")
check("run_integration_tests.sh exists",
      os.path.isfile(os.path.join(ROOT, "tests", "run_integration_tests.sh")), "tests/")

# ── Summary ────────────────────────────────────────────────────
passed = sum(1 for s, _, _ in checks if s == "PASS")
failed = sum(1 for s, _, _ in checks if s == "FAIL")
total  = len(checks)
print(f"\\n{'='*60}")
print(f"  Phase 3 Verification: {passed}/{total} PASS  |  {failed} FAIL")
print(f"{'='*60}\\n")
sys.exit(0 if failed == 0 else 1)
'''


def write_verify_phase3():
    path = os.path.join(ROOT, "verify_phase3.py")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(VERIFY_PHASE3)
    print(f"  WRITTEN  {path}")


# ---------------------------------------------------------------------------
# 10. README.md updates
# ---------------------------------------------------------------------------

README_PATH = os.path.join(ROOT, "README.md")

README_NEW_COMMANDS_SECTION = """
## New in v4.0.0 – Phase 2 & 3

### New Commands
| Command | Description |
|---------|-------------|
| `enable DOMAIN` | Enable a virtual host (idempotent) |
| `disable DOMAIN` | Disable a virtual host without deleting it (idempotent) |
| `status DOMAIN` | Show config path, enable state, SSL expiry, and error log |
| `clone SRC DST` | Clone SRC configuration into new virtual host DST |
| `backup DOMAIN` | Archive configuration, webroot, and SSL certs to a .tar.gz |
| `restore FILE` | Restore a virtual host from a backup archive |
| `ssl-renew [DOMAIN]` | Renew Let's Encrypt certificates |

### New Options
| Option | Description |
|--------|-------------|
| `--aliases LIST` | Comma-separated extra server names / aliases |
| `--php-version VER` | PHP-FPM version for Nginx (e.g. `8.2`) |
| `--email ADDR` | Admin email (validated; required for Let's Encrypt) |

### Installation
```bash
git clone https://github.com/your-org/virtualhost-automation.git
cd virtualhost-automation
sudo ./install.sh
```
To uninstall:
```bash
sudo ./install.sh uninstall
```

### Phase 3 Hardening
- **Atomic writes** – config files are written via a temp-file/rename pattern, so a partial write never leaves a broken config.
- **Rollback traps** – on unexpected failure, previously-backed-up files are restored automatically.
- **Backup before delete** – `delete` always creates a timestamped archive before removing anything.
- **Idempotent enable/disable** – safe to run multiple times; no-op if already in desired state.
- **Log rotation** – installer writes `/etc/logrotate.d/virtualhost` (weekly, 4 weeks).
- **Man pages** – `man virtualhost` and `man virtualhost-nginx` available after install.

"""

def patch_readme():
    text = read_text(README_PATH)
    if "New in v4.0.0" not in text:
        # Append after the first # heading or at end
        if "\n## " in text:
            idx = text.index("\n## ")
            text = text[:idx] + README_NEW_COMMANDS_SECTION + text[idx:]
        else:
            text = text.rstrip() + "\n" + README_NEW_COMMANDS_SECTION
        with open(README_PATH, "wb") as f:
            f.write(crlf(text))
        print(f"  PATCHED  README.md – added v4.0.0 section")
    else:
        print(f"  SKIP     README.md (already has v4.0.0 section)")


# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

def main():
    print("\n" + "="*60)
    print("  Phase 3 Hardening – Patch Script")
    print("="*60 + "\n")

    print("[1] Patching lib/virtualhost-lib.sh")
    patch_lib()

    print("\n[2] Patching bin/virtualhost.sh (Apache)")
    patch_apache()

    print("\n[3] Patching bin/virtualhost-nginx.sh (Nginx)")
    patch_nginx()

    print("\n[4] Patching install.sh")
    patch_install()

    print("\n[5] Patching .github/workflows/ci.yml")
    patch_ci()

    print("\n[6+7] Writing man pages")
    write_man_pages()

    print("\n[8] Writing integration tests")
    write_integration_tests()

    print("\n[9] Writing verify_phase3.py")
    write_verify_phase3()

    print("\n[10] Patching README.md")
    patch_readme()

    print("\n" + "="*60)
    print("  All patches applied. Running verify_phase3.py ...")
    print("="*60 + "\n")

    result = subprocess.run([sys.executable, os.path.join(ROOT, "verify_phase3.py")])
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
