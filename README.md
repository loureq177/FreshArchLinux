# FreshArchLinux

A Bash script to set up a fresh Arch Linux environment with essential applications and configurations.

## Features

- Mount and configure external 512GB home drive
- Systemd-boot timeout configuration
- Pacman configuration (Color, multilib)
- Yay AUR helper installation
- Remove unwanted packages (epiphany, gnome-calendar, etc.)
- Install essential applications (via `packages.txt`)
- NVIDIA Early KMS and brightness configuration
- LazyVim setup
- Firewall setup (UFW with KDE Connect/LocalSend rules)
- Lofree keyboard Function keys fix
- Zen Browser as default browser
- Dotfiles management with stow
- GNOME environment setup (theme, fonts, keyboard, clock)
- Audio configuration (microphone volume)
- System cleanup and orphan removal

## Prerequisites

- Run as a **regular user** (not root) — the script will prompt for `sudo` when needed
- `git` and `base-devel` must be available (used to bootstrap `yay`)

## Configuration

Before running the script, review and edit the `config` file:

```
UUID="..."              # UUID of your external home drive (check with: lsblk -f)
LOG_FILE="/tmp/arch-setup.log"
LOADER_CONF="/boot/loader/loader.conf"
BOOT_TIMEOUT=0          # systemd-boot menu timeout in seconds
MICROPHONE_VOLUME=0.3   # microphone volume (0.0 – 1.0)
```

> **Important:** The `UUID` is specific to the author's machine. You must replace it with the UUID of your own drive before running the script.

You can also customize the package lists:

- `packages.txt` — packages to install via `yay` (one per line)
- `unwanted_packages.txt` — packages to remove via `pacman` (one per line)

## Usage

```bash
bash fresh_archlinux.sh
```

The script will display the loaded configuration and wait for confirmation before proceeding.
Logs are saved to the path set in `LOG_FILE` (default: `/tmp/arch-setup.log`).

## Notes

- **Dotfiles:** `setup_dotfiles` clones `https://github.com/loureq176/dotfiles.git` into `~/.files` and applies it via `stow`. Replace the URL in the script if you want to use your own dotfiles repo.
