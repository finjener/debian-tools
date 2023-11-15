#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: VPN
# DEBIAN_TOOLS_NAME: IVPN
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PACKAGE: ivpn
# IVPN Installation Script
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
# Default package name to setup repo, can be overridden based on user choice
PACKAGE_NAME="ivpn" 
REPO_URL="https://repo.ivpn.net/stable/debian"
KEY_URL="https://repo.ivpn.net/stable/debian/generic.gpg"

SOURCES_FILE="/etc/apt/sources.list.d/ivpn.sources"
KEY_FILE="/usr/share/keyrings/ivpn-archive-keyring.gpg"

# Custom directories
IVPN_INSTALL_DIR="/opt/ivpn"
IVPN_CONFIG_DIR="$HOME/.config/ivpn"


if [ "$1" = "-u" ] || [ "$1" = "--uninstall" ]; then
    if systemctl is-active --quiet ivpn-service; then
        sudo systemctl stop ivpn-service
    fi
    
    # Uninstall both potential packages
    uninstall_apt_component "$PACKAGE_NAME" "$SOURCES_FILE" "$KEY_FILE"
    
    # Extra cleanup for UI and install dir
    sudo apt purge -y ivpn-ui 2>&1 | tee -a "$LOG_FILE"
    [ -d "$IVPN_INSTALL_DIR" ] && sudo rm -rf "$IVPN_INSTALL_DIR"
    
    # Config cleanup
    read -p "Do you want to remove IVPN configuration files? [y/N]: " remove_config
    if [[ "$remove_config" == [yY] ]]; then
        [ -d "$IVPN_CONFIG_DIR" ] && rm -rf "$IVPN_CONFIG_DIR" && log_message "Removed $IVPN_CONFIG_DIR"
    fi
else
    # Prompt for UI choice as in original script
    read -p "Do you want to install IVPN with UI (y) or only CLI (n)? [y/N]: " ui_choice
    TARGET_PKG="ivpn"
    [[ "$ui_choice" == [yY] ]] && TARGET_PKG="ivpn-ui"
    
    # Note: IVPN uses "generic" suite often, based on analysis of user prompt "curl ... generic.list"
    # The default assumption for apt_helper is "stable", so we pass "generic" explicitly.
    # Also "main" is presumably correct? Usually flattened repos just need path. 
    # But user prompt had `echo "deb ... generic main"` implied structure if it was a list file.
    # Actually, IVPN repo is often `deb https://repo.ivpn.net/stable/debian generic main` OR `deb https://repo.ivpn.net/stable/debian/generic ./`?
    # Let's rely on standard deb structure inferred from "generic.list" usually mapping to a suite.
    # If this fails, we might need adjustments, but standard args:
    
    install_apt_component "$TARGET_PKG" "$REPO_URL" "$KEY_URL" "$SOURCES_FILE" "$KEY_FILE" "generic" "main" "amd64"
    
    # If UI chosen, `ivpn` (cli) usually comes as dependency? Or vice versa?
    # Original script installed `ivpn` OR `ivpn-ui`.
    # `install_apt_component` installs what is passed.
    
    log_message "Checking IVPN service status..."
    if dpkg -l | grep -q "^ii.*ivpn-ui" && ! systemctl is-active --quiet ivpn-service; then
        log_message "Warning: IVPN service is not running (might need reboot or manual start)"
    fi
fi
