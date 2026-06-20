#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOGS="${XDG_CACHE_HOME:-$HOME/.cache}/arch-setup.log"
(umask 077 && mkdir -p "$(dirname "$LOGS")")
exec > >(tee -a "$LOGS") 2>&1

main() {
    check_user
    welcome_message
    mount_external_home

    # -- Installations ------------
    install_and_setup_paru
    install_packages
    install_flatpaks

    # -- Fixes --------------------
    fix_display_brightness
    fix_fn_keys_lofree
    fix_touchpad

    # -- Optimizations ------------
    optimize_base_boot_params
    optimize_nvidia_rtd3
    optimize_mkinitcpio_hooks
    optimize_mkinitcpio_compression
    optimize_bootloader_timeout

    # --Configurations ------------
    configure_default_shell
    configure_uki_preset
    configure_dotfiles
    configure_daemons
    configure_firewall
    configure_nvidia_cdi
    configure_hyprland_multigpu
    configure_progressive_webapps

    sudo mkinitcpio -P
    cleanup
    finished_message
}

check_user() {
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}[ERROR] Please run as normal user (DO NOT USE SUDO to start script)${NC}"
        exit 1
    fi
    sudo -v
    sudo_keepalive() {
        while true; do
            sudo -n true
            sleep 60
            kill -0 "$$" 2>/dev/null || exit
        done
    }
    sudo_keepalive &
    KEEPALIVE_PID=$!
    trap 'kill $KEEPALIVE_PID 2>/dev/null' EXIT
}

welcome_message() {
    L1="    ____               __        ___            __      __                    "
    L2="   / __/_______  _____/ /_      /   |  ________/ /___  / /   ( )___  __  ___  __"
    L3="  / /_/ ___/ _ \/ ___/ __ \    / /| | / ___/ ___/ __ \/ /   / / __ \/ / / / |/_/"
    L4=" / __/ /  /  __(__  ) / / /   / ___ |/ /  / /__/ / / / /___/ / / / / /_/ />  <  "
    L5="/_/ /_/   \___/____/_/ /_/   /_/  |_/_/   \___/_/ /_/_____/_/_/ /_/\__,_/_/|_|  "
    clear
    printf "\033[38;2;94;189;230m%s\033[0m\n" "$L1"
    printf "\033[38;2;23;147;209m%s\033[0m\n" "$L2"
    printf "\033[38;2;18;122;173m%s\033[0m\n" "$L3"
    printf "\033[38;2;14;95;135m%s\033[0m\n" "$L4"
    printf "\033[38;2;9;66;94m%s\033[0m\n" "$L5"
    echo -e "\nUser: ${YELLOW}$USER${NC}\n"

    echo -e "${BLUE}=== ACTION PLAN ===${NC}"
    echo " 1. Mount external home"
    echo " 2. Install:   package manager, packages, flatpaks"
    echo " 3. Fix:       touchpad, nvidia-brightness, lofree fn keys"
    echo " 4. Optimize:  boot_params, mkinitcpio_hooks, nvidia, bootloader_timeout"
    echo " 5. Configure: default shell, splash screen, dotfiles, daemons, firewall"
    echo " 6. Clean up"
    echo -e "${BLUE}===================${NC}\n"

    echo -e "${RED}Press ENTER to start the setup, or Ctrl+C to abort...${NC}"
    read -r
    echo -e "\n${GREEN}Here we go! Buckle up...${NC}\n"
}

_log_info() { echo -e "${BLUE}\n[INFO]${NC} $*"; }
_log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
_log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
_log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

mount_external_home() {
    local UUID="f49038fe-5540-46a8-82a5-40f6ed890d8d"
    _log_info "Configuring external drive with UUID: $UUID"

    if ! blkid -U "$UUID" >/dev/null; then
        _log_warn "Drive with UUID $UUID not found. Skipping mount."
        return 0
    fi

    if ! grep -q "$UUID" /etc/fstab; then
        if ! awk '$2 == "/home" {found=1; exit} END {exit !found}' /etc/fstab; then
            echo "UUID=$UUID /home ext4 defaults 0 2" | sudo tee -a /etc/fstab >/dev/null
            _log_ok "Added $UUID to /etc/fstab"
        else
            _log_warn "/home is already defined in /etc/fstab by another device. Skipping."
            return 0
        fi
    fi

    mountpoint -q /home && {
        _log_info "Home already mounted."
        return 0
    }
    if [ -d "/home/$USER" ] && [ "$(stat -c '%U' /home/"$USER" 2>/dev/null)" != "$USER" ]; then
        sudo chown -Rh "$USER":"$USER" /home/"$USER"
        sudo chmod 700 /home/"$USER"
    fi
    _log_ok "Home drive ready."
}

install_and_setup_paru() {
    if ! command -v paru &>/dev/null; then
        sudo pacman -S --needed --noconfirm git base-devel rust
        (
            cd /tmp
            git clone https://aur.archlinux.org/paru.git
            cd paru
            makepkg -si --noconfirm
        )
        rm -rf /tmp/paru
        _log_ok "paru installed."
    else
        _log_info "paru already installed - skipping."
    fi
    paru -Syu --devel --noconfirm
}

install_packages() {
    source "$SCRIPT_DIR/packages.sh"
    _log_info "Installing essential applications..."

    for label in "${PKG_GROUPS[@]}"; do
        declare -n arr="${label}_PKGS"
        _install_group "$label" "${arr[@]}"
    done
}

_install_group() {
    local label="$1"
    shift
    _log_info "Installing [$label]_PKGS..."
    paru -S --noconfirm --needed "$@" || {
        _log_error "Failed: $label"
        return 1
    }
    _log_ok "[$label] done."
}

install_flatpaks() {
    source "$SCRIPT_DIR/flatpaks.sh"
    _log_info "Configuring Flatpak and installing applications for user..."
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install --user -y --or-update flathub "${FLATPAK_APPS[@]}"
    _log_ok "Flatpaks installed for $USER."
}

# -- Fixes -------------------------------------------------------------------

fix_display_brightness() {
    _log_info "Configuring Native Hybrid parameters..."
    local params=(
        acpi_backlight=native
        video.brightness_switch_enabled=0
        amdgpu.dcfeaturemask=0x8
        amdgpu.abmlevel=0
    )
    _add_kernel_params "${params[@]}"

    sudo tee -a /etc/acpi/handler.sh >/dev/null <<'EOF'
# --- ACPI brightness (added by FreshArchLinux) ---
video/brightnessup)
    case "$2" in
        BRTUP) brightnessctl set +5% ;;
        *)     logger "BrightnessUP undefined: $2" ;;
    esac
    ;;
video/brightnessdown)
    case "$2" in
        BRTDN) brightnessctl set 5%- ;;
        *)     logger "BrightnessDOWN undefined: $2" ;;
    esac
    ;;
EOF
    _log_ok "Brightness fixed. Kernel params and ACPI brightness handlers added."
}

fix_fn_keys_lofree() {
    _log_info "Fixing Lofree function keys..."
    if [ -d "/sys/module/hid_apple" ]; then
        echo 2 | sudo tee /sys/module/hid_apple/parameters/fnmode >/dev/null
        _log_ok "hid_apple fnmode set to 2 (runtime)"
    else
        _log_warn "hid_apple module not loaded. Is the keyboard connected?"
    fi
    _add_kernel_params "hid_apple.fnmode=2"
}

fix_touchpad() {
    _log_info "Fixing Lenovo Legion touchpad (i8042 controller)..."
    _add_kernel_params "i8042.nopnp"
    _log_ok "Touchpad boot parameters applied."
}

_add_kernel_params() {
    local -a params=("$@")
    local cmdline_file="/etc/kernel/cmdline"

    if [ ! -f "$cmdline_file" ]; then
        _log_error "$cmdline_file does not exist!"
        return 1
    fi

    _log_info "Adding boot parameters: ${params[*]}"

    local new_cmdline
    new_cmdline=$(cat "$cmdline_file")

    for param in "${params[@]}"; do
        local key="${param%%=*}"
        local escaped_key
        escaped_key=$(printf '%s' "$key" | sed 's/[^[:alnum:]_]/\\&/g')
        new_cmdline=$(echo "$new_cmdline" | sed -E "s/ *${escaped_key}(=[^ ]+)?//g")
    done

    echo "$new_cmdline ${params[*]}" | tr -s ' ' | sudo tee "$cmdline_file" >/dev/null
    _log_ok "Updated parameters in: $cmdline_file"
}

# -- Optimizations ----------------------------------------------------------

optimize_base_boot_params() {
    local params=(
        mem_sleep_default=deep
        quiet
        loglevel=3
        nowatchdog
        amd_pstate=active
        console=tty1
        tpm_tis.interrupts=0
        tpm_tis.force=0
        8250.nr_uarts=0
    )
    _log_info "Configuring base boot parameters (performance, power)..."
    _add_kernel_params "${params[@]}"

    echo -e "blacklist tpm\nblacklist tpm_crb\nblacklist tpm_tis\nblacklist tpm_tis_core" | sudo tee /etc/modprobe.d/tpm-blacklist.conf >/dev/null
}

optimize_nvidia_rtd3() {
    _log_info "Configuring NVIDIA RTD3 (Dynamic Power Management)..."
    sudo rm -f /etc/modprobe.d/nvidia-blacklist.conf \
        /etc/modprobe.d/envycontrol.conf
    sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<'EOF'
options nvidia-drm modeset=1
options nvidia NVreg_DynamicPowerManagement=0x02
EOF
    sudo tee /etc/udev/rules.d/80-nvidia-pm.rules >/dev/null <<'EOF'
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="on"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="on"
EOF
    sudo udevadm control --reload-rules
    _log_ok "NVIDIA RTD3 configured."
}

optimize_mkinitcpio_hooks() {
    local config_file="/etc/mkinitcpio.conf"

    sudo sed -i -E "s|^MODULES=\(.*\)|MODULES=()|" "$config_file"

    local current_hooks
    current_hooks=$(grep -oP '^HOOKS=\(\K[^)]*' "$config_file")

    if echo "$current_hooks" | grep -qw "udev"; then
        current_hooks=$(echo "$current_hooks" |
            sed -e 's/\budev\b/systemd/' \
                -e 's/\bkeymap\b/sd-vconsole/' \
                -e 's/\bconsolefont\b//' |
            tr -s ' ' | sed 's/ $//')
    fi

    current_hooks=$(echo "$current_hooks" | sed 's/\bkms\b//' | tr -s ' ' | sed 's/^ //')

    sudo sed -i -E "s|^HOOKS=\(.*\)|HOOKS=($current_hooks)|" "$config_file"
    _log_ok "Updated HOOKS to: ($current_hooks)"
}

optimize_mkinitcpio_compression() {
    local conf="/etc/mkinitcpio.conf"
    _log_info "Optimizing initramfs size and compression..."

    sudo sed -i -e '/^COMPRESSION=/d' -e '/^COMPRESSION_OPTIONS=/d' -e '/^MODULES_DECOMPRESS=/d' "$conf"

    echo 'COMPRESSION="zstd"' | sudo tee -a "$conf" >/dev/null
    echo 'COMPRESSION_OPTIONS=(-2 -T0)' | sudo tee -a "$conf" >/dev/null
    echo 'MODULES_DECOMPRESS="no"' | sudo tee -a "$conf" >/dev/null

    _log_ok "Initramfs compression optimized (zstd, no module decompression)."
}

optimize_bootloader_timeout() {
    local loader_file="/boot/loader/loader.conf"
    if ! sudo bootctl is-installed 2>/dev/null; then
        _log_warn "systemd-boot not installed — skipping."
        return 0
    fi
    sudo mkdir -p "/boot/loader"
    if [ -f "$loader_file" ]; then
        sudo sed -i '/^timeout/d' "$loader_file"
    fi
    echo "timeout 0" | sudo tee -a "$loader_file" >/dev/null
    _log_ok "Bootloader timeout set to 0 in $loader_file."
}

# -- Configuration -----------------------------------------------------------

configure_default_shell() {
    local zsh_path="/usr/bin/zsh"
    if [ "$SHELL" != "$zsh_path" ]; then
        _log_info "Changing default shell to zsh for $USER..."
        sudo chsh -s "$zsh_path" "$USER"
        _log_ok "Default shell changed to zsh."
    fi
}

configure_uki_preset() {
    _log_info "Configuring UKI presets..."
    sudo mkdir -p /boot/EFI/Linux
    sudo tee /etc/mkinitcpio.d/linux.preset >/dev/null <<EOF
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default' 'fallback')
default_uki="/boot/EFI/Linux/arch-linux.efi"
default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"
fallback_uki="/boot/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
EOF

    _log_ok "UKI preset configured."
}

configure_dotfiles() {
    _log_info "Downloading and linking dotfiles..."
    if [ ! -d "$HOME/.files" ]; then
        git clone https://github.com/loureq177/.files.git ~/.files
    else
        _log_info "Dotfiles directory already exists."
    fi

    if [ -f ~/.files/install.sh ]; then
        chmod +x ~/.files/install.sh
        ~/.files/install.sh
    else
        _log_warn "No install.sh found in dotfiles — skipping."
    fi
    _log_ok "Dotfiles installed."
}

configure_daemons() {
    local sys_disable=(
        fwupd-refresh.timer   # for firmware updates
        fwupd-refresh.service # for firmware updates
        cups.service          # for printing
        avahi-daemon.service  # for printing
        pcscd.service         # for YubiKey support
    )

    local sys_enable=(
        ly@tty1.service
        podman.socket
        ufw.service
        NetworkManager.service
        bluetooth.service
        cups.socket         # for printing
        avahi-daemon.socket # for printing
        pcscd.socket        # for YubiKey support
        acpid.service       # for brightness to work with video.brightness_switch_enabled=0
        upower.service
    )

    local sys_mask=(
        getty@tty1.service                 # tty1 is managed by ly dm
        systemd-tpm2-setup-early.service   # encryption support
        systemd-tpm2-setup.service         # encryption support
        watchdog.service                   # for battery saving
        wpa_supplicant.service             # default nm backend is iwd
        NetworkManager-wait-online.service # don't wait for wifi connect on startup
        systemd-pcrproduct.service         # TPM2 PCR measurement
        systemd-pcrphase-sysinit.service   # TPM2
        systemd-pcrphase-initrd.service    # TPM2
        systemd-pcrphase.service           # TPM2
        nvidia-persistenced.service
    )

    local usr_enable=(
        psd.service             # profile-sync-daemon (puts browser profile to RAM)
        pipewire.service        # audio
        pipewire-pulse.service  # audio
        hyprpolkitagent.service # for password popups
        rclone-sync.timer       # my own cloud sync daemon
    )

    local usr_mask=(
        at-spi-dbus-bus.service # accessibility features
    )

    _log_info "Enabling system daemons..."

    sudo systemctl disable "${sys_disable[@]}" 2>/dev/null || true
    sudo systemctl enable "${sys_enable[@]}" 2>/dev/null || true
    sudo systemctl mask "${sys_mask[@]}" 2>/dev/null || true

    systemctl --user enable "${usr_enable[@]}" 2>/dev/null || true
    systemctl --user mask "${usr_mask[@]}" 2>/dev/null || true

    _log_ok "Daemons configured."
}

configure_firewall() {
    _log_info "Configuring firewall"
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw --force enable
    _log_ok "Firewall configured properly"
}

configure_progressive_webapps() {
    local pwa_repo="$HOME/.files/archlinux/pwa"
    local bin_dir="$pwa_repo/.local/bin"
    local desktop_dir="$pwa_repo/.local/share/applications"
    local icon_dir="$pwa_repo/.local/share/icons/hicolor/scalable/apps"

    mkdir -p "$bin_dir" "$desktop_dir" "$icon_dir"

    local profile="\$HOME/.local/share/pwa/chromium-profile"

    _log_info "Downloading 2026 app icons..."

    local -A icon_urls
    icon_urls[pwa_calendar]="https://upload.wikimedia.org/wikipedia/commons/f/fa/Google_Calendar_icon_%282026%29.svg"
    icon_urls[pwa_gmail]="https://upload.wikimedia.org/wikipedia/commons/8/8f/Gmail_icon_%282026%29.svg"
    icon_urls[pwa_tasks]="https://upload.wikimedia.org/wikipedia/commons/3/3f/Google_Tasks_Logo_05.2026.svg"

    local name
    for name in "${!icon_urls[@]}"; do
        curl -fsSL -o "$icon_dir/$name.svg" "${icon_urls[$name]}" || _log_warn "Failed to download $name icon"
    done

    local apps=(
        "Calendar|https://calendar.google.com|pwa_calendar|chrome-calendar.google.com__-Default|Network;Office;"
        "Gmail|https://mail.google.com|pwa_gmail|chrome-mail.google.com__-Default|Network;Email;"
        "WhatsApp|https://web.whatsapp.com|whatsapp-desktop|chrome-web.whatsapp.com__-Default|Network;InstantMessaging;"
        "Tasks|https://tasks.google.com|pwa_tasks|chrome-tasks.google.com__-Default|Office;Utility;"
    )

    local class bin desktop
    for app in "${apps[@]}"; do
        IFS='|' read -r name url icon wm_class categories <<<"$app"
        class="pwa-$(echo "$name" | tr '[:upper:]' '[:lower:]')"
        bin="$bin_dir/$class"
        desktop="$desktop_dir/$class.desktop"

        cat >"$bin" <<PWAEOF
#!/bin/bash
chromium --ozone-platform-hint=auto \\
  --user-data-dir="$profile" \\
  --app=$url
PWAEOF
        chmod +x "$bin"

        cat >"$desktop" <<DESKTOPEOF
[Desktop Entry]
Name=$name
Exec=$class
Icon=$icon
Terminal=false
Type=Application
StartupWMClass=$wm_class
Categories=$categories
DESKTOPEOF
    done

    _log_info "Restowing pwa package..."
    (cd "$HOME/.files/archlinux" && stow --restow --target "$HOME" pwa)

    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

    _log_ok "Progressive web apps configured (2026 icons, stow-managed)."
}

cleanup() {
    _log_info "Cleaning up..."
    if [ -x "$HOME/.local/bin/sysclean" ]; then
        "$HOME/.local/bin/sysclean"
        _log_ok "System cleanup complete."
    else
        _log_warn "sysclean not found at $HOME/.local/bin/sysclean — skipping."
    fi
}

configure_nvidia_cdi() {
    _log_info "Scheduling NVIDIA CDI generation for first boot..."
    sudo tee /etc/systemd/system/nvidia-cdi-generate.service >/dev/null <<'EOF'
[Unit]
Description=Generate NVIDIA CDI spec for container GPU passthrough
After=systemd-udev-settle.service
ConditionPathExists=!/etc/cdi/nvidia.yaml

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl enable nvidia-cdi-generate.service
    _log_ok "NVIDIA CDI service enabled (runs once on next boot)."
}

configure_hyprland_multigpu() {
    _log_info "Configuring Hyprland multi-GPU (AMD primary, NVIDIA for external)..."

    local amd_pci_id nvidia_pci_id
    amd_pci_id=$(lspci -d ::03xx | grep -i 'AMD\|ATI' | head -1 | cut -f1 -d' ')
    nvidia_pci_id=$(lspci -d ::03xx | grep -i 'NVIDIA' | head -1 | cut -f1 -d' ')

    if [ -z "$amd_pci_id" ]; then
        _log_warn "No AMD GPU detected — skipping."
        return 0
    fi

    sudo tee /etc/udev/rules.d/99-hyprland-gpus.rules >/dev/null <<EOF
KERNEL=="card*", KERNELS=="0000:$amd_pci_id", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/amd-igpu"
EOF

    if [ -n "$nvidia_pci_id" ]; then
        sudo tee -a /etc/udev/rules.d/99-hyprland-gpus.rules >/dev/null <<EOF
KERNEL=="card*", KERNELS=="0000:$nvidia_pci_id", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/nvidia-dgpu"
EOF
        _log_ok "Detected NVIDIA at PCI: $nvidia_pci_id → /dev/dri/nvidia-dgpu"
    fi

    sudo udevadm control --reload
    sudo udevadm trigger --subsystem-match=drm

    _log_ok "Detected AMD at PCI: $amd_pci_id → /dev/dri/amd-igpu"
}

finished_message() {
    echo ""
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN} INSTALLATION COMPLETED SUCCESSFULLY!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Logs saved to: $LOGS"
    echo "System is primed for Hyprland login. Enjoy the speed."
    echo "Restart is necessary for the installation to finish."
    echo ""
}

main
