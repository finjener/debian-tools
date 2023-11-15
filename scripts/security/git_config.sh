#!/bin/bash


# DEBIAN_TOOLS_CATEGORY: Security
# DEBIAN_TOOLS_NAME: Git Config
# DEBIAN_TOOLS_TYPE: BackupRestore
# Git Config Backup & Restore Script
# Backs up global git configuration files

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

# Initialize logging
dt_init_log "git_config"

# Configuration
BACKUP_CATEGORY="git_config"

# Files to backup
GIT_FILES=(
    "$HOME/.gitconfig"
    "$HOME/.gitignore_global"
    "$HOME/.git-credentials"
    "$HOME/.config/git/config"
    "$HOME/.config/git/ignore"
    "$HOME/.config/git/attributes"
)

# --------------------------------------------------------------------------------
# HELPER FUNCTIONS
# --------------------------------------------------------------------------------

show_current_config() {
    dt_info "Current Git configuration:"
    dt_divider
    
    echo -e "\n${C_BBLUE}User:${C_RESET}"
    local name=$(git config --global user.name 2>/dev/null)
    local email=$(git config --global user.email 2>/dev/null)
    [ -n "$name" ] && echo "  Name: $name"
    [ -n "$email" ] && echo "  Email: $email"
    
    echo -e "\n${C_BBLUE}Config Files:${C_RESET}"
    for file in "${GIT_FILES[@]}"; do
        if [ -f "$file" ]; then
            echo -e "  ${C_GREEN}${SYM_CHECK}${C_RESET} $file ($(stat -c%s "$file") bytes)"
        else
            echo -e "  ${C_DIM}○ $file (not found)${C_RESET}"
        fi
    done
    
    echo -e "\n${C_BBLUE}Aliases:${C_RESET}"
    local alias_count=$(git config --global --get-regexp alias 2>/dev/null | wc -l)
    git config --global --get-regexp alias 2>/dev/null | head -5 | while read -r line; do
        echo "  $line"
    done
    [ "$alias_count" -gt 5 ] && echo "  ... and $((alias_count - 5)) more"
    
    dt_divider
}

# --------------------------------------------------------------------------------
# BACKUP
# --------------------------------------------------------------------------------

do_backup() {
    dt_header "Git Config Backup"
    
    local backup_dir=$(dt_backup_path "$BACKUP_CATEGORY")
    
    dt_step 1 3 "Collecting config files..."
    
    local backup_subdir="$backup_dir/git_temp_$DT_TIMESTAMP"
    mkdir -p "$backup_subdir"
    
    local found_files=0
    
    for file in "${GIT_FILES[@]}"; do
        if [ -f "$file" ]; then
            local rel_path="${file#$HOME/}"
            local dest_dir="$backup_subdir/$(dirname "$rel_path")"
            mkdir -p "$dest_dir"
            cp "$file" "$dest_dir/"
            dt_success "Backed up: $rel_path"
            ((found_files++))
        fi
    done
    
    if [ "$found_files" -eq 0 ]; then
        rm -rf "$backup_subdir"
        dt_warn "No git config files found"
        exit 0
    fi
    
    # Save config dump
    {
        echo "# Git Global Configuration Dump"
        echo "# Generated: $(date)"
        echo "# User: $USER"
        echo ""
        git config --global --list 2>/dev/null
    } > "$backup_subdir/config_dump.txt"
    
    dt_step 2 3 "Creating archive..."
    
    local archive_name="git_config_$DT_TIMESTAMP.tar.gz"
    tar -czf "$backup_dir/$archive_name" -C "$backup_dir" "git_temp_$DT_TIMESTAMP"
    rm -rf "$backup_subdir"
    
    chmod 600 "$backup_dir/$archive_name"
    
    dt_step 3 3 "Done!"
    
    dt_summary \
        "File=$backup_dir/$archive_name" \
        "Size=$(du -h "$backup_dir/$archive_name" | cut -f1)" \
        "Files backed up=$found_files"
}

# --------------------------------------------------------------------------------
# RESTORE
# --------------------------------------------------------------------------------

do_restore() {
    local archive="$1"
    
    dt_header "Git Config Restore"
    
    if [ -z "$archive" ]; then
        dt_error "Please provide a backup file"
        echo "  Usage: $0 --restore <backup_file>"
        exit 1
    fi
    
    if [ ! -f "$archive" ]; then
        dt_exit_error "File not found: $archive"
    fi
    
    dt_info "Restoring from: $(basename "$archive")"
    
    dt_step 1 3 "Checking archive..."
    
    echo ""
    echo "Archive contents:"
    tar -tzf "$archive" | head -15
    echo ""
    
    # Check for existing config
    local has_existing=false
    for file in "${GIT_FILES[@]}"; do
        [ -f "$file" ] && has_existing=true && break
    done
    
    if [ "$has_existing" = true ]; then
        dt_warn "Existing git config found"
        show_current_config
        
        if dt_confirm "Create safety backup first?"; then
            do_backup
        fi
        
        if ! dt_confirm "Overwrite existing config?" "n"; then
            dt_info "Cancelled"
            exit 0
        fi
    fi
    
    dt_step 2 3 "Extracting..."
    
    local temp_dir=$(mktemp -d)
    tar -xzf "$archive" -C "$temp_dir"
    
    local extracted=$(find "$temp_dir" -maxdepth 1 -type d -name "git_*" | head -1)
    [ -z "$extracted" ] && extracted="$temp_dir"
    
    dt_step 3 3 "Restoring files..."
    
    local restored=0
    
    if [ -f "$extracted/.gitconfig" ]; then
        cp "$extracted/.gitconfig" "$HOME/"
        chmod 644 "$HOME/.gitconfig"
        dt_success "Restored: ~/.gitconfig"
        ((restored++))
    fi
    
    if [ -f "$extracted/.gitignore_global" ]; then
        cp "$extracted/.gitignore_global" "$HOME/"
        chmod 644 "$HOME/.gitignore_global"
        dt_success "Restored: ~/.gitignore_global"
        ((restored++))
    fi
    
    if [ -f "$extracted/.git-credentials" ]; then
        dt_warn ".git-credentials contains stored passwords"
        if dt_confirm "Restore credentials?" "n"; then
            cp "$extracted/.git-credentials" "$HOME/"
            chmod 600 "$HOME/.git-credentials"
            dt_success "Restored: ~/.git-credentials"
            ((restored++))
        fi
    fi
    
    if [ -d "$extracted/.config/git" ]; then
        dt_ensure_dir "$HOME/.config/git"
        for file in "$extracted/.config/git"/*; do
            [ -f "$file" ] || continue
            cp "$file" "$HOME/.config/git/"
            chmod 644 "$HOME/.config/git/$(basename "$file")"
            dt_success "Restored: ~/.config/git/$(basename "$file")"
            ((restored++))
        done
    fi
    
    rm -rf "$temp_dir"
    
    dt_success "Restore completed! ($restored files)"
    echo ""
    show_current_config
}

# --------------------------------------------------------------------------------
# SETUP
# --------------------------------------------------------------------------------

do_setup() {
    dt_header "Git Configuration Setup"
    
    if ! dt_require_command "git" "Git"; then
        exit 1
    fi
    
    dt_step 1 3 "User configuration..."
    
    local current_name=$(git config --global user.name 2>/dev/null)
    local current_email=$(git config --global user.email 2>/dev/null)
    
    echo "Current user.name: ${current_name:-<not set>}"
    read -p "New user.name [$current_name]: " new_name
    [ -n "$new_name" ] && git config --global user.name "$new_name"
    
    echo "Current user.email: ${current_email:-<not set>}"
    read -p "New user.email [$current_email]: " new_email
    [ -n "$new_email" ] && git config --global user.email "$new_email"
    
    dt_step 2 3 "Recommended settings..."
    
    if dt_confirm "Apply recommended settings?"; then
        git config --global init.defaultBranch main
        git config --global core.editor "vim"
        git config --global pull.rebase false
        git config --global push.autoSetupRemote true
        git config --global color.ui auto
        git config --global core.autocrlf input
        
        git config --global alias.st "status"
        git config --global alias.co "checkout"
        git config --global alias.br "branch"
        git config --global alias.ci "commit"
        git config --global alias.lg "log --oneline --graph --decorate"
        git config --global alias.last "log -1 HEAD"
        git config --global alias.unstage "reset HEAD --"
        
        dt_success "Recommended settings applied"
    fi
    
    dt_step 3 3 "Global gitignore..."
    
    if [ ! -f "$HOME/.gitignore_global" ]; then
        if dt_confirm "Create default .gitignore_global?"; then
            cat > "$HOME/.gitignore_global" << 'EOF'
# OS files
.DS_Store
Thumbs.db
*~

# Editor files
*.swp
*.swo
.idea/
.vscode/
*.sublime-*

# Build artifacts
*.o
*.pyc
__pycache__/
node_modules/
.cache/
dist/
build/

# Environment
.env
.env.local
*.log
EOF
            git config --global core.excludesfile "$HOME/.gitignore_global"
            dt_success "Created ~/.gitignore_global"
        fi
    fi
    
    echo ""
    show_current_config
}

# --------------------------------------------------------------------------------
# LIST
# --------------------------------------------------------------------------------

do_list() {
    dt_header "Git Config Backups"
    
    local backup_dir=$(dt_backup_path "$BACKUP_CATEGORY")
    
    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
        dt_warn "No backups found."
        exit 0
    fi
    
    echo ""
    ls -lht "$backup_dir"/git_config_* 2>/dev/null
    echo ""
}

# --------------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------------

show_usage() {
    echo "Git Config Backup & Restore"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  --backup, -b              Create a backup of git config"
    echo "  --restore, -r <file>      Restore git config from backup"
    echo "  --list, -l                List available backups"
    echo "  --show, -s                Show current git configuration"
    echo "  --setup                   Interactive setup wizard"
    echo ""
    echo "Backup location: $DT_BACKUP_DIR/git_config/"
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
    --show|-s)
        show_current_config
        ;;
    --setup)
        do_setup
        ;;
    --help|-h|*)
        show_usage
        ;;
esac
