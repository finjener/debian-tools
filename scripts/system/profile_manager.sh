#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: System
# DEBIAN_TOOLS_NAME: Profile Manager
# DEBIAN_TOOLS_TYPE: Interactive
# Profile Manager
# Intelligently manages shell profile configurations
# Supports multiple configuration types and smart profile management

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "profile_manager"

# Configuration definitions
# Each configuration has: name, marker, check_command, config_block
declare -A CONFIGURATIONS

# Legacy functions for compatibility
exit_with_error() {
    dt_error "$1"
    exit 1
}

log_message() {
    dt_log "$1" true
}

# ============================================================================
# CONFIGURATION DEFINITIONS
# Add new environment configurations here
# ============================================================================

register_configuration() {
    local name="$1"
    local marker="$2"
    local check_command="$3"
    local config_block="$4"
    
    CONFIGURATIONS["${name}_marker"]="$marker"
    CONFIGURATIONS["${name}_check"]="$check_command"
    CONFIGURATIONS["${name}_block"]="$config_block"
}

# XDG_DATA_DIRS Configuration for Flatpak
register_configuration \
    "xdg_flatpak" \
    "# XDG_DATA_DIRS for Flatpak" \
    'grep -q "export XDG_DATA_DIRS=.*flatpak" "$profile_file"' \
    'if [ -d "/var/lib/flatpak/exports/share" ] || [ -d "$HOME/.local/share/flatpak/exports/share" ]; then
    export XDG_DATA_DIRS="/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
fi'

# Add more configurations here following the same pattern
# Example: PATH modifications, custom environment variables, etc.

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

check_system_requirements() {
    log_message "Checking system requirements..."

    if [ "$EUID" -eq 0 ]; then
        exit_with_error "This script should not be run as root. Please run without sudo."
    fi

    if [ ! -w "$HOME" ]; then
        exit_with_error "Home directory is not writable"
    fi
}

detect_desktop_environment() {
    if [ -n "$KDE_FULL_SESSION" ] || [ "$XDG_CURRENT_DESKTOP" = "KDE" ]; then
        echo "kde"
    elif [ "$XDG_CURRENT_DESKTOP" = "GNOME" ]; then
        echo "gnome"
    elif [ "$XDG_CURRENT_DESKTOP" = "XFCE" ]; then
        echo "xfce"
    else
        echo "unknown"
    fi
}

backup_profile() {
    local profile_file="$1"
    local backup_file="${profile_file}.bak.$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$profile_file" ]; then
        log_message "Creating backup of $profile_file at $backup_file"
        if ! cp "$profile_file" "$backup_file"; then
            exit_with_error "Failed to create backup of $profile_file"
        fi
        log_message "Backup created successfully: $backup_file"
        echo "$backup_file"
    else
        log_message "$profile_file does not exist, will create new file"
        echo ""
    fi
}

is_configuration_present() {
    local config_name="$1"
    local profile_file="$2"
    
    if [ ! -f "$profile_file" ]; then
        return 1
    fi
    
    local check_command="${CONFIGURATIONS[${config_name}_check]}"
    if [ -z "$check_command" ]; then
        log_message "Error: No check command defined for $config_name"
        return 1
    fi
    
    # Execute the check command
    eval "$check_command"
}

add_configuration() {
    local config_name="$1"
    local profile_file="$2"
    
    local marker="${CONFIGURATIONS[${config_name}_marker]}"
    local config_block="${CONFIGURATIONS[${config_name}_block]}"
    
    if [ -z "$marker" ] || [ -z "$config_block" ]; then
        log_message "Error: Configuration $config_name not found"
        return 1
    fi
    
    log_message "Adding configuration: $config_name"
    
    # Ensure profile file exists
    touch "$profile_file"
    
    # Add configuration block with marker
    {
        echo ""
        echo "$marker"
        echo "# Added by profile_manager.sh"
        echo "$config_block"
    } >> "$profile_file"
    
    log_message "Configuration $config_name added successfully"
    return 0
}

remove_configuration() {
    local config_name="$1"
    local profile_file="$2"
    
    local marker="${CONFIGURATIONS[${config_name}_marker]}"
    
    if [ -z "$marker" ]; then
        log_message "Error: Configuration $config_name not found"
        return 1
    fi
    
    if [ ! -f "$profile_file" ]; then
        log_message "Profile file $profile_file does not exist"
        return 1
    fi
    
    log_message "Removing configuration: $config_name"
    
    # Create temporary file
    local temp_file="${profile_file}.tmp"
    
    # Remove the configuration block (from marker to next empty line or EOF)
    awk -v marker="$marker" '
        BEGIN { skip = 0 }
        $0 == marker { skip = 1; next }
        skip && /^$/ { skip = 0; next }
        !skip { print }
    ' "$profile_file" > "$temp_file"
    
    if [ -s "$temp_file" ]; then
        mv "$temp_file" "$profile_file"
        log_message "Configuration $config_name removed successfully"
        return 0
    else
        rm -f "$temp_file"
        log_message "Error: Failed to remove configuration"
        return 1
    fi
}

list_available_configurations() {
    echo "Available configurations:"
    echo
    
    local configs=()
    for key in "${!CONFIGURATIONS[@]}"; do
        if [[ "$key" == *"_marker" ]]; then
            local config_name="${key%_marker}"
            configs+=("$config_name")
        fi
    done
    
    # Sort and display
    IFS=$'\n' sorted=($(sort <<<"${configs[*]}"))
    unset IFS
    
    for config in "${sorted[@]}"; do
        local marker="${CONFIGURATIONS[${config}_marker]}"
        echo "  $config"
        echo "    $marker"
    done
}

check_configuration_status() {
    local profile_file="$1"
    
    echo "Configuration status in $profile_file:"
    echo
    
    local configs=()
    for key in "${!CONFIGURATIONS[@]}"; do
        if [[ "$key" == *"_marker" ]]; then
            local config_name="${key%_marker}"
            configs+=("$config_name")
        fi
    done
    
    # Sort and check status
    IFS=$'\n' sorted=($(sort <<<"${configs[*]}"))
    unset IFS
    
    for config in "${sorted[@]}"; do
        if is_configuration_present "$config" "$profile_file"; then
            echo "  ✓ $config (configured)"
        else
            echo "  ✗ $config (not configured)"
        fi
    done
}

refresh_desktop_environment() {
    local de_type="$1"
    
    log_message "Attempting to refresh desktop environment ($de_type)..."
    
    case "$de_type" in
        kde)
            if command -v kbuildsycoca5 &>/dev/null; then
                log_message "Running kbuildsycoca5 to refresh KDE..."
                kbuildsycoca5 --noincremental 2>&1 | tee -a "$DT_LOG_FILE" && return 0 || return 1
            elif command -v kbuildsycoca6 &>/dev/null; then
                log_message "Running kbuildsycoca6 to refresh KDE..."
                kbuildsycoca6 --noincremental 2>&1 | tee -a "$DT_LOG_FILE" && return 0 || return 1
            else
                log_message "Warning: kbuildsycoca not found"
                return 1
            fi
            ;;
        gnome)
            log_message "GNOME usually auto-detects changes"
            command -v gtk-update-icon-cache &>/dev/null && \
                gtk-update-icon-cache -f ~/.local/share/icons/hicolor 2>&1 | tee -a "$DT_LOG_FILE"
            return 0
            ;;
        *)
            log_message "Desktop refresh not needed or unsupported"
            return 0
            ;;
    esac
}

show_usage() {
    cat << 'EOF'
Usage: profile_manager.sh [COMMAND] [OPTIONS]

Profile Manager - Intelligently manage shell profile configurations

Commands:
  add CONFIG               Add a configuration to profile
  remove CONFIG            Remove a configuration from profile
  list                     List all available configurations
  status                   Show status of all configurations
  apply-all                Apply all missing configurations
  help                     Show this help message

Options:
  --profile FILE           Profile file to use (default: ~/.profile)
  --force                  Force operation even if already configured
  --skip-refresh           Skip desktop environment refresh
  --backup                 Create backup before making changes (default: yes)
  --no-backup              Skip backup creation

Examples:
  # Check what configurations are available
  ./profile_manager.sh list

  # Check current status
  ./profile_manager.sh status

  # Add XDG Flatpak configuration
  ./profile_manager.sh add xdg_flatpak

  # Remove a configuration
  ./profile_manager.sh remove xdg_flatpak

  # Apply all missing configurations
  ./profile_manager.sh apply-all

  # Use custom profile file
  ./profile_manager.sh add xdg_flatpak --profile ~/.bash_profile

EOF
}

main() {
    local command=""
    local config_name=""
    local profile_file="$HOME/.profile"
    local force=false
    local skip_refresh=false
    local do_backup=true
    
    # Parse command
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 0
    fi
    
    command="$1"
    shift
    
    # Parse config name for add/remove commands
    if [[ "$command" == "add" || "$command" == "remove" ]]; then
        if [[ $# -eq 0 ]]; then
            echo "Error: Configuration name required for $command command"
            echo
            show_usage
            exit 1
        fi
        config_name="$1"
        shift
    fi
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile)
                profile_file="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            --skip-refresh)
                skip_refresh=true
                shift
                ;;
            --no-backup)
                do_backup=false
                shift
                ;;
            --backup)
                do_backup=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log_message "Starting profile manager..."
    log_message "Command: $command"
    log_message "Profile: $profile_file"
    
    # Execute command
    case "$command" in
        list)
            list_available_configurations
            exit 0
            ;;
        status)
            check_configuration_status "$profile_file"
            exit 0
            ;;
        add)
            check_system_requirements
            
            # Check if configuration exists
            if ! [[ -v CONFIGURATIONS[${config_name}_marker] ]]; then
                echo "Error: Configuration '$config_name' not found"
                echo
                list_available_configurations
                exit 1
            fi
            
            # Check if already present
            if is_configuration_present "$config_name" "$profile_file"; then
                if [ "$force" = false ]; then
                    echo "Configuration '$config_name' is already present in $profile_file"
                    echo "Use --force to add anyway"
                    exit 0
                else
                    log_message "Forcing addition (--force flag set)"
                fi
            fi
            
            # Create backup
            local backup_file=""
            if [ "$do_backup" = true ]; then
                backup_file=$(backup_profile "$profile_file")
            fi
            
            # Add configuration
            if add_configuration "$config_name" "$profile_file"; then
                echo "✓ Configuration '$config_name' added to $profile_file"
                [ -n "$backup_file" ] && echo "  Backup: $backup_file"
                
                # Refresh desktop if applicable
                if [ "$skip_refresh" = false ]; then
                    local de_type=$(detect_desktop_environment)
                    refresh_desktop_environment "$de_type"
                fi
                
                echo
                echo "To activate changes:"
                echo "  1. Log out and log back in (recommended)"
                echo "  2. Run: source $profile_file"
                echo "  3. Start a new terminal session"
            else
                exit_with_error "Failed to add configuration"
            fi
            ;;
        remove)
            check_system_requirements
            
            # Check if configuration exists
            if ! [[ -v CONFIGURATIONS[${config_name}_marker] ]]; then
                echo "Error: Configuration '$config_name' not found"
                echo
                list_available_configurations
                exit 1
            fi
            
            # Check if present
            if ! is_configuration_present "$config_name" "$profile_file"; then
                echo "Configuration '$config_name' is not present in $profile_file"
                exit 0
            fi
            
            # Create backup
            local backup_file=""
            if [ "$do_backup" = true ]; then
                backup_file=$(backup_profile "$profile_file")
            fi
            
            # Remove configuration
            if remove_configuration "$config_name" "$profile_file"; then
                echo "✓ Configuration '$config_name' removed from $profile_file"
                [ -n "$backup_file" ] && echo "  Backup: $backup_file"
            else
                exit_with_error "Failed to remove configuration"
            fi
            ;;
        apply-all)
            check_system_requirements
            
            echo "Checking which configurations need to be applied..."
            echo
            
            local configs_to_add=()
            for key in "${!CONFIGURATIONS[@]}"; do
                if [[ "$key" == *"_marker" ]]; then
                    local cfg="${key%_marker}"
                    if ! is_configuration_present "$cfg" "$profile_file"; then
                        configs_to_add+=("$cfg")
                    fi
                fi
            done
            
            if [ ${#configs_to_add[@]} -eq 0 ]; then
                echo "All configurations are already applied!"
                exit 0
            fi
            
            echo "The following configurations will be added:"
            for cfg in "${configs_to_add[@]}"; do
                echo "  - $cfg"
            done
            echo
            read -p "Continue? [y/N]: " confirm
            if [[ "$confirm" != [yY] ]]; then
                echo "Cancelled"
                exit 0
            fi
            
            # Create backup once
            local backup_file=""
            if [ "$do_backup" = true ]; then
                backup_file=$(backup_profile "$profile_file")
            fi
            
            # Add all configurations
            local added=0
            for cfg in "${configs_to_add[@]}"; do
                if add_configuration "$cfg" "$profile_file"; then
                    echo "✓ Added: $cfg"
                    ((added++))
                else
                    echo "✗ Failed: $cfg"
                fi
            done
            
            echo
            echo "Applied $added configuration(s)"
            [ -n "$backup_file" ] && echo "Backup: $backup_file"
            
            # Refresh desktop
            if [ "$skip_refresh" = false ]; then
                local de_type=$(detect_desktop_environment)
                refresh_desktop_environment "$de_type"
            fi
            ;;
        help|--help|-h)
            show_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown command '$command'"
            echo
            show_usage
            exit 1
            ;;
    esac
    
    log_message "Profile manager completed"
}

main "$@"
