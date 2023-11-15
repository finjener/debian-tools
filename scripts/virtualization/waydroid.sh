#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Virtualization
# DEBIAN_TOOLS_NAME: Waydroid
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PACKAGE: waydroid
# Waydroid Installation Script
# Android container for Wayland

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "waydroid"

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
        OS_VERSION=$VERSION_ID
    else
        exit_with_error "Cannot detect OS: /etc/os-release not found"
    fi
}

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

    if [ "$EUID" -eq 0 ]; then
        exit_with_error "This script should not be run as root. Please run without sudo."
    fi

    local kernel_version
    kernel_version=$(uname -r | cut -d. -f1,2)
    if ! awk -v ver="$kernel_version" 'BEGIN{exit(ver>=5.10?0:1)}'; then
        log_message "Warning: Kernel version $kernel_version might be too old for WayDroid (recommended: 5.10+)"
        read -p "Continue anyway? [y/N]: " continue_anyway
        [[ "$continue_anyway" != [yY] ]] && exit_with_error "Aborted due to kernel version requirement"
    fi

    available_space=$(df -BG /var | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 5 ]; then
        log_message "Warning: Less than 5GB of free space available ($available_space GB)"
        read -p "Continue anyway? [y/N]: " continue_anyway
        [[ "$continue_anyway" != [yY] ]] && exit_with_error "Aborted due to insufficient disk space"
    fi

    local dns_servers=("8.8.8.8" "1.1.1.1")
    local connected=false
    for dns in "${dns_servers[@]}"; do
        if ping -c 1 "$dns" &> /dev/null; then
            connected=true
            break
        fi
    done
    if ! $connected; then
        exit_with_error "No internet connection detected (tried multiple DNS servers)"
    fi

    if [ -z "$WAYLAND_DISPLAY" ]; then
        log_message "Warning: WayDroid requires Wayland session"
        read -p "Continue anyway? [y/N]: " continue_anyway
        [[ "$continue_anyway" != [yY] ]] && exit_with_error "Aborted due to missing Wayland session"
    fi

    detect_os
    case "$OS_NAME" in
        "debian")
            local required_packages=("curl" "lxc" "python3" "systemd")
            local missing_packages=()
            
            for pkg in "${required_packages[@]}"; do
                if ! dpkg -l | grep -q "^ii.*$pkg"; then
                    missing_packages+=("$pkg")
                fi
            done
            
            if [ ${#missing_packages[@]} -gt 0 ]; then
                log_message "Installing required packages: ${missing_packages[*]}"
                if ! sudo apt update 2>&1 | tee -a "$DT_LOG_FILE" || ! sudo apt install -y "${missing_packages[@]}" 2>&1 | tee -a "$DT_LOG_FILE"; then
                    exit_with_error "Failed to install required packages"
                fi
            fi
        
            exit_with_error "Unsupported operating system: $OS_NAME"
            ;;
    esac

    if ! grep -q "^flags.*\bvmx\b" /proc/cpuinfo && ! grep -q "^flags.*\bsvm\b" /proc/cpuinfo; then
        exit_with_error "CPU virtualization support (VMX/SVM) not detected"
    fi
}

verify_installation() {
    log_message "Verifying installation..."
    
    detect_os
    case "$OS_NAME" in
        "debian")
            if ! dpkg -l | grep -q "^ii.*waydroid"; then
                exit_with_error "WayDroid not installed correctly"
            fi
            ;;
    esac
    
    if [ ! -x "$(command -v waydroid)" ]; then
        exit_with_error "WayDroid executable not found or not executable"
    fi
    
    if ! systemctl list-unit-files | grep -q waydroid; then
        exit_with_error "WayDroid systemd service not installed properly"
    fi
    
    local required_dirs=("/var/lib/waydroid" "/etc/waydroid")
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            exit_with_error "Required directory $dir not found"
        fi
    done
    
    log_message "Installation verification completed successfully"
}

cleanup_waydroid() {
    log_message "Cleaning up WayDroid data..."
    
    local services=("waydroid-container.service" "waydroid-container")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_message "Stopping $service..."
            if ! sudo systemctl stop "$service" 2>&1 | tee -a "$DT_LOG_FILE"; then
                log_message "Warning: Failed to stop $service"
            fi
        fi
    done
    
    local directories=(
        "/var/lib/waydroid"
        "/home/.waydroid"
        "$HOME/waydroid"
        "$HOME/.share/waydroid"
        "$HOME/.local/share/waydroid"
        "$HOME/.local/share/applications/*waydroid*"
    )
    
    for dir in "${directories[@]}"; do
        if [ -e "$dir" ]; then
            log_message "Removing $dir..."
            if ! sudo rm -rf "$dir" 2>&1 | tee -a "$DT_LOG_FILE"; then
                log_message "Warning: Failed to remove $dir"
            fi
        fi
    done
    
    if [ -f "/etc/lxc/lxc-usernet" ]; then
        log_message "Cleaning up LXC configuration..."
        if ! sudo sed -i '/waydroid/d' /etc/lxc/lxc-usernet 2>&1 | tee -a "$DT_LOG_FILE"; then
            log_message "Warning: Failed to clean LXC configuration"
        fi
    fi
    
    log_message "WayDroid data cleanup completed"
}


main() {
    log_message "Starting WayDroid script..."
    
    detect_os
    log_message "Detected OS: $OS_NAME $OS_VERSION"
    
    check_system_requirements

    case "${1:-}" in
        "-u"|"--uninstall")
            case "$OS_NAME" in
                "debian")
                    if ! dpkg -l | grep -q "waydroid"; then
                        log_message "WayDroid is not installed."
                        exit 0
                    fi
                    ;;
            esac

            read -p "Do you want to uninstall WayDroid? [y/N]: " proceed
            if [[ "$proceed" != [yY] ]]; then
                log_message "Uninstallation cancelled by user"
                exit 0
            fi


            case "$OS_NAME" in
                "debian")
                    log_message "Removing WayDroid package..."
                    if ! sudo apt purge -y waydroid 2>&1 | tee -a "$DT_LOG_FILE"; then
                        exit_with_error "Failed to remove WayDroid package"
                    fi

                    log_message "Removing WayDroid repository..."
                    sudo rm -f /etc/apt/sources.list.d/waydroid.list 2>&1 | tee -a "$DT_LOG_FILE"

                    log_message "Updating package lists..."
                    if ! sudo apt update 2>&1 | tee -a "$DT_LOG_FILE"; then
                        exit_with_error "Failed to update package lists"
                    fi
                    ;;
                "fedora")
                    log_message "Removing WayDroid package..."
                    if ! rpm-ostree uninstall waydroid 2>&1 | tee -a "$DT_LOG_FILE"; then
                        exit_with_error "Failed to remove WayDroid package"
                    fi
                    log_message "Please reboot your system to complete the uninstallation"
                    ;;
            esac

            cleanup_waydroid
            ;;
            
        ""|"-i"|"--install")
            case "$OS_NAME" in
                "debian")
                    if dpkg -l | grep -q "waydroid"; then
                        log_message "WayDroid is already installed."
                        exit 0
                    fi
                    ;;
            esac

            read -p "Do you want to install WayDroid? [y/N]: " proceed
            if [[ "$proceed" != [yY] ]]; then
                log_message "Installation cancelled by user"
                exit 0
            fi

            case "$OS_NAME" in
                "debian")
                    log_message "Adding WayDroid repository..."
                    if ! curl https://repo.waydro.id | sudo bash 2>&1 | tee -a "$DT_LOG_FILE"; then
                        exit_with_error "Failed to add WayDroid repository"
                    fi

                    log_message "Updating package lists..."
                    if ! sudo apt update 2>&1 | tee -a "$DT_LOG_FILE"; then
                        exit_with_error "Failed to update package lists"
                    fi

                    log_message "Installing WayDroid..."
                    if ! sudo apt install -y waydroid 2>&1 | tee -a "$DT_LOG_FILE"; then
                        exit_with_error "Failed to install WayDroid"
                    fi
                    ;;
            esac

            verify_installation

            log_message "WayDroid installation completed successfully"

            echo "Please reboot your system to complete the installation"
            ;;
        *)
            echo "Usage: $0 [-i|--install] [-u|--uninstall]"
            echo "  -i, --install    Install WayDroid (default)"
            echo "  -u, --uninstall  Uninstall WayDroid"
            exit 1
            ;;
    esac
    
    log_message "Script completed successfully"
}

main "$@"
