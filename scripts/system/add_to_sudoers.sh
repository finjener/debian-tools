#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: System
# DEBIAN_TOOLS_NAME: Add to Sudoers
# DEBIAN_TOOLS_TYPE: Configure
# Sudoers Configuration Script
# Adds users to sudoers file and sudo group

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "add_to_sudoers"

# Legacy functions for compatibility
exit_with_error() {
    dt_error "$1"
    exit 1
}

log_message() {
    dt_log "$1" true
}

check_system_requirements() {
    log_message "Checking system requirements..."

    if ! command -v sudo &>/dev/null; then
        exit_with_error "sudo is not installed on this system"
    fi

    if ! sudo -v &>/dev/null; then
        exit_with_error "Current user does not have sudo privileges"
    fi

    if ! sudo test -w /etc/sudoers; then
        exit_with_error "/etc/sudoers is not writable even with sudo"
    fi
}

validate_username() {
    local username="$1"
    
    if [ -z "$username" ]; then
        exit_with_error "Username cannot be empty"
    fi
    
    if ! [[ "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
        exit_with_error "Invalid username. Only alphanumeric characters and underscores are allowed."
    fi
    
    if ! getent passwd "$username" > /dev/null 2>&1; then
        exit_with_error "User $username does not exist in the system"
    fi
    
    if groups "$username" | grep -q "\bsudo\b"; then
        log_message "Note: User $username is already in the sudo group"
    fi
    
    if sudo grep -q "^$username\s" /etc/sudoers; then
        exit_with_error "User $username already has an entry in /etc/sudoers"
    fi
}

backup_sudoers() {
    local backup_file="/etc/sudoers.bak_${timestamp}"
    log_message "Creating backup of sudoers file at $backup_file"
    
    if ! sudo cp /etc/sudoers "$backup_file"; then
        exit_with_error "Failed to create backup of sudoers file"
    fi
    
    if ! sudo chmod 440 "$backup_file"; then
        exit_with_error "Failed to set permissions on sudoers backup file"
    fi
}

add_to_sudo_group() {
    local username="$1"
    log_message "Adding user $username to sudo group..."
    
    if ! sudo usermod -aG sudo "$username"; then
        exit_with_error "Failed to add user to sudo group"
    fi
    log_message "Successfully added $username to sudo group"
}

add_to_sudoers() {
    local username="$1"
    local sudoers_entry="$username    ALL=(ALL:ALL) ALL"
    
    log_message "Adding user $username to sudoers file..."
    
    if ! echo "$sudoers_entry" | sudo EDITOR='tee -a' visudo > /dev/null; then
        exit_with_error "Failed to add user to sudoers file"
    fi
    
    if ! sudo grep -q "^$username\s" /etc/sudoers; then
        exit_with_error "Failed to verify sudoers entry"
    fi
    
    log_message "Successfully added $username to sudoers file"
}

main() {
    log_message "Starting sudoers configuration script..."
    
    check_system_requirements
    
    read -p "Enter the username: " username
    validate_username "$username"
    
    echo -e "\nWarning: Adding a user to sudoers grants them administrative privileges."
    echo "This is a security-sensitive operation."
    read -p "Are you sure you want to add user $username to sudoers? [y/N]: " confirm
    if [[ "$confirm" != [yY] ]]; then
        log_message "Operation cancelled by user"
        exit 0
    fi
    
    backup_sudoers
    
    add_to_sudo_group "$username"
    add_to_sudoers "$username"
    
    log_message "All operations completed successfully"
    echo -e "\nSuccessfully added $username to sudoers and sudo group"
    echo "Log file: $DT_LOG_FILE"
    echo "Please log out and log back in for the changes to take effect"
}

main
