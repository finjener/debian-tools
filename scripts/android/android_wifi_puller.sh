#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Android
# DEBIAN_TOOLS_NAME: WiFi Password Puller
# DEBIAN_TOOLS_TYPE: Configure
# Android WiFi Configuration Puller
# Pulls WiFi configuration files from an Android device

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "android_wifi_puller"

# Backup directory (use centralized backups)
backup_dir=$(dt_backup_path "android_wifi")
backup_folder="$backup_dir/wifi_backup_${DT_TIMESTAMP}"

WIFI_FILES=(
    "/data/misc/wifi/wpa_supplicant.conf"
    "/data/misc/wifi/WifiConfigStore.xml"
    "/data/misc/wifi/softap.conf"
    "/data/vendor/wifi/wpa/wpa_supplicant.conf"
    "/data/vendor/wifi/WifiConfigStore.xml"
    "/data/vendor/wifi/wpa_supplicant/wpa_supplicant.conf"
    "/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml"
    "/data/misc/apexdata/com.android.wifi/WifiConfigStoreSoftAp.xml"
    "/data/wifi/wpa_supplicant.conf"
    "/data/wpa_supplicant.conf"
    "/data/misc/wifi/wpa.conf"
    "/data/misc/wifi/p2p_supplicant.conf"
    "/data/misc/wifi/hostapd.conf"
    "/data/vendor/wifi/hostapd/hostapd.conf"
    "/data/misc/wifi/wigig_supplicant.conf"
    "/data/misc/wifi/wigig_p2p_supplicant.conf"
    "/data/misc/wifi/wigig_hostapd.conf"
)

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

    if ! command -v adb &>/dev/null; then
        exit_with_error "ADB is not installed or not in PATH. Please install Android platform tools."
    fi

    available_space=$(df -BM . | awk 'NR==2 {print $4}' | sed 's/M//')
    if [ "$available_space" -lt 100 ]; then
        log_message "Warning: Less than 100MB of free space available ($available_space MB)"
        read -p "Continue anyway? [y/N]: " continue_anyway
        [[ "$continue_anyway" != [yY] ]] && exit_with_error "Aborted due to insufficient disk space"
    fi
}

check_device_connection() {
    log_message "Checking device connection..."

    local devices
    devices=$(adb devices | grep -v "List" | grep -v "^$")
    if [ -z "$devices" ]; then
        exit_with_error "No Android device found. Please connect a device and enable USB debugging."
    fi

    if [ "$(echo "$devices" | wc -l)" -gt 1 ]; then
        exit_with_error "Multiple devices found. Please connect only one device."
    fi

    if ! echo "$devices" | grep -q "device$"; then
        exit_with_error "Device is not authorized. Please check USB debugging settings and authorize the connection."
    fi
}

check_root_access() {
    log_message "Checking root access on device..."

    if adb root 2>&1 | tee -a "$DT_LOG_FILE"; then
        sleep 2
        adb wait-for-device
        log_message "Successfully switched to root with 'adb root'"
        return 0
    fi

    if adb shell "su -c whoami" 2>/dev/null | grep -q "root"; then
        log_message "Root access available through 'su'"
        return 0
    fi

    if adb shell "whoami" 2>/dev/null | grep -q "root"; then
        log_message "Already running as root in shell"
        return 0
    fi

    log_message "Warning: Root access not available or not properly configured"
    read -p "Continue anyway? This might result in incomplete data. [y/N]: " continue_anyway
    [[ "$continue_anyway" != [yY] ]] && exit_with_error "Root access required but not available"
}

backup_existing_files() {
    if [ -d "$backup_folder" ]; then
        local backup_count=1
        while [ -d "${backup_folder}_${backup_count}" ]; do
            ((backup_count++))
        done
        backup_folder="${backup_folder}_${backup_count}"
    fi

    mkdir -p "$backup_folder"
    log_message "Created backup directory: $backup_folder"
}

try_pull_file() {
    local source_file="$1"
    local target_file="$2"
    local filename=$(basename "$source_file")
    local temp_path="/sdcard/temp_wifi_backup_${timestamp}"

    if adb pull "$source_file" "$target_file" 2>&1 | tee -a "$DT_LOG_FILE"; then
        return 0
    fi

    if adb shell "cp '$source_file' '$temp_path' 2>/dev/null"; then
        if adb shell "chmod 644 '$temp_path' 2>/dev/null" && \
           adb pull "$temp_path" "$target_file" 2>&1 | tee -a "$DT_LOG_FILE"; then
            adb shell "rm '$temp_path'" 2>&1 | tee -a "$DT_LOG_FILE"
            return 0
        fi
        adb shell "rm '$temp_path'" 2>&1 | tee -a "$DT_LOG_FILE"
    fi

    if adb shell "su -c 'cp \"$source_file\" \"$temp_path\"'" 2>&1 | tee -a "$DT_LOG_FILE"; then
        if adb shell "su -c 'chmod 644 \"$temp_path\"'" 2>&1 | tee -a "$DT_LOG_FILE" && \
           adb pull "$temp_path" "$target_file" 2>&1 | tee -a "$DT_LOG_FILE"; then
            adb shell "su -c 'rm \"$temp_path\"'" 2>&1 | tee -a "$DT_LOG_FILE"
            return 0
        fi
        adb shell "su -c 'rm \"$temp_path\"'" 2>&1 | tee -a "$DT_LOG_FILE"
    fi

    if adb shell "su -c 'cat \"$source_file\"'" > "$target_file" 2>&1 | tee -a "$DT_LOG_FILE"; then
        if [ -s "$target_file" ]; then
            return 0
        fi
    fi

    return 1
}

pull_wifi_files() {
    log_message "Pulling WiFi configuration files..."
    local success_count=0
    local total_files=${#WIFI_FILES[@]}

    local existing_files=()

    log_message "Searching for WiFi configuration files..."
    adb shell "find /data -name '*wifi*' -type d 2>/dev/null" | while read dir; do
        log_message "Checking directory: $dir"
        adb shell "ls -la $dir 2>/dev/null" 2>&1 | tee -a "$DT_LOG_FILE"
    done

    for file in "${WIFI_FILES[@]}"; do
        log_message "Checking for file: $file"
        if adb shell "[ -f '$file' ]" 2>/dev/null; then
            existing_files+=("$file")
            log_message "Found existing file: $file"
            adb shell "ls -l '$file'" 2>&1 | tee -a "$DT_LOG_FILE"
        else
            log_message "File not found: $file"
        fi
    done

    if [ ${#existing_files[@]} -eq 0 ]; then
        exit_with_error "No WiFi configuration files found on device"
    fi

    for file in "${existing_files[@]}"; do
        local filename=$(basename "$file")
        local target="$backup_folder/$filename"

        log_message "Attempting to pull $file..."
        if try_pull_file "$file" "$target"; then
            ((success_count++))
            log_message "Successfully pulled $filename"
            chmod 600 "$target"
        else
            log_message "Warning: Failed to pull $filename"
        fi
    done

    if [ "$success_count" -eq 0 ]; then
        exit_with_error "Failed to pull any WiFi configuration files"
    fi

    log_message "Successfully pulled $success_count out of ${#existing_files[@]} files"

    local -r max_backups=5
    local backup_count
    backup_count=$(ls -1d "$backup_dir/wifi_backup_"* 2>/dev/null | wc -l)

    if [ "$backup_count" -gt "$max_backups" ]; then
        log_message "Removing old backups..."
        ls -1td "$backup_dir/wifi_backup_"* | tail -n +$((max_backups + 1)) | xargs rm -rf
    fi
}

verify_pulled_files() {
    log_message "Verifying pulled files..."
    local verified_count=0

    for file in "$backup_folder"/*; do
        if [ -f "$file" ] && [ -s "$file" ]; then
            ((verified_count++))

            if grep -q "<?xml" "$file" 2>/dev/null || \
               grep -q "network=" "$file" 2>/dev/null || \
               grep -q "ctrl_interface=" "$file" 2>/dev/null; then
                log_message "Verified $(basename "$file") appears to be valid"
            else
                log_message "Warning: $(basename "$file") might be corrupted or empty"
            fi

            if [ "$(stat -c %a "$file")" != "600" ]; then
                chmod 600 "$file"
                log_message "Fixed permissions for $(basename "$file")"
            fi
        fi
    done

    log_message "Verified $verified_count files"
}

display_usage() {
    echo "Android WiFi Configuration Puller"
    echo "================================"
    echo "This script pulls WiFi configuration files from an Android device."
    echo ""
    echo "Requirements:"
    echo "  - Android platform tools (adb)"
    echo "  - Connected Android device with USB debugging enabled"
    echo "  - Root access on the device (for complete data)"
    echo ""
    echo "The following files will be attempted to be pulled:"
    printf '%s\n' "${WIFI_FILES[@]}" | sed 's/^/  - /'
    echo ""
    echo "Files will be saved in: $backup_dir"
}

main() {
    log_message "Starting Android WiFi puller script..."

    display_usage

    check_system_requirements
    check_device_connection
    check_root_access

    backup_existing_files

    pull_wifi_files
    verify_pulled_files

    log_message "WiFi configuration files have been saved in: $backup_folder"
    echo -e "\nWiFi configuration files have been saved in: $backup_folder"
    echo "Check $DT_LOG_FILE for details."
}

main "$@"
