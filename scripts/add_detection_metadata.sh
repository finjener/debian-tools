#!/usr/bin/env bash
# Add detection metadata to all scripts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$SCRIPT_DIR" || exit 1

add_detect() {
    local script="$1"
    local method="$2"
    local value="$3"
    
    if [ ! -f "$script" ]; then
        echo "  ⚠️  $script not found"
        return
    fi
    
    if grep -q "DEBIAN_TOOLS_DETECT" "$script"; then
        echo "  ✓ $script (already has detection)"
        return
    fi
    
    # Add after TYPE line
    sed -i "/DEBIAN_TOOLS_TYPE/a # DEBIAN_TOOLS_DETECT_${method}: ${value}" "$script"
    echo "  ✅ Added: $script → ${method}: ${value}"
}

echo "════════════════════════════════════════════"
echo "Adding Detection Metadata to All Scripts"
echo "════════════════════════════════════════════"

echo -e "\n🔐 VPN"
add_detect "vpn/mullvad.sh" "PACKAGE" "mullvad-vpn"
add_detect "vpn/ivpn.sh" "PACKAGE" "ivpn"
add_detect "vpn/airvpn-eddie-ui.sh" "PACKAGE" "eddie-ui"
add_detect "vpn/nym_vpn.sh" "PACKAGE" "nym-vpn-app"

echo -e "\n🌐 Browsers"
add_detect "browsers/brave-browser.sh" "COMMAND" "brave-browser --version"
add_detect "browsers/librewolf.sh" "PACKAGE" "librewolf"
add_detect "browsers/floorp.sh" "COMMAND" "floorp --version"

echo -e "\n✏️ AI Editors"
add_detect "ai-editors/cursor.sh" "PATH" "/usr/bin/cursor"
add_detect "ai-editors/windsurf.sh" "PATH" "/usr/bin/windsurf"
add_detect "ai-editors/antigravity.sh" "PATH" "/usr/bin/antigravity"

echo -e "\n🎮 Gaming"
add_detect "gaming/steam.sh" "PACKAGE" "steam-launcher"

echo -e "\n💬 Communication"
add_detect "communication/signal.sh" "PACKAGE" "signal-desktop"

echo -e "\n📱 Virtualization"
add_detect "virtualization/qemu_kvm.sh" "PACKAGE" "qemu-system-x86"
add_detect "virtualization/waydroid.sh" "PACKAGE" "waydroid"

echo -e "\n💻 Development"
add_detect "development/vscodium.sh" "PACKAGE" "codium"
add_detect "development/unityhub.sh" "PATH" "/opt/unityhub/unityhub"
add_detect "development/container_tools.sh" "COMMAND" "podman --version"
add_detect "development/rust_dev.sh" "COMMAND" "rustc --version"

echo -e "\n⚙️ System"
add_detect "system/xanmod.sh" "PACKAGE" "linux-xanmod"
add_detect "system/sddm_kwallet_pam.sh" "PACKAGE" "libpam-kwallet5"
# Configuration scripts - no detection needed (always show neutral)
# grub_config, unstable_repo, sources_list_contrib_nonfree, etc.

echo -e "\n🖥️ Desktop"
add_detect "desktop/sddm_kwallet_pam.sh" "PACKAGE" "libpam-kwallet5"

echo -e "\n🤖 Android"
# Interactive tools - no install state

echo -e "\n🔒 Security"
# Backup/restore scripts - no install state

echo -e "\n📦 Packages"
# Package manager scripts - no install state

echo -e "\n✅ Done! Detection metadata added to applicable scripts."
echo "Scripts without detection (backup/config/interactive) will show neutral status."
