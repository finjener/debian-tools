#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Editors
# DEBIAN_TOOLS_NAME: Antigravity AI
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PATH: /usr/bin/antigravity
# Antigravity Installation Script
# Official installation: https://us-central1-apt.pkg.dev

set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "antigravity"

# Configuration
PACKAGE_NAME="antigravity"
KEY_URL="https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg"
KEY_FILE="/etc/apt/keyrings/antigravity-repo-key.gpg"
LIST_FILE="/etc/apt/sources.list.d/antigravity.list"

# Repository configuration (using old-style .list format as per official docs)
REPO_LINE="deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main"

install_antigravity() {
    dt_header "Antigravity IDE Installation"
    
    dt_step 1 4 "Installing prerequisites..."
    sudo apt-get install -y curl gpg 2>&1 | tee -a "$DT_LOG_FILE"
    
    dt_step 2 4 "Adding GPG key..."
    curl -fsSL "$KEY_URL" | sudo gpg --dearmor --yes -o "$KEY_FILE" 2>&1 | tee -a "$DT_LOG_FILE"
    
    dt_step 3 4 "Adding repository..."
    echo "$REPO_LINE" | sudo tee "$LIST_FILE" > /dev/null
    dt_success "Repository added: $LIST_FILE"
    
    dt_step 4 4 "Installing Antigravity..."
    sudo apt update 2>&1 | tee -a "$DT_LOG_FILE"
    sudo apt install -y "$PACKAGE_NAME" 2>&1 | tee -a "$DT_LOG_FILE"
    
    dt_success "Antigravity installed successfully!"
}

uninstall_antigravity() {
    dt_header "Antigravity IDE Uninstallation"
    
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

if [ "$1" = "-u" ] || [ "$1" = "--uninstall" ]; then
    uninstall_antigravity
else
    install_antigravity
fi
