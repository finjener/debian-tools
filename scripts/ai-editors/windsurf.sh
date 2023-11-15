#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Editors
# DEBIAN_TOOLS_NAME: Windsurf
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PATH: /usr/bin/windsurf
# Windsurf AI Editor Installation Script
# Uses shared apt_helper library

set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
utils_path="$script_dir/../utils/apt_helper.sh"

if [ ! -f "$utils_path" ]; then
    echo "Error: Shared library not found at $utils_path"
    exit 1
fi

source "$utils_path"

# Configuration
PACKAGE_NAME="windsurf"
REPO_URL="https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/apt"
KEY_URL="https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/windsurf.gpg"

SOURCES_FILE="/etc/apt/sources.list.d/windsurf.sources"
# Keeping the specific name used in previous manual setups to avoid duplicate keys if slightly named differently
KEY_FILE="/etc/apt/keyrings/windsurf-stable.gpg" 

# Legacy cleanup
LEGACY_LIST="/etc/apt/sources.list.d/windsurf.list"
# Note: Legacy key file path might be the same as current KEY_FILE, logic handles this gracefully

if [ "$1" = "-u" ] || [ "$1" = "--uninstall" ]; then
    uninstall_apt_component "$PACKAGE_NAME" "$SOURCES_FILE" "$KEY_FILE" "$LEGACY_LIST"
else
    install_apt_component "$PACKAGE_NAME" "$REPO_URL" "$KEY_URL" "$SOURCES_FILE" "$KEY_FILE" "stable" "main" "amd64" "$LEGACY_LIST"
fi
