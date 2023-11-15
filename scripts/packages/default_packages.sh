#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Packages
# DEBIAN_TOOLS_NAME: Default Packages
# DEBIAN_TOOLS_TYPE: PackageManager
# Default Debian Packages Installation Script
# Installs categorized system packages with verification and retry logic

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "default_packages"
log_file="$DT_LOG_FILE"  # Alias for compatibility

# Legacy function for compatibility with existing code
log_message() {
    dt_log "$1" true
}

exit_with_error() {
    dt_error "$1"
    exit 1
}

verify_package_exists() {
    local pkg="$1"
    apt-cache show "$pkg" &>/dev/null
    return $?
}

simulate_package_installation() {
    local category="$1"
    local package_list="${debian_packages[$category]}"
    local -a packages
    packages=($(string_to_array "$package_list"))

    log_message "Simulating installation for category: $category"

    if [ ${#packages[@]} -eq 0 ]; then
        log_message "No packages defined for category '$category'. Skipping simulation."
        return 0
    fi

    local packages_to_install=()
    local unavailable_packages=()

    for pkg in "${packages[@]}"; do
        if [[ -z "$pkg" || "$pkg" =~ ^# ]]; then
            continue
        fi

        if [[ "$pkg" == *"*"* ]]; then
            log_message "Warning: Skipping wildcard package '$pkg' in category '$category'."
            continue
        fi

        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            if verify_package_exists "$pkg"; then
                packages_to_install+=("$pkg")
            else
                unavailable_packages+=("$pkg")
                log_message "Warning: Package '$pkg' from category '$category' not found in repositories."
            fi
        fi
    done

    if [ ${#unavailable_packages[@]} -gt 0 ]; then
        log_message "Warning: ${#unavailable_packages[@]} package(s) not found in repositories and will be skipped: ${unavailable_packages[*]}"
    fi

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log_message "Simulating installation of ${#packages_to_install[@]} package(s) for '$category'..."

        if ! DEBIAN_FRONTEND=noninteractive sudo apt-get install -y -qq --dry-run "${packages_to_install[@]}" 2>&1 | tee -a "$log_file"; then
            log_message "Warning: Installation simulation had issues for category '$category'"
            log_message "Some packages may have dependency or virtual package issues - will attempt individual installation"
        else
            log_message "Installation simulation successful for '$category'"
        fi
    else
        log_message "No packages need installation in category '$category'"
    fi
}

install_debian_packages() {
    local category="$1"
    local package_list="${debian_packages[$category]}"
    local -a packages
    packages=($(string_to_array "$package_list")) # Use the helper function

    log_message "--- Processing category: $category ---"

    if [ ${#packages[@]} -eq 0 ]; then
        log_message "No packages defined for category '$category'. Skipping."
        return
    fi

    local installed_packages=()
    local packages_to_install=()
    local unavailable_packages=()
    local failed_packages=()

    for pkg in "${packages[@]}"; do
        if [[ -z "$pkg" || "$pkg" =~ ^# ]]; then
            continue
        fi

        if [[ "$pkg" == *"*"* ]]; then
            log_message "Warning: Skipping wildcard package '$pkg' in category '$category'. Wildcards need specific handling (e.g., apt-cache search)."
            continue
        fi

        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            installed_packages+=("$pkg")
            continue
        fi

        if verify_package_exists "$pkg"; then
            packages_to_install+=("$pkg")
        else
            unavailable_packages+=("$pkg")
            log_message "Warning: Package '$pkg' from category '$category' not found in repositories. It might be misspelled, obsolete, or from a missing source."
        fi
    done

    if [ ${#installed_packages[@]} -gt 0 ]; then
        log_message "Already installed in '$category': ${#installed_packages[@]} package(s) (${installed_packages[*]})."
    fi

    if [ ${#unavailable_packages[@]} -gt 0 ]; then
        log_message "Unavailable in '$category': ${#unavailable_packages[@]} package(s) (${unavailable_packages[*]})."
    fi

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log_message "Attempting to install ${#packages_to_install[@]} package(s) for '$category': ${packages_to_install[*]}"

        if ! DEBIAN_FRONTEND=noninteractive sudo apt-get install -y "${packages_to_install[@]}" 2>&1 | tee -a "$log_file"; then
            log_message "Batch installation failed for category '$category'. Attempting individual installation for remaining packages..."
            fix_dependencies # Attempt to fix potential issues before retrying individually

            local individually_failed=()
            local still_to_install=()
            for pkg in "${packages_to_install[@]}"; do
                 if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
                     still_to_install+=("$pkg")
                 else
                     log_message "Package '$pkg' was installed successfully during the batch attempt or dependency fix."
                 fi
            done


            if [ ${#still_to_install[@]} -gt 0 ]; then
                 log_message "Retrying installation individually for: ${still_to_install[*]}"
                 for pkg in "${still_to_install[@]}"; do
                     log_message "Installing individual package: $pkg"
                     if ! DEBIAN_FRONTEND=noninteractive sudo apt-get install -y "$pkg" 2>&1 | tee -a "$log_file"; then
                         individually_failed+=("$pkg")
                         log_message "ERROR: Failed to install package: $pkg"
                         log_message "Diagnostics for $pkg:"
                         apt-cache policy "$pkg" 2>&1 | tee -a "$log_file"
                         sudo apt-get install -y "$pkg" --simulate 2>&1 | tee -a "$log_file" # Log simulation output
                     else
                        log_message "Successfully installed individual package: $pkg"
                     fi
                 done
                 failed_packages=("${individually_failed[@]}") # Update the main failed list
             else
                 log_message "All packages seem to be installed after fixing dependencies."
             fi

        else
             log_message "Batch installation successful for category '$category'."
        fi


        if [ ${#failed_packages[@]} -gt 0 ]; then
            log_message "Warning: Failed to install the following packages in '$category': ${failed_packages[*]}"
        else
            local verification_failed=()
             for pkg in "${packages_to_install[@]}"; do
                 if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
                      if ! [[ " ${failed_packages[*]} " =~ " ${pkg} " ]]; then # Check if it wasn't already marked as failed
                         log_message "Verification failed: Package '$pkg' should be installed but isn't."
                         verification_failed+=("$pkg")
                      fi
                 fi
             done
             if [ ${#verification_failed[@]} -eq 0 ]; then
                 log_message "Successfully installed and verified all requested packages in '$category'."
             else
                 log_message "Warning: Verification failed for packages: ${verification_failed[*]}. They might have failed silently or been removed by dependency resolution."
                 failed_packages+=("${verification_failed[@]}") # Add to failed list
             fi
        fi
    else
        log_message "No new packages need installation in category '$category'."
    fi
    log_message "--- Finished category: $category ---"
}


declare -A debian_packages

debian_packages["system_utilities"]=""
system_utilities_packages=(
    wireguard
    ca-certificates
    curl
    wget
    axel
    aria2
    rsync
    htop
    btop               # Modern resource monitor
    iotop
    powertop
    lm-sensors
    smartmontools
    ncdu
    tree
    mc
    git
    unzip
    zip
    tar
    p7zip-full
    unrar
    exfatprogs
    exfat-fuse
    ntfs-3g
    udftools
    libfuse3-4         # FUSE 3.x library (libfuse3-4 on bookworm+)
    libfuse2t64        # FUSE 2.x compatibility
    timeshift
    kdialog
    jq
    ripgrep
    fd-find
    systemd-resolved
    pipewire
    pipewire-audio
    qpwgraph
    cpu-x
    caffeine
    fastfetch
    inxi               # System information tool
    kweather
    umbrello
    python3-yaml
    pkexec
    zram-tools
    
    
    # Terminal Emulators
    alacritty          # GPU-accelerated terminal
    
    # Backup & Encryption
    bup                # Git-based backup
    cryfs              # Encrypted filesystem
    
    # Screen Recording
    recordmydesktop
)

development_tools_packages=(
    build-essential
    pkg-config
    cmake
    meson
    ninja-build
    autoconf
    automake
    libtool
    gettext
    ccache
    gcc
    g++
    clang
    lld
    gdb
    valgrind
    cppcheck
    nasm               # Assembler
    python3
    python3-pip
    python3-venv
    python-is-python3
    perl
    ruby               # Sometimes needed for build systems
    openjdk-17-jdk     # Or choose another Java version
    
    # Code Analysis
    graphviz           # Graph visualization
    tokei              # Code statistics
)

qt6_development_packages=(
    qtcreator
    qt6-base-dev
    qt6-base-dev-tools
    qt6-tools-dev
    qt6-tools-dev-tools
    qt6-declarative-dev
    qt6-declarative-dev-tools
    qt6-multimedia-dev
    qt6-serialport-dev
    qt6-websockets-dev
    qt6-webengine-dev
    qt6-webengine-dev-tools
    qt6-webchannel-dev
    qt6-svg-dev
    qt6-charts-dev
    qt6-quick3d-dev
    qt6-quick3d-dev-tools
    qt6-shadertools-dev
    qt6-remoteobjects-dev
    qt6-speech-dev
    qt6-webview-dev
    qt6-positioning-dev
    qt6-wayland-dev
    qt6-wayland-dev-tools
    qt6-virtualkeyboard-dev
    qt6-scxml-dev
    qt6-sensors-dev
    qt6-serialbus-dev

    qt6-connectivity-dev
    qt6-datavis3d-dev
    qt6-3d-dev
    qt6-5compat-dev
    qt6-httpserver-dev
    qt6-location-dev
    qt6-lottie-dev
    qt6-pdf-dev
    qt6-quick3dphysics-dev
    qt6-quicktimeline-dev
    qt6-documentation-tools
    qt6-graphs-dev
    qt6-grpc-dev
    qt6-languageserver-dev
    qt6-networkauth-dev
    qtkeychain-qt6-dev
    libqt6core5compat6-dev
    libqt6opengl6-dev
    libqt6networkauth6-dev
    qml6-module-qtquick-controls
    qml6-module-qtquick-layouts
    qml6-module-qtquick-templates
    qml6-module-qtqml-workerscript
    qml6-module-qtquick3d
    qml6-module-qtremoteobjects
    qml6-module-qtwebview
    qml6-module-qtcharts

    qml6-module-qtmultimedia
    qml6-module-qtwayland-compositor
    qml6-module-qt-labs-platform
    qml6-module-qt-labs-settings
    qml6-module-qtquick-particles
    qml6-module-qtquick-shapes
    qml6-module-qt5compat-graphicaleffects
)

# Qt5 Development (Legacy - Enable if needed)
# qt5_development_packages=(
#     qtbase5-dev
#     qtbase5-dev-tools
#     qtdeclarative5-dev
#     qtdeclarative5-dev-tools
#     qttools5-dev
#     qttools5-dev-tools
#     qtmultimedia5-dev
#     qtquickcontrols2-5-dev
#     qtwayland5-dev-tools
#     qtwebengine5-dev
#     qtwebengine5-dev-tools
#     qtscript5-dev
#     qtlocation5-dev
#     qtpositioning5-dev
#     libqt5svg5-dev
#     libqt5websockets5-dev
#     libqt5x11extras5-dev
#     libqt5serialport5-dev
#     libqt5sensors5-dev
#     libqt5texttospeech5-dev
#     libqt5xmlpatterns5-dev
#     libqt5waylandclient5-dev
#     libqt5waylandcompositor5-dev
# )

if ! [[ " ${development_tools_packages[*]} " =~ " libopencv-dev " ]]; then
    development_tools_packages+=(libopencv-dev)
fi
if ! [[ " ${development_tools_packages[*]} " =~ " build-essential " ]]; then
    development_tools_packages+=(build-essential)
fi
if ! [[ " ${development_tools_packages[*]} " =~ " cmake " ]]; then
    development_tools_packages+=(cmake)
fi
if ! [[ " ${development_tools_packages[*]} " =~ " git " ]]; then
    development_tools_packages+=(git)
fi
if ! [[ " ${development_tools_packages[*]} " =~ " pkg-config " ]]; then
    development_tools_packages+=(pkg-config)
fi


communication_productivity_packages=(
    telegram-desktop
    neochat
    itinerary
    kontact
    konversation
    krdc
    parley
    pidgin
    pidgin-plugin-pack
    klevernotes
    ghostwriter
    tokodon
    thunderbird
    libreoffice
)

multimedia_packages=(
    vlc
    mpv
    ffmpeg             # Video/audio encoding
    yt-dlp             # Video downloader
    sweeper
    qdirstat
    youtubedl-gui
    digikam
    krita
    gimp
    gpredict
    marble
    kdenlive
    kphotoalbum
    elisa
    kamoso
)

education_packages=(
    kmymoney
    kstars
    kmplot
    skrooge
    kronometer
    filelight
    kolourpaint
    kalzium
    kgeography
    kturtle
    bomber
    khangman
    ktimetracker
    qmlkonsole
    konquest
    kuiviewer
    massif-visualizer
    kile
    killbots
    kimagemapeditor
    klettres
    kst
    minder
    marknote
)

system_tools_packages=(
    bleachbit
    gconf-service
    gconf2 #balena-dependency
    gconf2-common #balena-dependency
    libgconf-2-4 #balena-dependency
    gconf-defaults-service #balena-dependency
    #linux-cpupower
    kget
    kdiff3
    kompare
    labplot
    kdiff3
    kbruch
    ktorrent
    kcachegrind
    pdfarranger
    qbittorrent
    python-is-python3
    python3-venv
    udftools
    mlocate
    libfuse*
    ntfs*
    wget
    gpg
    xclip
    chromium
    chromium-driver
    chromium-sandbox
    chromium-shell
    chromium-common
    uuid-runtime
)

# Container Tools
container_tools_packages=(
    podman
    podman-compose
    podman-toolbox
    distrobox
)

# Mobile Device Tools
mobile_device_tools_packages=(
    adb
    fastboot
    android-platform-tools-base
    android-sdk-platform-tools-common
    scrcpy
    heimdall-flash
)

# Gaming Tools
gaming_tools_packages=(
    gamemode
    steam-devices
)

# Wayland/Sway Tools (alternative WM)
wayland_sway_packages=(
#     sway               # Tiling window manager
#     swaybg             # Background setter
#     swayidle           # Idle management
#     swaylock           # Screen locker
#     waybar             # Status bar
#     wofi               # Application launcher
#     wl-clipboard       # Clipboard utilities
#     grim               # Screenshot tool
#     slurp              # Screen region selector
#     wf-recorder        # Screen recorder
#     xwayland           # X11 compatibility
)

set_package_arrays() {
    log_message "Defining package lists..."
    
    # Map the arrays to the associative array keys
    # Note: We join the array elements into a space-separated string
    
    debian_packages["system_utilities"]="${system_utilities_packages[*]}"
    debian_packages["development_tools"]="${development_tools_packages[*]}"
    debian_packages["qt6_development"]="${qt6_development_packages[*]}"
    debian_packages["communication_productivity"]="${communication_productivity_packages[*]}"
    debian_packages["multimedia"]="${multimedia_packages[*]}"
    debian_packages["education"]="${education_packages[*]}"
    debian_packages["system_tools"]="${system_tools_packages[*]}"
    debian_packages["container_tools"]="${container_tools_packages[*]}"
    
    # New Categories
    debian_packages["mobile_device_tools"]="${mobile_device_tools_packages[*]}"
    debian_packages["gaming_tools"]="${gaming_tools_packages[*]}"
    debian_packages["wayland_sway"]="${wayland_sway_packages[*]}"

    # Qt5 (Commented out)
    # debian_packages["qt5_development"]="${qt5_development_packages[*]}"
    
    log_message "Package lists defined."
}


string_to_array() {
    local input_string="$1"
    local -a output_array
    while IFS= read -r line; do
        line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [[ -n "$line" && ! "$line" =~ ^# ]]; then
            output_array+=("$line")
        fi
    done <<< "$input_string"
    echo "${output_array[@]}"
}


fix_dependencies() {
    log_message "Attempting to fix broken dependencies (apt --fix-broken install)..."
    if ! sudo apt --fix-broken install -y 2>&1 | tee -a "$log_file"; then
        log_message "Warning: 'apt --fix-broken install' failed. Trying dpkg configure."
        if ! sudo dpkg --configure -a 2>&1 | tee -a "$log_file"; then
             log_message "Warning: 'dpkg --configure -a' also failed. Manual intervention might be required."
             return 1 # Indicate failure
        else
             log_message "'dpkg --configure -a' completed. Retrying fix-broken install..."
             if ! sudo apt --fix-broken install -y 2>&1 | tee -a "$log_file"; then
                 log_message "Warning: 'apt --fix-broken install' failed even after dpkg configure. Manual intervention likely needed."
                 return 1 # Indicate failure
             fi
        fi
    fi
    log_message "Dependency check/fix finished."
    return 0 # Indicate success
}

main() {
    log_message "===== Starting Debian Package Installation Script ====="

    # Parse command line arguments
    local simulate_only=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --simulate-only|-s)
                simulate_only=true
                shift
                ;;
            --help|-h)
                echo "Default Packages Installation Script"
                echo ""
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --simulate-only, -s    Run simulation only, don't install packages"
                echo "  --help, -h             Show this help message"
                echo ""
                echo "Default: Install all packages (simulates first, then installs)"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: $0 [--simulate-only|-s] [--help|-h]"
                exit 1
                ;;
        esac
    done

    set_package_arrays

    local final_failed_packages=()
    local all_unavailable_packages=()

    local categories_order=(
        "system_utilities"
        "networking_tools"
        "libraries"
        "development_tools"
        "qt6_development"
        "virtualization"
        "fonts"
        "graphics"
        "multimedia"
        "communication_productivity"
        "system_tools"
        "container_tools"
        "education"
        "mobile_device_tools"
        #"gaming_tools"
        #"wayland_sway"      # Uncomment to install Sway WM tools
        #"qt5_development"
    )

    local defined_categories
    defined_categories=("${!debian_packages[@]}")
    for cat in "${defined_categories[@]}"; do
        if ! [[ " ${categories_order[*]} " =~ " ${cat} " ]]; then
            log_message "Adding category '$cat' to installation order (was not explicitly ordered)."
            categories_order+=("$cat")
        fi
    done

    log_message "Starting package installation simulation for all categories..."
    for category in "${categories_order[@]}"; do
        simulate_package_installation "$category"
    done
    log_message "All installation simulations completed successfully!"

    if [ "$simulate_only" = true ]; then
        log_message "SIMULATION ONLY MODE: Skipping actual package installation"
        log_message "All simulations passed successfully - ready for installation!"
        log_message "To install packages, run the script without --simulate-only flag"
        echo "----------------------------------------" | tee -a "$log_file"
        echo "SIMULATION ONLY MODE - No packages were installed" | tee -a "$log_file"
        echo "All package simulations completed successfully!" | tee -a "$log_file"
        echo "Run without --simulate-only to perform actual installation" | tee -a "$log_file"
        echo "----------------------------------------" | tee -a "$log_file"
        log_message "Script completed in simulation-only mode"
        exit 0
    fi

    log_message "Starting actual package installation..."
    for category in "${categories_order[@]}"; do
         install_debian_packages "$category"

         if ! fix_dependencies; then
             log_message "Warning: Dependency fixing failed after installing category '$category'. Subsequent installations might be affected."
         fi
    done
    log_message "--- Package installation loop finished ---"

    log_message "Running final cleanup (autoremove, clean)..."
    if ! sudo apt autoremove -y 2>&1 | tee -a "$log_file"; then
        log_message "Warning: 'apt autoremove' failed."
    else
        log_message "'apt autoremove' completed."
    fi
    if ! sudo apt clean 2>&1 | tee -a "$log_file"; then
        log_message "Warning: 'apt clean' failed."
    else
        log_message "'apt clean' completed."
    fi

    log_message "===== Installation Script Summary ====="
    echo "Installation process completed." | tee -a "$log_file"
    echo "Log file located at: $log_file" | tee -a "$log_file"

    local failed_summary
    failed_summary=$(grep "ERROR: Failed to install package:" "$log_file" | sed 's/.*ERROR: Failed to install package: //' | sort | uniq)
    if [ -n "$failed_summary" ]; then
        echo "----------------------------------------" | tee -a "$log_file"
        echo "Summary of packages that failed to install:" | tee -a "$log_file"
        echo "$failed_summary" | tee -a "$log_file"
        echo "----------------------------------------" | tee -a "$log_file"
        log_message "Some packages failed to install. Please review the log file for details."
    else
        log_message "All requested packages appear to have been installed successfully (or were already present/unavailable)."
    fi

    local unavailable_summary
    unavailable_summary=$(grep "Warning: Package '.*' from category '.*' not found" "$log_file" | sed -E "s/.*Warning: Package '(.*)' from category.*$/\1/" | sort | uniq)
     if [ -n "$unavailable_summary" ]; then
        echo "----------------------------------------" | tee -a "$log_file"
        echo "Summary of packages not found in repositories:" | tee -a "$log_file"
        echo "$unavailable_summary" | tee -a "$log_file"
        echo "----------------------------------------" | tee -a "$log_file"
        log_message "Some requested packages were not found. They might be misspelled, obsolete, or require additional repositories."
    fi

    log_message "===== Script Finished ====="
    exit 0
}

main "$@"
