#!/usr/bin/env bash
# apache_virtualhost.sh — Clean & Safe Apache VirtualHost Creator/Remover
# Usage: sudo ./apache_virtualhost.sh create|delete domain [rootDir]

set -o errexit
set -o nounset
set -o pipefail
IFS=$'\n\t'

ACTION=${1:-}
DOMAIN=${2:-}
USER_ROOT=${3:-}
EMAIL="webmaster@localhost"
SITES_AVAILABLE="/etc/apache2/sites-available"
SITES_ENABLED="/etc/apache2/sites-enabled"
DEFAULT_WEBROOT="/var/www"
CONF_FILE="$SITES_AVAILABLE/$DOMAIN.conf"

err() { echo "ERROR: $*" >&2; }
info() { echo "INFO: $*"; }
usage() {
  echo "Usage: sudo $0 create|delete domain [rootDir]";
  exit 2;
}

# Must run as root
if [[ $(id -u) -ne 0 ]]; then
  err "Run as root (use sudo)"; exit 1;
fi

# Validate ACTION & DOMAIN
[[ -z "$ACTION" || -z "$DOMAIN" ]] && usage
[[ "$ACTION" != "create" && "$ACTION" != "delete" ]] && usage
[[ ! "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] && { err "Invalid domain"; exit 1; }

# Identify original sudo user
OWNER=${SUDO_USER:-}
[[ -z "$OWNER" ]] && OWNER=$(logname 2>/dev/null || echo "root")

# Decide webroot
if [[ -n "$USER_ROOT" ]]; then
  if [[ "$USER_ROOT" == /* ]]; then
    ROOT_DIR="$USER_ROOT"
  else
    ROOT_DIR="$DEFAULT_WEBROOT/$USER_ROOT"
  fi
else
  SAFE=${DOMAIN//./}
  ROOT_DIR="$DEFAULT_WEBROOT/$SAFE"
fi

# Add entry to /etc/hosts (safe, no duplicate)
add_hosts() {
  local ip="127.0.0.1"
  if grep -Eq "^[[:space:]]*$ip[[:space:]]+$DOMAIN[[:space:]]*$" /etc/hosts; then
    info "$DOMAIN already in /etc/hosts"
  else
    echo -e "$ip\t$DOMAIN" >> /etc/hosts
    info "Added $DOMAIN to /etc/hosts"
  fi
}

remove_hosts() {
  sed -i.bak -E "/(^|\s)$DOMAIN(\s|\$)/d" /etc/hosts || true
  info "Removed $DOMAIN from hosts (backup: /etc/hosts.bak)"
}

# Create Apache configuration
create_conf() {
  if [[ -e "$CONF_FILE" ]]; then err "Config exists: $CONF_FILE"; exit 1; fi

  cat > "$CONF_FILE" <<EOF
<VirtualHost *:80>
    ServerAdmin $EMAIL
    ServerName $DOMAIN
    ServerAlias $DOMAIN

    DocumentRoot $ROOT_DIR

    <Directory $ROOT_DIR>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-access.log combined
</VirtualHost>
EOF

  info "Created config: $CONF_FILE"
}

# Reload Apache safely
reload_apache() {
  apache2ctl configtest
  systemctl reload apache2 || systemctl restart apache2
  info "Apache reloaded"
}

# ---------------- CREATE ----------------
if [[ "$ACTION" == "create" ]]; then
  info "Creating VirtualHost for $DOMAIN at $ROOT_DIR"

  # Create webroot
  if [[ ! -d "$ROOT_DIR" ]]; then
    mkdir -p "$ROOT_DIR"
    chmod 755 "$ROOT_DIR"
    info "Created directory $ROOT_DIR"

    # Add test php file
    cat > "$ROOT_DIR/phpinfo.php" <<'PHP'
<?php phpinfo();
PHP
    info "Added phpinfo.php"
  else
    info "Directory exists: $ROOT_DIR"
  fi

  # Ownership
  chown -R "$OWNER:$OWNER" "$ROOT_DIR"

  # Config
  create_conf

  # Enable site
  a2ensite "$DOMAIN.conf" >/dev/null
  info "Enabled site $DOMAIN"

  add_hosts
  reload_apache

  info "Complete! Visit: http://$DOMAIN"
  exit 0
fi

# ---------------- DELETE ----------------
if [[ "$ACTION" == "delete" ]]; then
  info "Deleting VirtualHost $DOMAIN"

  if [[ ! -e "$CONF_FILE" ]]; then
    err "Domain does not exist: $DOMAIN"; exit 1;
  fi

  a2dissite "$DOMAIN.conf" >/dev/null || true
  info "Disabled site"

  rm -f "$CONF_FILE"
  info "Removed config file"

  remove_hosts
  reload_apache

  # Ask for webroot deletion
  if [[ -d "$ROOT_DIR" ]]; then
    read -rp "Delete directory $ROOT_DIR? [y/N]: " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
      rm -rf "$ROOT_DIR"
      info "Deleted $ROOT_DIR"
    else
      info "Kept webroot"
    fi
  fi

  info "Removed VirtualHost $DOMAIN"
  exit 0
fi
