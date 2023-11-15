#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Browsers
# DEBIAN_TOOLS_NAME: Floorp Browser
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_COMMAND: floorp --version
# Floorp Browser Installation Script
# Official installation: https://ppa.floorp.app

set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "floorp"

# Configuration
PACKAGE_NAME="floorp"
KEY_URL="https://ppa.floorp.app/KEY.gpg"
KEY_FILE="/usr/share/keyrings/Floorp.gpg"
LIST_FILE="/etc/apt/sources.list.d/Floorp.list"
LIST_URL="https://ppa.floorp.app/Floorp.list"

install_floorp() {
    dt_header "Floorp Browser Installation"
    
    dt_step 1 4 "Installing prerequisites..."
    sudo apt-get install -y curl gpg 2>&1 | tee -a "$DT_LOG_FILE"
    
    dt_step 2 4 "Adding GPG key..."
    curl -fsSL "$KEY_URL" | sudo gpg --dearmor -o "$KEY_FILE" 2>&1 | tee -a "$DT_LOG_FILE"
    dt_success "GPG key added: $KEY_FILE"
    
    dt_step 3 4 "Adding repository..."
    sudo curl -sS --compressed -o "$LIST_FILE" "$LIST_URL" 2>&1 | tee -a "$DT_LOG_FILE"
    dt_success "Repository added: $LIST_FILE"
    
    dt_step 4 4 "Installing Floorp..."
    sudo apt update 2>&1 | tee -a "$DT_LOG_FILE"
    sudo apt install -y "$PACKAGE_NAME" 2>&1 | tee -a "$DT_LOG_FILE"
    
    dt_success "Floorp Browser installed successfully!"
    
    # Verify installation
    if command -v floorp &>/dev/null; then
        dt_info "Floorp binary location: $(which floorp)"
    fi
}

uninstall_floorp() {
    dt_header "Floorp Browser Uninstallation"
    
    if ! dpkg -l | grep -q "^ii.*$PACKAGE_NAME"; then
        dt_warn "$PACKAGE_NAME is not installed."
        exit 0
    fi
    
    if ! dt_confirm "Are you sure you want to uninstall $PACKAGE_NAME?" "n"; then
        dt_info "Uninstallation cancelled."
        exit 0
    fi
    
    dt_info "Purging package..."
    sudo apt-get purge -y "$PACKAGE_NAME" 2>&1 | tee -a "$DT_LOG_FILE"
    
    dt_info "Removing configuration files..."
    [ -f "$LIST_FILE" ] && sudo rm "$LIST_FILE"
    [ -f "$KEY_FILE" ] && sudo rm "$KEY_FILE"
    
    sudo apt-get autoremove -y 2>&1 | tee -a "$DT_LOG_FILE"
    sudo apt-get update 2>&1 | tee -a "$DT_LOG_FILE"
    
    dt_success "Uninstallation complete."
}

show_usage() {
    echo "Floorp Browser Installation Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --uninstall, -u       Uninstall Floorp Browser"
    echo "  --help, -h            Show this help message"
    echo ""
    echo "Log location: $DT_LOG_DIR/"
    echo ""
}

case "$1" in
    --uninstall|-u)
        uninstall_floorp
        ;;
    --help|-h)
        show_usage
        ;;
    *)
        install_floorp
        ;;
esac
