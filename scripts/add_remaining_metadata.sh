#!/usr/bin/env bash
# Add metadata to remaining scripts based on actual filesystem

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$SCRIPT_DIR" || exit 1

add_metadata() {
    local script="$1"
    local category="$2"
    local name="$3"
    local type="$4"
    
    if [ ! -f "$script" ]; then
        echo "  ⚠️  $script not found"
        return
    fi
    
    if grep -q "DEBIAN_TOOLS_CATEGORY" "$script"; then
        echo "  ✓ $script (already has metadata)"
        return
    fi
    
    sed -i "2a\\
\\
# DEBIAN_TOOLS_CATEGORY: $category\\
# DEBIAN_TOOLS_NAME: $name\\
# DEBIAN_TOOLS_TYPE: $type" "$script"
    
    echo "  ✅ Added: $script"
}

echo "═══ AI Editors ═══"
add_metadata "ai-editors/antigravity.sh" "Editors" "Antigravity AI" "InstallUninstall"

echo -e "\n═══ Android ═══"
add_metadata "android/android_flash.sh" "Android" "Android Flash Tool" "Interactive"
add_metadata "android/android_pixel_root.sh" "Android" "Pixel Root" "Interactive"
add_metadata "android/android_wifi_puller.sh" "Android" "WiFi Password Puller" "Configure"

echo -e "\n═══ Browsers ═══"
add_metadata "browsers/floorp.sh" "Browsers" "Floorp Browser" "InstallUninstall"

echo -e "\n═══ Desktop ═══"
add_metadata "desktop/sddm_kwallet_pam.sh" "Desktop" "SDDM KWallet PAM" "Configure"

echo -e "\n═══ Development ═══"
add_metadata "development/container_tools.sh" "Development" "Container Tools" "InstallUninstall"
add_metadata "development/rust_dev.sh" "Development" "Rust Development" "Configure"
add_metadata "development/unityhub.sh" "Development" "Unity Hub" "InstallUninstall"
add_metadata "development/vscodium.sh" "Development" "VSCodium" "InstallUninstall"

echo -e "\n═══ Security ═══"
add_metadata "security/git_config.sh" "Security" "Git Config" "BackupRestore"
add_metadata "security/kwallet_backup.sh" "Security" "KWallet Backup" "BackupRestore"

echo -e "\n═══ System ═══"
add_metadata "system/add_to_sudoers.sh" "System" "Add to Sudoers" "Configure"
add_metadata "system/bashrc_configs.sh" "System" "Bashrc Configs" "BackupRestore"
add_metadata "system/change_os_id.sh" "System" "Change OS ID" "Configure"
add_metadata "system/grub_config.sh" "System" "GRUB Config" "Configure"
add_metadata "system/profile_manager.sh" "System" "Profile Manager" "Interactive"
add_metadata "system/systemd_resolved_config.sh" "System" "Systemd Resolved" "Configure"
add_metadata "system/unstable_repo.sh" "System" "Unstable Repo" "Configure"
add_metadata "system/user_groups.sh" "System" "User Groups" "Configure"
add_metadata "system/xanmod.sh" "System" "XanMod Kernel" "InstallUninstall"

echo -e "\n═══ Virtualization ═══"
add_metadata "virtualization/qemu_kvm.sh" "Virtualization" "QEMU/KVM" "InstallUninstall"
add_metadata "virtualization/waydroid.sh" "Virtualization" "Waydroid" "InstallUninstall"

echo -e "\n═══ VPN ═══"
add_metadata "vpn/airvpn-eddie-ui.sh" "VPN" "AirVPN Eddie" "InstallUninstall"

echo -e "\n✅ Done adding metadata to all remaining scripts!"
