#!/bin/bash


# DEBIAN_TOOLS_CATEGORY: Security
# DEBIAN_TOOLS_NAME: GPG Keys
# DEBIAN_TOOLS_TYPE: BackupRestore
# GPG Keys Backup & Restore Script
# Exports and imports GPG keys (public, private, trust database)
# Includes ownertrust for complete key restoration

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

# Initialize logging
dt_init_log "gpg_keys"

# Configuration
GNUPG_DIR="$HOME/.gnupg"
BACKUP_CATEGORY="gpg"

# --------------------------------------------------------------------------------
# HELPER FUNCTIONS
# --------------------------------------------------------------------------------

check_gpg_exists() {
    if ! command -v gpg &>/dev/null; then
        dt_error "GPG is not installed. Install with: sudo apt install gnupg"
        return 1
    fi
    return 0
}

gpg_public_key_count() {
    # NOTE: grep returns exit code 1 when it finds no matches (even though it prints 0).
    # Avoid emitting "0\n0" which breaks integer comparisons.
    local key_count
    key_count="$(gpg --list-keys 2>/dev/null | grep -c "^pub" || true)"
    key_count="${key_count:-0}"
    echo "$key_count"
}

list_gpg_keys() {
    dt_info "Current GPG keys:"
    dt_divider
    echo -e "${C_BBLUE}Public Keys:${C_RESET}"
    gpg --list-keys --keyid-format LONG 2>/dev/null
    echo ""
    echo -e "${C_BBLUE}Secret Keys:${C_RESET}"
    gpg --list-secret-keys --keyid-format LONG 2>/dev/null
    dt_divider
}

# --------------------------------------------------------------------------------
# BACKUP
# --------------------------------------------------------------------------------

do_backup() {
    local encrypt="${1:-false}"
    
    dt_header "GPG Keys Backup"
    
    local backup_dir=$(dt_backup_path "$BACKUP_CATEGORY")
    
    dt_step 1 6 "Checking GPG keys..."
    
    if ! check_gpg_exists; then
        dt_exit_error "GPG is not available."
    fi

    local key_count
    key_count="$(gpg_public_key_count)"
    if [ "$key_count" -eq 0 ]; then
        dt_warn "No GPG keys found in keyring; nothing to backup."
        # Treat as success so batch runs don't fail on machines without GPG keys.
        exit 0
    fi

    list_gpg_keys
    
    local backup_subdir="$backup_dir/gpg_temp_$DT_TIMESTAMP"
    mkdir -p "$backup_subdir"
    chmod 700 "$backup_subdir"
    
    dt_step 2 6 "Exporting public keys..."
    if gpg --export --armor > "$backup_subdir/public_keys.asc" 2>> "$DT_LOG_FILE"; then
        dt_success "Public keys exported"
    else
        dt_warn "No public keys to export"
    fi
    
    dt_step 3 6 "Exporting secret keys..."
    dt_warn "You may be prompted for passphrase(s) (pinentry dialog)."
    if gpg --export-secret-keys --armor > "$backup_subdir/secret_keys.asc" 2>> "$DT_LOG_FILE"; then
        dt_success "Secret keys exported"
    else
        dt_warn "Secret key export failed or no secret keys available"
    fi
    
    # Export secret subkeys (optional; may also require pinentry)
    if [[ "${DEBIAN_TOOLS_GPG_INCLUDE_SECRET_SUBKEYS:-}" == "1" ]]; then
        if gpg --export-secret-subkeys --armor > "$backup_subdir/secret_subkeys.asc" 2>> "$DT_LOG_FILE"; then
            dt_success "Secret subkeys exported"
        else
            dt_warn "Secret subkey export failed"
        fi
    fi
    
    dt_step 4 6 "Exporting ownertrust..."
    if gpg --export-ownertrust > "$backup_subdir/ownertrust.txt" 2>> "$DT_LOG_FILE"; then
        dt_success "Ownertrust exported"
    fi
    
    # Create key inventory
    {
        echo "GPG Key Backup - $DT_TIMESTAMP"
        echo "================================"
        echo ""
        echo "Public Keys:"
        gpg --list-keys --keyid-format LONG 2>/dev/null
        echo ""
        echo "Secret Keys:"
        gpg --list-secret-keys --keyid-format LONG 2>/dev/null
    } > "$backup_subdir/key_inventory.txt"
    
    # Optional full backup
    if dt_confirm "Also backup entire .gnupg directory?" "n"; then
        dt_info "Backing up full .gnupg..."
        tar -cpf "$backup_subdir/gnupg_full.tar" -C "$HOME" .gnupg 2>&1 | tee -a "$DT_LOG_FILE"
        dt_success "Full .gnupg backed up"
    fi
    
    chmod 600 "$backup_subdir"/*
    
    dt_step 5 6 "Creating archive..."
    
    local archive_name="gpg_backup_$DT_TIMESTAMP.tar"
    tar -cpf "$backup_dir/$archive_name" -C "$backup_dir" "gpg_temp_$DT_TIMESTAMP" 2>&1 | tee -a "$DT_LOG_FILE"
    rm -rf "$backup_subdir"
    
    local final_file="$backup_dir/$archive_name"
    
    dt_step 6 6 "Finalizing..."
    
    if [ "$encrypt" = "true" ]; then
        dt_info "Encrypting with GPG..."
        echo ""
        
        if gpg --symmetric --cipher-algo AES256 "$final_file" 2>&1 | tee -a "$DT_LOG_FILE"; then
            rm "$final_file"
            final_file="${final_file}.gpg"
            dt_success "Backup encrypted"
        else
            dt_warn "Encryption failed, compressing instead"
            gzip "$final_file"
            final_file="${final_file}.gz"
        fi
    else
        gzip "$final_file"
        final_file="${final_file}.gz"
    fi
    
    chmod 600 "$final_file"
    
    dt_summary \
        "File=$final_file" \
        "Size=$(du -h "$final_file" | cut -f1)"
    
    echo ""
    dt_error "CRITICAL: This contains PRIVATE keys!"
    dt_warn "Store securely. Never share or upload unencrypted."
}

# --------------------------------------------------------------------------------
# RESTORE
# --------------------------------------------------------------------------------

do_restore() {
    local archive="$1"
    
    dt_header "GPG Keys Restore"
    
    if [ -z "$archive" ]; then
        dt_error "Please provide a backup file"
        echo "  Usage: $0 --restore <backup_file>"
        exit 1
    fi
    
    if [ ! -f "$archive" ]; then
        dt_exit_error "File not found: $archive"
    fi
    
    dt_info "Restoring from: $(basename "$archive")"
    
    dt_step 1 4 "Checking backup..."
    
    local is_encrypted=false
    if [[ "$archive" == *.gpg ]]; then
        is_encrypted=true
        dt_info "Backup is encrypted (GPG)"
    fi
    
    # Safety check
    if check_gpg_exists 2>/dev/null; then
        dt_warn "You already have GPG keys!"
        list_gpg_keys
        
        echo ""
        echo "Options:"
        echo "  1. Merge (import alongside existing)"
        echo "  2. Replace (backup current first)"
        echo "  3. Cancel"
        read -p "Choose [1/2/3]: " choice
        
        case "$choice" in
            1) dt_info "Will merge keys" ;;
            2)
                local backup_dir=$(dt_backup_path "$BACKUP_CATEGORY")
                local safety="$backup_dir/gpg_safety_$DT_TIMESTAMP.tar.gz"
                if ! tar -czpf "$safety" -C "$HOME" .gnupg 2>/dev/null; then
                    dt_exit_error "Failed to create safety backup. Aborting restore to protect existing keys."
                fi
                chmod 600 "$safety"
                dt_success "Safety backup: $safety"
                ;;
            *) dt_info "Cancelled"; exit 0 ;;
        esac
    fi
    
    dt_step 2 4 "Extracting..."
    
    local temp_dir=$(mktemp -d)
    local work_file="$archive"
    
    if [ "$is_encrypted" = true ]; then
        dt_info "Decrypting..."
        local decrypted="$temp_dir/gpg_backup.tar"
        if ! gpg --decrypt --output "$decrypted" "$archive" 2>&1 | tee -a "$DT_LOG_FILE"; then
            rm -rf "$temp_dir"
            dt_exit_error "Decryption failed"
        fi
        work_file="$decrypted"
    elif [[ "$archive" == *.tar.gz ]]; then
        local decomp="$temp_dir/gpg_backup.tar"
        gunzip -c "$archive" > "$decomp"
        work_file="$decomp"
    fi
    
    tar -xpf "$work_file" -C "$temp_dir" 2>&1 | tee -a "$DT_LOG_FILE"
    
    local extracted=$(find "$temp_dir" -maxdepth 1 -type d -name "gpg_*" | head -1)
    [ -z "$extracted" ] && extracted="$temp_dir"
    
    # Check for full backup
    if [ -f "$extracted/gnupg_full.tar" ]; then
        if dt_confirm "Full .gnupg backup found. Restore entirely?" "n"; then
            dt_info "Restoring full .gnupg..."
            [ -d "$GNUPG_DIR" ] && mv "$GNUPG_DIR" "${GNUPG_DIR}.backup_$DT_TIMESTAMP"
            tar -xpf "$extracted/gnupg_full.tar" -C "$HOME"
            chmod 700 "$GNUPG_DIR"
            dt_success "Full restore complete"
            rm -rf "$temp_dir"
            list_gpg_keys
            return
        fi
    fi
    
    dt_step 3 4 "Importing keys..."
    
    if [ -f "$extracted/public_keys.asc" ]; then
        dt_info "Importing public keys..."
        gpg --import "$extracted/public_keys.asc" 2>&1 | tee -a "$DT_LOG_FILE" && dt_success "Public keys imported"
    fi
    
    if [ -f "$extracted/secret_keys.asc" ]; then
        dt_info "Importing secret keys..."
        gpg --import "$extracted/secret_keys.asc" 2>&1 | tee -a "$DT_LOG_FILE" && dt_success "Secret keys imported"
    fi
    
    dt_step 4 4 "Restoring trust..."
    
    if [ -f "$extracted/ownertrust.txt" ]; then
        gpg --import-ownertrust "$extracted/ownertrust.txt" 2>> "$DT_LOG_FILE" && dt_success "Ownertrust restored"
    fi
    
    rm -rf "$temp_dir"
    
    dt_success "Restore completed!"
    list_gpg_keys
    
    echo ""
    dt_info "Set ultimate trust for your own keys:"
    echo "  gpg --edit-key <KEY_ID>"
    echo "  gpg> trust → 5 → quit"
}

# --------------------------------------------------------------------------------
# LIST / VERIFY
# --------------------------------------------------------------------------------

do_list() {
    dt_header "GPG Backups"
    
    local backup_dir=$(dt_backup_path "$BACKUP_CATEGORY")
    
    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
        dt_warn "No backups found."
        exit 0
    fi
    
    echo ""
    ls -lht "$backup_dir"/gpg_* 2>/dev/null
    echo ""
}

do_verify() {
    dt_header "GPG Verification"
    
    dt_step 1 3 "Checking installation..."
    
    if ! dt_require_command "gpg" "GnuPG"; then
        exit 1
    fi
    
    dt_result "Version" "$(gpg --version | head -1)"
    dt_result "Home" "$GNUPG_DIR"
    
    if [ -d "$GNUPG_DIR" ]; then
        dt_result "Permissions" "$(stat -c '%a' "$GNUPG_DIR")"
    fi
    
    dt_step 2 3 "Listing keys..."
    list_gpg_keys
    
    dt_step 3 3 "Testing encryption..."
    
    local test_string="GPG test - $(date)"
    if echo "$test_string" | gpg --symmetric --armor --batch --passphrase "test" 2>/dev/null | \
       gpg --decrypt --batch --passphrase "test" 2>/dev/null | grep -q "GPG test"; then
        dt_success "Symmetric encryption working"
    else
        dt_warn "Encryption test failed"
    fi
}

# --------------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------------

show_usage() {
    echo "GPG Keys Backup & Restore"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  --backup, -b              Create a backup of GPG keys"
    echo "  --backup-encrypted, -be   Create an encrypted backup"
    echo "  --restore, -r <file>      Restore GPG keys from backup"
    echo "  --list, -l                List available backups"
    echo "  --show, -s                Show current GPG keys"
    echo "  --verify, -v              Verify GPG installation"
    echo ""
    echo "Backup location: $DT_BACKUP_DIR/gpg/"
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
        list_gpg_keys
        ;;
    --verify|-v)
        do_verify
        ;;
    --help|-h|*)
        show_usage
        ;;
esac
