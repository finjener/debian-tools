#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: System
# DEBIAN_TOOLS_NAME: Unstable Repo
# DEBIAN_TOOLS_TYPE: Configure
# Debian Unstable Repository Setup Script
# Adds unstable repo with proper pinning for selective package installation

set -e

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "unstable_repo"

SOURCES_FILE="/etc/apt/sources.list.d/unstable.sources"
PREFERENCES_FILE="/etc/apt/preferences.d/99unstable"

# Legacy function for compatibility
log_message() {
    dt_log "$1" true
}

create_unstable_sources() {
    log_message "Creating $SOURCES_FILE..."

    cat << EOF | sudo tee "$SOURCES_FILE" > /dev/null
Types: deb
URIs: http://deb.debian.org/debian/
Suites: unstable
Components: main contrib non-free
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

    log_message "Created $SOURCES_FILE"
}

create_unstable_preferences() {
    log_message "Creating apt preferences (pinning) for unstable..."

    # Configure pinning:
    # 500 = Default priority (Testing/Forky)
    # 100 = Installed packages
    # 50  = Unstable (will only install if explicitly requested via -t unstable)
    
    # Note: User's intent for unstable implies mixing. Pinning is CRITICAL.
    
    cat << EOF | sudo tee "$PREFERENCES_FILE" > /dev/null
Package: *
Pin: release a=unstable
Pin-Priority: 50
EOF

    log_message "Created $PREFERENCES_FILE"
}

main() {
    log_message "Starting Unstable Repository Setup..."
    
    if [ "$1" = "-u" ] || [ "$1" = "--uninstall" ]; then
        log_message "Removing Unstable repository configuration..."
        [ -f "$SOURCES_FILE" ] && sudo rm "$SOURCES_FILE" && log_message "Removed $SOURCES_FILE"
        [ -f "$PREFERENCES_FILE" ] && sudo rm "$PREFERENCES_FILE" && log_message "Removed $PREFERENCES_FILE"
        sudo apt update
        exit 0
    fi
    
    create_unstable_sources
    create_unstable_preferences
    
    log_message "Updating package lists..."
    if sudo apt update; then
        log_message "Unstable repository added successfully."
    else
        log_message "Warning: apt update failed."
        exit 1
    fi
}

main "$@"
