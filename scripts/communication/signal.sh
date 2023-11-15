#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Communication
# DEBIAN_TOOLS_NAME: Signal
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PACKAGE: signal-desktop
# Signal Desktop Installation Script
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
PACKAGE_NAME="signal-desktop"
REPO_URL="https://updates.signal.org/desktop/apt"
KEY_URL="https://updates.signal.org/desktop/apt/keys.asc"

SOURCES_FILE="/etc/apt/sources.list.d/signal-desktop.sources"
KEY_FILE="/usr/share/keyrings/signal-desktop-keyring.gpg"

# Legacy cleanup
LEGACY_LIST="/etc/apt/sources.list.d/signal-desktop.list"
# Note: Key file path reused

if [ "$1" = "-u" ] || [ "$1" = "--uninstall" ]; then
    uninstall_apt_component "$PACKAGE_NAME" "$SOURCES_FILE" "$KEY_FILE" "$LEGACY_LIST"
else
    install_apt_component "$PACKAGE_NAME" "$REPO_URL" "$KEY_URL" "$SOURCES_FILE" "$KEY_FILE" "xenial" "main" "amd64" "$LEGACY_LIST"
fi
