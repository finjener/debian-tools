#!/usr/bin/env bash

# ============================================================================
# Debian Tools - Common Library
# ============================================================================
# Shared utilities for all debian-tools scripts
# Provides: centralized paths, logging, colored output, helper functions
#
# Usage: source this file at the top of your script
#   source "$(dirname "${BASH_SOURCE[0]}")/../utils/common.sh"
#   # or
#   source "/path/to/debian-tools/scripts/utils/common.sh"
# ============================================================================

# Ensure this script is sourced, not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This script must be sourced, not run directly."
    echo "Usage: source ${BASH_SOURCE[0]}"
    exit 1
fi

# Enable strict error checking for pipelines
# This ensures that 'cmd | tee' fails if 'cmd' fails
set -o pipefail

# ============================================================================
# CENTRALIZED PATH RESOLUTION
# ============================================================================
# This is the SINGLE SOURCE OF TRUTH for all paths in debian-tools.
# All scripts source this file and use these exported variables.
#
# Path Structure:
#   common.sh location: <repo>/scripts/utils/common.sh
#   Repository root:    <repo>/
#   Logs directory:     <repo>/logs/
#   Backups directory:  <repo>/backups/
#
# The paths are calculated relative to this file's location, ensuring
# consistent behavior whether scripts run via terminal, GUI, or from any directory.
# ============================================================================

# Calculate absolute path of this file's directory (scripts/utils/)
_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Calculate repository root: go up two levels from scripts/utils/ to repo root
# This uses cd to resolve .. properly and pwd to get absolute path
_REPO_ROOT="$(cd "$_COMMON_DIR/../.." && pwd)"

# Export repository root for scripts that need to reference project files
export DT_REPO_ROOT="$_REPO_ROOT"

# Set default paths relative to repository root
# Environment variables can override these defaults
export DT_LOG_DIR="${DEBIAN_TOOLS_LOG_DIR:-${DT_LOG_DIR:-$_REPO_ROOT/logs}}"
export DT_BACKUP_DIR="${DEBIAN_TOOLS_BACKUP_DIR:-${DT_BACKUP_DIR:-$_REPO_ROOT/backups}}"
export DT_DATA_DIR="${DEBIAN_TOOLS_DATA_DIR:-${DT_DATA_DIR:-$_REPO_ROOT}}"

# Ensure directories exist (create if missing)
mkdir -p "$DT_LOG_DIR" "$DT_BACKUP_DIR"

# Script metadata (set by calling script)
export DT_SCRIPT_NAME="${DT_SCRIPT_NAME:-unknown}"
export DT_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
export DT_LOG_FILE=""

# ============================================================================
# COLOR PALETTE
# ============================================================================

# Check if terminal supports colors
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    export DT_COLOR_ENABLED=true
else
    export DT_COLOR_ENABLED=false
fi

# Color definitions
if [[ "$DT_COLOR_ENABLED" == true ]]; then
    export C_RESET='\033[0m'
    export C_BOLD='\033[1m'
    export C_DIM='\033[2m'
    
    # Standard colors
    export C_RED='\033[0;31m'
    export C_GREEN='\033[0;32m'
    export C_YELLOW='\033[0;33m'
    export C_BLUE='\033[0;34m'
    export C_MAGENTA='\033[0;35m'
    export C_CYAN='\033[0;36m'
    export C_WHITE='\033[0;37m'
    
    # Bold colors
    export C_BRED='\033[1;31m'
    export C_BGREEN='\033[1;32m'
    export C_BYELLOW='\033[1;33m'
    export C_BBLUE='\033[1;34m'
    export C_BCYAN='\033[1;36m'
    
    # Symbols
    export SYM_CHECK="✓"
    export SYM_CROSS="✗"
    export SYM_ARROW="→"
    export SYM_BULLET="•"
    export SYM_WARN="⚠"
    export SYM_INFO="ℹ"
else
    export C_RESET='' C_BOLD='' C_DIM=''
    export C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_MAGENTA='' C_CYAN='' C_WHITE=''
    export C_BRED='' C_BGREEN='' C_BYELLOW='' C_BBLUE='' C_BCYAN=''
    export SYM_CHECK="[OK]" SYM_CROSS="[X]" SYM_ARROW="->" SYM_BULLET="*" SYM_WARN="[!]" SYM_INFO="[i]"
fi

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

# Initialize logging for a script
# Usage: dt_init_log "script_name"
dt_init_log() {
    local script_name="${1:-$DT_SCRIPT_NAME}"
    DT_SCRIPT_NAME="$script_name"
    DT_LOG_FILE="$DT_LOG_DIR/${script_name}_${DT_TIMESTAMP}.log"
    
    # Create log header
    {
        echo "========================================"
        echo "Script: $script_name"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "User: $USER"
        echo "Host: $(hostname)"
        echo "========================================"
        echo ""
    } > "$DT_LOG_FILE"
}

# Write to log file (and optionally to terminal)
# Usage: dt_log "message" [show_terminal]
dt_log() {
    local message="$1"
    local show="${2:-false}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Only write to log if initialized
    if [[ -n "$DT_LOG_FILE" ]]; then
        echo "[$timestamp] $message" >> "$DT_LOG_FILE"
    fi
    
    if [[ "$show" == true ]]; then
        echo "$message"
    fi
}

# ============================================================================
# OUTPUT FUNCTIONS
# ============================================================================

# Print a styled header box
# Usage: dt_header "Title"
dt_header() {
    local title="$1"
    local width=50
    local padding=$(( (width - ${#title} - 2) / 2 ))
    
    echo ""
    echo -e "${C_CYAN}╭$(printf '─%.0s' $(seq 1 $width))╮${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}$(printf ' %.0s' $(seq 1 $padding))${C_BOLD}${title}${C_RESET}$(printf ' %.0s' $(seq 1 $((width - padding - ${#title}))))${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}╰$(printf '─%.0s' $(seq 1 $width))╯${C_RESET}"
    echo ""
    
    dt_log "=== $title ===" false
}

# Print a section divider
# Usage: dt_divider
dt_divider() {
    echo -e "${C_DIM}$(printf '─%.0s' $(seq 1 50))${C_RESET}"
}

# Print step progress
# Usage: dt_step 1 5 "Doing something..."
dt_step() {
    local current="$1"
    local total="$2"
    local message="$3"
    
    echo -e "\n${C_BBLUE}[${current}/${total}]${C_RESET} ${C_BOLD}${message}${C_RESET}"
    dt_log "[${current}/${total}] $message" false
}

# Print info message
# Usage: dt_info "Message"
dt_info() {
    echo -e "  ${C_BLUE}${SYM_INFO}${C_RESET} $1"
    dt_log "[INFO] $1" false
}

# Print success message
# Usage: dt_success "Message"
dt_success() {
    echo -e "  ${C_GREEN}${SYM_CHECK}${C_RESET} $1"
    dt_log "[SUCCESS] $1" false
}

# Print warning message
# Usage: dt_warn "Message"
dt_warn() {
    echo -e "  ${C_YELLOW}${SYM_WARN}${C_RESET} $1"
    dt_log "[WARN] $1" false
}

# Print error message
# Usage: dt_error "Message"
dt_error() {
    echo -e "  ${C_RED}${SYM_CROSS}${C_RESET} $1" >&2
    dt_log "[ERROR] $1" false
}

# Print a result/output line
# Usage: dt_result "Label" "Value"
dt_result() {
    local label="$1"
    local value="$2"
    echo -e "  ${C_DIM}${label}:${C_RESET} ${C_CYAN}${value}${C_RESET}"
    dt_log "$label: $value" false
}

# Print summary box
# Usage: dt_summary "key1=value1" "key2=value2" ...
dt_summary() {
    echo ""
    dt_divider
    echo -e "${C_BOLD}Summary:${C_RESET}"
    for item in "$@"; do
        local key="${item%%=*}"
        local value="${item#*=}"
        echo -e "  ${C_DIM}${key}:${C_RESET} ${value}"
    done
    dt_divider
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Ensure directory exists
# Usage: dt_ensure_dir "/path/to/dir"
dt_ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        dt_log "Created directory: $dir" false
    fi
}

# Confirmation prompt
# Usage: if dt_confirm "Proceed?"; then ... fi
# Usage: if dt_confirm "Proceed?" "n"; then ... fi  # default no
dt_confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local response

    # GUI-friendly confirmation:
    # If we're not attached to a TTY (e.g., launched from GUI), try a graphical prompt.
    # Falls back to the provided default without blocking.
    if [[ ! -t 0 ]]; then
        if command -v kdialog &>/dev/null && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
            if kdialog --yesno "$prompt"; then
                return 0
            else
                return 1
            fi
        fi
        if command -v zenity &>/dev/null && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
            if zenity --question --text="$prompt"; then
                return 0
            else
                return 1
            fi
        fi

        # Non-interactive fallback: honor default without blocking.
        if [[ "$default" == "y" ]]; then
            dt_warn "Non-interactive: auto-yes for prompt: $prompt"
            return 0
        else
            dt_warn "Non-interactive: auto-no for prompt: $prompt"
            return 1
        fi
    fi
    
    if [[ "$default" == "y" ]]; then
        read -p "$prompt [Y/n]: " response
        [[ -z "$response" || "$response" =~ ^[yY] ]]
    else
        read -p "$prompt [y/N]: " response
        [[ "$response" =~ ^[yY] ]]
    fi
}

# Check if command exists
# Usage: dt_require_command "gpg" "GnuPG" || exit 1
dt_require_command() {
    local cmd="$1"
    local name="${2:-$cmd}"
    
    if ! command -v "$cmd" &>/dev/null; then
        dt_error "$name is not installed"
        return 1
    fi
    return 0
}

# Check if running as root (and optionally reject)
# Usage: dt_check_root      # warns if root
# Usage: dt_check_root true # exits if root
dt_check_root() {
    local exit_if_root="${1:-false}"
    
    if [[ "$EUID" -eq 0 ]]; then
        if [[ "$exit_if_root" == true ]]; then
            dt_error "This script should not be run as root"
            exit 1
        else
            dt_warn "Running as root"
        fi
        return 0
    fi
    return 1
}

# GUI-compatible sudo wrapper
# Uses pkexec for graphical auth when no TTY is available
# Usage: dt_sudo apt-get install -y package
# Usage: dt_sudo dpkg -i file.deb
dt_sudo() {
    # If already root, just run the command
    if [[ "$EUID" -eq 0 ]]; then
        "$@"
        return $?
    fi
    
    # Check if we have a TTY for interactive sudo
    if [[ -t 0 ]]; then
        # Terminal mode - use regular sudo
        sudo "$@"
        return $?
    fi
    
    # Non-interactive mode (GUI) - try pkexec for graphical prompt
    # Check if pkexec is available
    if command -v pkexec &>/dev/null; then
        # pkexec requires full path for some commands
        local cmd="$1"
        shift
        
        # Get full path to command if it exists
        local full_cmd
        if command -v "$cmd" &>/dev/null; then
            full_cmd=$(command -v "$cmd")
        else
            full_cmd="$cmd"
        fi
        
        dt_info "Requesting root privileges for: $cmd"
        pkexec "$full_cmd" "$@"
        return $?
    else
        # pkexec not available, fall back to sudo with warning
        dt_warn "pkexec not found, falling back to sudo (install 'policykit-1' for GUI authentication)"
        sudo "$@"
        return $?
    fi
}

# Get backup directory for a specific category
# Usage: backup_path=$(dt_backup_path "ssh")
dt_backup_path() {
    local category="$1"
    local path="$DT_BACKUP_DIR/$category"
    dt_ensure_dir "$path"
    echo "$path"
}

# Exit with error
# Usage: dt_exit_error "Something went wrong"
dt_exit_error() {
    dt_error "$1"
    exit 1
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Auto-detect script name from caller if not set
if [[ "$DT_SCRIPT_NAME" == "unknown" ]]; then
    # Get the name of the script that sourced this file
    if [[ -n "${BASH_SOURCE[1]:-}" ]]; then
        DT_SCRIPT_NAME=$(basename "${BASH_SOURCE[1]}" .sh)
    fi
fi
