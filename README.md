# FreshArchLinux

**WARNING:** Running this on your hardware may damage your system. Review before executing.

This is my personal post-install script for Arch Linux. I use it to quickly
deploy my environment on my specific hardware.

It automates setting up Hyprland, audio, development tools, and my dotfiles.

## Features

- **Installations** Installs everything I need from the official arch repository
  and flathub (system tools, dev environment, daily apps).
- **Fixes:** Kernel parameters for Lenovo Legion touchpads, Lofree Fn keys, and
  NVIDIA/AMD hybrid brightness.
- **Optimizations** Optimizes `mkinitcpio`, sets up NVIDIA RTD3 for power
  saving, and handles NVIDIA CDI generation.
- **Configurations** Daemons, UFW firewall, UKI presets, Zsh as the default
  shell.
- **Dotfiles:** Automatically clones and installs my setup from
  [`loureq177/.files`](https://github.com/loureq177/.files).

## Usage

```bash
chmod +x fresh_archlinux.sh
./fresh_archlinux.sh
```
