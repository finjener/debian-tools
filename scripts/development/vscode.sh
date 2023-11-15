#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Development
# DEBIAN_TOOLS_NAME: Visual Studio Code
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PACKAGE: code
# Visual Studio Code Installation Script
# Uses shared apt_helper library
# Note: Uses official Microsoft repository instead of direct .deb download
# to ensure updates and consistency with project structure.

set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
utils_path="$script_dir/../utils/apt_helper.sh"

if [ ! -f "$utils_path" ]; then
    echo "Error: Shared library not found at $utils_path"
    exit 1
fi

source "$utils_path"

# Configuration
PACKAGE_NAME="code"
# Official Microsoft VS Code Repo
REPO_URL="https://packages.microsoft.com/repos/code"
KEY_URL="https://packages.microsoft.com/keys/microsoft.asc"

SOURCES_FILE="/etc/apt/sources.list.d/vscode.sources"
KEY_FILE="/usr/share/keyrings/microsoft-archive-keyring.gpg"

# Custom directories
VSCODE_CONFIG_DIR="$HOME/.config/Code"
VSCODE_DATA_DIR="$HOME/.vscode"

if [ "$1" = "-u" ] || [ "$1" = "--uninstall" ]; then
    # Standard uninstall
    uninstall_apt_component "$PACKAGE_NAME" "$SOURCES_FILE" "$KEY_FILE"
    
    # Custom post-uninstall steps (cleaning user data)
    read -p "Do you want to remove local VS Code configuration and extensions? [y/N]: " remove_config
    if [[ "$remove_config" == [yY] ]]; then
        [ -d "$VSCODE_CONFIG_DIR" ] && rm -rf "$VSCODE_CONFIG_DIR" && log_message "Removed $VSCODE_CONFIG_DIR"
        [ -d "$VSCODE_DATA_DIR" ] && rm -rf "$VSCODE_DATA_DIR" && log_message "Removed $VSCODE_DATA_DIR"
    fi
else
    # Install with explicit architectures
    install_apt_component "$PACKAGE_NAME" "$REPO_URL" "$KEY_URL" "$SOURCES_FILE" "$KEY_FILE" "stable" "main" "amd64 arm64 armhf"
fi
