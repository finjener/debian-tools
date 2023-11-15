#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Development
# DEBIAN_TOOLS_NAME: VSCodium
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PACKAGE: codium
# VSCodium Installation Script
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
PACKAGE_NAME="codium"
# Use specific URL from user prompt
REPO_URL="https://download.vscodium.com/debs"
# Use specific Key URL from user prompt
KEY_URL="https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg"

SOURCES_FILE="/etc/apt/sources.list.d/vscodium.sources"
KEY_FILE="/usr/share/keyrings/vscodium-archive-keyring.gpg"

# Custom directories
VSCODIUM_CONFIG_DIR="$HOME/.config/VSCodium"
VSCODIUM_DATA_DIR="$HOME/.vscode-oss"

# Helper for backups (preserved from original script)

if [ "$1" = "-u" ] || [ "$1" = "--uninstall" ]; then
    # Custom pre-uninstall steps
    
    # Standard uninstall
    uninstall_apt_component "$PACKAGE_NAME" "$SOURCES_FILE" "$KEY_FILE"
    
    # Custom post-uninstall steps (cleaning user data)
    read -p "Do you want to remove local VSCodium configuration and data files? [y/N]: " remove_config
    if [[ "$remove_config" == [yY] ]]; then
        [ -d "$VSCODIUM_CONFIG_DIR" ] && rm -rf "$VSCODIUM_CONFIG_DIR" && log_message "Removed $VSCODIUM_CONFIG_DIR"
        [ -d "$VSCODIUM_DATA_DIR" ] && rm -rf "$VSCODIUM_DATA_DIR" && log_message "Removed $VSCODIUM_DATA_DIR"
    fi
else
    # Install with explicit amd64 and arm64 as requested
    install_apt_component "$PACKAGE_NAME" "$REPO_URL" "$KEY_URL" "$SOURCES_FILE" "$KEY_FILE" "vscodium" "main" "amd64 arm64"
fi
