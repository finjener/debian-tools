#!/bin/bash


# DEBIAN_TOOLS_CATEGORY: Desktop
# DEBIAN_TOOLS_NAME: KDE Settings
# DEBIAN_TOOLS_TYPE: BackupRestore
# KDE Plasma 6 Backup & Restore Script
# Backs up critical configuration files and user data for KDE Plasma 6.
# Restores them by carefully handling the Plasma session (systemd).

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

# Initialize logging
dt_init_log "kde_settings"

# Configuration
BACKUP_CATEGORY="kde"

# --------------------------------------------------------------------------------
# FILE LISTS
# --------------------------------------------------------------------------------

# Config files in ~/.config/
CONFIG_FILES=(
    # Core Plasma & Shell
    "kdeglobals"
    "plasma-org.kde.plasma.desktop-appletsrc"
    "plasmashellrc"
    "plasmarc"
    "ksplashrc"
    "klaunchrc"
    "krunnerrc"
    "plasmanotifyrc"
    
    # KWin / Display
    "kwinrc"
    "kwinrulesrc"
    "kwinoutputconfig.json"
    "kscreenlockerrc"
    "ksmserverrc"
    "kgammarc"

    # Logic & Daemons
    "kded5rc"
    "kded6rc"
    "kconf_updaterc"
    "ktimezonedrc"
    "kaccessrc"
    "plasma-localerc"
    "powerdevilrc"
    "powermanagementprofilesrc"
    "bluedevilglobalrc"

    # Input & Shortcuts
    "kglobalshortcutsrc"
    "khotkeysrc"
    "kcminputrc"
    "kxkbrc"
    "touchpadrc"

    # Activities
    "kactivitymanagerdrc"
    "kactivitymanagerd-statsrc"
    "kactivitymanagerd-pluginsrc"

    # System & Environment
    "user-dirs.dirs"
    "mimeapps.list"
    "Trolltech.conf"
    
    # GTK Integration
    "gtkrc"
    "gtkrc-2.0"
    "gtk-3.0/settings.ini"
    "gtk-4.0/settings.ini"
    "xsettingsd/xsettingsd.conf"

    # Core KDE Apps
    "dolphinrc"
    "katerc"
    "katevirc"
    "konsolerc"
    "yakuakerc"
    "spectaclerc"
    "gwenviewrc"
    "arkrc"
    "okularrc"
    "systemmonitorrc"
    "systemsettingsrc"
)

# Directories in ~/.local/share/
SHARE_DIRS=(
    "plasma"
    "plasmashell"
    "konsole"
    "kxmlgui5"
    "kwin"
    "aurorae"
    "color-schemes"
    "icons"
    "fonts"
    "kactivitymanagerd"
    "knotifications6"
)

# Individual files in ~/.local/share/
SHARE_FILES=(
    "user-places.xbel"
)

# Autostart
AUTOSTART_DIR=".config/autostart"

# --------------------------------------------------------------------------------
# BACKUP
# --------------------------------------------------------------------------------

do_backup() {
    dt_header "KDE Plasma Backup"
    
    local backup_dir=$(dt_backup_path "$BACKUP_CATEGORY")
    
    dt_step 1 3 "Collecting configuration files..."
    
    local files_to_backup=()
    local config_count=0
    local share_count=0
    
    # Config Files
    for file in "${CONFIG_FILES[@]}"; do
        if [ -f "$HOME/.config/$file" ]; then
            files_to_backup+=("-C" "$HOME" ".config/$file")
            ((config_count++))
        fi
    done
    dt_success "Found $config_count config files"

    # Share Directories
    for dir in "${SHARE_DIRS[@]}"; do
        if [ -d "$HOME/.local/share/$dir" ]; then
            files_to_backup+=("-C" "$HOME" ".local/share/$dir")
            ((share_count++))
        fi
    done
    dt_success "Found $share_count share directories"
    
    # Share Files
    for file in "${SHARE_FILES[@]}"; do
        if [ -f "$HOME/.local/share/$file" ]; then
            files_to_backup+=("-C" "$HOME" ".local/share/$file")
        fi
    done

    # Autostart
    if [ -d "$HOME/$AUTOSTART_DIR" ]; then
        files_to_backup+=("-C" "$HOME" "$AUTOSTART_DIR")
        dt_success "Found autostart directory"
    fi

    dt_step 2 3 "Creating archive..."
    
    local backup_file="$backup_dir/kde_backup_$DT_TIMESTAMP.tar.gz"
    
    if ! tar -czf "$backup_file" "${files_to_backup[@]}" --ignore-failed-read 2>&1 | tee -a "$DT_LOG_FILE"; then
        dt_exit_error "Failed to create backup archive"
    fi
    
    dt_step 3 3 "Verifying..."
    
    local item_count=$(tar -tzf "$backup_file" 2>/dev/null | wc -l)
    dt_success "Archive contains $item_count items"
    
    dt_summary \
        "File=$backup_file" \
        "Size=$(du -h "$backup_file" | cut -f1)" \
        "Config files=$config_count" \
        "Share dirs=$share_count"
}

# --------------------------------------------------------------------------------
# RESTORE
# --------------------------------------------------------------------------------

do_restore() {
    local archive="$1"
    
    dt_header "KDE Plasma Restore"
    
    # If no archive specified, ask user to select one
    if [ -z "$archive" ]; then
        local backup_dir=$(dt_backup_path "$BACKUP_CATEGORY")
        local backups=($(ls "$backup_dir"/kde_*.tar.gz 2>/dev/null))
        
        if [ ${#backups[@]} -eq 0 ]; then
            dt_error "No backups found in $backup_dir"
            exit 1
        fi
        
        echo "Select a backup to restore:"
        select file in "${backups[@]}" "Cancel"; do
            case $file in
                Cancel)
                    dt_info "Restore cancelled."
                    exit 0
                    ;;
                *)
                    if [ -n "$file" ]; then
                        archive="$file"
                        break
                    else
                        echo "Invalid selection. Please try again."
                    fi
                    ;;
            esac
        done
    fi

    if [ ! -f "$archive" ]; then
        dt_exit_error "File not found: $archive"
    fi

    dt_info "Restoring from: $(basename "$archive")"
    
    dt_warn "This will overwrite your current KDE settings!"
    dt_warn "You may need to log out and back in for changes to apply."
    
    if ! dt_confirm "Continue with restore?" "n"; then
        dt_info "Restore cancelled."
        exit 0
    fi

    dt_step 1 5 "Creating safety backup..."
    
    local backup_dir=$(dt_backup_path "$BACKUP_CATEGORY")
    local safety_backup="$backup_dir/kde_safety_$DT_TIMESTAMP.tar.gz"
    tar -czf "$safety_backup" -C "$HOME" .config .local/share/plasma .local/share/kwin 2>&1 | tee -a "$DT_LOG_FILE"
    dt_success "Safety backup: $safety_backup"

    # dt_step 2 5 "Stopping Plasma Shell..."
    # systemctl --user stop plasma-plasmashell.service 2>/dev/null
    # sleep 2
    # dt_success "Plasma Shell stopped"

    dt_step 3 5 "Restoring files..."
    
    if ! tar -xzf "$archive" -C "$HOME" 2>&1 | tee -a "$DT_LOG_FILE"; then
        dt_warn "Some files may have failed to restore"
    fi
    dt_success "Files restored"
    
    dt_step 4 5 "Clearing cache..."
    
    rm -rf "$HOME/.cache/plasma"* 2>/dev/null
    rm -rf "$HOME/.cache/kwin"* 2>/dev/null
    rm -rf "$HOME/.cache/qtshadercache"* 2>/dev/null
    rm -rf "$HOME/.cache/kscreen"* 2>/dev/null
    dt_success "Cache cleared"
    
    # dt_step 5 5 "Restarting Plasma..."
    
    # systemctl --user daemon-reload
    # systemctl --user start plasma-plasmashell.service
    
    dt_success "Restore completed!"
    echo ""
    dt_info "If you see glitches, log out and back in."
}

# --------------------------------------------------------------------------------
# LIST
# --------------------------------------------------------------------------------

do_list() {
    dt_header "KDE Backups"
    
    local backup_dir=$(dt_backup_path "$BACKUP_CATEGORY")
    
    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
        dt_warn "No backups found."
        exit 0
    fi
    
    echo ""
    ls -lht "$backup_dir"/kde_* 2>/dev/null
    echo ""
}

# --------------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------------

show_usage() {
    echo "KDE Plasma Backup & Restore"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  --backup, -b              Create a backup of KDE settings"
    echo "  --restore, -r <file>      Restore KDE settings from backup"
    echo "  --list, -l                List available backups"
    echo ""
    echo "Backup location: $DT_BACKUP_DIR/kde/"
    echo "Log location:    $DT_LOG_DIR/"
    echo ""
}

case "$1" in
    --backup|-b)
        do_backup
        ;;
    --restore|-r)
        do_restore "$2"
        ;;
    --list|-l)
        do_list
        ;;
    --help|-h|*)
        show_usage
        ;;
esac
