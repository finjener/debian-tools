#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: VPN
# DEBIAN_TOOLS_NAME: Nym VPN
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PACKAGE: nym-vpn-app
# NymVPN Installation Script
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
PACKAGE_NAME="nym-vpn"
REPO_URL="https://apt.nymtech.net/"
# Key URL located from nymtech s3 bucket as per search results
KEY_URL="http://apt.nymtech.net.s3-website.eu-central-1.amazonaws.com/nymtech.gpg"

SOURCES_FILE="/etc/apt/sources.list.d/nymtech.sources"
KEY_FILE="/usr/share/keyrings/nymtech.gpg"

# Legacy cleanup
LEGACY_LIST="/etc/apt/sources.list.d/nymtech.list"

# Note: User's existing setup uses 'jammy' suite on a Debian system. 
# We will match this to ensure compatibility with their current state.
SUITE="jammy"

if [ "$1" = "-u" ] || [ "$1" = "--uninstall" ]; then
    uninstall_apt_component "$PACKAGE_NAME" "$SOURCES_FILE" "$KEY_FILE" "$LEGACY_LIST"
else
    # Install with amd64 architecture as requested
    install_apt_component "$PACKAGE_NAME" "$REPO_URL" "$KEY_URL" "$SOURCES_FILE" "$KEY_FILE" "$SUITE" "main" "amd64" "$LEGACY_LIST"
    
    log_message "NymVPN installation complete."
fi
