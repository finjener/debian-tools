#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Browsers
# DEBIAN_TOOLS_NAME: Brave Browser
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_COMMAND: brave-browser --version
# DEBIAN_TOOLS_DESCRIPTION: Install and uninstall Brave browser
# Brave Browser Installation Script
# Official installation: https://brave.com/linux/

set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "brave-browser"

# Configuration
PACKAGE_NAME="brave-browser"
KEY_URL="https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg"
KEY_FILE="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
SOURCES_FILE="/etc/apt/sources.list.d/brave-browser-release.sources"
SOURCES_URL="https://brave-browser-apt-release.s3.brave.com/brave-browser.sources"

install_brave() {
    dt_header "Brave Browser Installation"
    
    dt_step 1 4 "Installing prerequisites..."
    sudo apt-get install -y curl 2>&1 | tee -a "$DT_LOG_FILE"
    
    dt_step 2 4 "Adding GPG key..."
    sudo curl -fsSLo "$KEY_FILE" "$KEY_URL" 2>&1 | tee -a "$DT_LOG_FILE"
    dt_success "GPG key added: $KEY_FILE"
    
    dt_step 3 4 "Adding repository..."
    sudo curl -fsSLo "$SOURCES_FILE" "$SOURCES_URL" 2>&1 | tee -a "$DT_LOG_FILE"
    dt_success "Repository added: "$SOURCES_FILE""
    
    dt_step 4 4 "Installing Brave Browser..."
    sudo apt update 2>&1 | tee -a "$DT_LOG_FILE"
    sudo apt install -y "$PACKAGE_NAME" 2>&1 | tee -a "$DT_LOG_FILE"
    
    dt_success "Brave Browser installed successfully!"
    
    # Verify installation
    if command -v brave-browser &>/dev/null; then
        dt_info "Brave binary location: $(which brave-browser)"
    fi
}

uninstall_brave() {
    dt_header "Brave Browser Uninstallation"
    
    if ! dpkg -l | grep -q "^ii.*$PACKAGE_NAME"; then
        dt_warn "$PACKAGE_NAME is not installed."
        exit 0
    fi
    
    if ! dt_confirm "Are you sure you want to uninstall $PACKAGE_NAME?" "n"; then
        dt_info "Uninstallation cancelled."
        exit 0
    fi
    
    dt_info "Purging package..."
    sudo apt-get purge -y "$PACKAGE_NAME" brave-keyring 2>&1 | tee -a "$DT_LOG_FILE"
    
    dt_info "Removing configuration files..."
    [ -f "$SOURCES_FILE" ] && sudo rm "$SOURCES_FILE"
    [ -f "$KEY_FILE" ] && sudo rm "$KEY_FILE"
    
    sudo apt-get autoremove -y 2>&1 | tee -a "$DT_LOG_FILE"
    sudo apt-get update 2>&1 | tee -a "$DT_LOG_FILE"
    
    dt_success "Uninstallation complete."
}

show_usage() {
    echo "Brave Browser Installation Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --uninstall, -u       Uninstall Brave Browser"
    echo "  --help, -h            Show this help message"
    echo ""
    echo "Log location: $DT_LOG_DIR/"
    echo ""
}

case "$1" in
    --uninstall|-u)
        uninstall_brave
        ;;
    --help|-h)
        show_usage
        ;;
    *)
        install_brave
        ;;
esac
