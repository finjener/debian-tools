#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: System
# DEBIAN_TOOLS_NAME: Systemd Resolved
# DEBIAN_TOOLS_TYPE: Configure
# systemd-resolved Configuration Script
# Configures DNS settings for systemd-resolved

USER_PREFIX="custom_dns_01"

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "systemd_resolved_config"

backup_dir="/var/backups/systemd-resolved"

RESOLVED_CONF="/etc/systemd/resolved.conf.d/${USER_PREFIX}-dns.conf"
RESOLVED_CONF_BAK=""

DNS_CONFIGS=(
    "#  This file is part of systemd."
    "#"
    "#  systemd is free software; you can redistribute it and/or modify it under the"
    "#  terms of the GNU Lesser General Public License as published by the Free"
    "#  Software Foundation; either version 2.1 of the License, or (at your option)"
    "#  any later version."
    "#"
    "# Entries in this file show the compile time defaults. Local configuration"
    "# should be created by either modifying this file, or by creating \"drop-ins\" in"
    "# the resolved.conf.d/ subdirectory. The latter is generally recommended."
    "# Defaults can be restored by simply deleting this file and all drop-ins."
    "#"
    "# Use 'systemd-analyze cat-config systemd/resolved.conf' to display the full config."
    "#"
    "# See resolved.conf(5) for details."
    ""
    "[Resolve]"
    "# Some examples of DNS servers which may be used for DNS= and FallbackDNS=:"
    "# Cloudflare: 1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 2606:4700:4700::1111#cloudflare-dns.com 2606:4700:4700::1001#cloudflare-dns.com"
    "# Google:     8.8.8.8#dns.google 8.8.4.4#dns.google 2001:4860:4860::8888#dns.google 2001:4860:4860::8844#dns.google"
    "# Quad9:      9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net"
    ""
    "# Default system settings"
    "#DNS="
    "#FallbackDNS="
    "#Domains="
    "#DNSSEC=no"
    "#DNSOverTLS=no"
    "#MulticastDNS=yes"
    "#LLMNR=yes"
    "#Cache=yes"
    "#CacheFromLocalhost=no"
    "#DNSStubListener=yes"
    "#DNSStubListenerExtra="
    "#ReadEtcHosts=yes"
    "#ResolveUnicastSingleLabel=no"
    ""
    "# Mullvad DNS servers"
    "#DNS=194.242.2.2#dns.mullvad.net"
    "#DNS=194.242.2.3#adblock.dns.mullvad.net"
    "#DNS=194.242.2.4#base.dns.mullvad.net"
    "#DNS=194.242.2.5#extended.dns.mullvad.net"
    "#DNS=194.242.2.9#all.dns.mullvad.net"
    ""
    "# LibreDNS servers"
    "# DNS without adblock"
    "#DNS=116.202.176.26#dot.libredns.gr"
    "# DNS with adblock"
    "#DNS=116.202.176.26#noads.libredns.gr"
    ""
    "# General settings"
    "#DNSSEC=no"
    "#DNSOverTLS=yes"
    "#Domains=~."
    "#FallbackDNS=127.0.0.1 ::1"
)

# Legacy functions for compatibility
exit_with_error() {
    dt_error "$1"
    exit 1
}

log_message() {
    dt_log "$1" true
}

detect_os() {
    log_message "Detecting operating system..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION_ID="$VERSION_ID"
        log_message "Detected OS: $OS_ID $OS_VERSION_ID"
    else
        exit_with_error "Cannot detect operating system"
    fi
    
    if [[ "$OS_ID" == "fedora" ]]; then
        log_message "Fedora detected. This script is for Debian-based systems only."
        exit_with_error "Unsupported OS: Fedora. Please use the Fedora-specific script for systemd-resolved configuration."
    fi
    
    if [[ "$OS_ID" != "debian" && "$OS_ID" != "ubuntu" ]]; then
        exit_with_error "Unsupported operating system: $OS_ID. This script supports Debian and Ubuntu."
    fi
    
    RESOLVED_CONF_BAK="${backup_dir}/${USER_PREFIX}-dns.conf_${timestamp}"
}

check_install_systemd_resolved() {
    log_message "Checking if systemd-resolved is installed..."
    
    if ! dpkg -l | grep -q "^ii.*systemd-resolved"; then
        log_message "systemd-resolved is not installed"
        log_message "Attempting to install systemd-resolved..."
        
        if ! apt-get update 2>&1 | tee -a "$DT_LOG_FILE" || ! apt-get install -y systemd-resolved 2>&1 | tee -a "$DT_LOG_FILE"; then
            exit_with_error "Failed to install systemd-resolved. Please install it manually."
        fi
        
        log_message "systemd-resolved installed successfully"
    fi
    
    if ! systemctl is-active --quiet systemd-resolved; then
        log_message "Starting systemd-resolved service..."
        if ! systemctl start systemd-resolved 2>&1 | tee -a "$DT_LOG_FILE"; then
            exit_with_error "Failed to start systemd-resolved service"
        fi
    fi
}

check_system_requirements() {
    log_message "Checking system requirements..."

    if [ "$EUID" -ne 0 ]; then
        exit_with_error "This script must be run as root (use sudo)"
    fi

    check_install_systemd_resolved

    if [ ! -f "$RESOLVED_CONF" ]; then
        log_message "Configuration file does not exist, it will be created"
    fi

    if [ ! -d "$backup_dir" ]; then
        log_message "Creating backup directory: $backup_dir"
        if ! mkdir -p "$backup_dir"; then
            exit_with_error "Failed to create backup directory"
        fi
    fi
}

backup_configuration() {
    log_message "Creating backup of resolved.conf..."
    
    if [ -f "$RESOLVED_CONF" ]; then
        if ! cp "$RESOLVED_CONF" "$RESOLVED_CONF_BAK"; then
            exit_with_error "Failed to create backup"
        fi
        log_message "Backup created at: $RESOLVED_CONF_BAK"
    else
        log_message "No existing configuration to backup"
    fi
    
    local -r max_backups=5
    local backup_count
    backup_count=$(ls -1 "${backup_dir}/${USER_PREFIX}-dns.conf_"* 2>/dev/null | wc -l)
    
    if [ "$backup_count" -gt "$max_backups" ]; then
        log_message "Removing old backups..."
        ls -1t "${backup_dir}/${USER_PREFIX}-dns.conf_"* | tail -n +$((max_backups + 1)) | xargs rm
    fi
}

verify_configuration() {
    log_message "Verifying configuration..."
    
    if [ -f "$RESOLVED_CONF" ]; then
        if [ ! -r "$RESOLVED_CONF" ]; then
            exit_with_error "Cannot read $RESOLVED_CONF"
        fi
        
        if [ ! -w "$RESOLVED_CONF" ]; then
            exit_with_error "Cannot write to $RESOLVED_CONF"
        fi
        
        local file_perms
        file_perms=$(stat -c "%a" "$RESOLVED_CONF")
        if [ "$file_perms" != "644" ]; then
            log_message "Warning: $RESOLVED_CONF has incorrect permissions: $file_perms (should be 644)"
            read -p "Fix permissions? [y/N]: " fix_perms
            if [[ "$fix_perms" == [yY] ]]; then
                chmod 644 "$RESOLVED_CONF"
            fi
        fi
    fi
}

update_configuration() {
    log_message "Updating resolved.conf configuration..."
    
    mkdir -p "$(dirname "$RESOLVED_CONF")"
    
    printf '%s\n' "${DNS_CONFIGS[@]}" > "$RESOLVED_CONF"
    
    chown root:root "$RESOLVED_CONF"
    chmod 644 "$RESOLVED_CONF"
    
    log_message "Configuration updated successfully"
}

restart_service() {
    log_message "Restarting systemd-resolved service..."
    
    if ! systemctl restart systemd-resolved 2>&1 | tee -a "$DT_LOG_FILE"; then
        log_message "Warning: Failed to restart systemd-resolved"
        read -p "Continue anyway? [y/N]: " continue_anyway
        [[ "$continue_anyway" != [yY] ]] && exit_with_error "Failed to restart systemd-resolved"
    fi
    
    log_message "Service restart handled successfully"
}

display_usage() {
    echo "systemd-resolved Configuration Script"
    echo "==================================="
    echo "This script configures systemd-resolved with predefined DNS settings."
    echo "Current configuration prefix: ${USER_PREFIX}"
    echo ""
    echo "The script will:"
    echo "  1. Backup the current configuration"
    echo "  2. Update resolved.conf with new settings"
    echo "  3. Restart the systemd-resolved service"
    echo ""
    echo "Available DNS configurations:"
    printf '%s\n' "${DNS_CONFIGS[@]}" | grep "^#DNS=" | sed 's/^#/  /'
}

main() {
    log_message "Starting systemd-resolved configuration script for Debian-based systems..."
    log_message "Using configuration prefix: ${USER_PREFIX}"
    
    display_usage
    
    detect_os
    
    read -p "Do you want to update the systemd-resolved configuration? [y/N]: " confirm
    if [[ "$confirm" != [yY] ]]; then
        log_message "Operation cancelled by user"
        exit 0
    fi
    
    check_system_requirements
    verify_configuration
    
    backup_configuration
    
    update_configuration
    
    restart_service
    
    log_message "Configuration completed successfully"
    echo -e "\nConfiguration has been updated. Check $DT_LOG_FILE for details."
    echo "Configuration file: $RESOLVED_CONF"
    
    if [ -f "$RESOLVED_CONF_BAK" ]; then
        echo "A backup of the original configuration is saved at: $RESOLVED_CONF_BAK"
    fi
}

main "$@"
