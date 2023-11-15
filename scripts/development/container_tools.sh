#!/bin/bash


# DEBIAN_TOOLS_CATEGORY: Development
# DEBIAN_TOOLS_NAME: Container Tools
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_COMMAND: podman --version
# Container Development Tools Setup
# Installs Docker, Podman, Distrobox, and related utilities.

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "container_tools"

# Legacy logging functions for compatibility
log_info() { dt_info "$1"; }
log_success() { dt_success "$1"; }
log_warn() { dt_warn "$1"; }
log_error() { dt_error "$1"; }

# --------------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------------

main() {
    log_info "Starting Container Tools installation..."
    log_info "Log file: $DT_LOG_FILE"
    
    # Needs sudo for apt
    if [ "$EUID" -ne 0 ]; then
        log_warn "This script requires sudo privileges to install packages."
        # We'll just let the sudo command inside fail or prompt if needed, 
        # but better to re-exec or just use sudo for specific commands.
        # We will use 'sudo' prefix for apt commands.
    fi

    # List of packages to install
    # docker.io: Debian's docker package
    # docker-compose: The older python one, OR docker-compose-plugin? 
    # Debian Bookworm+ typically has docker.io and docker-compose-plugin (or docker-compose).
    # We will try to be broad.
    
    local packages=(
        "docker.io"
        "podman"
        "podman-compose"
        "podman-toolbox" # If available
        "distrobox"
        "uidmap" # Required for rootless podman
        "slirp4netns" # Required for rootless networking
        "fuse-overlayfs" # Improved overlay fs
        # Optional: try to install docker-compose if available
        "docker-compose"
    )

    log_info "Updating package lists..."
    sudo apt update 2>&1 | tee -a "$DT_LOG_FILE"

    log_info "Installing packages: ${packages[*]}"
    if sudo apt install -y "${packages[@]}" 2>&1 | tee -a "$DT_LOG_FILE"; then
        log_success "Container tools installed successfully."
    else
        log_error "Failed to install some packages. Check the output above."
        # Don't exit, proceed to configuration checks
    fi

    # Post-Install Configuration Checks

    # 1. Docker Group
    if getent group docker > /dev/null; then
        if groups "$USER" | grep -q "\bdocker\b"; then
            log_success "User '$USER' is already in the 'docker' group."
        else
            log_warn "User '$USER' is NOT in the 'docker' group."
            log_warn "You will need to run 'sudo usermod -aG docker $USER' or use our 'user_groups.sh' script."
            # Optional: Offer to run it?
            # We'll leave it to the user to run the dedicated user_groups script to keep this focused.
        fi
    fi

    # 2. Podman Rootless Check
    log_info "Verifying Podman (Rootless)..."
    if podman info &>/dev/null; then
        log_success "Podman is working correctly."
    else
        log_warn "Podman verify failed. You might need to re-login to apply subuid/subgid changes."
    fi

    # 3. Distrobox Check
    if command -v distrobox &>/dev/null; then
        local db_ver=$(distrobox version 2>/dev/null | head -n 1)
        log_success "Distrobox is installed: $db_ver"
    fi
    
    log_info "Installation complete."
    log_info "Recommended: Run './scripts/system/user_groups.sh' to ensure you have permissions for Docker."
}

main "$@"
