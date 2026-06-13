# FreshArchLinux

A Bash script to provision a fresh Arch Linux system with Hyprland, NVIDIA/AMD hybrid GPU support, essential apps, and dotfiles.

## Features

- External home drive auto-mount via UUID
- Rustup and `paru` (AUR helper) installation
- Package groups: system, GPU (NVIDIA + AMD), fingerprint, Hyprland, audio, CLI, apps, themes
- Flatpak app installation (Zen Browser, Spotify, VS Code, Discord, LibreOffice, etc.)
- UFW firewall (deny incoming, allow outgoing)
- NVIDIA DRM early KMS + brightness fix (hybrid AMD iGPU / NVIDIA dGPU)
- Boot parameters: performance governor, deep sleep, quiet boot, AMD pstate
- Lofree keyboard Fn key fix (`hid_apple.fnmode=2`)
- Default shell change to Zsh
- Unified Kernel Image (UKI) preset configuration
- Dotfiles bootstrap from GitHub (`loureq176/dotfiles`)
- Systemd service management (ly, NetworkManager, pipewire, podman, cups, etc.)
- PAM GNOME keyring auto-unlock
- Microphone volume preset (pipewire)
- System cleanup

## Prerequisites

- Arch Linux installed (minimum base system)
- Internet connection
- `sudo` configured for your user

## Usage

```bash
chmod +x fresh_archlinux.sh
./fresh_archlinux.sh
```

Do NOT run with `sudo` — the script calls `sudo` internally as needed.

## Configuration

Edit `user.conf` to set:
- `UUID` — UUID of external drive to mount at `/home`
- `MICROPHONE_VOLUME` — initial microphone volume (0.0–1.0)

Package lists are in `packages_pacman.sh`, `packages_flatpak.sh`, and `packages_aur.sh`.
