#!/bin/bash


# DEBIAN_TOOLS_CATEGORY: Desktop
# DEBIAN_TOOLS_NAME: SDDM KWallet PAM
# DEBIAN_TOOLS_TYPE: Configure
# DEBIAN_TOOLS_DETECT_PACKAGE: libpam-kwallet5
# SDDM KWallet PAM Configuration
# Configures /etc/pam.d/sddm to automatically unlock the default KWallet upon login.

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

# Initialize logging
dt_init_log "sddm_kwallet_pam"

# --------------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------------

main() {
    dt_header "SDDM KWallet PAM Setup"
    
    dt_step 1 4 "Checking permissions..."
    
    if [ "$EUID" -ne 0 ]; then
        dt_warn "This script requires sudo privileges"
        exec sudo "$0" "$@"
    fi
    dt_success "Running as root"

    local pam_file="/etc/pam.d/sddm"

    dt_step 2 4 "Installing dependencies..."
    
    if ! apt update -qq && apt install -y libpam-kwallet5 2>&1 | tee -a "$DT_LOG_FILE"; then
        dt_exit_error "Failed to install libpam-kwallet5"
    fi
    dt_success "libpam-kwallet5 installed"

    dt_step 3 4 "Configuring PAM..."
    
    if [ ! -f "$pam_file" ]; then
        dt_exit_error "PAM file $pam_file not found. Is SDDM installed?"
    fi
    
    # Backup
    cp "$pam_file" "${pam_file}.bak_${DT_TIMESTAMP}"
    dt_success "Backup: ${pam_file}.bak_${DT_TIMESTAMP}"

    if grep -q "pam_kwallet5.so" "$pam_file"; then
        dt_info "pam_kwallet5 already configured"
    else
        # Add auth line
        if grep -q "@include common-auth" "$pam_file"; then
            sed -i '/@include common-auth/a auth    optional        pam_kwallet5.so' "$pam_file"
            dt_success "Added auth optional pam_kwallet5.so"
        else
            echo "auth    optional        pam_kwallet5.so" >> "$pam_file"
            dt_warn "Appended auth line (fallback)"
        fi
        
        # Add session line
        if grep -q "@include common-session" "$pam_file"; then
            sed -i '/@include common-session/a session optional        pam_kwallet5.so auto_start' "$pam_file"
            dt_success "Added session optional pam_kwallet5.so auto_start"
        else
            echo "session optional        pam_kwallet5.so auto_start" >> "$pam_file"
        fi
    fi
    
    dt_step 4 4 "Verifying configuration..."
    
    dt_divider
    grep "pam_kwallet5" "$pam_file"
    dt_divider
    
    dt_success "Configuration complete!"
    dt_info "Please logout and login to test."
}

main "$@"
