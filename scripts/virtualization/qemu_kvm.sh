#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Virtualization
# DEBIAN_TOOLS_NAME: QEMU/KVM
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PACKAGE: qemu-system-x86
# QEMU/KVM Installation Script
# Installs virtualization packages and configures user groups

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "qemu_kvm"

DEBIAN_PACKAGES=(
    "qemu-kvm"
    "libvirt-daemon-system"
    "libvirt-clients"
    "bridge-utils"
    "virt-manager"
    "swtpm"
    "ovmf"
    "qemu-utils"
    "virt-viewer"
)

REQUIRED_GROUPS=("libvirt" "kvm")

# Legacy functions for compatibility
exit_with_error() {
    dt_error "$1"
    exit 1
}

log_message() {
    dt_log "$1" true
}

validate_username() {
    local username="$1"

    if [ -z "$username" ]; then
        exit_with_error "Username cannot be empty"
    fi

    if ! id "$username" &>/dev/null; then
        exit_with_error "User '$username' does not exist"
    fi
}

manage_user_groups() {
    local username="$1"
    local action="$2"

    validate_username "$username"

    for group in "${REQUIRED_GROUPS[@]}"; do
        log_message "Checking $username membership in $group group..."

        if [ "$action" = "add" ]; then
            if ! groups "$username" | grep -qw "$group"; then
                log_message "Adding $username to $group group..."
                if ! sudo usermod -aG "$group" "$username"; then
                    exit_with_error "Failed to add $username to $group group"
                fi
            else
                log_message "User $username is already a member of $group"
            fi
        elif [ "$action" = "remove" ]; then
            if groups "$username" | grep -qw "$group"; then
                log_message "Removing $username from $group group..."
                if ! sudo gpasswd -d "$username" "$group"; then
                    exit_with_error "Failed to remove $username from $group group"
                fi
            else
                log_message "User $username is not a member of $group"
            fi
        fi
    done
}

manage_libvirt_service() {
    local action="$1"

    log_message "Managing libvirt service: $action"

    case "$action" in
        enable)
            if ! sudo systemctl enable libvirtd 2>&1 | tee -a "$DT_LOG_FILE"; then
                exit_with_error "Failed to enable libvirtd service"
            fi
            ;;
        disable)
            if ! sudo systemctl disable libvirtd 2>&1 | tee -a "$DT_LOG_FILE"; then
                exit_with_error "Failed to disable libvirtd service"
            fi
            ;;
        start)
            if ! sudo systemctl start libvirtd 2>&1 | tee -a "$DT_LOG_FILE"; then
                exit_with_error "Failed to start libvirtd service"
            fi
            ;;
        stop)
            if ! sudo systemctl stop libvirtd 2>&1 | tee -a "$DT_LOG_FILE"; then
                exit_with_error "Failed to stop libvirtd service"
            fi
            ;;
    esac
}

install_qemu_kvm() {
    log_message "Installing QEMU/KVM packages..."

    log_message "Updating package lists..."
    if ! sudo apt update 2>&1 | tee -a "$DT_LOG_FILE"; then
        exit_with_error "Failed to update package lists"
    fi

    log_message "Installing required packages..."
    if ! sudo apt install -y "${DEBIAN_PACKAGES[@]}" 2>&1 | tee -a "$DT_LOG_FILE"; then
        exit_with_error "Failed to install QEMU/KVM packages"
    fi

    manage_libvirt_service "enable"
    manage_libvirt_service "start"
}

uninstall_qemu_kvm() {
    log_message "Uninstalling QEMU/KVM..."

    manage_libvirt_service "stop"
    manage_libvirt_service "disable"

    log_message "Removing QEMU/KVM packages..."
    if ! sudo apt purge -y "${DEBIAN_PACKAGES[@]}" 2>&1 | tee -a "$DT_LOG_FILE"; then
        exit_with_error "Failed to remove QEMU/KVM packages"
    fi

    log_message "Cleaning up dependencies..."
    if ! sudo apt autoremove -y 2>&1 | tee -a "$DT_LOG_FILE"; then
        exit_with_error "Failed to clean up dependencies"
    fi
}

main() {
    log_message "Starting QEMU/KVM script..."

    case "${1:-}" in
        "-u"|"--uninstall")
            read -p "Are you sure you want to uninstall QEMU/KVM and related tools? [y/N]: " confirm
            if [[ "$confirm" != [yY] ]]; then
                log_message "Uninstallation cancelled by user"
                exit 0
            fi

            read -p "Enter the username: " username

            manage_user_groups "$username" "remove"

            uninstall_qemu_kvm
            ;;

        ""|"-i"|"--install")
            echo -e "\nQEMU/KVM and related tools will be installed:"
            printf '%s\n' "${DEBIAN_PACKAGES[@]}" | sed 's/^/- /'

            read -p "Do you want to proceed? [y/N]: " confirm
            if [[ "$confirm" != [yY] ]]; then
                log_message "Installation cancelled by user"
                exit 0
            fi

            read -p "Enter the username: " username

            install_qemu_kvm

            manage_user_groups "$username" "add"

            echo -e "\nInstallation complete. Please log out and log back in for the group changes to take effect."
            echo "You can then launch virt-manager to manage virtual machines."
            ;;

        *)
            echo "Usage: $0 [-i|--install] [-u|--uninstall]"
            echo "  -i, --install    Install QEMU/KVM and related tools (default)"
            echo "  -u, --uninstall  Uninstall QEMU/KVM and related tools"
            exit 1
            ;;
    esac

    log_message "Script completed successfully"
}

main "$@"
