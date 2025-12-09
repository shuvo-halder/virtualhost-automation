#!/usr/bin/env bash
# create_virtualhost.sh
# Usage: sudo ./create_virtualhost.sh create|delete domain [rootDir]
# Clean, safe and optimized script to create or remove nginx virtual hosts

set -o errexit
set -o nounset
set -o pipefail
IFS=$'\n\t'

# --- Defaults ---
ACTION=${1:-}
DOMAIN=${2:-}
USER_PROVIDED_ROOT=${3:-}
SITES_AVAILABLE='/etc/nginx/sites-available'
SITES_ENABLED='/etc/nginx/sites-enabled'
DEFAULT_WEB_ROOT='/var/www'
PHP_FPM_SOCKET='127.0.0.1:9000' # change to unix:/run/php/php8.1-fpm.sock if needed
WEB_USER='www-data'
WEB_GROUP='www-data'

# --- Helpers ---
err() { echo "ERROR: $*" >&2; }
info() { echo "INFO: $*"; }
usage() {
  cat <<EOF
Usage: sudo $0 create|delete domain [rootDir]
Examples:
  sudo $0 create example.test         # creates /var/www/example
  sudo $0 create example.test site1   # creates /var/www/site1
  sudo $0 delete example.test
EOF
  exit 2
}

# Ensure run as root
if [[ $(id -u) -ne 0 ]]; then
  err "This script must be run as root (use sudo)"
  exit 1
fi

# Validate action
if [[ -z "$ACTION" || -z "$DOMAIN" ]]; then
  usage
fi

if [[ "$ACTION" != "create" && "$ACTION" != "delete" ]]; then
  err "Action must be 'create' or 'delete'"
  usage
fi

# Basic domain validation (letters, digits, hyphen, dot)
if ! [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]]; then
  err "Domain contains invalid characters"
  exit 1
fi

# Determine owner (the real user who invoked sudo)
OWNER=${SUDO_USER:-}
if [[ -z "$OWNER" ]]; then
  # fallback to logname or root
  OWNER=$(logname 2>/dev/null || echo "root")
fi

# Determine root dir
if [[ -n "$USER_PROVIDED_ROOT" ]]; then
  # If user provided an absolute path, use it as-is
  if [[ "$USER_PROVIDED_ROOT" == /* ]]; then
    ROOT_DIR="$USER_PROVIDED_ROOT"
  else
    ROOT_DIR="$DEFAULT_WEB_ROOT/$USER_PROVIDED_ROOT"
  fi
else
  # default: strip dots from domain (example.com -> examplecom)
  SAFE_NAME=${DOMAIN//./}
  ROOT_DIR="$DEFAULT_WEB_ROOT/$SAFE_NAME"
fi

# Quote helper for paths
q() { printf '%s' "$1"; }

# Function: add host to /etc/hosts (avoid duplicates)
add_hosts_entry() {
  local ip='127.0.0.1'
  if grep -Eq "^[[:space:]]*${ip}[[:space:]]+${DOMAIN}[[:space:]]*$" /etc/hosts; then
    info "/etc/hosts already contains ${DOMAIN}"
  else
    echo -e "${ip}\t${DOMAIN}" >> /etc/hosts
    info "Added ${DOMAIN} to /etc/hosts"
  fi
}

# Function: remove host entry
remove_hosts_entry() {
  # remove any line that contains the exact domain token
  sed -i.bak -E "/(^|\s)${DOMAIN}(\s|\$)/d" /etc/hosts || true
  info "Removed ${DOMAIN} from /etc/hosts (if existed). Backup saved to /etc/hosts.bak"
}

# Function: create nginx config
create_nginx_conf() {
  local conf_path="$SITES_AVAILABLE/$DOMAIN"
  if [[ -e "$conf_path" ]]; then
    err "Nginx config already exists at $conf_path"
    return 1
  fi

  cat > "$conf_path" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root ${ROOT_DIR};

    index index.php index.html index.htm;

    # Serve static files directly with caching
    location ~* \.\
(jpg|jpeg|gif|css|png|js|ico|html|svg|woff|woff2|ttf)
    {
        access_log off;
        expires max;
        add_header Cache-Control "public";
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
        fastcgi_pass ${PHP_FPM_SOCKET};
        fastcgi_index index.php;
        include snippets/fastcgi-php.conf;
    }

    # Deny access to hidden files
    location ~ /\.|^\. {
        deny all;
    }

    error_log /var/log/nginx/${DOMAIN}_error.log;
    access_log /var/log/nginx/${DOMAIN}_access.log;
}
EOF

  info "Wrote nginx config to $conf_path"
}

# Function: enable site (symlink)
enable_site() {
  local conf_path="$SITES_AVAILABLE/$DOMAIN"
  local link_path="$SITES_ENABLED/$DOMAIN"
  if [[ -L "$link_path" || -e "$link_path" ]]; then
    err "Site already enabled: $link_path"
    return 1
  fi
  ln -s "$conf_path" "$link_path"
  info "Enabled site: $link_path"
}

# Function: disable site
disable_site() {
  local link_path="$SITES_ENABLED/$DOMAIN"
  if [[ -L "$link_path" || -e "$link_path" ]]; then
    rm -f "$link_path"
    info "Disabled site: $link_path"
  else
    info "Site not enabled: $link_path"
  fi
}

# Function: restart nginx safely
reload_nginx() {
  if nginx -t; then
    systemctl reload nginx || systemctl restart nginx
    info "Nginx reloaded"
  else
    err "Nginx configuration test failed. Please check /etc/nginx/sites-available/${DOMAIN}"
    return 1
  fi
}

# ----------------------
# ACTION: CREATE
# ----------------------
if [[ "$ACTION" == "create" ]]; then
  info "Creating virtual host for ${DOMAIN} with root ${ROOT_DIR}"

  # create webroot
  if [[ ! -d "$ROOT_DIR" ]]; then
    mkdir -p -- "$ROOT_DIR"
    info "Created directory $ROOT_DIR"
  else
    info "Directory already exists: $ROOT_DIR"
  fi

  chmod 755 -- "$ROOT_DIR"
  chown -R "${OWNER}:${WEB_GROUP}" -- "$ROOT_DIR" || chown -R "${WEB_USER}:${WEB_GROUP}" -- "$ROOT_DIR"

  # Add a safe phpinfo test file (only if not exists)
  if [[ ! -e "$ROOT_DIR/phpinfo.php" ]]; then
    cat > "$ROOT_DIR/phpinfo.php" <<'PHP'
<?php
// Temporary phpinfo for verification. Remove in production.
phpinfo();
PHP
    info "Added phpinfo.php to $ROOT_DIR"
  else
    info "phpinfo.php already present"
  fi

  # create nginx conf
  create_nginx_conf

  # enable site
  enable_site

  # add host entry
  add_hosts_entry

  # test & reload nginx
  reload_nginx

  info "Complete! Visit http://${DOMAIN} (ensure your browser resolves .test/.local to 127.0.0.1 if needed)"
  exit 0
fi

# ----------------------
# ACTION: DELETE
# ----------------------
if [[ "$ACTION" == "delete" ]]; then
  info "Removing virtual host ${DOMAIN}"

  # disable site
  disable_site

  # remove nginx config
  local_conf="$SITES_AVAILABLE/$DOMAIN"
  if [[ -e "$local_conf" ]]; then
    rm -f -- "$local_conf"
    info "Removed $local_conf"
  else
    info "Nginx config not found: $local_conf"
  fi

  # remove host entry
  remove_hosts_entry

  # reload nginx
  if nginx -t; then
    systemctl reload nginx || systemctl restart nginx
    info "Nginx reloaded"
  else
    # If test fails after removal, try restarting to ensure nginx uses remaining config
    systemctl restart nginx || true
    info "Attempted to restart nginx"
  fi

  # ask to remove webroot
  if [[ -d "$ROOT_DIR" ]]; then
    echo -n "Delete webroot ${ROOT_DIR}? [y/N]: "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      rm -rf -- "$ROOT_DIR"
      info "Removed webroot $ROOT_DIR"
    else
      info "Kept webroot $ROOT_DIR"
    fi
  else
    info "Webroot not found: $ROOT_DIR"
  fi

  info "Complete: ${DOMAIN} removed"
  exit 0
fi
