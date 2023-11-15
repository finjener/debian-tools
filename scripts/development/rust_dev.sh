#!/bin/bash


# DEBIAN_TOOLS_CATEGORY: Development
# DEBIAN_TOOLS_NAME: Rust Development
# DEBIAN_TOOLS_TYPE: Configure
# DEBIAN_TOOLS_DETECT_COMMAND: rustc --version
# Rust Development Environment Setup
# Installs packages required for compiling C/C++ (build-essential) and installs Rust via rustup.

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "rust_dev"

# --------------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------------

main() {
    dt_info "Starting Rust environment setup..."
    dt_info "Log file: $DT_LOG_FILE"

    # 1. Install System Dependencies (C Linker)
    dt_info "Variables: Checking for build-essential and curl..."
    if ! dpkg -l | grep -q "build-essential" || ! command -v curl &>/dev/null; then
        dt_warn "Missing dependencies. Requesting sudo to install 'build-essential' and 'curl'..."
        if sudo apt update && sudo apt install -y build-essential curl 2>&1 | tee -a "$DT_LOG_FILE"; then
            dt_success "System dependencies installed."
        else
            dt_error "Failed to install system dependencies."
            exit 1
        fi
    else
        dt_success "System dependencies (build-essential, curl) are present."
    fi

    # 2. Check/Install Rustup
    if command -v rustup &>/dev/null; then
        dt_info "Rustup is already installed. Updating..."
        if rustup update 2>&1 | tee -a "$DT_LOG_FILE"; then
            dt_success "Rust toolchain updated."
        else
            dt_error "Failed to update Rust toolchain."
        fi
    else
        dt_info "Installing Rust via rustup (non-interactive)..."
        if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>&1 | tee -a "$DT_LOG_FILE"; then
            dt_success "Rust installed successfully."
            
            # Source environment for this session
            if [ -f "$HOME/.cargo/env" ]; then
                source "$HOME/.cargo/env"
            fi
        else
            dt_error "Rust installation failed."
            exit 1
        fi
    fi

    # 3. Verify
    dt_info "Verifying installation..."
    if command -v rustc &>/dev/null; then
        local version=$(rustc --version)
        local cargo_ver=$(cargo --version)
        dt_success "Verification passed:"
        echo "   $version"
        echo "   $cargo_ver"
        dt_info "NOTE: You may need to restart your shell or run 'source $HOME/.cargo/env' to use rustc in this terminal."
    else
        # If we just installed it, it might not be in PATH yet for this script execution context if sourcing failed
        if [ -f "$HOME/.cargo/bin/rustc" ]; then
             dt_success "Rust installed to $HOME/.cargo/bin/rustc"
             dt_warn "Please restart your terminal to update PATH."
        else
             dt_error "Verification failed. 'rustc' not found."
        fi
    fi
}

main "$@"
