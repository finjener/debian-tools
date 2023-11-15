#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Gaming
# DEBIAN_TOOLS_NAME: Steam
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PACKAGE: steam-launcher
# Steam Installation Script
# Uses shared apt_helper library

set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# Determine utils path (handling being in scripts/gaming/)
utils_path="$script_dir/../utils/apt_helper.sh"

if [ ! -f "$utils_path" ]; then
    echo "Error: Shared library not found at $utils_path"
    exit 1
fi

source "$utils_path"

# Configuration
PACKAGE_NAME="steam-launcher"
TARGET_PACKAGE="steam-launcher" # apt package name
# Note: official package in repo is usually steam-launcher which pulls in dependencies?
# Or just "steam"? 'apt-cache search steam' normally shows 'steam' in multiverse (Debian) or 'steam-launcher' in Valve repo.
# User wants the valve repo.
# In Valve repo, package is often "steam-launcher".
# Let's verify standard behavior: Valve repo provides steam-launcher.
# User provided: https://repo.steampowered.com/steam/
# This is usually for "steam" package too.
# Let's try installing "steam-launcher" as primary, keeping "steam" as fallback?
# Helper supports one package.
# Most reliable for Valve repo is "steam-launcher".

REPO_URL="https://repo.steampowered.com/steam/"
KEY_URL="http://repo.steampowered.com/steam/signature.gpg"

SOURCES_FILE="/etc/apt/sources.list.d/steam-stable.sources"
KEY_FILE="/usr/share/keyrings/steam.gpg"

# Legacy cleanup
LEGACY_LIST="/etc/apt/sources.list.d/steam.list"

# Dependencies
# Steam needs 32-bit architecture enabled
enable_i386() {
    log_message "Checking for i386 architecture..."
    if ! dpkg --print-foreign-architectures | grep -q "i386"; then
        log_message "Enabling i386 architecture..."
        sudo dpkg --add-architecture i386
        sudo apt update 2>&1 | tee -a "$LOG_FILE"
    fi
}

if [ "$1" = "-u" ] || [ "$1" = "--uninstall" ]; then
    uninstall_apt_component "$PACKAGE_NAME" "$SOURCES_FILE" "$KEY_FILE" "$LEGACY_LIST"
    # We do NOT remove i386 capability as it might break other things (wine, etc)
else
    enable_i386
    
    # Install with amd64 architecture implied for repo? or does it need i386?
    # Valve repo usually has [arch=amd64,i386]
    # apt_helper defaults to amd64 if passed.
    # We should pass "amd64 i386"
    
    install_apt_component "$PACKAGE_NAME" "$REPO_URL" "$KEY_URL" "$SOURCES_FILE" "$KEY_FILE" "stable" "steam" "amd64 i386" "$LEGACY_LIST"
    
    log_message "Steam installation complete."
fi
