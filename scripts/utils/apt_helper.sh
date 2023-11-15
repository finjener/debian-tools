#!/usr/bin/env bash

# Shared utilities for Debian Tools APT installation scripts
# Provides standardized logging and APT component management (Deb822)

# Ensure this script is sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This script is meant to be sourced, not run directly."
    exit 1
fi

# Source common library for centralized logging
UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
source "$UTILS_DIR/common.sh"

# Script name from caller for logging
if [ -z "$PACKAGE_NAME" ]; then
    PACKAGE_NAME=$(basename "${BASH_SOURCE[1]}" .sh)
fi

# Initialize logging
dt_init_log "$PACKAGE_NAME"

# Legacy compatibility: LOG_FILE for scripts that reference it directly
LOG_FILE="$DT_LOG_FILE"

# Legacy logging functions (for backward compatibility)
log_message() {
    local message="$1"
    dt_log "$message" true
}

exit_with_error() {
    local message="$1"
    dt_error "$message"
    exit 1
}

# Generic function to install an external APT component
# usage: install_apt_component <package_name> <repo_url> <key_url> <sources_file> <key_path> [suite] [component] [arch]
install_apt_component() {
    local package_name="$1"
    local repo_url="$2"
    local key_url="$3"
    local sources_file="$4"
    local key_path="$5"
    local suite="${6:-stable}"
    local component="${7:-main}"
    local arch="${8:-amd64}"
    
    # Optional legacy cleanup args
    local legacy_list_file="$9"
    local legacy_key_file="${10}"

    log_message "Starting installation for $package_name..."

    if dpkg -l | grep -q "^ii.*$package_name"; then
        log_message "$package_name is already installed."
    fi

    # Cleanup legacy files if provided
    if [ -n "$legacy_list_file" ] && [ -f "$legacy_list_file" ]; then
        log_message "Removing legacy list file: $legacy_list_file"
        dt_sudo rm "$legacy_list_file"
    fi
     if [ -n "$legacy_key_file" ] && [ -f "$legacy_key_file" ]; then
        log_message "Removing legacy key file: $legacy_key_file"
        dt_sudo rm "$legacy_key_file"
    fi

    log_message "Installing prerequisites (wget, gpg, curl, apt-transport-https)..."
    dt_sudo apt-get install -y wget gpg curl apt-transport-https 2>&1 | tee -a "$LOG_FILE"

    log_message "Adding GPG key..."
    # Ensure directory exists
    local key_dir=$(dirname "$key_path")
    dt_sudo mkdir -p "$key_dir"

    # Download key (try wget first, fallback to curl)
    if wget -qO- "$key_url" | gpg --dearmor | dt_sudo tee "$key_path" > /dev/null; then
        log_message "GPG key downloaded successfully (wget)."
    elif curl -fsSL "$key_url" | gpg --dearmor | dt_sudo tee "$key_path" > /dev/null; then
        log_message "GPG key downloaded successfully (curl)."
    else
        # Some keys might already be armored or binary, try direct download if dearmor fails
        if wget -qO- "$key_url" | dt_sudo tee "$key_path" > /dev/null; then
             log_message "GPG key downloaded (raw)."
        else
             exit_with_error "Failed to download GPG key from $key_url"
        fi
    fi

    log_message "Creating apt sources file ($sources_file)..."
    cat << EOF | dt_sudo tee "$sources_file" > /dev/null
Types: deb
URIs: $repo_url
Suites: $suite
Components: $component
Architectures: $arch
Signed-By: $key_path
EOF

    log_message "Updating package lists..."
    dt_sudo apt-get update 2>&1 | tee -a "$LOG_FILE"

    log_message "Installing $package_name..."
    if dt_sudo apt-get install -y "$package_name" 2>&1 | tee -a "$LOG_FILE"; then
        log_message "$package_name installed successfully."
    else
        exit_with_error "Failed to install $package_name. Check log: $LOG_FILE"
    fi
}

# Generic function to uninstall an external APT component
# usage: uninstall_apt_component <package_name> <sources_file> <key_path> [legacy_list_file] [legacy_key_file]
uninstall_apt_component() {
    local package_name="$1"
    local sources_file="$2"
    local key_path="$3"
    local legacy_list_file="$4"
    local legacy_key_file="$5"

    log_message "Uninstalling $package_name..."

    if ! dpkg -l | grep -q "^ii.*$package_name"; then
        log_message "$package_name is not installed."
        return 0
    fi

    if ! dt_confirm "Are you sure you want to uninstall $package_name?" "n"; then
        log_message "Uninstallation aborted by user."
        exit 0
    fi

    log_message "Purging package..."
    dt_sudo apt-get purge -y "$package_name" 2>&1 | tee -a "$LOG_FILE"

    log_message "Removing configuration files..."
    [ -f "$sources_file" ] && dt_sudo rm "$sources_file"
    [ -f "$key_path" ] && dt_sudo rm "$key_path"
    [ -n "$legacy_list_file" ] && [ -f "$legacy_list_file" ] && dt_sudo rm "$legacy_list_file"
    [ -n "$legacy_key_file" ] && [ -f "$legacy_key_file" ] && dt_sudo rm "$legacy_key_file"

    log_message "Cleaning up..."
    dt_sudo apt-get autoremove -y 2>&1 | tee -a "$LOG_FILE"
    dt_sudo apt-get update 2>&1 | tee -a "$LOG_FILE"

    log_message "Uninstallation complete."
}
