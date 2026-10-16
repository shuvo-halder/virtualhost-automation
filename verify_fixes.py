#!/usr/bin/env python3
"""Verify all Phase-1 bug fixes were applied correctly."""
import sys

def check(path, patterns):
    with open(path, 'rb') as f:
        c = f.read().decode('utf-8')
    ok = True
    for label, pat, should_exist in patterns:
        found = pat in c
        status = 'OK' if found == should_exist else 'FAIL'
        if status == 'FAIL':
            ok = False
        print(f"  [{'OK' if status == 'OK' else 'FAIL'}] {label}")
    return ok

print('=== lib/virtualhost-lib.sh ===')
check('lib/virtualhost-lib.sh', [
    ('init_colors() defined', 'init_colors() {', True),
    ('readonly C_RED removed', 'readonly C_RED', False),
    ('web_group fix applied', 'using $web_group)', True),
    ('web_user bug removed', 'using $web_user)', False),
    ('normalize_proxy_pass returns 0', "# Unrecognized format", True),
    ('add_hosts_entry independent www', 'Add www. alias independently', True),
    ('remove_hosts_entry uses escaped_domain', 'escaped_domain', True),
    ('check_proxy_backend detects scheme', 'default_port=443', True),
    ('curl uses original proxy_url', 'connect-timeout 2 "$proxy_url"', True),
])

print('')
print('=== bin/virtualhost.sh ===')
check('bin/virtualhost.sh', [
    ('init_colors called in main', 'init_colors', True),
    ('force-https guard present', '--force-https requires --self-signed', True),
    ('create_apache_conf FORCE_HTTPS wrap', 'Only write full HTTP block when NOT force-redirecting', True),
    ('proxy conf FORCE_HTTPS wrap', 'Only write full HTTP proxy block', True),
    ('cmd_delete webroot before delete', 'Capture webroot NOW, before the config file is deleted', True),
])

print('')
print('=== bin/virtualhost-nginx.sh ===')
check('bin/virtualhost-nginx.sh', [
    ('email arg -e added to nginx parser', '-e|--email)', True),
    ('init_colors called in nginx main', 'init_colors', True),
    ('force-https guard in nginx', '--force-https requires --self-signed', True),
    ('.conf extension in create_nginx_conf', 'SITES_AVAILABLE/${domain}.conf', True),
    ('.conf extension in enable_site', 'SITES_ENABLED/${domain}.conf', True),
    ('list_hosts glob uses *.conf', 'SITES_ENABLED"/*.conf', True),
    ('basename strips .conf', 'basename "$site" .conf', True),
    ('cmd_delete webroot before delete', 'Capture webroot NOW, before the config file is deleted', True),
    ('FORCE_HTTPS wrap in nginx conf', 'Only write full HTTP block when NOT force-redirecting', True),
    ('FORCE_HTTPS wrap in nginx proxy conf', 'Only write full HTTP proxy block when NOT force-redirecting', True),
    ('fastcgi duplicate removed (no include fastcgi_params + split_path)', 'include fastcgi_params;\n        fastcgi_split_path_info', False),
    ('snippets/fastcgi-php.conf still present', 'include snippets/fastcgi-php.conf;', True),
])

print('')
print('=== .github/workflows/ci.yml ===')
check('.github/workflows/ci.yml', [
    ('ShellCheck pinned to 2.0.0', 'action-shellcheck@2.0.0', True),
    ('floating @master removed', 'action-shellcheck@master', False),
])
