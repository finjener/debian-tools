#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Packages
# DEBIAN_TOOLS_NAME: Flatpak Packages
# DEBIAN_TOOLS_TYPE: PackageManager
# Flatpak Packages Installation Script
# Installs Flatpak applications from Flathub

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "flatpak_packages"
log_file="$DT_LOG_FILE"  # Alias for compatibility

# Default to interactive mode; -y/--yes enables non-interactive
AUTO_YES=false

# Default to system-wide installation
# Can be changed to user-space with --user flag
INSTALL_SCOPE="--system"

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

    available_space=$(df -BG /var | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 10 ]; then
        log_message "Warning: Less than 10GB of free space available ($available_space GB)"
        if [ "$AUTO_YES" = false ]; then
            read -p "Continue anyway? [y/N]: " continue_anyway
            [[ "$continue_anyway" != [yY] ]] && exit_with_error "Aborted due to insufficient disk space"
        fi
    fi

    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        exit_with_error "No internet connection detected"
    fi
}

install_flatpak() {
    log_message "Checking Flatpak installation..."
    if ! command -v flatpak &>/dev/null; then
        log_message "Flatpak is not installed. Installing Flatpak..."
        
        # Run update and install; fail if either command fails and log output
        if ! sudo apt update 2>&1 | tee -a "$log_file" || ! sudo apt install -y flatpak 2>&1 | tee -a "$log_file"; then
            exit_with_error "Failed to install Flatpak"
        fi
        log_message "Flatpak installed successfully"
        
        if ! command -v flatpak &>/dev/null; then
            exit_with_error "Flatpak was installed but the command is not available. Please restart your terminal and try again."
        fi
    else
        log_message "Flatpak is installed"
    fi
}

install_plasma_discover_backend() {
    log_message "Checking plasma-discover-backend-flatpak installation..."
    
    if command -v apt &>/dev/null; then
        if ! dpkg -s plasma-discover-backend-flatpak &>/dev/null; then
            log_message "Installing plasma-discover-backend-flatpak..."
            if ! sudo apt install -y plasma-discover-backend-flatpak 2>&1 | tee -a "$log_file"; then
                log_message "Warning: Failed to install plasma-discover-backend-flatpak"
            else
                log_message "plasma-discover-backend-flatpak installed successfully"
            fi
        else
            log_message "plasma-discover-backend-flatpak is already installed"
        fi
    else
        log_message "apt not found, skipping plasma-discover-backend-flatpak installation"
    fi
}

verify_remote() {
    local remote_name="$1"
    local remote_url="$2"
    
    log_message "Verifying $remote_name repository functionality..."
    
    if ! flatpak remote-ls "$remote_name" --columns=application &>/dev/null; then
        log_message "Warning: $remote_name repository not functioning properly"
        log_message "Attempting to repair $remote_name repository..."
        
        flatpak remote-delete --force "$remote_name" &>/dev/null
        if ! flatpak remote-add --if-not-exists "$remote_name" "$remote_url" 2>&1 | tee -a "$log_file"; then
            exit_with_error "Failed to repair $remote_name repository"
        fi
        
        if ! flatpak remote-ls "$remote_name" --columns=application &>/dev/null; then
            exit_with_error "$remote_name repository still not functioning properly after repair attempt"
        fi
        
        log_message "$remote_name repository repaired successfully"
    else
        log_message "$remote_name repository is functioning properly"
    fi
}

ensure_repo_priority() {
    log_message "Checking repository priorities..."

    # Only manage Flathub priority (Fedora support disabled)
    local current_priorities
    current_priorities=$(flatpak remote-list --columns=name,priority)

    if flatpak remote-list | grep -q "flathub"; then
        local flathub_priority
        flathub_priority=$(echo "$current_priorities" | grep "flathub" | awk '{print $2}')
        if [ "$flathub_priority" != "1" ]; then
            log_message "Setting Flathub as the default repository (priority 1)..."
            flatpak remote-modify --prio=1 flathub
        else
            log_message "Flathub is already set as default repository (priority 1)"
        fi
    fi

    log_message "Current Flatpak repository configuration:"
    flatpak remote-list --columns=name,priority | tee -a "$log_file"
}

setup_repositories() {
    # Early exit if Flathub exists and priority is already correct
    local flathub_priority
    if flatpak remote-list | grep -q "flathub"; then
        flathub_priority=$(flatpak remote-list --columns=name,priority | awk '/flathub/ {print $2}')
        if [[ "$flathub_priority" == "1" ]]; then
            log_message "Flathub repository is present and priority is correct. Skipping repository setup."
            return
        fi
    fi
    log_message "Setting up Flatpak repositories..."
    
    # Fedora repository support disabled — only manage Flathub
    local has_fedora=false
    local has_flathub=false

    if flatpak remote-list | grep -q "flathub"; then
        has_flathub=true
        log_message "Flathub repository is already added"
    fi
    
    if [ "$has_flathub" = false ]; then
        log_message "Adding Flathub repository..."
        if ! flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>&1 | tee -a "$log_file"; then
            exit_with_error "Failed to add Flathub repository"
        else
            log_message "Flathub repository added successfully"
            has_flathub=true
            
            verify_remote "flathub" "https://flathub.org/repo/flathub.flatpakrepo"
        fi
    else
        if ! flatpak remote-info flathub &>/dev/null; then
            log_message "Enabling Flathub repository..."
            if ! flatpak remote-modify --enable flathub 2>&1 | tee -a "$log_file"; then
                log_message "Warning: Failed to enable Flathub repository"
            fi
        fi
        
        verify_remote "flathub" "https://flathub.org/repo/flathub.flatpakrepo"
    fi
    
    ensure_repo_priority
    
    log_message "Updating XDG_DATA_DIRS environment variable..."
    export XDG_DATA_DIRS="/var/lib/flatpak/exports/share:/home/$USER/.local/share/flatpak/exports/share:$XDG_DATA_DIRS"
    log_message "XDG_DATA_DIRS is now: $XDG_DATA_DIRS"
}

extract_app_name() {
    local full_id="$1"
    
    if [[ "$full_id" == *"."* ]]; then
        echo "$full_id" | sed 's/.*\.//'
    else
        echo "$full_id" | sed 's/.*\///'
    fi
}

check_app_in_repo() {
    local app_id="$1"
    local repo="$2"
    local app_name=$(extract_app_name "$app_id")
    
    if flatpak remote-ls "$repo" | grep -q "^$app_id$"; then
        printf "%s" "$app_id"
        return 0
    fi
    
    local search_result=$(flatpak remote-ls "$repo" | grep -i "$app_name")
    
    if [ -n "$search_result" ]; then
        local found_line=$(echo "$search_result" | head -n 1)
        
        for word in $found_line; do
            if [[ "$word" == *.* ]]; then
                printf "%s" "$word"
                return 0
            fi
        done
    fi
    
    return 1
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Install or uninstall Flatpak applications from Flathub repository"
    echo
    echo "Options:"
    echo "  -y, --yes            Automatically answer 'yes' to all prompts"
    echo "  -u, --uninstall      Uninstall all flatpak applications"
    echo "  -s, --simulate-only  Show what would be installed (dry run)"
    echo "  --user               Install in user space (no sudo required)"
    echo "  -h, --help           Show this help message"
    echo
    echo "Default: Install system-wide (/var/lib/flatpak/)"
    echo
}

parse_args() {
    UNINSTALL_MODE=false
    SIMULATE_ONLY=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)
                AUTO_YES=true
                shift
                ;;
            -u|--uninstall)
                UNINSTALL_MODE=true
                shift
                ;;
            -s|--simulate-only)
                SIMULATE_ONLY=true
                shift
                ;;
            --user)
                INSTALL_SCOPE="--user"
                log_message "User-space installation mode enabled (no sudo required)"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

install_flatpak_apps() {
    local apps=("$@")
    local failed_apps=()
    local installed_apps=()
    local skipped_apps=()

    for app in "${apps[@]}"; do
        if [[ "$app" =~ ^#.* ]]; then
            skipped_apps+=("$app")
            continue
        fi

        if flatpak list --app --columns=application | grep -xq "$app"; then
            log_message "$app is already installed"
            installed_apps+=("$app")
            continue
        fi

        local app_name=$(extract_app_name "$app")
        local found_app_id=""

        # Only use Flathub repository (Fedora support disabled)
        found_app_id=$(check_app_in_repo "$app" "flathub" 2>/dev/null) || true

        if [ -n "$found_app_id" ]; then
            log_message "Found '$app_name' in Flathub as '$found_app_id'"
            log_message "Installing $found_app_id from Flathub repository..."
            
            # Use sudo for system-wide installations
            if [ "$INSTALL_SCOPE" = "--system" ]; then
                if sudo flatpak install $INSTALL_SCOPE -y --noninteractive flathub "$found_app_id"; then
                    log_message "Successfully installed $found_app_id from Flathub repository"
                    installed_apps+=("$app")
                else
                    log_message "Failed to install $found_app_id from Flathub repository"
                    failed_apps+=("$app")
                fi
            else
                if flatpak install $INSTALL_SCOPE -y --noninteractive flathub "$found_app_id"; then
                    log_message "Successfully installed $found_app_id from Flathub repository"
                    installed_apps+=("$app")
                else
                    log_message "Failed to install $found_app_id from Flathub repository"
                    failed_apps+=("$app")
                fi
            fi
        else
            log_message "App '$app_name' not found in Flathub repository"
            failed_apps+=("$app")
        fi
    done
    
    echo -e "\nInstallation Summary:"
    echo "Successfully installed: ${#installed_apps[@]} apps"
    echo "Failed to install: ${#failed_apps[@]} apps"
    echo "Skipped (commented or user declined): ${#skipped_apps[@]} apps"
    
    if [ ${#failed_apps[@]} -gt 0 ]; then
        echo -e "\nFailed applications:"
        printf '%s\n' "${failed_apps[@]}"
    fi
    
    local eol_runtimes=$(flatpak list --runtime | grep -i "eol" || true)
    if [ -n "$eol_runtimes" ]; then
        echo -e "\nWarning: The following runtimes are End-of-Life:"
        echo "$eol_runtimes"
        
        if [ "$AUTO_YES" = true ]; then
            log_message "Automatically updating EOL runtimes..."
            flatpak update -y
        else
            read -p "Do you want to update these runtimes? [y/N]: " update_runtimes
            if [[ "$update_runtimes" == [yY] ]]; then
                log_message "Updating EOL runtimes..."
                flatpak update -y
            fi
        fi
    fi
}

update_flatpak_apps() {
    log_message "Updating Flatpak applications..."
    
    # Use sudo for system-wide updates
    if [ "$INSTALL_SCOPE" = "--system" ]; then
        if ! sudo flatpak update $INSTALL_SCOPE -y 2>&1 | tee -a "$log_file"; then
            log_message "Warning: Failed to update some Flatpak applications"
            return 1
        fi
    else
        if ! flatpak update $INSTALL_SCOPE -y 2>&1 | tee -a "$log_file"; then
            log_message "Warning: Failed to update some Flatpak applications"
            return 1
        fi
    fi
    
    log_message "Flatpak applications updated successfully"
    return 0
}

uninstall_flatpak_apps() {
    local apps=("$@")
    local failed_uninstalls=()
    local successful_uninstalls=()
    local not_installed=()
    
    log_message "Starting flatpak application uninstallation..."
    
    if [ "$AUTO_YES" = false ]; then
        echo "WARNING: This will uninstall all flatpak applications listed in the script."
        read -p "Do you want to proceed with uninstallation? [y/N]: " confirm
        if [[ "$confirm" != [yY] ]]; then
            log_message "Uninstallation cancelled by user"
            return 0
        fi
    fi
    
    for app in "${apps[@]}"; do
        if [[ "$app" =~ ^#.* ]]; then
            continue
        fi
        
        local app_name=$(extract_app_name "$app")
        local installed_app_id=$(flatpak list --app | grep -i "$app_name" | awk '{print $2}')
        
        if [ -z "$installed_app_id" ]; then
            log_message "$app_name is not installed"
            not_installed+=("$app")
            continue
        fi
        
        log_message "Uninstalling $installed_app_id..."
        
        if [ "$AUTO_YES" = false ]; then
            read -p "Do you want to uninstall $installed_app_id? [y/N]: " uninstall_confirm
            if [[ "$uninstall_confirm" != [yY] ]]; then
                log_message "Skipping uninstallation of $installed_app_id"
                continue
            fi
        fi
        
        if flatpak uninstall -y "$installed_app_id"; then
            log_message "Successfully uninstalled $installed_app_id"
            successful_uninstalls+=("$installed_app_id")
        else
            log_message "Failed to uninstall $installed_app_id"
            failed_uninstalls+=("$installed_app_id")
        fi
    done
    
    echo -e "\nUninstallation Summary:"
    echo "Successfully uninstalled: ${#successful_uninstalls[@]} apps"
    echo "Failed to uninstall: ${#failed_uninstalls[@]} apps"
    echo "Not installed: ${#not_installed[@]} apps"
    
    if [ ${#failed_uninstalls[@]} -gt 0 ]; then
        echo -e "\nFailed uninstallations:"
        printf '%s\n' "${failed_uninstalls[@]}"
    fi
    
    return 0
}

uninstall_all_flatpaks() {
    log_message "Uninstalling all flatpak applications..."
    
    if [ "$AUTO_YES" = false ]; then
        echo "WARNING: This will uninstall ALL flatpak applications on your system, including those not installed by this script."
        read -p "Are you sure you want to uninstall ALL flatpak applications? [y/N]: " confirm_all
        if [[ "$confirm_all" != [yY] ]]; then
            log_message "Complete uninstallation cancelled by user"
            return 0
        fi
    fi
    
    local installed_apps=($(flatpak list --app --columns=application))
    
    if [ ${#installed_apps[@]} -eq 0 ]; then
        log_message "No flatpak applications are installed"
        return 0
    fi
    
    log_message "Uninstalling all ${#installed_apps[@]} flatpak applications..."
    
    if flatpak uninstall --all -y; then
        log_message "Successfully uninstalled all flatpak applications"
    else
        log_message "Failed to uninstall some flatpak applications"
    fi
    
    log_message "Removing unused runtimes and extensions..."
    flatpak uninstall --unused -y
    
    return 0
}

communication_apps=(
    "network.loki.Session"
    #"org.kde.tokodon"
    "org.telegram.desktop"
    #"io.github.kukuruzka165.materialgram"
    #"org.mozilla.Thunderbird"
    #"org.kde.neochat"
    "io.github.ungoogled_software.ungoogled_chromium"
)

media_apps=(
    "org.kde.plasmatube"
    "org.kde.audiotube"
    "com.stremio.Stremio"
    "io.freetubeapp.FreeTube"
    "org.js.nuclear.Nuclear"
    "com.github.neithern.g4music"
    "io.github.mhogomchungu.media-downloader"
    #"org.kde.digikam"
    #"org.kde.kdenlive"
    #"org.kde.krita"
    #"org.kde.elisa"
    "org.kde.pixelwheels"
    "org.kde.kdiamond" # Mirror Hall/Diamond game
    "net.lutris.Lutris"
)

productivity_apps=(
    "io.github.alainm23.planify"
    #"md.obsidian.Obsidian"
    "org.cryptomator.Cryptomator"
    "org.kde.CrowTranslate"
    "org.gnome.gitlab.somas.Apostrophe"
    "com.github.alainm23.byte"
    #"org.kde.ghostwriter"
    #"org.kde.klevernotes"
    #"org.kde.kmymoney"
    #"org.kde.umbrello"
    #"org.kde.kgeography"
    #"org.kde.marknote"
    #"org.kde.okular"
)

system_tools=(
    "io.github.giantpinkrobots.bootqt"
    "com.github.tchx84.Flatseal"
    "io.github.giantpinkrobots.flatsweep"
    "net.nokyan.Resources"
    "app.drey.Warp"
    "io.github.flattool.Warehouse"
    "org.gabmus.whatip"
    "io.podman_desktop.PodmanDesktop"
    "io.gitlab.adhami3310.Impression"
    "net.fasterland.converseen"
    "org.kde.isoimagewriter"
    #"org.kde.kget"
    #"org.kde.gwenview"
    #"org.kde.kcalc"
    #"org.kde.kolourpaint"
    #"org.kde.krdc"
    #"org.kde.skanpage"
    #"org.kde.kweather"
    "org.kde.pix"
    #"org.qbittorrent.qBittorrent"
)

dev_tools=(
    "org.gaphor.Gaphor"
    "re.sonny.Workbench"
    #"com.vscodium.codium"
)

privacy_tools=(
    "website.i2pd.i2pd"
    "fr.romainvigier.MetadataCleaner"
    "org.onionshare.OnionShare"
    "io.frama.tractor.carburetor"
)

flatpak_apps=(
    "${communication_apps[@]}"
    "${media_apps[@]}"
    "${productivity_apps[@]}"
    "${system_tools[@]}"
    "${dev_tools[@]}"
    "${privacy_tools[@]}"
)

main() {
    log_message "Starting Flatpak package management script..."
    
    parse_args "$@"
    
    check_system_requirements
    
    install_flatpak
    
    if [ "$UNINSTALL_MODE" = true ]; then
        if [ "$AUTO_YES" = false ]; then
            echo "Uninstall options:"
            echo "1. Uninstall only applications listed in this script"
            echo "2. Uninstall ALL flatpak applications on the system"
            read -p "Enter your choice [1/2]: " uninstall_choice
            
            case "$uninstall_choice" in
                1)
                    uninstall_flatpak_apps "${flatpak_apps[@]}"
                    ;;
                2)
                    uninstall_all_flatpaks
                    ;;
                *)
                    log_message "Invalid choice. Exiting."
                    exit 1
                    ;;
            esac
        else
            uninstall_flatpak_apps "${flatpak_apps[@]}"
        fi
        
        log_message "Uninstallation completed"
        echo "Log file: $log_file"
    else
        install_plasma_discover_backend
        
        setup_repositories
        
        echo -e "\nPackages will be installed in the following categories:"
        echo "1. Communication and Social Media (${#communication_apps[@]} apps)"
        echo "2. Media and Entertainment (${#media_apps[@]} apps)"
        echo "3. Productivity and Organization (${#productivity_apps[@]} apps)"
        echo "4. System Tools and Utilities (${#system_tools[@]} apps)"
        echo "5. Development Tools (${#dev_tools[@]} apps)"
        echo "6. Privacy and Security (${#privacy_tools[@]} apps)"
        
        echo -e "\nInstallation will use the Flathub repository."
        
        # Handle simulate-only mode
        if [ "$SIMULATE_ONLY" = true ]; then
            log_message "SIMULATION MODE - showing what would be installed:"
            local would_install=()
            local already_installed=()
            
            for app in "${flatpak_apps[@]}"; do
                if [[ "$app" =~ ^#.* ]]; then
                    continue
                fi
                if flatpak list --app --columns=application | grep -xq "$app"; then
                    already_installed+=("$app")
                else
                    would_install+=("$app")
                fi
            done
            
            echo -e "\nAlready installed: ${#already_installed[@]} apps"
            echo "Would install: ${#would_install[@]} apps"
            
            if [ ${#would_install[@]} -gt 0 ]; then
                echo -e "\nApps that would be installed:"
                printf '  %s\n' "${would_install[@]}"
            fi
            
            log_message "Simulation complete - no changes made"
            exit 0
        fi
        
        if [ "$AUTO_YES" = false ]; then
            read -p "Do you want to proceed with the installation? [y/N]: " confirm
            if [[ "$confirm" != [yY] ]]; then
                log_message "Installation cancelled by user"
                exit 0
            fi
        else
            echo "Automatic installation mode enabled - proceeding without confirmation"
        fi
        
        install_flatpak_apps "${flatpak_apps[@]}"
        
        update_flatpak_apps
        
        log_message "Running cleanup..."
        if [ "$INSTALL_SCOPE" = "--system" ]; then
            if ! sudo flatpak uninstall $INSTALL_SCOPE --unused -y 2>&1 | tee -a "$log_file"; then
                log_message "Warning: Failed to remove unused Flatpak runtimes"
            fi
        else
            if ! flatpak uninstall $INSTALL_SCOPE --unused -y 2>&1 | tee -a "$log_file"; then
                log_message "Warning: Failed to remove unused Flatpak runtimes"
            fi
        fi
        
        log_message "Installation completed"
        echo "Log file: $log_file"
    fi
}

main "$@"
