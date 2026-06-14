# FreshArchLinux

A Bash script to provision a fresh Arch Linux system with Hyprland, NVIDIA/AMD
hybrid GPU support, essential apps, and dotfiles.

## Features

- External home drive auto-mount via UUID
- Rustup and `paru` (AUR helper) installation
- Package groups: system, GPU (NVIDIA + AMD), fingerprint, Hyprland, audio, CLI,
  apps, themes
- Flatpak app installation (Zen Browser, Spotify, VS Code, Discord, LibreOffice,
  etc.)
- UFW firewall (deny incoming, allow outgoing)
- NVIDIA DRM early KMS + brightness fix (hybrid AMD iGPU / NVIDIA dGPU)
- Boot parameters: performance governor, deep sleep, quiet boot, AMD pstate
- Lofree keyboard Fn key fix (`hid_apple.fnmode=2`)
- Default shell change to Zsh
- Unified Kernel Image (UKI) preset configuration
- Dotfiles bootstrap from GitHub (`loureq177/.files`)
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

Package lists are in `packages.sh` and `flatpaks.sh`
