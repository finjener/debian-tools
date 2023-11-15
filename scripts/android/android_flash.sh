#!/usr/bin/env bash


# DEBIAN_TOOLS_CATEGORY: Android
# DEBIAN_TOOLS_NAME: Android Flash Tool
# DEBIAN_TOOLS_TYPE: Interactive
# Android Fastboot Flashing Script
# Helps flash Android partitions and sideload updates

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "android_flash"

REQUIRED_COMMANDS=("fastboot" "adb")
VALID_PARTITIONS=("boot" "dtbo" "vbmeta" "vendor_boot")
VALID_SLOTS=("a" "b" "general")

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

    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            exit_with_error "$cmd is not installed. Please install Android platform tools."
        fi
    done

    if ! fastboot devices | grep -q "fastboot"; then
        exit_with_error "No device found in fastboot mode. Please connect a device and put it in fastboot mode."
    fi
}

check_adb_device() {
    log_message "Checking ADB device..."

    if ! adb devices | grep -q "device$"; then
        exit_with_error "No device found in ADB mode. Please connect a device and enable USB debugging."
    fi
}

validate_file() {
    local file="$1"
    local type="$2"
    
    log_message "Validating $type file: $file"
    
    if [ ! -f "$file" ]; then
        exit_with_error "File not found: $file"
    fi
    
    if [ ! -r "$file" ]; then
        exit_with_error "File is not readable: $file"
    fi
    
    if [ "$type" = "image" ]; then
        if ! file "$file" | grep -qi "android.*bootimg\|data"; then
            log_message "Warning: File $file might not be a valid Android image file"
            read -p "Continue anyway? [y/N]: " continue_anyway
            [[ "$continue_anyway" != [yY] ]] && exit_with_error "Aborted due to invalid file type"
        fi
    fi
}

display_menu() {
    local prompt="$1"
    shift
    local options=("$@")
    local choice

    while true; do
        echo -e "\n$prompt"
        for i in "${!options[@]}"; do
            echo "$((i+1))) ${options[i]}"
        done
        read -p "Enter the number of your choice: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            return $((choice-1))
        else
            log_message "Invalid input. Please enter a number between 1 and ${#options[@]}."
        fi
    done
}

flash_partition() {
    local slot="$1"
    local part="$2"
    local image="$3"

    local valid_part=false
    for valid_partition in "${VALID_PARTITIONS[@]}"; do
        if [ "$part" = "$valid_partition" ]; then
            valid_part=true
            break
        fi
    done
    
    if [ "$valid_part" = false ]; then
        exit_with_error "Invalid partition: $part"
    fi

    local partition="${part}"
    if [ "$slot" != "general" ]; then
        partition="${part}_${slot}"
    fi

    validate_file "$image" "image"

    log_message "Flashing $partition with $image..."
    log_message "Flashing $partition with $image..."
    if ! fastboot flash "$partition" "$image" 2>&1 | tee -a "$DT_LOG_FILE"; then
        exit_with_error "Failed to flash $partition"
    fi
    
    log_message "Successfully flashed $partition"
}

flash_adb() {
    local file="$1"

    validate_file "$file" "zip"

    check_adb_device

    log_message "Flashing file $file via ADB sideload..."
    log_message "Flashing file $file via ADB sideload..."
    if ! adb -d sideload "$file" 2>&1 | tee -a "$DT_LOG_FILE"; then
        exit_with_error "Failed to flash $file via ADB sideload"
    fi
    
    log_message "Successfully flashed $file via ADB sideload"
}

display_usage() {
    echo "Android Fastboot Flashing Script"
    echo "================================"
    echo "This script helps flash Android partitions and sideload updates."
    echo ""
    echo "Requirements:"
    echo "  - Android platform tools (adb, fastboot)"
    echo "  - Device in fastboot/recovery mode"
    echo "  - Appropriate image files"
    echo ""
    echo "Supported partitions: ${VALID_PARTITIONS[*]}"
    echo "Supported slots: ${VALID_SLOTS[*]}"
}

main() {
    log_message "Starting Android flash script..."
    
    display_usage
    
    check_system_requirements

    display_menu "Choose the slot:" "Slot A" "Slot B" "General (no slot)"
    case $? in
        0) slot="a" ;;
        1) slot="b" ;;
        2) slot="general" ;;
        *) exit_with_error "Invalid slot choice" ;;
    esac

    log_message "Selected slot: ${slot^^}"

    while true; do
        display_menu "Choose the part to flash:" "${VALID_PARTITIONS[@]}" "Next"
        local choice=$?
        
        if [ "$choice" -eq ${#VALID_PARTITIONS[@]} ]; then
            log_message "Moving to next step..."
            break
        fi
        
        part="${VALID_PARTITIONS[$choice]}"
        log_message "Selected partition: $part"

        read -e -p "Enter the path to the ${part}.img file: " image_path
        flash_partition "$slot" "$part" "$image_path"
    done

    while true; do
        display_menu "Choose action:" "Flash file via ADB sideload" "Finish"
        case $? in
            0)
                read -e -p "Enter the path to the file to flash: " file_path
                flash_adb "$file_path"
                ;;
            1)
                log_message "Finishing flash process..."
                break
                ;;
        esac
    done

    log_message "Flash process completed successfully"
    echo -e "\nFlashing process completed. Check $DT_LOG_FILE for details."
}

main "$@"
