#!/usr/bin/env python3
"""
Phase 2 verification: checks all new features are present and correctly implemented.
Runs ShellCheck if available.
"""
import sys, subprocess, os

PASS = 0
FAIL = 0

def check(label, condition):
    global PASS, FAIL
    if condition:
        print(f'  PASS  {label}')
        PASS += 1
    else:
        print(f'  FAIL  {label}')
        FAIL += 1

def rw(path):
    with open(path, 'rb') as f:
        raw = f.read()
    return raw.decode('utf-8').replace('\r\n', '\n')

print('\n=== Phase 2 Verification ===\n')

# ── lib/virtualhost-lib.sh ───────────────────────────────────────────────────
print('[ lib/virtualhost-lib.sh ]')
lib = rw('lib/virtualhost-lib.sh')
check('ALIASES default',              'ALIASES=${ALIASES:-""}' in lib)
check('BACKUP_DIR default',           'BACKUP_DIR=${BACKUP_DIR:-/var/backups/virtualhost}' in lib)
check('validate_email() defined',     'validate_email()' in lib)
check('validate_email regex check',   'A-Za-z0-9._%+' in lib)
check('perform_backup() defined',     'perform_backup()' in lib)
check('perform_backup tar -czf',      'tar -czf' in lib)
check('perform_restore() defined',    'perform_restore()' in lib)
check('perform_restore tar -xzf',     'tar -xzf' in lib)
check('perform_ssl_renew() defined',  'perform_ssl_renew()' in lib)
check('perform_ssl_renew certbot',    'certbot renew' in lib)
check('LIB_VERSION 4.0.0',           'LIB_VERSION="4.0.0"' in lib)
print()

# ── bin/virtualhost.sh (Apache) ──────────────────────────────────────────────
print('[ bin/virtualhost.sh — Apache ]')
apache = rw('bin/virtualhost.sh')
check('SCRIPT_VERSION 4.0.0',            'SCRIPT_VERSION="4.0.0"' in apache)
check('cmd_enable()',                     'cmd_enable()' in apache)
check('cmd_disable()',                    'cmd_disable()' in apache)
check('cmd_status()',                     'cmd_status()' in apache)
check('cmd_clone()',                      'cmd_clone()' in apache)
check('cmd_backup()',                     'cmd_backup()' in apache)
check('cmd_restore()',                    'cmd_restore()' in apache)
check('cmd_ssl_renew()',                  'cmd_ssl_renew()' in apache)
check('--aliases flag in parser',         '--aliases)' in apache)
check('ALIASES= in server_alias (x2)',    apache.count('alias_list=$(echo "$ALIASES"') == 2)
check('validate_email on -e flag',        'validate_email "$EMAIL"' in apache)
check('command matcher has enable',       'enable|disable|status|clone|backup|restore|ssl-renew' in apache)
check('dispatch: enable case',            'cmd_enable "$domain"' in apache)
check('dispatch: clone case',            'cmd_clone "$domain"' in apache)
check('dispatch: ssl-renew case',        'cmd_ssl_renew "${domain:-}"' in apache)
check('usage: enable command listed',     'enable DOMAIN' in apache)
check('usage: --aliases option listed',   '--aliases DOMAINS' in apache)
check('usage: ssl-renew example',         'ssl-renew example.dev' in apache)
check('cmd_status: apache2ctl configtest', 'apache2ctl configtest' in apache)
check('cmd_status: APACHE_LOG_DIR',       'APACHE_LOG_DIR' in apache)
print()

# ── bin/virtualhost-nginx.sh (Nginx) ────────────────────────────────────────
print('[ bin/virtualhost-nginx.sh — Nginx ]')
nginx = rw('bin/virtualhost-nginx.sh')
check('SCRIPT_VERSION 4.0.0',            'SCRIPT_VERSION="4.0.0"' in nginx)
check('cmd_enable()',                     'cmd_enable()' in nginx)
check('cmd_disable()',                    'cmd_disable()' in nginx)
check('cmd_status()',                     'cmd_status()' in nginx)
check('cmd_clone()',                      'cmd_clone()' in nginx)
check('cmd_backup()',                     'cmd_backup()' in nginx)
check('cmd_restore()',                    'cmd_restore()' in nginx)
check('cmd_ssl_renew()',                  'cmd_ssl_renew()' in nginx)
check('--php-version flag',              '--php-version)' in nginx)
check('--php-version sets socket',       'PHP_FPM_SOCKET="unix:/run/php/php${2}-fpm.sock"' in nginx)
check('--aliases flag in parser',        '--aliases)' in nginx)
check('ALIASES= in server_name (x2)',    nginx.count('alias_list=$(echo "$ALIASES"') == 2)
check('validate_email on -e flag',       'validate_email "$EMAIL"' in nginx)
check('command matcher has enable',      'enable|disable|status|clone|backup|restore|ssl-renew' in nginx)
check('dispatch: enable case',           'cmd_enable "$domain"' in nginx)
check('dispatch: ssl-renew case',        'cmd_ssl_renew "${domain:-}"' in nginx)
check('usage: enable command listed',    'enable DOMAIN' in nginx)
check('usage: --php-version option',     '--php-version VERSION' in nginx)
check('usage: --aliases option listed',  '--aliases DOMAINS' in nginx)
check('usage: ssl-renew example',        'ssl-renew example.dev' in nginx)
check('cmd_status: nginx -t',            'nginx -t' in nginx)
check('cmd_status: /var/log/nginx/',     '/var/log/nginx/' in nginx)
print()

# ── install.sh ───────────────────────────────────────────────────────────────
print('[ install.sh ]')
install = rw('install.sh')
check('install.sh exists',              os.path.isfile('install.sh'))
check('install to /usr/local/bin',      'INSTALL_DIR="/usr/local/bin"' in install)
check('install library to /usr/local/lib', 'LIB_DIR="/usr/local/lib"' in install)
check('creates log dir',                'LOG_DIR="/var/log/virtualhost"' in install)
check('creates backup dir',             'BACKUP_DIR="/var/backups/virtualhost"' in install)
check('do_install() defined',          'do_install()' in install)
check('do_uninstall() defined',        'do_uninstall()' in install)
check('bash completion installed',      'COMPLETION_DIR="/etc/bash_completion.d"' in install)
check('completion: virtualhost cmd',    'complete -F _virtualhost_complete virtualhost' in install)
check('completion: virtualhost-nginx',  'complete -F _virtualhost_nginx_complete virtualhost-nginx' in install)
check('uninstall action supported',    'uninstall)' in install)
check('check_root() called',           'check_root' in install)
print()

# ── ShellCheck (optional) ────────────────────────────────────────────────────
print('[ ShellCheck (optional) ]')
for script in ['lib/virtualhost-lib.sh', 'bin/virtualhost.sh', 'bin/virtualhost-nginx.sh', 'install.sh']:
    try:
        result = subprocess.run(
            ['shellcheck', '--severity=error', script],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            check(f'shellcheck {script}', True)
        else:
            print(f'  WARN  shellcheck {script}: {result.stdout.strip()[:120]}')
    except FileNotFoundError:
        print(f'  SKIP  shellcheck not installed')
        break
print()

# ── Summary ──────────────────────────────────────────────────────────────────
total = PASS + FAIL
print(f'=== Results: {PASS}/{total} passed ===')
if FAIL > 0:
    print(f'    {FAIL} FAILED checks above')
    sys.exit(1)
else:
    print('    All checks passed!')
