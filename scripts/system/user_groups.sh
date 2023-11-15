#!/bin/bash


# DEBIAN_TOOLS_CATEGORY: System
# DEBIAN_TOOLS_NAME: User Groups
# DEBIAN_TOOLS_TYPE: Configure
# User Group Management Script
# Adds the current (or specified) user to essential system groups for development,
# virtualization, and hardware access.

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "user_groups"

# Legacy logging functions for compatibility
log_info() { dt_info "$1"; }
log_success() { dt_success "$1"; }
log_warn() { dt_warn "$1"; }
log_error() { dt_error "$1"; }

# --------------------------------------------------------------------------------
# DEFINITIONS
# --------------------------------------------------------------------------------

# Default groups to add the user to:
# - sudo: Administrative privileges
# - docker: Run docker without sudo
# - libvirt/kvm: Virtualization management
# - plugdev: Mount removable devices
# - input: Access input devices (gampeads, etc)
# - video/audio: Hardware acceleration / sound
# - netdev: Network manager control
TARGET_GROUPS=(
    "sudo"
    "docker"
    "libvirt"
    "kvm"
    "libvirt-qemu"
    "plugdev"
    "input"
    "video"
    "render"
    "audio"
    "netdev"
    "dialout" # Serial ports (Arduino etc)
    "bluetooth"
)

# --------------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------------

main() {
    local target_user="${1:-$USER}"

    # Check if user exists
    if ! id "$target_user" &>/dev/null; then
        log_error "User '$target_user' does not exist."
        exit 1
    fi

    log_info "Managing groups for user: $target_user"
    log_info "Log file: $DT_LOG_FILE"
    
    # Needs root for usermod
    if [ "$EUID" -ne 0 ]; then
        log_warn "This script requires sudo privileges to modify user groups."
        exec sudo "$0" "$target_user"
    fi

    local groups_added=0

    for group in "${TARGET_GROUPS[@]}"; do
        # 1. Check if group exists on system
        if ! getent group "$group" > /dev/null; then
            log_warn "Group '$group' does not exist on this system. Skipping."
            continue
        fi

        # 2. Check if user is already a member
        if id -nG "$target_user" | grep -qw "$group"; then
            echo -e " - User '$target_user' is already in '${GREEN}$group${NC}'"
        else
            # 3. Add user to group
            log_info "Adding '$target_user' to group '$group'..."
            usermod -aG "$group" "$target_user"
            
            if [ $? -eq 0 ]; then
                log_success "Added to '$group'"
                ((groups_added++))
            else
                log_error "Failed to add to '$group'"
            fi
        fi
    done

    echo "------------------------------------------------"
    if [ "$groups_added" -gt 0 ]; then
        log_success "Operation complete. $groups_added groups added."
        log_warn "NOTE: You must log out and log back in (or reboot) for group changes to take effect."
    else
        log_info "Operation complete. No changes were necessary."
    fi
    
    # Verify
    echo -e "\nCurrent groups for $target_user:"
    id -nG "$target_user"
}

main "$@"
