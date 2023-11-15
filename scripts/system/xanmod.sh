#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: System
# DEBIAN_TOOLS_NAME: XanMod Kernel
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PACKAGE: linux-xanmod
# XanMod Kernel Installation Script
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
PACKAGE_NAME="linux-xanmod-x64v3"
# Note: Using http as per official docs, though https preferred if available. 
# Docs say http://deb.xanmod.org
REPO_URL="http://deb.xanmod.org"
KEY_URL="https://dl.xanmod.org/archive.key"

SOURCES_FILE="/etc/apt/sources.list.d/xanmod-release.sources"
KEY_FILE="/etc/apt/keyrings/xanmod-archive-keyring.gpg"

# Legacy cleanup
LEGACY_LIST="/etc/apt/sources.list.d/xanmod-release.list"

# Dependencies for building external modules (e.g., Nvidia drivers, VirtualBox)
DEPENDENCIES=("dkms" "libdw-dev" "clang" "lld" "llvm")

install_dependencies() {
    log_message "Installing dependencies for external module building..."
    if ! sudo apt install -y --no-install-recommends "${DEPENDENCIES[@]}" 2>&1 | tee -a "$LOG_FILE"; then
        log_message "Warning: Failed to install some dependencies. Kernel installation will proceed."
    fi
}

if [ "$1" = "-u" ] || [ "$1" = "--uninstall" ]; then
    uninstall_apt_component "$PACKAGE_NAME" "$SOURCES_FILE" "$KEY_FILE" "$LEGACY_LIST"
    
    # Optional dependency cleanup? 
    # Usually better not to remove generic tools like clang unless we're sure.
    log_message "Note: Build dependencies (${DEPENDENCIES[*]}) were NOT removed to avoid breaking other tools."
else
    # Install dependencies first
    install_dependencies
    
    # XanMod repo structure: 
    # deb http://deb.xanmod.org releases main
    # BUT user prompt said: http://deb.xanmod.org $(lsb_release -sc) main
    # Official docs usually say: releases main
    # However, user requested: $(lsb_release -sc)
    # Let's check lsb_release. If not available, fallback?
    # apt_helper uses "stable" by default if not passed.
    # We should pass the detected codename.
    
    if command -v lsb_release &> /dev/null; then
        SUITE=$(lsb_release -sc)
    else
        # Fallback to /etc/os-release
        source /etc/os-release
        SUITE="${VERSION_CODENAME:-stable}"
    fi
    
    # WARNING: XanMod often uses 'releases' as suite for all, OR specific codenames.
    # User specifically asked for: `echo "deb ... http://deb.xanmod.org $(lsb_release -sc) main"`
    # So we will honor that.
    
    # Architecture: XanMod is x86_64 specific usually. apt_helper defaults to amd64. 
    # User prompt had `deb [signed-by=...] ...` without [arch=amd64] explicitly in the echo command, 
    # BUT `apt_helper` enforces arch if passed.
    # Let's use "amd64" to be safe as xanmod is x86-64 optimized.
    
    install_apt_component "$PACKAGE_NAME" "$REPO_URL" "$KEY_URL" "$SOURCES_FILE" "$KEY_FILE" "$SUITE" "main" "amd64" "$LEGACY_LIST"
    
    log_message "XanMod Kernel installed. Please reboot to take effect."
    log_message "Check platform compatibility: https://xanmod.org/#psabi"
fi
