#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Packages
# DEBIAN_TOOLS_NAME: DEB Packages
# DEBIAN_TOOLS_TYPE: PackageManager
# External DEB Package Installation Script
# Downloads and installs .deb packages from direct URLs

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "deb_packages"
log_file="$DT_LOG_FILE"  # Alias for compatibility

# Download directory (stay local to script)
download_dir="$script_dir/deb_downloads"
mkdir -p "$download_dir"

# Legacy functions for compatibility
exit_with_error() {
    dt_error "$1"
    exit 1
}

log_message() {
    dt_log "$1" true
}

# ============================================================================
# GITHUB API HELPERS
# ============================================================================

# Cache directory for GitHub API responses
cache_dir="$HOME/.cache/debian-tools"
mkdir -p "$cache_dir"

# Get cached GitHub API response or fetch new
get_cached_github_api() {
    local repo="$1"
    local cache_file="$cache_dir/github_${repo//\//_}.json"
    local cache_max_age=3600  # 1 hour
    
    # Check if cache exists and is recent
    if [ -f "$cache_file" ]; then
        local cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
        if [ $cache_age -lt $cache_max_age ]; then
            cat "$cache_file"
            return 0
        fi
    fi
    
    # Fetch from API and cache
    log_message "Fetching latest release info for $repo from GitHub API..."
    local response=$(curl -s "https://api.github.com/repos/$repo/releases/latest")
    
    # Check for API rate limit
    if echo "$response" | grep -q "API rate limit exceeded"; then
        log_message "Warning: GitHub API rate limit exceeded, using cached data if available"
        [ -f "$cache_file" ] && cat "$cache_file" || echo "{}"
        return 1
    fi
    
    echo "$response" | tee "$cache_file"
}

# Get releases filtered by tag prefix (for multi-product repos)
get_github_releases_by_tag() {
    local repo="$1"
    local tag_prefix="$2"
    local cache_file="$cache_dir/github_${repo//\//_}_tags.json"
    local cache_max_age=3600  # 1 hour
    
    # Check if cache exists and is recent
    if [ -f "$cache_file" ]; then
        local cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
        if [ $cache_age -lt $cache_max_age ]; then
            cat "$cache_file"
            return 0
        fi
    fi
    
    # Fetch from API and cache
    log_message "Fetching releases with tag prefix '$tag_prefix' for $repo from GitHub API..."
    local response=$(curl -s "https://api.github.com/repos/$repo/releases?per_page=100")
    
    # Check for API rate limit
    if echo "$response" | grep -q "API rate limit exceeded"; then
        log_message "Warning: GitHub API rate limit exceeded, using cached data if available"
        [ -f "$cache_file" ] && cat "$cache_file" || echo "[]"
        return 1
    fi
    
    echo "$response" | tee "$cache_file"
}

# Extract latest .deb download URL from GitHub release
get_github_latest_deb() {
    local repo="$1"
    local pattern="$2"
    local tag_prefix="$3"  # Optional: filter by tag prefix (e.g., "auth-v", "desktop-v")
    
    local api_response
    
    # If tag prefix specified, use filtered releases
    if [ -n "$tag_prefix" ]; then
        api_response=$(get_github_releases_by_tag "$repo" "$tag_prefix")
        
        # Parse JSON to find first release with matching tag prefix
        # Extract the entire release object (from opening { to matching })
        local in_release=false
        local brace_count=0
        local current_release=""
        local found_match=false
        
        while IFS= read -r line; do
            # Check if this line starts a new release object
            if [[ "$line" == *"{"* ]] && [[ "$current_release" == "" ]]; then
                in_release=true
                brace_count=1
                current_release="$line"
                continue
            fi
            
            if [ "$in_release" = true ]; then
                current_release+=$'\n'"$line"
                
                # Count braces to find end of release object
                brace_count=$((brace_count + $(echo "$line" | tr -cd '{' | wc -c)))
                brace_count=$((brace_count - $(echo "$line" | tr -cd '}' | wc -c)))
                
                # When we've closed the release object
                if [ $brace_count -eq 0 ]; then
                    # Check if this release has the tag prefix we want
                    if echo "$current_release" | grep -q "\"tag_name\": \"${tag_prefix}"; then
                        # Found matching release, use it
                        api_response="$current_release"
                        found_match=true
                        break
                    fi
                    # Reset for next release
                    current_release=""
                    in_release=false
                fi
            fi
        done <<< "$api_response"
        
        if [ "$found_match" = false ]; then
            log_message "Warning: No releases found with tag prefix '$tag_prefix' for $repo"
            return 1
        fi
    else
        # Use standard latest release
        api_response=$(get_cached_github_api "$repo")
    fi
    
    # Convert glob pattern to regex (replace * with .*)
    local regex_pattern="${pattern//\*/.*}"
    
    # Extract download URL matching pattern
    echo "$api_response" \
        | grep "browser_download_url" \
        | grep -E "$regex_pattern" \
        | head -n 1 \
        | cut -d '"' -f 4
}

# Extract version from GitHub release
get_github_latest_version() {
    local repo="$1"
    local tag_prefix="$2"  # Optional: filter by tag prefix
    
    local api_response
    
    # If tag prefix specified, use filtered releases
    if [ -n "$tag_prefix" ]; then
        api_response=$(get_github_releases_by_tag "$repo" "$tag_prefix")
        echo "$api_response" | grep '"tag_name"' | grep "\"${tag_prefix}" | head -n 1 | cut -d '"' -f 4
    else
        api_response=$(get_cached_github_api "$repo")
        echo "$api_response" | grep '"tag_name"' | head -n 1 | cut -d '"' -f 4
    fi
}

# Get currently installed version
get_installed_version() {
    local package="$1"
    local system_package="${package_names[$package]:-$package}"
    
    # Try dpkg first
    if dpkg -l "$system_package" 2>/dev/null | grep -q "^ii"; then
        dpkg -l "$system_package" | grep "^ii" | awk '{print $3}' | cut -d '-' -f 1
        return 0
    fi
    
    # Try command version
    if [ -n "${package_commands[$package]}" ]; then
        local cmd="${package_commands[$package]}"
        if command -v "$cmd" &>/dev/null; then
            "$cmd" --version 2>/dev/null | head -n 1 | grep -oP '\d+\.\d+(\.\d+)?' | head -n 1
            return 0
        fi
    fi
    
    echo ""
}

declare -A package_names=(
    ["kdiskmark"]="kdiskmark"
    ["java"]="jdk-17"
    ["ente-photos"]="ente"
    ["ente-auth"]="ente-auth"
)

# Package-specific command checks (for apps that install with different package names)
declare -A package_commands=(
    ["ente-photos"]="ente"
    ["ente-auth"]="enteauth"
    ["kdiskmark"]="kdiskmark"
    ["bitwarden"]="bitwarden"
    ["obsidian"]="obsidian"
    ["windscribe"]="windscribe-cli"
    ["standard-notes"]="standard-notes"
)

check_package_installed() {
    local package="$1"
    local system_package="${package_names[$package]:-$package}"
    
    # First check if there's a command-based check
    if [ -n "${package_commands[$package]}" ]; then
        if command -v "${package_commands[$package]}" &> /dev/null; then
            log_message "Package $package is already installed (command check)"
            return 0
        fi
    fi
    
    # Special check for Simplex (installed to /opt/simplex/bin/simplex)
    if [ "$package" == "simplex" ]; then
        if [ -x "/opt/simplex/bin/simplex" ]; then
            log_message "Package $package is already installed (file check)"
            return 0
        fi
    fi
    
    # Fall back to dpkg check
    if dpkg -l 2>/dev/null | grep -q "^ii.*$system_package"; then
        log_message "Package $package is already installed"
        return 0
    fi
    return 1
}

check_system_requirements() {
    local skip_root_check="${1:-false}"
    
    log_message "Checking system requirements..."

    # Skip root check in non-interactive mode (GUI handles via pkexec)
    if [[ -t 0 ]] && [ "$skip_root_check" != "true" ] && [ "$EUID" -eq 0 ]; then
        exit_with_error "This script should not be run as root. Please run without sudo."
    fi

    available_space=$(df -BG /var | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 5 ]; then
        log_message "Warning: Less than 5GB of free space available ($available_space GB)"
        if ! dt_confirm "Continue anyway?" "n"; then
            exit_with_error "Aborted due to insufficient disk space"
        fi
    fi

    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        exit_with_error "No internet connection detected"
    fi
}

verify_download() {
    local file="$1"
    local expected_size="$2"
    
    if [ ! -f "$file" ]; then
        return 1
    fi
    
    if ! dpkg-deb -I "$file" &>/dev/null; then
        log_message "Warning: $file is not a valid Debian package"
        return 1
    fi
    
    if [ -n "$expected_size" ]; then
        local actual_size=$(stat -c%s "$file")
        if [ "$actual_size" -lt "$expected_size" ]; then
            log_message "Warning: $file size ($actual_size) is less than expected ($expected_size)"
            return 1
        fi
    fi
    
    return 0
}

download_package() {
    local url="$1"
    local output_file="$2"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        log_message "Downloading $(basename "$output_file") (Attempt $((retry_count + 1))/$max_retries)"
        
        if wget --quiet --show-progress "$url" -O "$output_file" 2>&1 | tee -a "$log_file"; then
            if verify_download "$output_file"; then
                log_message "Successfully downloaded $(basename "$output_file")"
                return 0
            fi
        fi
        
        log_message "Download failed, retrying..."
        rm -f "$output_file"
        retry_count=$((retry_count + 1))
        sleep 2
    done
    
    return 1
}

install_package() {
    local deb_file="$1"
    local package_name=$(basename "$deb_file")
    
    log_message "Installing $package_name..."
    
    if dpkg -l | grep -q "^ii.*$(basename "$package_name" .deb)"; then
        log_message "$package_name is already installed"
        return 0
    fi
    
    if ! dt_sudo apt-get install -f -y 2>&1 | tee -a "$log_file"; then
        log_message "Warning: Failed to install dependencies"
    fi
    
    if dt_sudo dpkg -i "$deb_file" 2>&1 | tee -a "$log_file"; then
        log_message "Successfully installed $package_name"
        return 0
    else
        log_message "Attempting to fix broken dependencies..."
        if dt_sudo apt-get install -f -y 2>&1 | tee -a "$log_file" && dt_sudo dpkg -i "$deb_file" 2>&1 | tee -a "$log_file"; then
            log_message "Successfully installed $package_name after fixing dependencies"
            return 0
        fi
        log_message "Failed to install $package_name"
        return 1
    fi
}
# ============================================================================
# PACKAGE DEFINITIONS
# ============================================================================

# GitHub-hosted packages (auto-update via API)
# Format: "package_name" => "owner/repo:file_pattern:tag_prefix"
# tag_prefix is optional - used for repos with multiple products (e.g., desktop vs web)
declare -A github_packages=(
    ["ente-photos"]="ente-io/photos-desktop:ente-.*-amd64.deb"
    ["ente-auth"]="ente-io/ente:ente-auth-.*-x86_64.deb:auth-v"
    ["bitwarden"]="bitwarden/clients:.*-amd64.deb:desktop-v"
    ["obsidian"]="obsidianmd/obsidian-releases:obsidian_.*_amd64.deb"
    ["standard-notes"]="standardnotes/app:standard-notes-.*-linux-amd64.deb"
    ["simplex"]="simplex-chat/simplex-chat:simplex-desktop-ubuntu-.*-x86_64.deb"
    ["kdiskmark"]="JonMagon/KDiskMark:kdiskmark_.*_amd64.deb"
    ["affine"]="toeverything/AFFiNE:affine-.*-stable-linux-x64.deb"
    ["opencode"]="anomalyco/opencode:opencode-desktop-linux-amd64.deb"
)

# Static URLs (already auto-updating redirect)
declare -A static_packages=(
    ["windscribe"]="https://windscribe.com/install/desktop/linux_deb_x64"
    ["boosteroid"]="https://boosteroid.com/linux/installer/boosteroid-install-x64.deb"
    ["steam"]="https://cdn.fastly.steamstatic.com/client/installer/steam.deb"
)

# Package URLs (populated dynamically from sources above)
declare -A package_urls

# Package versions (tracked for update checking)
declare -A package_versions

# ============================================================================
# PACKAGE URL POPULATION
# ============================================================================

populate_package_urls() {
    log_message "Resolving package download URLs..."
    
    # Process GitHub packages
    for package in "${!github_packages[@]}"; do
        # Parse package definition: "repo:pattern" or "repo:pattern:tag_prefix"
        local definition="${github_packages[$package]}"
        local repo pattern tag_prefix
        
        # Count colons to determine format
        if [[ "$definition" == *:*:* ]]; then
            # Format: repo:pattern:tag_prefix
            IFS=':' read -r repo pattern tag_prefix <<< "$definition"
        else
            # Format: repo:pattern
            IFS=':' read -r repo pattern <<< "$definition"
            tag_prefix=""
        fi
        
        local url=$(get_github_latest_deb "$repo" "$pattern" "$tag_prefix")
        if [ -n "$url" ]; then
            package_urls[$package]="$url"
            package_versions[$package]=$(get_github_latest_version "$repo" "$tag_prefix")
            log_message "  $package: ${package_versions[$package]}"
        else
            log_message "Warning: Failed to get URL for $package from $repo"
        fi
    done
    
    # Add static packages
    for package in "${!static_packages[@]}"; do
        package_urls[$package]="${static_packages[$package]}"
        package_versions[$package]="latest"
    done
    
    log_message "Resolved ${#package_urls[@]} package URLs"
}

# ============================================================================
# UPDATE CHECKING
# ============================================================================

check_for_updates() {
    echo "Checking for package updates..."
    echo
    
    local updates_available=0
    
    # Sort packages for consistent output
    local sorted_packages=($(for pkg in "${!package_urls[@]}"; do echo "$pkg"; done | sort))
    
    for package in "${sorted_packages[@]}"; do
        local installed_ver=$(get_installed_version "$package")
        local latest_ver="${package_versions[$package]}"
        
        if [ -z "$installed_ver" ]; then
            echo "  $package: Not installed (${latest_ver} available)"
            ((updates_available++))
        elif [ "$latest_ver" = "latest" ]; then
            echo "  $package: ${installed_ver} (latest version unknown)"
        else
            # Simple version comparison (strip 'v' prefix)
            local installed_clean="${installed_ver#v}"
            local latest_clean="${latest_ver#v}"
            
            if [ "$installed_clean" != "$latest_clean" ]; then
                echo "  $package: ${installed_ver} → ${latest_ver} (update available)"
                ((updates_available++))
            else
                echo "  $package: ${installed_ver} (up to date)"
            fi
        fi
    done
    
    echo
    if [ $updates_available -gt 0 ]; then
        echo "$updates_available package(s) can be updated or installed"
        echo "Run without --check-updates to install/update packages"
    else
        echo "All installed packages are up to date!"
    fi
}

show_usage() {
    cat << 'EOF'
Usage: deb_packages.sh [OPTIONS]

Install or update .deb packages from GitHub releases and other sources.

Options:
  --simulate-only, -s    Dry run (show what would be installed)
  --check-updates        Check for available updates without installing
  --help, -h             Show this help message

Default: Install/update all packages

Examples:
  # Check for updates
  ./deb_packages.sh --check-updates
  
  # Simulate installation
  ./deb_packages.sh --simulate-only
  
  # Install/update packages
  ./deb_packages.sh

Packages are automatically fetched from GitHub releases API.
Cache location: ~/.cache/debian-tools/
EOF
}

main() {
    log_message "Starting DEB package installation script..."
    
    # Parse arguments first (before populating URLs)
    local simulate_only=false
    local check_updates=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --simulate-only|-s)
                simulate_only=true
                shift
                ;;
            --check-updates)
                check_updates=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Populate package URLs from sources
    populate_package_urls
    
    # Handle check-updates command
    if [ "$check_updates" = true ]; then
        check_for_updates
        exit 0
    fi
    
    check_system_requirements "$simulate_only"
    
    echo "The following packages will be checked for installation:"
    local to_install=()
    local already_installed=()
    
    for package in "${!package_urls[@]}"; do
        if check_package_installed "$package"; then
            already_installed+=("$package")
            echo "- $package (already installed)"
        else
            to_install+=("$package")
            echo "- $package (will be installed)"
        fi
    done
    
    # Handle simulate-only mode
    if [ "$simulate_only" = true ]; then
        log_message "SIMULATION MODE - showing what would be installed:"
        echo -e "\nAlready installed: ${#already_installed[@]} packages"
        echo "Would install: ${#to_install[@]} packages"
        
        if [ ${#to_install[@]} -gt 0 ]; then
            echo -e "\nPackages that would be installed:"
            for package in "${to_install[@]}"; do
                echo "  $package: ${package_urls[$package]}"
            done
        fi
        
        log_message "Simulation complete - no changes made"
        exit 0
    fi
    
    if ! dt_confirm "Do you want to proceed with installation of missing packages?" "n"; then
        log_message "Installation cancelled by user"
        exit 0
    fi
    
    declare -A installation_status
    
    for package in "${!package_urls[@]}"; do
        if check_package_installed "$package"; then
            installation_status[$package]="Already Installed"
            continue
        fi
        
        url="${package_urls[$package]}"
        
        # Special handling for Windscribe which has a generic executable name without extension
        if [ "$package" == "windscribe" ]; then
            output_file="$download_dir/windscribe.deb"
        else
            output_file="$download_dir/$(basename "$url")"
        fi
        
        if ! download_package "$url" "$output_file"; then
            installation_status[$package]="Download Failed"
            continue
        fi
        
        if ! install_package "$output_file"; then
            installation_status[$package]="Installation Failed"
            continue
        fi
        
        installation_status[$package]="Success"
    done
    
    echo -e "\nInstallation Summary:"
    for package in "${!installation_status[@]}"; do
        echo "$package: ${installation_status[$package]}"
    done | tee -a "$log_file"
    
    log_message "Running cleanup..."
    if ! dt_sudo apt-get autoremove -y 2>&1 | tee -a "$log_file"; then
        log_message "Warning: Autoremove failed"
    fi
    
    if ! dt_sudo apt-get clean 2>&1 | tee -a "$log_file"; then
        log_message "Warning: Clean failed"
    fi
    
    log_message "Installation completed"
    echo "Log file: $log_file"
    echo "Downloaded packages are kept in: $download_dir"
}

main "$@"
