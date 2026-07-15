# Virtualhost Automation v3.0.0

> **Production-Grade Virtual Host Manager for Apache & Nginx on Ubuntu/Debian**

Bash scripts to safely create and manage Apache/Nginx virtual hosts on Ubuntu/Debian servers with professional features like SSL/HTTPS, Let's Encrypt, logging, dry-run mode, validation, JSON output, and comprehensive documentation.

---

## ✨ Features

### Core Features
- ✅ **Create Virtual Hosts** — Automated setup with best practices
- ✅ **Delete Virtual Hosts** — Safe removal with backup options
- ✅ **List All Hosts** — View all active virtual hosts
- ✅ **DNS Management** — Automatic /etc/hosts entries
- ✅ **Domain Validation** — Strict input validation
- ✅ **Permission Management** — Proper ownership and permissions
- ✅ **Test Files** — Auto-generated phpinfo.php and index.html

### 🆕 v3.0.0 New Features
- 🔒 **SSL/HTTPS Support** — Let's Encrypt (`-l`) and self-signed (`--self-signed`) certificates
- 🔄 **HTTP→HTTPS Redirect** — Force all traffic to HTTPS with `--force-https`
- 🌐 **www Alias** — Create ServerAlias with www. prefix via `--with-www`
- ⚡ **Non-Interactive Mode** — Skip prompts with `--force` flag
- 📋 **JSON Output** — Machine-readable output for `list --json`
- 🎨 **Colored Output** — Color-coded messages (disable with `--no-color`)
- 🧩 **Shared Library** — DRY codebase with `lib/virtualhost-lib.sh`
- 🔍 **PHP-FPM Auto-Detection** (Nginx) — Automatically detects installed PHP versions
- 🚫 **Skip Options** — `--no-index` and `--no-hosts` for fine-grained control

### Production Features
- 🔐 **Security Hardened** — Deny hidden files, proper permissions, SSL security headers
- 📝 **Comprehensive Logging** — All operations logged to `/var/log/virtualhost/`
- 🔍 **Verbose Mode** — Detailed output with `-v` flag
- 🎯 **Dry-Run Mode** — Preview changes with `-d` flag without executing
- 💾 **Backups** — Automatic backups of modified system files
- ⚡ **Performance** — Gzip compression, caching headers, static file optimization
- 🐛 **Error Handling** — Graceful error messages and recovery
- 📚 **Help System** — Full `--help` and `--version` commands

### Apache-Specific
- `mod_rewrite` enabled by default
- Framework-ready configuration (Laravel, WordPress, Drupal)
- Gzip compression enabled
- Deny access to hidden files
- Error/Access logging per domain
- SSL virtual host with HSTS and security headers

### Nginx-Specific
- PHP-FPM socket support (TCP & Unix)
- Auto-detection of installed PHP-FPM versions
- Static file caching with 30-day expiry
- Security hardening (deny hidden files)
- Fastcgi parameters optimization
- Per-domain error/access logging
- SSL server block with HTTP/2 support

### 🆕 v3.1.0 Proxy Pass Features
- 🔄 **Reverse Proxy** — Proxy pass to any backend server (Node.js, React, Next.js, Vue, etc.)
- 🔌 **WebSocket Support** — WebSocket proxy with `--proxy-websocket` flag
- 🚀 **Framework Ready** — Works with Express, Next.js, Nuxt, React dev server, Vite, and more
- ⚡ **Performance Optimized** — Proper proxy buffers, timeouts, and header forwarding
- 🔒 **SSL with Proxy** — Full SSL/HTTPS support for proxied backends
- 🧩 **Backend Health Check** — Validates backend is reachable before creating config
- 📋 **Auto Module Detection** — Warns if required proxy modules are missing (Apache)

---

## 📋 Requirements

- Ubuntu 18.04+ or Debian 9+
- Apache 2.4+ or Nginx 1.14+
- PHP 7.0+ (optional, for phpinfo test)
- Sudo access (root privileges)
- Bash 4.0+
- OpenSSL (for self-signed certificates)
- Certbot (optional, for Let's Encrypt)

### For Apache:
```bash
sudo apt-get install apache2 apache2-utils php libapache2-mod-php
sudo a2enmod rewrite ssl headers
```

### For Nginx:
```bash
sudo apt-get install nginx php-fpm
```

---

## 📦 Installation

### Method 1: Clone Repository (Recommended)
```bash
git clone https://github.com/shuvo-halder/virtualhost-automation.git
cd virtualhost-automation
chmod +x bin/virtualhost.sh bin/virtualhost-nginx.sh lib/virtualhost-lib.sh

# Optional: Link to PATH
sudo ln -s $(pwd)/bin/virtualhost.sh /usr/local/bin/virtualhost
sudo ln -s $(pwd)/bin/virtualhost-nginx.sh /usr/local/bin/virtualhost-nginx
```

### Method 2: Quick Install
```bash
# Download and install both scripts globally
cd /usr/local/bin

# Apache
sudo wget https://raw.githubusercontent.com/shuvo-halder/virtualhost-automation/master/bin/virtualhost.sh
sudo chmod +x virtualhost.sh
sudo ln -s virtualhost.sh virtualhost

# Nginx
sudo wget https://raw.githubusercontent.com/shuvo-halder/virtualhost-automation/master/bin/virtualhost-nginx.sh
sudo chmod +x virtualhost-nginx.sh
sudo ln -s virtualhost-nginx.sh virtualhost-nginx

# Shared library
sudo mkdir -p /usr/local/lib
sudo wget -O /usr/local/lib/virtualhost-lib.sh https://raw.githubusercontent.com/shuvo-halder/virtualhost-automation/master/lib/virtualhost-lib.sh
```

### Method 3: Manual Download
1. Download `bin/virtualhost.sh` or `bin/virtualhost-nginx.sh` and `lib/virtualhost-lib.sh`
2. Make executable: `chmod +x /path/to/script.sh`
3. Run with: `sudo /path/to/script.sh [options] command domain`

---

## 🚀 Quick Start

### Apache
```bash
# Create virtual host
sudo virtualhost create example.dev

# Create with custom directory
sudo virtualhost create example.dev /var/www/mysite

# Create with Let's Encrypt SSL
sudo virtualhost -l create example.dev

# Delete virtual host
sudo virtualhost delete example.dev

# List all hosts
sudo virtualhost list

# Get help
sudo virtualhost --help
```

### Nginx
```bash
# Create virtual host
sudo virtualhost-nginx create example.dev

# Create with custom directory
sudo virtualhost-nginx create example.dev /var/www/mysite

# Create with Let's Encrypt SSL
sudo virtualhost-nginx -l create example.dev

# Delete virtual host
sudo virtualhost-nginx delete example.dev

# List all hosts
sudo virtualhost-nginx list

# Get help
sudo virtualhost-nginx --help
```

---

## 📖 Usage Guide

### General Syntax
```bash
sudo virtualhost [OPTIONS] COMMAND DOMAIN [ROOTDIR]
sudo virtualhost-nginx [OPTIONS] COMMAND DOMAIN [ROOTDIR]
```

### Commands

#### Create Virtual Host
```bash
sudo virtualhost create example.dev
sudo virtualhost create example.dev /var/www/custom_dir
```

**What it does:**
- Creates web root directory with proper permissions
- Generates Apache/Nginx configuration
- Enables the site
- Adds entry to /etc/hosts
- Creates phpinfo.php and index.html test files
- Reloads web server
- Logs all operations

#### Delete Virtual Host
```bash
sudo virtualhost delete example.dev
```

**What it does:**
- Disables the site
- Removes configuration
- Removes /etc/hosts entry (with backup)
- Prompts to delete web root (or auto-deletes with `--force`)
- Reloads web server
- Logs all operations

#### List Virtual Hosts
```bash
sudo virtualhost list
sudo virtualhost-nginx list --json
```

Shows all enabled virtual hosts with their paths. Use `--json` for machine-readable output.

#### Get Help
```bash
sudo virtualhost --help
sudo virtualhost-nginx --help
```

Shows comprehensive help and usage examples.

#### Show Version
```bash
sudo virtualhost --version
sudo virtualhost-nginx --version
```

Displays script version information.

### Options

| Option | Description | Example |
|--------|-------------|---------|
| `-h, --help` | Show help message | `sudo virtualhost -h` |
| `-V, --version` | Show version info | `sudo virtualhost --version` |
| `-v, --verbose` | Enable verbose output | `sudo virtualhost -v create example.dev` |
| `-d, --dry-run` | Preview without changes | `sudo virtualhost -d create example.dev` |
| `-s, --skip-reload` | Skip web server reload | `sudo virtualhost -s create example.dev` |
| `-e, --email` (Apache) | Set admin email | `sudo virtualhost -e admin@example.com create example.dev` |
| `-p, --php-socket` (Nginx) | PHP-FPM socket | `sudo virtualhost-nginx -p unix:/run/php/php8.1-fpm.sock create example.dev` |
| `-l, --letsencrypt` | Obtain Let's Encrypt SSL | `sudo virtualhost -l create example.dev` |
| `--self-signed` | Generate self-signed SSL | `sudo virtualhost --self-signed create example.dev` |
| `--force-https` | Redirect HTTP to HTTPS | `sudo virtualhost --force-https create example.dev` |
| `--with-www` | Add www. ServerAlias | `sudo virtualhost --with-www create example.dev` |
| `--force` | Non-interactive mode | `sudo virtualhost --force delete example.dev` |
| `--no-index` | Skip test files | `sudo virtualhost --no-index create example.dev` |
| `--no-hosts` | Skip /etc/hosts edit | `sudo virtualhost --no-hosts create example.dev` |
| `--json` | JSON output format | `sudo virtualhost list --json` |
| `--no-color` | Disable colored output | `sudo virtualhost --no-color create example.dev` |

---

## 💡 Advanced Usage

### SSL/HTTPS Setup

#### Let's Encrypt (Automatic)
```bash
# Create with Let's Encrypt SSL certificate
sudo virtualhost -l create example.dev
sudo virtualhost-nginx -l create example.dev
```

#### Self-Signed Certificate
```bash
# Create with self-signed SSL certificate
sudo virtualhost --self-signed create example.dev
```

#### Force HTTPS Redirect
```bash
# Create with SSL and force HTTPS
sudo virtualhost --self-signed --force-https create example.dev
```

### Dry-Run Mode (Preview Changes)
Test what would happen without making actual changes:
```bash
sudo virtualhost -d create example.dev
```

Output shows all planned operations but doesn't modify anything.

### Verbose Mode (Detailed Output)
See detailed step-by-step execution:
```bash
sudo virtualhost -v create example.dev
```

Shows detailed logs of each operation.

### Non-Interactive Operations
Skip all confirmation prompts:
```bash
sudo virtualhost --force delete example.dev
```

### JSON Output
Machine-readable output for automation:
```bash
sudo virtualhost list --json
# {"status":"success","message":"Virtual hosts listed","data":[{"domain":"example.dev","type":"apache"}]}
```

### Custom PHP Socket (Nginx)
Use Unix socket instead of TCP:
```bash
# TCP socket (default)
sudo virtualhost-nginx create example.dev

# Unix socket
sudo virtualhost-nginx -p unix:/run/php/php8.1-fpm.sock create example.dev
```

### Custom Admin Email (Apache)
Set server admin email:
```bash
sudo virtualhost -e webmaster@company.com create example.dev
```

### Reverse Proxy (Node.js, React, Next.js, etc.)
Proxy pass to any backend server running on your machine:

```bash
# Node.js / Express app running on port 3000
sudo virtualhost --proxy-pass http://localhost:3000 create myapp.dev

# React / Vite dev server running on port 5173
sudo virtualhost-nginx --proxy-pass http://localhost:5173 create reactapp.dev

# Next.js app running on port 3000
sudo virtualhost --proxy-pass http://localhost:3000 create nextapp.dev

# Vue / Nuxt app with WebSocket support (HMR)
sudo virtualhost-nginx --proxy-pass http://localhost:3000 --proxy-websocket create nuxtapp.dev
```

**What it does:**
- Creates a reverse proxy configuration instead of a document root
- All requests to `myapp.dev` are forwarded to your backend server
- Properly forwards real IP, host, and protocol headers
- Skips test file creation (phpinfo.php, index.html)
- Works with SSL/HTTPS when combined with `--self-signed` or `-l`

### Reverse Proxy with SSL
```bash
# Node.js app with self-signed SSL
sudo virtualhost --self-signed --proxy-pass http://localhost:3000 create myapp.dev

# Node.js app with Let's Encrypt SSL
sudo virtualhost -l --proxy-pass http://localhost:3000 create myapp.dev

# With HTTPS redirect
sudo virtualhost --self-signed --force-https --proxy-pass http://localhost:3000 create myapp.dev
```

### Reverse Proxy with WebSocket Support
For apps that need WebSocket connections (Nuxt, Socket.io, Laravel Echo, etc.):

```bash
# Apache
sudo virtualhost --proxy-pass http://localhost:3000 --proxy-websocket create myapp.dev

# Nginx
sudo virtualhost-nginx --proxy-pass http://localhost:3000 --proxy-websocket create myapp.dev
```

### Batch Operations
Create multiple hosts without reloading:
```bash
sudo virtualhost -s create site1.dev
sudo virtualhost -s create site2.dev
sudo virtualhost -s create site3.dev
sudo systemctl reload apache2  # One reload at the end
```

---

## 📊 Configuration

### Default Paths
```
Apache sites-available:  /etc/apache2/sites-available/
Apache sites-enabled:    /etc/apache2/sites-enabled/
Nginx sites-available:   /etc/nginx/sites-available/
Nginx sites-enabled:     /etc/nginx/sites-enabled/
Web root:                /var/www/
Logs:                    /var/log/virtualhost/
SSL certificates:        /etc/letsencrypt/live/ (Let's Encrypt)
                         /etc/ssl/ (self-signed)
```

### Logging
All operations are logged to: `/var/log/virtualhost/virtualhost-*.log`

View logs:
```bash
tail -f /var/log/virtualhost/virtualhost-*.log
```

### Environment Variables
```bash
# Set custom log directory
export LOG_DIR="/custom/log/path"
sudo virtualhost create example.dev

# Set custom admin email (Apache)
export EMAIL="admin@example.com"
sudo virtualhost create example.dev

# Set custom PHP-FPM socket (Nginx)
export PHP_FPM_SOCKET="unix:/run/php/php8.1-fpm.sock"
sudo virtualhost-nginx create example.dev
```

---

## 🔧 Configuration Details

### Apache VirtualHost Template
Each virtual host gets:
- ServerAdmin email
- ServerName and optional www alias
- DocumentRoot configuration
- mod_rewrite enabled for frameworks
- Gzip compression
- Error/Access logging
- Security headers for hidden files
- SSL virtual host (if enabled) with HSTS, X-Content-Type-Options, X-Frame-Options

### Nginx Server Block Template
Each virtual host gets:
- Server name configuration with optional www
- PHP-FPM fastcgi configuration (auto-detected)
- Static file caching (30 days)
- Security hardening
- Per-domain logging
- Framework-ready rewrites
- SSL server block (if enabled) with HTTP/2, TLSv1.2/TLSv1.3

---

## 📝 Examples

### Simple Website
```bash
sudo virtualhost create mysite.dev
# Creates: /var/www/mysite/
# Visit: http://mysite.dev
```

### Secure Website with SSL
```bash
sudo virtualhost --self-signed --force-https create mysite.dev
# Creates: /var/www/mysite/
# Visit: https://mysite.dev (auto-redirects from HTTP)
```

### Custom Directory
```bash
sudo virtualhost create api.example.dev /var/www/projects/api
# Creates: /var/www/projects/api/
# Visit: http://api.example.dev
```

### Development Environment
```bash
# Create multiple dev sites
sudo virtualhost -s create project1.dev
sudo virtualhost -s create project2.dev
sudo virtualhost -s create project3.dev
sudo systemctl reload apache2
```

### Testing Configuration
```bash
# Preview without making changes
sudo virtualhost -d create example.dev

# Dry-run with verbose output
sudo virtualhost -dv create example.dev
```

---

## 🐛 Troubleshooting

### Issue: "Run as root (use sudo)"
**Solution:** Always prefix commands with `sudo`
```bash
sudo virtualhost create example.dev
```

### Issue: "Domain does not exist: example.dev"
**Solution:** Double-check the domain name or create it first
```bash
sudo virtualhost create example.dev  # Create first
sudo virtualhost delete example.dev  # Then delete
```

### Issue: "Configuration test failed"
**Solution:** Check web server configuration syntax
```bash
# Apache
apache2ctl configtest

# Nginx
nginx -t
```

### Issue: Cannot access virtual host in browser
**Solution:** Verify /etc/hosts entry
```bash
grep example.dev /etc/hosts
# Should see: 127.0.0.1    example.dev
```

### Issue: Permission denied on web root
**Solution:** Check directory ownership
```bash
ls -la /var/www/example/
# Should be owned by your user or www-data
```

### Issue: PHP not working
**Solution:** Check PHP-FPM is running and properly configured
```bash
# Nginx
sudo systemctl status php-fpm
# or
sudo systemctl status php8.1-fpm

# Apache
apache2ctl -t  # Test configuration
```

### Issue: Port 80 already in use
**Solution:** Check what's using port 80
```bash
sudo lsof -i :80
# Kill the process or use different port
```

### Issue: Let's Encrypt certificate failed
**Solution:** Ensure port 80 is accessible from the internet
```bash
# For local development, use --self-signed instead
sudo virtualhost --self-signed create example.dev
```

---

## 📚 Logs and Debugging

### View Logs
```bash
# View today's logs
tail -f /var/log/virtualhost/virtualhost-apache-*.log
tail -f /var/log/virtualhost/virtualhost-nginx-*.log

# View all logs
ls -la /var/log/virtualhost/
```

### Check Web Server Logs
```bash
# Apache
tail -f /var/log/apache2/example.dev_error.log
tail -f /var/log/apache2/example.dev_access.log

# Nginx
tail -f /var/log/nginx/example.dev_error.log
tail -f /var/log/nginx/example.dev_access.log
```

---

## ✅ Verification

### Test Virtual Host Creation
```bash
# Create
sudo virtualhost create testsite.dev

# Verify /etc/hosts entry
grep testsite.dev /etc/hosts

# Verify site enabled
ls -l /etc/apache2/sites-enabled/ | grep testsite

# Verify directory
ls -la /var/www/testsite/

# Check in browser
curl http://testsite.dev

# View logs
tail -f /var/log/virtualhost/*.log
```

---

## 🔒 Security Notes

- Scripts require sudo (root privileges)
- Domain validation prevents invalid characters
- Permissions set to 755 for directories, 644 for files
- Backups created for /etc/hosts modifications
- Hidden files denied access in Apache/Nginx
- Proper user/group ownership enforced
- No SQL injection or command injection possible
- SSL configurations include HSTS, X-Content-Type-Options, X-Frame-Options
- Self-signed certificates use 2048-bit RSA keys
- HTTPS configurations use TLSv1.2 and TLSv1.3 only

---

## 🧪 Running Tests

```bash
# Run Apache tests
bash tests/test-virtualhost.sh

# Run Nginx tests
bash tests/test-virtualhost-nginx.sh
```

---

## 🤝 Contributing

Found a bug? Have a feature request? Contributions welcome!

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.

---

## 📞 Support

For issues, questions, or suggestions:
- Open an [GitHub Issue](https://github.com/shuvo-halder/virtualhost-automation/issues)
- Check [Troubleshooting Section](#-troubleshooting)
- Review [Examples](#-examples)

---

## 🚀 Changelog

### Version 3.0.0 (2026-06-23)
- ✨ SSL/HTTPS support (Let's Encrypt & self-signed)
- ✨ HTTP→HTTPS redirect (`--force-https`)
- ✨ www alias support (`--with-www`)
- ✨ Non-interactive mode (`--force`)
- ✨ JSON output for `list` command
- ✨ Colored output with `--no-color` option
- ✨ PHP-FPM auto-detection (Nginx)
- ✨ Shared library (`lib/virtualhost-lib.sh`)
- ✨ Skip options (`--no-index`, `--no-hosts`)
- ✨ GitHub Actions CI workflow
- ✨ Test suite for both Apache and Nginx
- ✨ CHANGELOG.md for version tracking
- 🔧 Fixed Apache ownership bug (owner:group)
- 📚 Complete documentation overhaul

### Version 2.0.0 (2026-05-05)
- ✨ Added comprehensive help system (`--help`, `--version`)
- ✨ Added dry-run mode (`-d`) for safe testing
- ✨ Added verbose logging (`-v`) for debugging
- ✨ Added centralized logging system
- ✨ Added domain validation and error handling
- ✨ Added list command to show all virtual hosts
- ✨ Added skip-reload option for batch operations
- ✨ Added custom PHP-FPM socket support (Nginx)
- ✨ Added custom admin email support (Apache)
- 📚 Complete documentation overhaul
- 🔒 Enhanced security features
- ⚡ Performance improvements

### Version 1.0.0 (2023-09-21)
- Initial release
- Basic create/delete functionality
- Apache and Nginx support

---

## 👨‍💻 Author

**Shuvo Halder** - [GitHub](https://github.com/shuvo-halder)

---

## 📎 Related Projects

- [Apache Virtual Host Docs](https://httpd.apache.org/docs/2.4/vhosts/)
- [Nginx Server Blocks](https://nginx.org/en/docs/http/server_names.html)
- [PHP-FPM Setup](https://www.php.net/manual/en/install.fpm.php)
- [Let's Encrypt](https://letsencrypt.org/)
- [Certbot](https://certbot.eff.org/)

---

**Made with ❤️ for Linux Developers & System Administrators**