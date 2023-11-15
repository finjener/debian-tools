#!/usr/bin/env bash
# Bulk add metadata headers to all debian-tools scripts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Function to add metadata if not present
add_metadata() {
    local script="$1"
    local category="$2"
    local name="$3"
    local type="$4"
    
    # Check if metadata already exists
    if grep -q "DEBIAN_TOOLS_CATEGORY" "$script"; then
        echo "  ✓ $script (already has metadata)"
        return
    fi
    
    # Add metadata after shebang (line 2)
    sed -i "2a\\
\\
# DEBIAN_TOOLS_CATEGORY: $category\\
# DEBIAN_TOOLS_NAME: $name\\
# DEBIAN_TOOLS_TYPE: $type" "$script"
    
    echo "  ✓ Added metadata to $script"
}

echo "Adding metadata to Security scripts..."
add_metadata "security/ssh_keys.sh" "Security" "SSH Keys" "BackupRestore"
add_metadata "security/gpg_keys.sh" "Security" "GPG Keys" "BackupRestore"
add_metadata "security/firewall.sh" "Security" "Firewall" "Configure"

echo -e "\nAdding metadata to Desktop scripts..."
add_metadata "desktop/kde_settings.sh" "Desktop" "KDE Settings" "BackupRestore"
add_metadata "desktop/konsole_profiles.sh" "Desktop" "Konsole Profiles" "BackupRestore"

echo -e "\nAdding metadata to Packages scripts..."
add_metadata "packages/default_packages.sh" "Packages" "Default Packages" "PackageManager"
add_metadata "packages/deb_packages.sh" "Packages" "DEB Packages" "PackageManager"
add_metadata "packages/flatpak_packages.sh" "Packages" "Flatpak Packages" "PackageManager"

echo -e "\nAdding metadata to System scripts..."
add_metadata "system/sources_list_contrib_nonfree.sh" "System" "APT Sources (contrib/non-free)" "Configure"
add_metadata "system/reduce_swappiness.sh" "System" "Reduce Swappiness" "Configure"
add_metadata "system/setup_backports.sh" "System" "Setup Backports" "Configure"

echo -e "\nAdding metadata to VPN scripts..."
add_metadata "vpn/mullvad.sh" "VPN" "Mullvad VPN" "InstallUninstall"
add_metadata "vpn/ivpn.sh" "VPN" "IVPN" "InstallUninstall"
add_metadata "vpn/nym_vpn.sh" "VPN" "Nym VPN" "InstallUninstall"

echo -e "\nAdding metadata to Browser scripts..."
add_metadata "browsers/brave-browser.sh" "Browsers" "Brave Browser" "InstallUninstall"
add_metadata "browsers/firefox.sh" "Browsers" "Firefox" "InstallUninstall"
add_metadata "browsers/google-chrome.sh" "Browsers" "Google Chrome" "InstallUninstall"
add_metadata "browsers/librewolf.sh" "Browsers" "LibreWolf" "InstallUninstall"
add_metadata "browsers/microsoft-edge.sh" "Browsers" "Microsoft Edge" "InstallUninstall"
add_metadata "browsers/tor-browser.sh" "Browsers" "Tor Browser" "InstallUninstall"
add_metadata "browsers/vivaldi.sh" "Browsers" "Vivaldi" "InstallUninstall"

echo -e "\nAdding metadata to AI Editors scripts..."
add_metadata "ai-editors/cursor.sh" "Editors" "Cursor" "InstallUninstall"
add_metadata "ai-editors/windsurf.sh" "Editors" "Windsurf" "InstallUninstall"
add_metadata "ai-editors/zed.sh" "Editors" "Zed" "InstallUninstall"

echo -e "\nAdding metadata to Development scripts..."
add_metadata "development/docker.sh" "Development" "Docker" "InstallUninstall"
add_metadata "development/nodejs.sh" "Development" "Node.js" "InstallUninstall"
add_metadata "development/rust.sh" "Development" "Rust" "InstallUninstall"
add_metadata "development/go.sh" "Development" "Go" "InstallUninstall"
add_metadata "development/python.sh" "Development" "Python Dev Tools" "InstallUninstall"

echo -e "\nAdding metadata to Virtualization scripts..."
add_metadata "virtualization/virtualbox.sh" "Virtualization" "VirtualBox" "InstallUninstall"
add_metadata "virtualization/qemu.sh" "Virtualization" "QEMU" "InstallUninstall"

echo -e "\nAdding metadata to Android scripts..."
add_metadata "android/adb.sh" "Android" "Android Debug Bridge" "InstallUninstall"
add_metadata "android/scrcpy.sh" "Android" "scrcpy" "InstallUninstall"

echo -e "\nAdding metadata to Communication scripts..."
add_metadata "communication/discord.sh" "Communication" "Discord" "InstallUninstall"
add_metadata "communication/signal.sh" "Communication" "Signal" "InstallUninstall"
add_metadata "communication/telegram.sh" "Communication" "Telegram" "InstallUninstall"
add_metadata "communication/slack.sh" "Communication" "Slack" "InstallUninstall"

echo -e "\nAdding metadata to Gaming scripts..."
add_metadata "gaming/steam.sh" "Gaming" "Steam" "InstallUninstall"
add_metadata "gaming/lutris.sh" "Gaming" "Lutris" "InstallUninstall"

echo -e "\n✅ Done! All scripts have metadata headers."
