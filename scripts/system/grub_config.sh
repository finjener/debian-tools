#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: System
# DEBIAN_TOOLS_NAME: GRUB Config
# DEBIAN_TOOLS_TYPE: Configure
# GRUB Configuration Script
# Enables saved default boot entry

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "grub_config"

grub_config="/etc/default/grub"

check_system_requirements() {
    dt_info "Checking system requirements..."

    if [ "$EUID" -eq 0 ]; then
        dt_exit_error "This script should not be run as root. Please run without sudo."
    fi

    if ! command -v update-grub &>/dev/null && ! [ -x "/usr/sbin/update-grub" ]; then
        dt_exit_error "update-grub command not found. Please ensure GRUB is properly installed."
    fi

    if [ ! -f "$grub_config" ]; then
        local alt_configs=("/etc/default/grub" "/etc/default/grub.d/grub.cfg" "/boot/grub/grub.cfg")
        for cfg in "${alt_configs[@]}"; do
            if [ -f "$cfg" ]; then
                grub_config="$cfg"
                dt_info "Found GRUB configuration at: $grub_config"
                break
            fi
        done
        
        if [ ! -f "$grub_config" ]; then
            dt_exit_error "GRUB configuration file not found in any standard location"
        fi
    fi

    if ! sudo test -w "$grub_config"; then
        dt_info "Attempting to fix GRUB config permissions..."
        if ! sudo chmod 644 "$grub_config"; then
            dt_exit_error "Cannot write to $grub_config even with sudo. Please check permissions."
        fi
    fi
}

backup_grub_config() {
    local backup_file="${grub_config}.bak_${DT_TIMESTAMP}"
    dt_info "Creating backup of GRUB configuration at $backup_file"
    
    if ! sudo cp "$grub_config" "$backup_file"; then
        dt_exit_error "Failed to create backup of GRUB configuration"
    fi
    
    if ! sudo chmod 644 "$backup_file"; then
        dt_exit_error "Failed to set permissions on backup file"
    fi
    
    dt_info "Backup created successfully"
}

line_exists() {
    local line="$1"
    grep -Fxq "$line" "$grub_config"
}

add_grub_config() {
    local added_count=0
    local skipped_count=0
    
    dt_info "Adding GRUB configuration entries..."
    
    declare -A config_lines=(
        ["GRUB_DEFAULT=saved"]="Enable saved default boot entry"
        ["GRUB_SAVEDEFAULT=true"]="Save last boot choice as new default"
    )
    
    for line in "${!config_lines[@]}"; do
        local description="${config_lines[$line]}"
        dt_info "Processing: $line ($description)"
        
        if ! line_exists "$line"; then
            if ! echo "$line" | sudo tee -a "$grub_config" > /dev/null; then
                dt_exit_error "Failed to add line: $line"
            fi
            dt_info "Added: $line"
            ((added_count++))
        else
            dt_info "Skipped: $line (already exists)"
            ((skipped_count++))
        fi
    done
    
    dt_info "Configuration summary: $added_count lines added, $skipped_count lines skipped"
}

update_grub_config() {
    dt_info "Updating GRUB configuration..."
    
    if ! sudo update-grub 2>&1 | tee -a "$DT_LOG_FILE"; then
        dt_exit_error "Failed to update GRUB configuration"
    fi
    
    dt_info "GRUB configuration updated successfully"
}

verify_configuration() {
    dt_info "Verifying GRUB configuration..."
    local failed=0
    local expected_lines=("GRUB_DEFAULT=saved" "GRUB_SAVEDEFAULT=true")
    
    for line in "${expected_lines[@]}"; do
        if ! line_exists "$line"; then
            dt_info "Warning: Line not found in configuration: $line"
            failed=1
        fi
    done
    
    if [ "$failed" -eq 1 ]; then
        dt_exit_error "Configuration verification failed"
    fi
    
    dt_info "Configuration verified successfully"
}

main() {
    dt_info "Starting GRUB configuration script..."
    
    check_system_requirements
    
    echo "Current GRUB configuration will be modified to:"
    echo "1. Enable saved default boot entry"
    echo "2. Save last boot choice as new default"
    
    read -p "Do you want to proceed with these changes? [y/N]: " confirm
    if [[ "$confirm" != [yY] ]]; then
        dt_info "Operation cancelled by user"
        exit 0
    fi
    
    backup_grub_config
    
    add_grub_config
    
    update_grub_config
    
    verify_configuration
    
    dt_info "All operations completed successfully"
    echo -e "\nGRUB configuration has been updated successfully"
    echo "Log file: $DT_LOG_FILE"
    echo "Backup created at: ${grub_config}.bak_${DT_TIMESTAMP}"
}

main
