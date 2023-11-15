#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: System
# DEBIAN_TOOLS_NAME: Bashrc Configs
# DEBIAN_TOOLS_TYPE: BackupRestore
# Bashrc Configuration Script
# Adds useful aliases and configurations to .bashrc

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "bashrc_configs"

bashrc_file="$HOME/.bashrc"

# Legacy functions for compatibility
exit_with_error() {
    dt_error "$1"
    exit 1
}

log_message() {
    dt_log "$1" true
}

check_system_requirements() {
    log_message "Checking system requirements..."

    if [ "$EUID" -eq 0 ]; then
        exit_with_error "This script should not be run as root. Please run without sudo."
    fi

    if [ ! -f "$bashrc_file" ]; then
        exit_with_error ".bashrc file not found in your home directory"
    fi

    if [ ! -w "$bashrc_file" ]; then
        exit_with_error ".bashrc file is not writable"
    fi

    local required_commands=("python" "git" "yt-dlp")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_message "Warning: $cmd is not installed. Related aliases might not work."
        fi
    done
}

backup_bashrc() {
    local backup_file="${bashrc_file}.bak_${timestamp}"
    log_message "Creating backup of .bashrc at $backup_file"
    
    if ! cp "$bashrc_file" "$backup_file"; then
        exit_with_error "Failed to create backup of .bashrc"
    fi
    
    log_message "Backup created successfully"
}

check_aliases_exist() {
    local aliases=(
        "createpenv"
        "entervenv"
        "setgitemail"
        "setgitname"
        "download_video_playlist"
        "download_video"
        "download_audio_playlist"
        "download_audio"
        "waydroid-reset"
        "pipupgrade"
    )
    
    for alias in "${aliases[@]}"; do
        if grep -q "alias $alias=" "$bashrc_file"; then
            return 0
        fi
    done
    return 1
}

add_alias_if_not_exists() {
    local alias_name="$1"
    local alias_command="$2"
    local category="$3"
    
    log_message "Processing alias: $alias_name ($category)"
    
    if ! grep -q "alias $alias_name=" "$bashrc_file"; then
        echo "alias $alias_name='$alias_command'" >> "$bashrc_file"
        log_message "Added alias: $alias_name"
        return 0
    else
        log_message "Skipped: Alias already exists: $alias_name"
        return 1
    fi
}

verify_aliases() {
    log_message "Verifying aliases..."
    local failed=0
    
    if ! (source "$bashrc_file" 2>/dev/null); then
        log_message "Warning: Error while sourcing .bashrc"
        failed=1
    fi
    
    for alias in "${!aliases[@]}"; do
        if ! grep -q "alias $alias=" "$bashrc_file"; then
            log_message "Warning: Alias not found: $alias"
            failed=1
        fi
    done
    
    if [ "$failed" -eq 1 ]; then
        return 1
    fi
    return 0
}

declare -A aliases=(
    ["createpenv"]="python -m venv venv:Python Environment"
    ["entervenv"]="source venv/bin/activate:Python Environment"
    ["pipupgrade"]="pip install --upgrade:Python Environment"
    
    ["setgitemail"]="git config user.email \"email@example.com\":Git Config"
    ["setgitname"]="git config user.name \"Your Name\":Git Config"
    
    ["download_video_playlist"]="yt-dlp -f bestvideo+bestaudio --add-metadata --merge-output-format mp4 -o \"%(playlist)s/%(playlist_index)s-%(title)s.%(ext)s\":Media Download"
    ["download_video"]="yt-dlp -f bestvideo+bestaudio --add-metadata --merge-output-format mp4 -o \"%(title)s.%(ext)s\":Media Download"
    
    ["download_audio_playlist"]="yt-dlp -x --audio-format mp3 --audio-quality 0 --embed-metadata --embed-thumbnail -o \"%(playlist)s/%(playlist_index)s-%(title)s.%(ext)s\":Media Download"
    ["download_audio"]="yt-dlp -x --audio-format mp3 --audio-quality 0 --embed-metadata --embed-thumbnail -o \"%(title)s.%(ext)s\":Media Download"
    
    ["waydroid-reset"]="sudo rm -rf /var/lib/waydroid /home/.waydroid ~/waydroid ~/.share/waydroid ~/.local/share/applications/*aydroid* ~/.local/share/waydroid:System Management"
)

main() {
    log_message "Starting .bashrc configuration script..."
    
    check_system_requirements
    
    echo -e "\nThis script will add the following alias categories to your .bashrc:"
    echo "1. Python Environment Management"
    echo "2. Git Configuration"
    echo "3. Media Download Utilities"
    echo "4. System Management Tools"
    
    read -p "Do you want to proceed with these changes? [y/N]: " confirm
    if [[ "$confirm" != [yY] ]]; then
        log_message "Operation cancelled by user"
        exit 0
    fi
    
    backup_bashrc
    
    if ! check_aliases_exist; then
        echo -e "\n# Custom aliases added by bashrc_configs.sh" >> "$bashrc_file"
    fi
    
    local added=0
    local skipped=0
    
    local current_category=""
    for alias_name in "${!aliases[@]}"; do
        IFS=':' read -r command category <<< "${aliases[$alias_name]}"
        
        if [ "$current_category" != "$category" ]; then
            echo -e "\n# $category aliases" >> "$bashrc_file"
            current_category="$category"
        fi
        
        if add_alias_if_not_exists "$alias_name" "$command" "$category"; then
            ((added++))
        else
            ((skipped++))
        fi
    done
    
    if ! verify_aliases; then
        log_message "Warning: Some aliases may not have been added correctly"
    fi
    
    echo -e "\nConfiguration Summary:"
    echo "Added: $added new aliases"
    echo "Skipped: $skipped existing aliases"
    
    log_message "All operations completed successfully"
    echo -e "\nBashrc configuration has been updated successfully"
    echo "Log file: $DT_LOG_FILE"
    echo "Backup created at: ${bashrc_file}.bak_${timestamp}"
    echo "Please run 'source ~/.bashrc' or start a new terminal session to use the new aliases"
    
    if [ -n "$BASH" ]; then
        source "$bashrc_file"
    fi
}

main
