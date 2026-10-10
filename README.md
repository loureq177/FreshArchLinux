# FreshArchLinux

**WARNING:** Running this on your hardware may damage your system. Review before executing.

This is my personal post-install script for Arch Linux. I use it to quickly
deploy my environment on my specific hardware.

It automates setting up Hyprland, audio, development tools, and my dotfiles.

## Features

- **Installations:** `paru`, the packages from `packages.sh`, and my dotfiles
  (which bring their own package lists and flatpaks).
- **Fixes:** Kernel parameters for Lenovo Legion touchpads, Lofree Fn keys, and
  NVIDIA/AMD hybrid brightness.
- **Optimizations:** Kernel boot parameters, a slim `mkinitcpio` and NVIDIA
  RTD3 for power saving.
- **Configurations:** Daemons, UFW firewall, UKI presets, Zsh as the default
  shell, fingerprint auth, web app launchers.
- **Dotfiles:** Clones [`loureq177/.files`](https://github.com/loureq177/.files)
  if missing and runs its installer.

## Usage

```bash
chmod +x fresh_archlinux.sh
./fresh_archlinux.sh
```
