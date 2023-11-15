#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Browsers
# DEBIAN_TOOLS_NAME: LibreWolf
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PACKAGE: librewolf
# LibreWolf Browser Installation Script
# Uses extrepo for repository management

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "librewolf"

if [ "$1" = "-u" ]; then
    dt_info "Uninstalling LibreWolf browser..."

    if ! dpkg -l | grep -q "librewolf"; then
        dt_info "LibreWolf browser is not installed."
        exit 0
    fi

    read -p "Do you want to uninstall LibreWolf browser? [y/N]: " proceed
    if [[ "$proceed" != [yY] ]]; then
        dt_info "Uninstallation aborted by the user."
        exit 0
    fi

    dt_info "Removing LibreWolf browser package..."
    if ! sudo apt purge -y librewolf 2>&1 | tee -a "$DT_LOG_FILE"; then
        dt_exit_error "Failed to remove LibreWolf browser package"
    fi

    if command -v extrepo &> /dev/null && extrepo list | grep -q "librewolf: enabled"; then
        dt_info "Disabling LibreWolf repository in extrepo..."
        if ! sudo extrepo disable librewolf 2>&1 | tee -a "$DT_LOG_FILE"; then
            dt_info "Warning: Failed to disable LibreWolf repository in extrepo."
        fi
    else
        if [ -f "/etc/apt/sources.list.d/librewolf.sources" ]; then
            dt_info "Removing LibreWolf repository..."
            if ! sudo rm /etc/apt/sources.list.d/librewolf.sources 2>&1 | tee -a "$DT_LOG_FILE"; then
                dt_exit_error "Failed to remove LibreWolf repository"
            fi
        fi

        if [ -f "/usr/share/keyrings/librewolf.gpg" ]; then
            dt_info "Removing LibreWolf keyring..."
            if ! sudo rm /usr/share/keyrings/librewolf.gpg 2>&1 | tee -a "$DT_LOG_FILE"; then
                dt_exit_error "Failed to remove LibreWolf keyring"
            fi
        fi
    fi

    dt_info "Updating package lists..."
    if ! sudo apt update 2>&1 | tee -a "$DT_LOG_FILE"; then
        dt_exit_error "Failed to update package lists"
    fi

    dt_info "LibreWolf browser uninstalled successfully."
else
    dt_info "Installing LibreWolf browser..."

    if dpkg -l | grep -q "librewolf"; then
        dt_info "LibreWolf browser is already installed."
        exit 0
    fi

    read -p "Do you want to install LibreWolf browser? [y/N]: " proceed
    if [[ "$proceed" != [yY] ]]; then
        dt_info "Installation aborted by the user."
        exit 0
    fi

    dt_info "Installing extrepo package manager..."
    # Note: common.sh sets pipefail so the if ! pattern catches failures through tee
    if ! sudo apt update 2>&1 | tee -a "$DT_LOG_FILE"; then
        dt_exit_error "Failed to update package lists"
    fi
     
    if ! sudo apt install -y extrepo 2>&1 | tee -a "$DT_LOG_FILE"; then
        dt_exit_error "Failed to install extrepo package manager"
    fi
    
    # Verify installation succeeded
    if ! command -v extrepo &>/dev/null; then
        dt_exit_error "extrepo installation failed (command not found)"
    fi

    dt_info "Enabling LibreWolf repository..."
    if ! sudo extrepo enable librewolf 2>&1 | tee -a "$DT_LOG_FILE"; then
        dt_exit_error "Failed to enable LibreWolf repository"
    fi

    dt_info "Updating package lists..."
    if ! sudo apt update 2>&1 | tee -a "$DT_LOG_FILE"; then
        dt_exit_error "Failed to update package lists"
    fi

    dt_info "Installing LibreWolf browser..."
    if ! sudo apt install -y librewolf 2>&1 | tee -a "$DT_LOG_FILE"; then
        dt_exit_error "Failed to install LibreWolf browser"
    fi

    dt_info "LibreWolf browser installed successfully."
fi
