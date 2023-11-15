#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: System
# DEBIAN_TOOLS_NAME: APT Sources (contrib/non-free)
# DEBIAN_TOOLS_TYPE: Configure
# APT Sources Contrib/Non-Free Configuration
# Intelligently adds missing components to Debian sources
# Supports modern .sources format with auto-detection

set -e

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "sources_list_contrib_nonfree"

# Legacy function for compatibility
log_message() {
    dt_log "$1" true
}

# Required components
REQUIRED_COMPONENTS=("main" "contrib" "non-free" "non-free-firmware")

# Detect Debian version/codename
detect_debian_codename() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$VERSION_CODENAME"
    else
        log_message "Error: Cannot detect Debian version"
        exit 1
    fi
}

# Get next available backup number
get_next_backup_number() {
    local base_path="$1"
    local number=1
    
    while [ -f "${base_path}.bak$(printf '%02d' $number)" ]; do
        ((number++))
    done
    
    printf '%02d' $number
}

# Create incremental backup
create_backup() {
    local source_file="$1"
    
    if [ ! -f "$source_file" ]; then
        log_message "Source file $source_file does not exist, skipping backup"
        return 0
    fi
    
    local backup_number=$(get_next_backup_number "$source_file")
    local backup_file="${source_file}.bak${backup_number}"
    
    log_message "Creating backup: $backup_file"
    sudo cp "$source_file" "$backup_file"
    
    echo "$backup_file"
}

# Parse components from .sources file
get_current_components() {
    local sources_file="$1"
    
    if [ ! -f "$sources_file" ]; then
        echo ""
        return
    fi
    
    # Extract Components line and return the components
    grep -E '^Components:' "$sources_file" | sed 's/^Components:[[:space:]]*//' || echo ""
}

# Check which components are missing
get_missing_components() {
    local current_components="$1"
    local missing=()
    
    for component in "${REQUIRED_COMPONENTS[@]}"; do
        if ! echo "$current_components" | grep -qw "$component"; then
            missing+=("$component")
        fi
    done
    
    echo "${missing[@]}"
}

# Merge components (current + missing)
merge_components() {
    local current="$1"
    shift
    local missing=("$@")
    
    # Start with current components
    local result="$current"
    
    # Add missing components
    for component in "${missing[@]}"; do
        if [ -z "$result" ]; then
            result="$component"
        else
            result="$result $component"
        fi
    done
    
    echo "$result"
}

# Update or create .sources file
update_sources_file() {
    local sources_file="$1"
    local suite="$2"
    local uri="$3"
    local components="$4"
    
    log_message "Updating $sources_file with components: $components"
    
    cat <<EOF | sudo tee "$sources_file" > /dev/null
Types: deb deb-src
URIs: $uri
Suites: $suite
Components: $components
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
}

# Process a single sources file
process_sources_file() {
    local sources_name="$1"
    local suite="$2"
    local uri="$3"
    local sources_dir="/etc/apt/sources.list.d"
    local sources_path="$sources_dir/$sources_name"
    
    log_message "Processing $sources_name..."
    
    # Get current components
    local current_components=$(get_current_components "$sources_path")
    log_message "Current components: ${current_components:-none}"
    
    # Check for missing components
    local missing_components=($(get_missing_components "$current_components"))
    
    if [ ${#missing_components[@]} -eq 0 ]; then
        log_message "✓ All required components already present in $sources_name"
        return 0
    fi
    
    log_message "Missing components in $sources_name: ${missing_components[*]}"
    
    # Create backup before modifying
    local backup_file=$(create_backup "$sources_path")
    
    # Merge components
    local new_components=$(merge_components "$current_components" "${missing_components[@]}")
    
    # Update the file
    update_sources_file "$sources_path" "$suite" "$uri" "$new_components"
    
    log_message "✓ Updated $sources_name (backup: $backup_file)"
}

show_usage() {
    cat << 'EOF'
Usage: sources_list_contrib_nonfree.sh [OPTIONS]

Intelligently add missing components to Debian APT sources

Options:
  --check-only    Only check what would be changed (dry run)
  -h, --help      Show this help message

This script will:
  1. Auto-detect your Debian version/codename
  2. Check which components are present in sources files
  3. Add only missing components: main, contrib, non-free, non-free-firmware
  4. Create incremental backups (.bak01, .bak02, etc.)

EOF
}

main() {
    local check_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check-only)
                check_only=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log_message "Starting APT sources configuration..."
    
    # Detect Debian codename
    local codename=$(detect_debian_codename)
    log_message "Detected Debian codename: $codename"
    
    # Define sources files to process
    local sources_files=(
        "debian.sources:${codename}:http://deb.debian.org/debian/"
        "debian-security.sources:${codename}-security:http://security.debian.org/debian-security/"
        "debian-updates.sources:${codename}-updates:http://deb.debian.org/debian/"
    )
    
    if [ "$check_only" = true ]; then
        log_message "CHECK ONLY MODE - No changes will be made"
        echo
        echo "Current status:"
        
        for sources_info in "${sources_files[@]}"; do
            IFS=':' read -r name suite uri <<< "$sources_info"
            local sources_path="/etc/apt/sources.list.d/$name"
            local current=$(get_current_components "$sources_path")
            local missing=($(get_missing_components "$current"))
            
            echo "  $name:"
            echo "    Current: ${current:-none}"
            if [ ${#missing[@]} -gt 0 ]; then
                echo "    Missing: ${missing[*]}"
            else
                echo "    Status: ✓ Complete"
            fi
            echo
        done
        
        exit 0
    fi
    
    # Confirm with user
    echo
    echo "This script will add missing APT source components:"
    echo "  Required: ${REQUIRED_COMPONENTS[*]}"
    echo "  Codename: $codename"
    echo
    read -p "Continue? [y/N]: " confirm
    if [[ "$confirm" != [yY] ]]; then
        log_message "Operation cancelled by user"
        exit 0
    fi
    
    # Process each sources file
    local modified=0
    for sources_info in "${sources_files[@]}"; do
        IFS=':' read -r name suite uri <<< "$sources_info"
        
        # Get current components
        local sources_path="/etc/apt/sources.list.d/$name"
        local current=$(get_current_components "$sources_path")
        local missing=($(get_missing_components "$current"))
        
        if [ ${#missing[@]} -gt 0 ]; then
            process_sources_file "$name" "$suite" "$uri"
            ((modified++))
        else
            log_message "✓ $name already has all required components"
        fi
    done
    
    if [ $modified -eq 0 ]; then
        echo
        echo "✓ All sources files already have the required components!"
        log_message "No changes needed"
    else
        echo
        echo "✓ Updated $modified sources file(s)"
        log_message "Updating APT package lists..."
        sudo apt update
        echo
        echo "APT sources configuration completed successfully!"
    fi
    
    log_message "Log file: $DT_LOG_FILE"
}

main "$@"
