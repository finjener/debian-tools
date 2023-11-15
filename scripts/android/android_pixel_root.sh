#!/bin/bash


# DEBIAN_TOOLS_CATEGORY: Android
# DEBIAN_TOOLS_NAME: Pixel Root
# DEBIAN_TOOLS_TYPE: Interactive
# Android Pixel 7 (Panther) Rooting & Maintenance Helper
# Based on user workflow for KernelSU and Factory Image updates.
# WARNING: This script performs dangerous operations.

# Source common library
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$script_dir/../utils/common.sh"

# Initialize logging
dt_init_log "android_pixel_root"

# Legacy logging functions for compatibility
log_info() { dt_info "$1"; }
log_success() { dt_success "$1"; }
log_warn() { dt_warn "$1"; }
log_error() { dt_error "$1"; }

check_tools() {
    local missing=0
    for cmd in adb fastboot; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "$cmd is not installed or not in PATH."
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        log_error "Please instal 'android-sdk-platform-tools' first."
        exit 1
    fi
}

check_device() {
    log_info "Checking for connected ADB devices..."
    local adb_devices=$(adb devices | grep -v "List" | grep "device$" | wc -l)
    
    if [ "$adb_devices" -eq 0 ]; then
        log_info "No ADB devices found. Checking Fastboot..."
        local fastboot_devices=$(fastboot devices | wc -l)
        if [ "$fastboot_devices" -eq 0 ]; then
            log_error "No Android device found via ADB or Fastboot."
            exit 1
        else
            log_info "Device found in Fastboot mode."
            return 2 # Fastboot
        fi
    else
        log_info "Device found in ADB mode."
        return 1 # ADB
    fi
}

# --------------------------------------------------------------------------------
# WORKFLOWS
# --------------------------------------------------------------------------------

# 1. Unlock Bootloader
unlock_bootloader() {
    log_warn "This will UNLOCK the bootloader."
    log_warn "ALL USER DATA WILL BE WIPED."
    read -p "Type 'UNLOCK' to confirm: " confirm
    if [ "$confirm" != "UNLOCK" ]; then
        log_info "Cancelled."
        return
    fi
    
    adb reboot bootloader 2>/dev/null
    log_info "Waiting for bootloader..."
    sleep 5
    
    log_info "Running: fastboot flashing unlock"
    fastboot flashing unlock
    
    log_info "Please confirm the unlock on the phone screen."
}

# 2. Flash Factory Image (Update)
flash_factory_image() {
    log_info "Flashing Factory Image..."
    log_info "Please ensure you have extracted the factory image zip."
    read -p "Enter path to the extracted directory (containing flash-all.sh): " image_dir
    
    if [ ! -d "$image_dir" ]; then
        log_error "Directory not found."
        return
    fi
    
    # Based on history: fastboot flash --slot all bootloader ...
    # But typically users run update scripts. History shows manual fastboot commands.
    # We will support the specific manual steps found in history if requested, or generic update.
    
    echo "Files in directory:"
    ls "$image_dir"
    
    read -p "Enter the bootloader image name (e.g., bootloader-panther...img): " bootloader_img
    read -p "Enter the radio image name (e.g., radio-panther...img): " radio_img
    read -p "Enter the update zip name (e.g., image-panther...zip): " update_zip
    
    log_info "Rebooting to bootloader..."
    adb reboot bootloader 2>/dev/null
    
    log_info "Flashing Bootloader..."
    fastboot flash --slot all bootloader "$image_dir/$bootloader_img"
    fastboot reboot bootloader
    sleep 5
    
    log_info "Flashing Radio..."
    fastboot flash --slot all radio "$image_dir/$radio_img"
    fastboot reboot bootloader
    sleep 5
    
    log_info "Updating System (-w wipes data, without -w preserves it)"
    read -p "Do you want to wipe data? (yes/NO): " wipe
    if [[ "$wipe" =~ ^[Yy]es$ ]]; then
        fastboot -w update "$image_dir/$update_zip"
    else
        fastboot update "$image_dir/$update_zip"
    fi
}

# 3. Root with KernelSU
root_kernelsu() {
    log_info "Rooting with KernelSU..."
    read -p "Enter path to patched init_boot image (kernelsu_patched_...img): " patched_img
    
    if [ ! -f "$patched_img" ]; then
        log_error "File not found: $patched_img"
        return
    fi
    
    log_info "Rebooting to bootloader..."
    adb reboot bootloader 2>/dev/null
    sleep 5
    
    log_info "Flashing init_boot..."
    fastboot flash init_boot "$patched_img"
    
    log_success "Flashed KernelSU image."
    
    read -p "Reboot now? (y/N) " reb
    if [[ "$reb" =~ ^[Yy]$ ]]; then
        fastboot reboot
    fi
}

# 4. Install APKs
install_tools() {
    log_info "Installing Helper APKs..."
    read -p "Enter directory containing APKs: " apk_dir
    
    if [ ! -d "$apk_dir" ]; then
        log_error "Directory not found."
        return
    fi
    
    local ksu_apk=$(find "$apk_dir" -name "KernelSU*.apk" | head -n 1)
    if [ -n "$ksu_apk" ]; then
        log_info "Installing KernelSU: $ksu_apk"
        adb install "$ksu_apk"
    fi
}

# --------------------------------------------------------------------------------
# MAIN MENU
# --------------------------------------------------------------------------------

show_menu() {
    echo "----------------------------------------"
    echo "  Android Pixel 7 Rooting/Helper Tool   "
    echo "----------------------------------------"
    echo "1. Verify Device Connection"
    echo "2. Unlock Bootloader (Wipes Data!)"
    echo "3. Flash Factory Image (Manual Mode)"
    echo "4. Flash KernelSU (Root)"
    echo "5. Install Tools (KernelSU APK)"
    echo "q. Quit"
    echo "----------------------------------------"
}

main() {
    check_tools
    
    while true; do
        show_menu
        read -p "Select option: " opt
        case $opt in
            1) check_device ;;
            2) unlock_bootloader ;;
            3) flash_factory_image ;;
            4) root_kernelsu ;;
            5) install_tools ;;
            q) exit 0 ;;
            *) echo "Invalid option" ;;
        esac
        echo
        read -p "Press Enter to continue..."
    done
}

main "$@"
