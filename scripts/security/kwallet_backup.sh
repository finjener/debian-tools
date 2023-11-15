#!/bin/bash


# DEBIAN_TOOLS_CATEGORY: Security
# DEBIAN_TOOLS_NAME: KWallet Backup
# DEBIAN_TOOLS_TYPE: BackupRestore
# KWallet Backup & Restore Script
# Backs up KDE Wallet data for credential restoration
# Note: KWallet stores passwords encrypted - backup preserves encryption

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

# Initialize logging
dt_init_log "kwallet"

# Configuration
KWALLET_DIR="$HOME/.local/share/kwalletd"
BACKUP_CATEGORY="kwallet"

# --------------------------------------------------------------------------------
# HELPER FUNCTIONS
# --------------------------------------------------------------------------------

check_kwallet_exists() {
    local found=false
    
    if [ -d "$KWALLET_DIR" ] && [ -n "$(ls -A "$KWALLET_DIR" 2>/dev/null)" ]; then
        found=true
    fi
    
    if [ -d "$HOME/.kde/share/apps/kwallet" ]; then
        found=true
    fi
    
    if ls "$HOME"/.local/share/kwalletd/*.kwl &>/dev/null 2>&1; then
        found=true
    fi
    
    if [ "$found" = false ]; then
        dt_warn "No KWallet data found"
        return 1
    fi
    return 0
}

list_wallets() {
    dt_info "Available wallets:"
    dt_divider
    
    if [ -d "$KWALLET_DIR" ]; then
        for wallet in "$KWALLET_DIR"/*.kwl; do
            [ -f "$wallet" ] && echo "  ${SYM_BULLET} $(basename "$wallet" .kwl)"
        done
    fi
    
    if [ -d "$HOME/.kde/share/apps/kwallet" ]; then
        for wallet in "$HOME/.kde/share/apps/kwallet"/*.kwl; do
            [ -f "$wallet" ] && echo "  ${SYM_BULLET} $(basename "$wallet" .kwl) (legacy KDE4)"
        done
    fi
    
    dt_divider
}

# --------------------------------------------------------------------------------
# BACKUP
# --------------------------------------------------------------------------------

do_backup() {
    local encrypt="${1:-false}"
    
    dt_header "KWallet Backup"
    
    local backup_dir=$(dt_backup_path "$BACKUP_CATEGORY")
    
    dt_step 1 4 "Checking KWallet data..."
    
    if ! check_kwallet_exists; then
        dt_exit_error "No KWallet data to backup"
    fi
    
    list_wallets
    
    local backup_subdir="$backup_dir/kwallet_temp_$DT_TIMESTAMP"
    mkdir -p "$backup_subdir"
    chmod 700 "$backup_subdir"
    
    dt_step 2 4 "Copying wallet files..."
    
    local files_copied=0
    
    if [ -d "$KWALLET_DIR" ]; then
        cp -r "$KWALLET_DIR"/* "$backup_subdir/" 2>&1 | tee -a "$DT_LOG_FILE" && ((files_copied++))
        dt_success "KWallet data copied"
    fi
    
    if [ -d "$HOME/.kde/share/apps/kwallet" ]; then
        mkdir -p "$backup_subdir/kde4_legacy"
        cp -r "$HOME/.kde/share/apps/kwallet"/* "$backup_subdir/kde4_legacy/" 2>&1 | tee -a "$DT_LOG_FILE" && ((files_copied++))
        dt_success "Legacy KDE4 wallets copied"
    fi
    
    if [ -f "$HOME/.config/kwalletrc" ]; then
        cp "$HOME/.config/kwalletrc" "$backup_subdir/"
        dt_success "KWallet config copied"
    fi
    
    if [ "$files_copied" -eq 0 ]; then
        rm -rf "$backup_subdir"
        dt_exit_error "No wallet files were copied"
    fi
    
    chmod -R 600 "$backup_subdir"/* 2>/dev/null
    chmod 700 "$backup_subdir"
    
    dt_step 3 4 "Creating archive..."
    
    local archive_name="kwallet_backup_$DT_TIMESTAMP.tar"
    tar -cpf "$backup_dir/$archive_name" -C "$backup_dir" "kwallet_temp_$DT_TIMESTAMP"
    rm -rf "$backup_subdir"
    
    local final_file="$backup_dir/$archive_name"
    
    dt_step 4 4 "Finalizing..."
    
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
    dt_warn "Wallet files are encrypted with your KWallet password"
    dt_info "You'll need that password when restoring"
}

# --------------------------------------------------------------------------------
# RESTORE
# --------------------------------------------------------------------------------

do_restore() {
    local archive="$1"
    
    dt_header "KWallet Restore"
    
    if [ -z "$archive" ]; then
        dt_error "Please provide a backup file"
        echo "  Usage: $0 --restore <backup_file>"
        exit 1
    fi
    
    if [ ! -f "$archive" ]; then
        dt_exit_error "File not found: $archive"
    fi
    
    dt_info "Restoring from: $(basename "$archive")"
    
    dt_step 1 4 "Checking daemon..."
    
    if pgrep -x "kwalletd5" >/dev/null || pgrep -x "kwalletd6" >/dev/null; then
        dt_warn "KWallet daemon is running"
        dt_info "Close with: kquitapp5 kwalletd5 (or kwalletd6)"
        if ! dt_confirm "Continue anyway?" "n"; then
            exit 0
        fi
    fi
    
    # Safety backup
    if check_kwallet_exists 2>/dev/null; then
        dt_warn "Existing KWallet data found"
        
        if dt_confirm "Create safety backup first?"; then
            local backup_dir=$(dt_backup_path "$BACKUP_CATEGORY")
            local safety="$backup_dir/kwallet_safety_$DT_TIMESTAMP.tar.gz"
            tar -czpf "$safety" -C "$HOME/.local/share" kwalletd 2>&1 | tee -a "$DT_LOG_FILE"
            chmod 600 "$safety"
            dt_success "Safety backup: $safety"
        fi
    fi
    
    dt_step 2 4 "Extracting..."
    
    local temp_dir=$(mktemp -d)
    local work_file="$archive"
    
    if [[ "$archive" == *.gpg ]]; then
        dt_info "Decrypting..."
        local decrypted="$temp_dir/kwallet_backup.tar"
        if ! gpg --decrypt --output "$decrypted" "$archive" 2>&1 | tee -a "$DT_LOG_FILE"; then
            rm -rf "$temp_dir"
            dt_exit_error "Decryption failed"
        fi
        work_file="$decrypted"
    elif [[ "$archive" == *.tar.gz ]]; then
        local decomp="$temp_dir/kwallet_backup.tar"
        gunzip -c "$archive" > "$decomp"
        work_file="$decomp"
    fi
    
    tar -xpf "$work_file" -C "$temp_dir"
    
    local extracted=$(find "$temp_dir" -maxdepth 1 -type d -name "kwallet_*" | head -1)
    [ -z "$extracted" ] && extracted="$temp_dir"
    
    dt_step 3 4 "Restoring files..."
    
    dt_ensure_dir "$KWALLET_DIR"
    
    for file in "$extracted"/*.kwl "$extracted"/*.salt; do
        [ -f "$file" ] || continue
        cp "$file" "$KWALLET_DIR/"
        dt_success "Restored: $(basename "$file")"
    done
    
    if [ -f "$extracted/kwalletrc" ]; then
        cp "$extracted/kwalletrc" "$HOME/.config/"
        dt_success "Restored: kwalletrc"
    fi
    
    dt_step 4 4 "Setting permissions..."
    
    chmod 700 "$KWALLET_DIR"
    chmod 600 "$KWALLET_DIR"/* 2>/dev/null
    
    rm -rf "$temp_dir"
    
    dt_success "Restore completed!"
    echo ""
    dt_info "Restart daemon: kquitapp5 kwalletd5 && kwalletd5 &"
}

# --------------------------------------------------------------------------------
# LIST
# --------------------------------------------------------------------------------

do_list() {
    dt_header "KWallet Backups"
    
    local backup_dir=$(dt_backup_path "$BACKUP_CATEGORY")
    
    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
        dt_warn "No backups found."
        exit 0
    fi
    
    echo ""
    ls -lht "$backup_dir"/kwallet_* 2>/dev/null
    echo ""
}

# --------------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------------

show_usage() {
    echo "KWallet Backup & Restore"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  --backup, -b              Create a backup of KWallet data"
    echo "  --backup-encrypted, -be   Create an encrypted backup"
    echo "  --restore, -r <file>      Restore KWallet from backup"
    echo "  --list, -l                List available backups"
    echo "  --show, -s                Show current wallets"
    echo ""
    echo "Backup location: $DT_BACKUP_DIR/kwallet/"
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
        if check_kwallet_exists; then
            list_wallets
        fi
        ;;
    --help|-h|*)
        show_usage
        ;;
esac
