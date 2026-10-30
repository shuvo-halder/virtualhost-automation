#!/usr/bin/env python3
"""Convert new shell files to CRLF line endings."""
import os

ROOT = r"c:\Users\ome\Desktop\virtualhost-automation"

files = [
    r"tests\test_enable_disable.sh",
    r"tests\test_clone.sh",
    r"tests\test_backup.sh",
    r"tests\run_integration_tests.sh",
    r"man\virtualhost.1",
    r"man\virtualhost-nginx.1",
]

for rel in files:
    path = os.path.join(ROOT, rel)
    with open(path, "rb") as f:
        content = f.read()
    content = content.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
    with open(path, "wb") as f:
        f.write(content)
    print(f"  CRLF  {rel}")

print("Done.")
