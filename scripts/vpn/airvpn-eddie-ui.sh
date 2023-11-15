#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: VPN
# DEBIAN_TOOLS_NAME: AirVPN Eddie
# DEBIAN_TOOLS_TYPE: InstallUninstall
# DEBIAN_TOOLS_DETECT_PACKAGE: eddie-ui
# AirVPN Eddie UI Installation Script
# Installs Eddie UI from official repository

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "airvpn_eddie"

EDDIE_REPO_SOURCES="/etc/apt/sources.list.d/eddie.website.sources"
EDDIE_KEY_FILE="/usr/share/keyrings/eddie.website-keyring.asc"
EDDIE_KEY_URL="https://eddie.website/repository/keys/eddie_maintainer_gpg.key"
EDDIE_REPO_URL="http://eddie.website/repository/apt"

check_requirements() {
    log_message "Checking system requirements..."
    if ! command -v curl &> /dev/null; then
        dt_error "curl is required but not installed (install with: sudo apt install curl)"
        exit 1
    fi
}

log_message() {
    dt_log "$1" true
}

add_repository() {
    log_message "Adding Eddie repository..."

    log_message "Installing Eddie signing key..."
    # Download key, dearmor, and save to keyrings
    if ! curl -fsSL "$EDDIE_KEY_URL" | gpg --dearmor | sudo tee "$EDDIE_KEY_FILE" > /dev/null; then
        dt_error "Failed to install Eddie signing key"
        exit 1
    fi

    log_message "Creating repository configuration..."
    cat << EOF | sudo tee "$EDDIE_REPO_SOURCES" > /dev/null
Types: deb
URIs: $EDDIE_REPO_URL
Suites: stable
Components: main
Architectures: amd64 arm64
Signed-By: $EDDIE_KEY_FILE
EOF

    log_message "Updating package lists..."
    if ! dt_sudo apt-get update 2>&1 | tee -a "$DT_LOG_FILE"; then
        dt_error "Failed to update package lists"
        exit 1
    fi
}

install_eddie() {
    log_message "Installing Eddie UI..."

    if ! dt_sudo apt-get install -y eddie-ui 2>&1 | tee -a "$DT_LOG_FILE"; then
        dt_error "Failed to install Eddie UI"
        exit 1
    fi

    if ! command -v eddie-ui &> /dev/null; then
        dt_error "Installation appeared to succeed but 'eddie-ui' command not found"
        exit 1
    fi
    
    dt_success "Eddie UI installed successfully"
}

uninstall_eddie() {
    log_message "Starting uninstallation..."

    if pgrep -f eddie-ui &>/dev/null; then
        log_message "Stopping Eddie service..."
        pkill -f eddie-ui
    fi

    log_message "Removing Eddie package..."
    if ! dt_sudo apt-get purge -y eddie-ui 2>&1 | tee -a "$DT_LOG_FILE"; then
        dt_error "Failed to remove Eddie package"
        exit 1
    fi

    if [ -f "$EDDIE_REPO_SOURCES" ]; then
        log_message "Removing repository configuration..."
        dt_sudo rm -f "$EDDIE_REPO_SOURCES"
    fi

    if [ -f "$EDDIE_KEY_FILE" ]; then
        log_message "Removing signing key..."
        dt_sudo rm -f "$EDDIE_KEY_FILE"
    fi
    
    dt_sudo apt-get autoremove -y 2>&1 | tee -a "$DT_LOG_FILE"
    dt_success "Uninstallation completed successfully"
}

main() {
    log_message "Starting Eddie script..."
    check_requirements

    case "${1:-}" in
        "-u"|"--uninstall")
            if ! dpkg -l | grep -q "eddie-ui"; then
                dt_info "Eddie UI is not installed"
                exit 0
            fi

            if ! dt_confirm "Are you sure you want to uninstall Eddie UI?" "n"; then
                 exit 0
            fi

            uninstall_eddie
            ;;

        ""|"-i"|"--install")
            if dpkg -l | grep -q "eddie-ui"; then
                dt_info "Eddie UI is already installed."
                 if ! dt_confirm "Re-install?" "n"; then
                    exit 0
                fi
            fi

            if ! dt_confirm "Proceed with installation of Eddie UI?" "y"; then
                exit 0
            fi

            add_repository
            install_eddie
            ;;

        *)
            echo "Usage: $0 [-i|--install] [-u|--uninstall]"
            exit 1
            ;;
    esac
}

main "$@"
