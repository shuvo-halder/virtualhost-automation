#!/usr/bin/env python3
"""
phase3_fixup.py - Fix remaining Phase 3 patches:
  1. install.sh  - logrotate + man page install steps
  2. ci.yml      - version 4.0.0 + verify jobs
"""
import os, sys, re, subprocess

ROOT = r"c:\Users\ome\Desktop\virtualhost-automation"

def crlf(text):
    return text.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8")

def read_text(path):
    with open(path, "rb") as f:
        return f.read().decode("utf-8").replace("\r\n", "\n")

# ──────────────────────────────────────────────────────────────
# 1. install.sh
# ──────────────────────────────────────────────────────────────
INSTALL_PATH = os.path.join(ROOT, "install.sh")

text = read_text(INSTALL_PATH)

if "logrotate" not in text:
    # Find the Bash completion comment  (box-drawing chars included)
    # Use a regex to find the comment line regardless of special chars
    m = re.search(r'(    #[^\n]*Bash completion[^\n]*\n)', text)
    if m:
        marker = m.group(1)
        logrotate_and_man = """\
    # Log rotation
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
        true
    endscript
}
LOGROTATECFG
        success "Installed logrotate config: $LOGROTATE_DIR/virtualhost"
    else
        warn "logrotate.d not found -- skipping log rotation config"
    fi

    # Man pages
    if [[ -d "$SCRIPT_DIR/man" ]]; then
        mkdir -p "$MAN_DIR"
        for manpage in "$SCRIPT_DIR/man/"*.1; do
            [[ -f "$manpage" ]] || continue
            install -m 644 "$manpage" "$MAN_DIR/"
            success "Installed man page: $MAN_DIR/$(basename "$manpage")"
        done
        command -v mandb &>/dev/null && mandb -q || true
    else
        warn "man/ directory not found -- skipping man page installation"
    fi

"""
        text = text.replace(marker, logrotate_and_man + marker)
        print("  PATCHED  install.sh - logrotate + man pages inserted")
    else:
        print("  WARN     install.sh - could not find Bash completion marker")
else:
    print("  SKIP     install.sh - logrotate already present")

with open(INSTALL_PATH, "wb") as f:
    f.write(crlf(text))
print(f"  WRITTEN  {INSTALL_PATH}")

# ──────────────────────────────────────────────────────────────
# 2. ci.yml
# ──────────────────────────────────────────────────────────────
CI_PATH = os.path.join(ROOT, ".github", "workflows", "ci.yml")

text = read_text(CI_PATH)

# Fix version 3.0.0 -> 4.0.0
if '"3.0.0"' in text:
    text = text.replace('EXPECTED="3.0.0"', 'EXPECTED="4.0.0"')
    print("  PATCHED  ci.yml - version 3.0.0 -> 4.0.0")
else:
    print("  SKIP     ci.yml version (already 4.0.0)")

# Add verify jobs if missing
if "verify_phase2" not in text:
    verify_block = """
  verify-features:
    name: Phase 2 and 3 Verification
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Run Phase 2 verification
        run: python3 verify_phase2.py

      - name: Run Phase 3 verification
        run: python3 verify_phase3.py
"""
    text = text.rstrip() + "\n" + verify_block + "\n"
    print("  PATCHED  ci.yml - added verify-features job")
else:
    print("  SKIP     ci.yml verify job (already present)")

# Add install.sh to push/PR paths if missing
if "install.sh" not in text:
    text = text.replace(
        "      - 'virtualhost-nginx.sh'\n  pull_request:",
        "      - 'virtualhost-nginx.sh'\n      - 'install.sh'\n  pull_request:",
    )
    print("  PATCHED  ci.yml - added install.sh to trigger paths")

with open(CI_PATH, "wb") as f:
    f.write(crlf(text))
print(f"  WRITTEN  {CI_PATH}")

# ──────────────────────────────────────────────────────────────
# Done
# ──────────────────────────────────────────────────────────────
print("\nRunning verify_phase3.py ...")
result = subprocess.run([sys.executable, os.path.join(ROOT, "verify_phase3.py")])
sys.exit(result.returncode)
