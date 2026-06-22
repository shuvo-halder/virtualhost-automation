# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-06-23

### Added
- **SSL/HTTPS Support** — Both Apache and Nginx scripts now support:
  - Let's Encrypt SSL certificates via `-l, --letsencrypt` flag
  - Self-signed SSL certificates via `--self-signed` flag
  - HTTP→HTTPS redirect via `--force-https` flag
  - SSL-enabled virtual host templates (port 443 with security headers)
- **New CLI Options:**
  - `--force` — Skip confirmation prompts for non-interactive operations
  - `--no-index` — Skip creation of test files (phpinfo.php, index.html)
  - `--no-hosts` — Skip /etc/hosts modification
  - `--with-www` — Create ServerAlias/server_name with www. prefix
  - `--json` — JSON output format for `list` command
  - `--no-color` — Disable colored output
- **PHP-FPM Auto-Detection** (Nginx) — Automatically detects installed PHP-FPM versions (8.4 through 7.0)
- **Shared Library** (`lib/virtualhost-lib.sh`) — Common functions extracted for DRY codebase
- **JSON Output** — `list` command now supports `--json` flag for programmatic consumption
- **Colored Output** — Color-coded messages (red for errors, green for success, yellow for warnings, blue for info, cyan for verbose)
- **Cleanup Trap** — Automatic cleanup on script failure
- **CI Workflow** — GitHub Actions CI configuration for ShellCheck validation
- **Test Files** — Basic test scripts for both Apache and Nginx managers
- **CHANGELOG.md** — Proper version tracking

### Changed
- **Repository Structure** — Reorganized into `bin/`, `lib/`, `locale/`, `tests/` directories
- **Root Scripts** — Now act as wrappers that delegate to `bin/` versions
- **index.html Template** — Modernized with gradient background, responsive design, and better styling
- **Documentation** — Updated for all new v3.0.0 features

### Fixed
- **Apache Ownership Bug** — `create_webroot()` now uses `$owner:$WEB_GROUP` instead of `$owner:$owner` (line 478 in v2.0.0)
- **Outdated Locale Templates** — `.pot` files regenerated to match v3.0.0 codebase

### Security
- SSL virtual host templates include HSTS, X-Content-Type-Options, and X-Frame-Options headers
- Self-signed certificates use 2048-bit RSA keys
- HTTPS configurations use TLSv1.2 and TLSv1.3 only

## [2.0.0] - 2026-05-05

### Added
- Comprehensive help system (`--help`, `--version`)
- Dry-run mode (`-d`) for safe testing
- Verbose logging (`-v`) for debugging
- Centralized logging system
- Domain validation and error handling
- List command to show all virtual hosts
- Skip-reload option for batch operations
- Custom PHP-FPM socket support (Nginx)
- Custom admin email support (Apache)
- Complete documentation overhaul

### Changed
- Enhanced security features
- Performance improvements

## [1.0.0] - 2023-09-21

### Added
- Initial release
- Basic create/delete functionality
- Apache and Nginx support