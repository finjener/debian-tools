----------this readme outdated and previous commits merged into one initial commit because of the dramatical updates--------------

# Debian Tools

A collection of scripts for setting up and configuring Debian-based systems with modern tools and applications.

## Project Structure

```
scripts/
├── android/
│   ├── android_flash.sh         # Android device flashing tool
│   └── android_wifi_puller.sh   # WiFi configuration backup from Android
├── browsers/
│   ├── brave-browser.sh         # Brave browser installation
│   └── librewolf.sh             # LibreWolf browser installation
├── communication/
│   └── signal.sh                # Signal messenger installation
├── development/
│   ├── unityhub.sh              # Unity Hub installation
│   └── vscodium.sh              # VSCodium installation
├── packages/
│   ├── deb_packages.sh          # Custom .deb package installation
│   ├── default_packages.sh      # Default system packages
│   └── flatpak_packages.sh      # Flatpak applications
├── system/
│   ├── add_to_sudoers.sh        # Add user to sudoers
│   ├── bashrc_configs.sh        # Bash configuration
│   ├── change_os_id.sh          # Change OS identification
│   ├── grub_config.sh           # GRUB bootloader configuration
│   ├── sources_list_contrib_nonfree.sh  # Repository setup
│   └── systemd_resolved_config.sh      # DNS resolver configuration
├── virtualization/
│   ├── qemu_kvm.sh              # QEMU/KVM virtualization setup
│   └── waydroid.sh              # Waydroid Android container
└── vpn/
    ├── airvpn-eddie-ui.sh       # AirVPN Eddie UI client
    ├── ivpn.sh                  # IVPN client
    ├── mullvad.sh               # Mullvad VPN
    └── protonvpn-gui.sh         # ProtonVPN GUI client
```

## Usage

Run any script directly from the project directory:

```bash
# Install default packages with simulation support
./scripts/packages/default_packages.sh --simulate-only

# Install browsers
./scripts/browsers/brave-browser.sh
./scripts/browsers/librewolf.sh

# Install development tools
./scripts/development/vscodium.sh
./scripts/development/unityhub.sh

# Install VPN clients
./scripts/vpn/mullvad.sh
./scripts/vpn/protonvpn-gui.sh

# System configuration
./scripts/system/sources_list_contrib_nonfree.sh
./scripts/system/bashrc_configs.sh
```

## Features

- **Package Management**: Install system packages, browsers, and applications
- **Development Tools**: Unity Hub, VSCodium, and Windsurf editor
- **VPN Support**: Multiple VPN providers (Mullvad, ProtonVPN, IVPN, AirVPN)
- **Android Tools**: Device flashing and WiFi configuration backup
- **System Configuration**: GRUB, bashrc, sudo, and DNS configuration
- **Virtualization**: QEMU/KVM and Waydroid setup

## Requirements

- Debian-based system (Debian, Ubuntu, etc.)
- Internet connection
- User with sudo privileges

## Notes

- Scripts include logging to `logs/` directories
- Some scripts support simulation mode (`--simulate-only`)
- Check individual script help for specific options
- All scripts are designed for modern Debian systems

