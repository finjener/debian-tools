#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: System
# DEBIAN_TOOLS_NAME: Change OS ID
# DEBIAN_TOOLS_TYPE: Configure
# Change OS ID Script
# Changes the OS ID in /etc/os-release (for software compatibility)

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "change_os_id"

OS_RELEASE_FILE="/etc/os-release"
BACKUP_DIR="/var/backups/os-release"
VALID_IDS=("ubuntu" "tuxedo")

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

    if [ "$EUID" -ne 0 ]; then
        exit_with_error "This script must be run as root (use sudo)"
    fi

    if [ ! -f "$OS_RELEASE_FILE" ]; then
        exit_with_error "OS release file not found: $OS_RELEASE_FILE"
    fi

    if [ ! -w "$OS_RELEASE_FILE" ]; then
        exit_with_error "OS release file is not writable"
    fi

    if [ ! -d "$BACKUP_DIR" ]; then
        log_message "Creating backup directory: $BACKUP_DIR"
        if ! mkdir -p "$BACKUP_DIR"; then
            exit_with_error "Failed to create backup directory"
        fi
    fi
}

validate_os_id() {
    local id="$1"
    
    if [ -z "$id" ]; then
        exit_with_error "OS ID cannot be empty"
    fi
    
    local valid=false
    for valid_id in "${VALID_IDS[@]}"; do
        if [ "$id" = "$valid_id" ]; then
            valid=true
            break
        fi
    done
    
    if [ "$valid" = false ]; then
        exit_with_error "Invalid OS ID: $id. Valid IDs are: ${VALID_IDS[*]}"
    fi
}

get_current_os_id() {
    local current_id
    current_id=$(grep "^ID=" "$OS_RELEASE_FILE" | cut -d= -f2)
    
    if [ -z "$current_id" ]; then
        exit_with_error "Failed to determine current OS ID"
    fi
    
    echo "$current_id"
}

backup_os_release() {
    local backup_file="${BACKUP_DIR}/os-release_${timestamp}"
    log_message "Creating backup at $backup_file"
    
    if ! cp "$OS_RELEASE_FILE" "$backup_file"; then
        exit_with_error "Failed to create backup"
    fi
    
    local -r max_backups=5
    local backup_count
    backup_count=$(ls -1 "${BACKUP_DIR}/os-release_"* 2>/dev/null | wc -l)
    
    if [ "$backup_count" -gt "$max_backups" ]; then
        log_message "Removing old backups..."
        ls -1t "${BACKUP_DIR}/os-release_"* | tail -n +$((max_backups + 1)) | xargs rm
    fi
}

verify_file() {
    local file="$1"
    local expected_id="$2"
    
    if ! grep -q "^ID=$expected_id$" "$file"; then
        return 1
    fi
    
    return 0
}

change_os_id() {
    local new_id="$1"
    local current_id
    current_id=$(get_current_os_id)
    
    log_message "Changing OS ID from $current_id to $new_id"
    
    validate_os_id "$current_id"
    validate_os_id "$new_id"
    
    if [ "$current_id" = "$new_id" ]; then
        log_message "OS ID is already set to $new_id"
        exit 0
    fi
    
    backup_os_release
    
    log_message "Modifying OS release file..."
    if ! sed -i "s/^ID=$current_id$/ID=$new_id/" "$OS_RELEASE_FILE"; then
        exit_with_error "Failed to change OS ID"
    fi
    
    if ! verify_file "$OS_RELEASE_FILE" "$new_id"; then
        log_message "Warning: Failed to verify OS ID change"
        log_message "Attempting to restore from backup..."
        if ! cp "${BACKUP_DIR}/os-release_${timestamp}" "$OS_RELEASE_FILE"; then
            exit_with_error "Failed to restore backup. Manual intervention required."
        fi
        exit_with_error "OS ID change failed, restored from backup"
    fi
    
    log_message "Successfully changed OS ID from $current_id to $new_id"
    log_message "Backup saved at: ${BACKUP_DIR}/os-release_${timestamp}"
}

display_usage() {
    echo "Usage: $0 [ubuntu|tuxedo]"
    echo "Changes the OS ID in $OS_RELEASE_FILE"
    echo ""
    echo "Arguments:"
    echo "  ubuntu    Change OS ID to ubuntu"
    echo "  tuxedo    Change OS ID to tuxedo"
    echo ""
    echo "Note: This script must be run with sudo"
}

main() {
    log_message "Starting OS ID change script..."
    
    if [ "$#" -ne 1 ]; then
        display_usage
        exit 1
    fi
    
    check_system_requirements
    
    case "$1" in
        ubuntu|tuxedo)
            read -p "Are you sure you want to change the OS ID to $1? [y/N]: " confirm
            if [[ "$confirm" != [yY] ]]; then
                log_message "Operation cancelled by user"
                exit 0
            fi
            
            change_os_id "$1"
            ;;
        -h|--help)
            display_usage
            exit 0
            ;;
        *)
            display_usage
            exit_with_error "Invalid argument: $1"
            ;;
    esac
    
    log_message "Script completed successfully"
}

main "$@"
