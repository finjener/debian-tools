#!/bin/bash


# DEBIAN_TOOLS_CATEGORY: Security
# DEBIAN_TOOLS_NAME: SSH Keys
# DEBIAN_TOOLS_TYPE: BackupRestore
# DEBIAN_TOOLS_DESCRIPTION: Backup and restore SSH keys with encryption support
# SSH Keys Backup & Restore Script
# Securely backs up ~/.ssh directory with encryption option
# Restores SSH keys while preserving correct permissions

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

# Initialize logging
dt_init_log "ssh_keys"

# Configuration
SSH_DIR="$HOME/.ssh"
BACKUP_CATEGORY="ssh"

# --------------------------------------------------------------------------------
# HELPER FUNCTIONS
# --------------------------------------------------------------------------------

check_ssh_exists() {
    if [ ! -d "$SSH_DIR" ]; then
        dt_error "SSH directory not found: $SSH_DIR"
        return 1
    fi
    
    if [ -z "$(ls -A "$SSH_DIR" 2>/dev/null)" ]; then
        dt_warn "SSH directory is empty: $SSH_DIR"
        return 1
    fi
    return 0
}

list_ssh_contents() {
    dt_info "Current SSH directory contents:"
    dt_divider
    ls -la "$SSH_DIR" 2>&1 | tee -a "$DT_LOG_FILE"
    dt_divider
    
    # Count keys
    local key_count=$(find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | wc -l)
    dt_info "Found $key_count public key(s)"
}

# --------------------------------------------------------------------------------
# BACKUP
# --------------------------------------------------------------------------------

do_backup() {
    local encrypt="${1:-false}"
    
    dt_header "SSH Keys Backup"
    
    local backup_dir=$(dt_backup_path "$BACKUP_CATEGORY")
    
    dt_step 1 4 "Checking SSH directory..."
    
    if ! check_ssh_exists; then
        dt_exit_error "Nothing to backup. SSH directory is empty or doesn't exist."
    fi
    
    list_ssh_contents
    
    dt_step 2 4 "Creating backup archive..."
    
    local backup_file="$backup_dir/ssh_backup_$DT_TIMESTAMP.tar"
    
    if ! tar -cpf "$backup_file" -C "$HOME" .ssh 2>&1 | tee -a "$DT_LOG_FILE"; then
        dt_exit_error "Failed to create backup archive"
    fi
    
    dt_step 3 4 "Finalizing backup..."
    
    local final_file="$backup_file"
    
    if [ "$encrypt" = "true" ]; then
        dt_info "Encrypting with GPG..."
        echo ""
        
        if gpg --symmetric --cipher-algo AES256 "$backup_file" 2>&1 | tee -a "$DT_LOG_FILE"; then
            rm "$backup_file"
            final_file="${backup_file}.gpg"
            dt_success "Backup encrypted"
        else
            dt_warn "Encryption failed. Keeping unencrypted."
            gzip "$backup_file"
            final_file="${backup_file}.gz"
        fi
    else
        gzip "$backup_file"
        final_file="${backup_file}.gz"
    fi
    
    dt_step 4 4 "Setting permissions..."
    chmod 600 "$final_file"
    dt_success "Permissions set (600)"
    
    dt_summary \
        "File=$final_file" \
        "Size=$(du -h "$final_file" | cut -f1)"
    
    echo ""
    dt_warn "SECURITY: Store this backup securely!"
}

# --------------------------------------------------------------------------------
# RESTORE
# --------------------------------------------------------------------------------

do_restore() {
    local archive="$1"
    
    dt_header "SSH Keys Restore"
    
    if [ -z "$archive" ]; then
        dt_error "Please provide a backup file to restore."
        echo "  Usage: $0 --restore <backup_file>"
        exit 1
    fi
    
    if [ ! -f "$archive" ]; then
        dt_exit_error "File not found: $archive"
    fi
    
    dt_info "Restoring from: $(basename "$archive")"
    
    dt_step 1 4 "Checking backup file..."
    
    local is_encrypted=false
    if [[ "$archive" == *.gpg ]]; then
        is_encrypted=true
        dt_info "Backup is encrypted (GPG)"
    fi
    
    # Safety check for existing keys
    if [ -d "$SSH_DIR" ] && [ -n "$(ls -A "$SSH_DIR" 2>/dev/null)" ]; then
        dt_warn "Current SSH directory is not empty!"
        list_ssh_contents
        
        if dt_confirm "Create safety backup first?"; then
            local backup_dir=$(dt_backup_path "$BACKUP_CATEGORY")
            local safety_backup="$backup_dir/ssh_safety_$DT_TIMESTAMP.tar.gz"
            tar -czpf "$safety_backup" -C "$HOME" .ssh
            chmod 600 "$safety_backup"
            dt_success "Safety backup: $safety_backup"
        fi
        
        if ! dt_confirm "Continue? This will OVERWRITE existing keys" "n"; then
            dt_info "Restore cancelled."
            exit 0
        fi
    fi
    
    dt_step 2 4 "Extracting backup..."
    
    local work_file="$archive"
    local temp_dir=$(mktemp -d)
    
    if [ "$is_encrypted" = true ]; then
        dt_info "Decrypting..."
        local decrypted_file="$temp_dir/ssh_backup.tar"
        
        if ! gpg --decrypt --output "$decrypted_file" "$archive" 2>&1 | tee -a "$DT_LOG_FILE"; then
            rm -rf "$temp_dir"
            dt_exit_error "Decryption failed"
        fi
        work_file="$decrypted_file"
    elif [[ "$archive" == *.tar.gz ]]; then
        local decompressed_file="$temp_dir/ssh_backup.tar"
        if ! gunzip -c "$archive" > "$decompressed_file"; then
            rm -rf "$temp_dir"
            dt_exit_error "Decompression failed"
        fi
        work_file="$decompressed_file"
    fi
    
    dt_step 3 4 "Restoring files..."
    
    dt_ensure_dir "$SSH_DIR"
    
    if ! tar -xpf "$work_file" -C "$HOME" 2>&1 | tee -a "$DT_LOG_FILE"; then
        rm -rf "$temp_dir"
        dt_exit_error "Failed to extract backup"
    fi
    
    rm -rf "$temp_dir"
    
    dt_step 4 4 "Setting permissions..."
    
    chmod 700 "$SSH_DIR"
    chmod 600 "$SSH_DIR"/* 2>/dev/null || true
    chmod 644 "$SSH_DIR"/*.pub 2>/dev/null || true
    chmod 644 "$SSH_DIR/known_hosts" 2>/dev/null || true
    chmod 644 "$SSH_DIR/config" 2>/dev/null || true
    
    dt_success "Permissions fixed"
    
    dt_success "Restore completed!"
    echo ""
    list_ssh_contents
    
    echo ""
    dt_info "Testing SSH agent..."
    if ssh-add -l &>/dev/null; then
        dt_success "SSH agent is running"
    else
        dt_warn "Run: eval \$(ssh-agent) && ssh-add"
    fi
}

# --------------------------------------------------------------------------------
# LIST BACKUPS
# --------------------------------------------------------------------------------

do_list() {
    dt_header "SSH Backups"
    
    local backup_dir=$(dt_backup_path "$BACKUP_CATEGORY")
    
    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
        dt_warn "No backups found."
        exit 0
    fi
    
    echo ""
    ls -lht "$backup_dir"/ssh_* 2>/dev/null
    echo ""
}

# --------------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------------

show_usage() {
    echo "SSH Keys Backup & Restore"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  --backup, -b              Create a backup of SSH keys"
    echo "  --backup-encrypted, -be   Create an encrypted backup (GPG)"
    echo "  --restore, -r <file>      Restore SSH keys from backup"
    echo "  --list, -l                List available backups"
    echo "  --show, -s                Show current SSH directory"
    echo ""
    echo "Backup location: $DT_BACKUP_DIR/ssh/"
    echo "Log location:    $DT_LOG_DIR/"
    echo ""
}

case "$1" in
    --backup|-b)
        do_backup false
        ;;
    --backup-encrypted|-be)
        do_backup true
        ;;
    --restore|-r)
        do_restore "$2"
        ;;
    --list|-l)
        do_list
        ;;
    --show|-s)
        if check_ssh_exists; then
            list_ssh_contents
        fi
        ;;
    --help|-h|*)
        show_usage
        ;;
esac
