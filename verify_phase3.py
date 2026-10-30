#!/usr/bin/env python3
"""verify_phase3.py - Verify Phase 3 hardening changes are present."""

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))

def read(path):
    with open(path, "rb") as f:
        return f.read().decode("utf-8", errors="replace").replace("\r\n", "\n")

checks = []

def check(name, condition, filepath=""):
    status = "PASS" if condition else "FAIL"
    checks.append((status, name, filepath))
    loc = f" ({filepath})" if filepath else ""
    print(f"  [{status}] {name}{loc}")

def sep(title):
    print(f"\n{'='*60}\n  {title}\n{'='*60}")

# lib/virtualhost-lib.sh
sep("lib/virtualhost-lib.sh")
lib = read(os.path.join(ROOT, "lib", "virtualhost-lib.sh"))
check("write_atomic() present",            "write_atomic()" in lib,        "lib/virtualhost-lib.sh")
check("is_site_enabled() present",         "is_site_enabled()" in lib,     "lib/virtualhost-lib.sh")
check("ROLLBACK_FILES array declared",     "ROLLBACK_FILES=()" in lib,     "lib/virtualhost-lib.sh")
check("ROLLBACK_CMDS array declared",      "ROLLBACK_CMDS=()" in lib,      "lib/virtualhost-lib.sh")
check("cleanup() handles rollback",        "Rollback" in lib,              "lib/virtualhost-lib.sh")
check("trap cleanup EXIT present",         "trap cleanup EXIT" in lib,     "lib/virtualhost-lib.sh")

# bin/virtualhost.sh (Apache)
sep("bin/virtualhost.sh")
apache = read(os.path.join(ROOT, "bin", "virtualhost.sh"))
check("is_site_enabled apache in cmd_enable",  "is_site_enabled apache" in apache,  "bin/virtualhost.sh")
check("already enabled no-op",                 "already enabled" in apache,         "bin/virtualhost.sh")
check("already disabled no-op",                "already disabled" in apache,        "bin/virtualhost.sh")
check("pre-deletion backup in cmd_delete",     "pre-deletion backup" in apache,     "bin/virtualhost.sh")
check("perform_backup called in cmd_delete",   "perform_backup" in apache,          "bin/virtualhost.sh")

# bin/virtualhost-nginx.sh
sep("bin/virtualhost-nginx.sh")
nginx = read(os.path.join(ROOT, "bin", "virtualhost-nginx.sh"))
check("is_site_enabled nginx in cmd_enable",   "is_site_enabled nginx" in nginx,    "bin/virtualhost-nginx.sh")
check("already enabled no-op",                 "already enabled" in nginx,          "bin/virtualhost-nginx.sh")
check("already disabled no-op",                "already disabled" in nginx,         "bin/virtualhost-nginx.sh")
check("pre-deletion backup in cmd_delete",     "pre-deletion backup" in nginx,      "bin/virtualhost-nginx.sh")
check("perform_backup called in cmd_delete",   "perform_backup" in nginx,           "bin/virtualhost-nginx.sh")

# install.sh
sep("install.sh")
install = read(os.path.join(ROOT, "install.sh"))
check("MAN_DIR declared",                      "MAN_DIR" in install,                "install.sh")
check("LOGROTATE_DIR declared",                "LOGROTATE_DIR" in install,          "install.sh")
check("logrotate config written",              "logrotate" in install,              "install.sh")
check("man page install step present",         "man/" in install or "MAN_DIR" in install, "install.sh")

# man pages
sep("man/")
man1 = os.path.join(ROOT, "man", "virtualhost.1")
man2 = os.path.join(ROOT, "man", "virtualhost-nginx.1")
check("man/virtualhost.1 exists",             os.path.isfile(man1),                "man/virtualhost.1")
check("man/virtualhost-nginx.1 exists",       os.path.isfile(man2),                "man/virtualhost-nginx.1")
check(".TH header in virtualhost.1",
      ".TH VIRTUALHOST 1" in read(man1) if os.path.isfile(man1) else False,        "man/virtualhost.1")
check(".TH header in virtualhost-nginx.1",
      ".TH VIRTUALHOST-NGINX 1" in read(man2) if os.path.isfile(man2) else False,  "man/virtualhost-nginx.1")

# CI
sep(".github/workflows/ci.yml")
ci = read(os.path.join(ROOT, ".github", "workflows", "ci.yml"))
check("version check updated to 4.0.0",       '4.0.0' in ci,                       "ci.yml")
check("verify_phase2 job present",            "verify_phase2" in ci,               "ci.yml")
check("verify_phase3 job present",            "verify_phase3" in ci,               "ci.yml")

# Integration tests
sep("tests/")
tests_dir = os.path.join(ROOT, "tests")
for f in ["test_enable_disable.sh", "test_clone.sh", "test_backup.sh", "run_integration_tests.sh"]:
    check(f"{f} exists",  os.path.isfile(os.path.join(tests_dir, f)),  "tests/")

# Summary
passed = sum(1 for s, _, _ in checks if s == "PASS")
failed = sum(1 for s, _, _ in checks if s == "FAIL")
total  = len(checks)
print(f"\n{'='*60}")
print(f"  Phase 3 Verification: {passed}/{total} PASS  |  {failed} FAIL")
print(f"{'='*60}\n")
sys.exit(0 if failed == 0 else 1)
