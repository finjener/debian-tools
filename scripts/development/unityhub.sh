#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Development
# DEBIAN_TOOLS_NAME: Unity Hub
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PATH: /opt/unityhub/unityhub
# Unity Hub Installation Script
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
PACKAGE_NAME="unityhub"
REPO_URL="https://hub.unity3d.com/linux/repos/deb"
KEY_URL="https://hub.unity3d.com/linux/keys/public"

SOURCES_FILE="/etc/apt/sources.list.d/unityhub.sources"
KEY_FILE="/usr/share/keyrings/Unity_Technologies_ApS.gpg"

# Legacy cleanup
LEGACY_LIST="/etc/apt/sources.list.d/unityhub.list"
# Note: Key file path reused

# Custom directories
UNITY_CONFIG_DIR="$HOME/.config/Unity Hub"

# Helper for backups

if [ "$1" = "-u" ] || [ "$1" = "--uninstall" ]; then
    # Custom pre-uninstall steps
    
    # Standard uninstall
    uninstall_apt_component "$PACKAGE_NAME" "$SOURCES_FILE" "$KEY_FILE" "$LEGACY_LIST"
    
    # Custom post-uninstall steps
    read -p "Do you want to remove local Unity Hub configuration files? [y/N]: " remove_config
    if [[ "$remove_config" == [yY] ]]; then
         [ -d "$UNITY_CONFIG_DIR" ] && rm -rf "$UNITY_CONFIG_DIR" && log_message "Removed $UNITY_CONFIG_DIR"
    fi
else
    install_apt_component "$PACKAGE_NAME" "$REPO_URL" "$KEY_URL" "$SOURCES_FILE" "$KEY_FILE" "stable" "main" "amd64" "$LEGACY_LIST"
fi
