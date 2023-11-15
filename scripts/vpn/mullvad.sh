#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: VPN
# DEBIAN_TOOLS_NAME: Mullvad VPN
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PACKAGE: mullvad-vpn
# Mullvad VPN Installation Script
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
PACKAGE_NAME="mullvad-vpn"
REPO_URL="https://repository.mullvad.net/deb/stable"
KEY_URL="https://repository.mullvad.net/deb/mullvad-keyring.asc"

SOURCES_FILE="/etc/apt/sources.list.d/mullvad.sources"
KEY_FILE="/usr/share/keyrings/mullvad-keyring.asc"

# Legacy cleanup
LEGACY_LIST="/etc/apt/sources.list.d/mullvad.list"

# Custom directories
MULLVAD_INSTALL_DIR="/opt/Mullvad VPN"

check_system_requirements() {
    log_message "Checking system requirements..."

    if [ "$EUID" -eq 0 ]; then
        exit_with_error "This script should not be run as root. Please run without sudo."
    fi

    # Disk space check
    available_space=$(df -BG /opt | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 1 ]; then
        log_message "Warning: Less than 1GB of free space available ($available_space GB)"
        read -p "Continue anyway? [y/N]: " continue_anyway
        [[ "$continue_anyway" != [yY] ]] && exit_with_error "Aborted due to insufficient disk space"
    fi

    # DNS Connectivity check
    if ! ping -c 1 8.8.8.8 &> /dev/null && ! ping -c 1 1.1.1.1 &> /dev/null; then
         exit_with_error "No internet connection detected (tried multiple DNS servers)"
    fi
    
    if ! pidof systemd >/dev/null; then
        exit_with_error "This script requires systemd to be running"
    fi
}


verify_mullvad_installation() {
     # Helper logic specific to Mullvad services
    if ! systemctl is-enabled --quiet mullvad-daemon 2>/dev/null; then
        log_message "Enabling Mullvad daemon..."
        if ! sudo systemctl enable --now mullvad-daemon 2>&1 | tee -a "$LOG_FILE"; then
            log_message "Warning: Failed to enable daemon"
        fi
    fi
    
    if ! curl -s https://api.mullvad.net/www/ &>/dev/null; then
        log_message "Warning: Cannot connect to Mullvad API (VPN might be blocking itself or offline)"
    fi
}

if [ "$1" = "-u" ] || [ "$1" = "--uninstall" ]; then
    # Custom Mullvad cleanup
    if systemctl is-active --quiet mullvad-daemon; then
         sudo systemctl stop mullvad-daemon
    fi
    
    # Uninstall core package and repo
    uninstall_apt_component "$PACKAGE_NAME" "$SOURCES_FILE" "$KEY_FILE" "$LEGACY_LIST"
    
    # Also remove browser
    if dpkg -l | grep -q "mullvad-browser"; then
        log_message "Removing Mullvad Browser..."
        sudo apt purge -y mullvad-browser 2>&1 | tee -a "$LOG_FILE"
    fi
    
    # Cleanup install dir
    [ -d "$MULLVAD_INSTALL_DIR" ] && sudo rm -rf "$MULLVAD_INSTALL_DIR"
else
    check_system_requirements
    
    # Install VPN (this sets up Repo and Key)
    # Using specific arch calculation as in original script, or default to amd64 if safer?
    # Original used: $(dpkg --print-architecture)
    # apt_helper defaults to amd64. 
    # Let's enforce amd64 to be safe and consistent with other scripts unless user is sure.
    # User's other scripts explicitly requested amd64. 
    # But Mullvad script originally supported auto-detect. 
    # I will stick to amd64 for consistency with the prompt instructions ("integrate these..."), 
    # but the prompt didn't explicitly restrict Mullvad to amd64 like others. 
    # However, keeping it simple: apt_helper takes explicit arch.
    
    # Install VPN (Manual implementation as requested)
    log_message "Installing Mullvad VPN..."
    
    # 1. Download key
    log_message "Downloading signing key..."
    if ! sudo curl -fsSLo /usr/share/keyrings/mullvad-keyring.asc https://repository.mullvad.net/deb/mullvad-keyring.asc; then
        exit_with_error "Failed to download Mullvad signing key"
    fi
    
    # 2. Add repo
    log_message "Adding repository..."
    # Note: explicitly using the architecture of the current system as requested
    echo "deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=$( dpkg --print-architecture )] https://repository.mullvad.net/deb/stable stable main" | sudo tee /etc/apt/sources.list.d/mullvad.list > /dev/null
    
    # Clean up potentially conflicting source file from previous attempts (apt_helper uses .sources)
    if [ -f "/etc/apt/sources.list.d/mullvad.sources" ]; then
         log_message "Removing conflicting /etc/apt/sources.list.d/mullvad.sources"
         sudo rm "/etc/apt/sources.list.d/mullvad.sources"
    fi

    # 3. Update and Install
    log_message "Updating package lists..."
    # Using tee to ensure output goes to stdout (terminal) AND log
    if ! sudo apt update 2>&1 | tee -a "$LOG_FILE"; then
        exit_with_error "apt update failed"
    fi
    
    log_message "Installing package..."
    if ! sudo apt install -y mullvad-vpn 2>&1 | tee -a "$LOG_FILE"; then
        exit_with_error "Failed to install mullvad-vpn"
    fi
    
    # Install Browser as requested in original script
    log_message "Installing Mullvad Browser..."
    if ! sudo apt install -y mullvad-browser 2>&1 | tee -a "$LOG_FILE"; then
        log_message "Warning: Mullvad Browser installation failed (VPN installed successfully)"
    fi
    
    verify_mullvad_installation
fi
