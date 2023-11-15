#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Editors
# DEBIAN_TOOLS_NAME: Cursor
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PATH: /usr/bin/cursor
# Cursor AI Editor Installation Script
# Uses shared apt_helper library

set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# Source shared library
# Assuming script is in scripts/ai-editors/, utils is in scripts/utils/
utils_path="$script_dir/../utils/apt_helper.sh"

if [ ! -f "$utils_path" ]; then
    echo "Error: Shared library not found at $utils_path"
    exit 1
fi

source "$utils_path"

# Configuration
PACKAGE_NAME="cursor"
REPO_URL="https://downloads.cursor.com/aptrepo"
KEY_URL="https://downloads.cursor.com/keys/anysphere.asc"

SOURCES_FILE="/etc/apt/sources.list.d/cursor.sources"
KEY_FILE="/etc/apt/keyrings/cursor.gpg"

# Legacy cleanup
LEGACY_LIST="/etc/apt/sources.list.d/cursor.list"
LEGACY_KEY="/etc/apt/keyrings/cursor.gpg" # Same as KEY_FILE in new setup, effectively overwritten, but good to track

if [ "$1" = "-u" ] || [ "$1" = "--uninstall" ]; then
    uninstall_apt_component "$PACKAGE_NAME" "$SOURCES_FILE" "$KEY_FILE" "$LEGACY_LIST"
else
    install_apt_component "$PACKAGE_NAME" "$REPO_URL" "$KEY_URL" "$SOURCES_FILE" "$KEY_FILE" "stable" "main" "amd64 arm64" "$LEGACY_LIST"
fi
