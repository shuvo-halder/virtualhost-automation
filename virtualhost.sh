#!/usr/bin/env bash
# virtualhost.sh — Wrapper for Apache VirtualHost Manager v3.0.0
# Version: 3.0.0
# Author: Shuvo Halder
# License: MIT
#
# This wrapper script locates and executes the main Apache virtualhost manager
# from the bin/ directory. Supports both development and installed paths.

set -o errexit
set -o nounset
set -o pipefail
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try to find the main script
if [[ -f "$SCRIPT_DIR/bin/virtualhost.sh" ]]; then
    exec "$SCRIPT_DIR/bin/virtualhost.sh" "$@"
elif [[ -f "/usr/local/bin/virtualhost.sh" ]]; then
    exec "/usr/local/bin/virtualhost.sh" "$@"
else
    echo "ERROR: virtualhost.sh not found in bin/ or /usr/local/bin/" >&2
    echo "Please run the installer or check your installation." >&2
    exit 1
fi