#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/arch-setup.log"
mkdir -p "$(dirname "$LOG_FILE")"
(
    umask 077
    mkdir -p "$(dirname "$LOG_FILE")"
)
exec > >(tee -a "$LOG_FILE") 2>&1

main() {
    check_user
    welcome_message
    mount_external_home

    # -- Installations ------------
    install_rustup
    install_and_setup_paru
    install_packages
    install_flatpaks

    # -- Fixes --------------------
    fix_brightness_nvidia
    fix_fn_keys_lofree
    fix_touchpad

    # -- Optimizations ------------
    optimize_base_boot_params
    optimize_mkinitcpio_hooks
    optimize_bootloader_timeout

    # --Configurations ------------
    configure_default_shell
    configure_uki_preset
    configure_dotfiles
    configure_daemons
    configure_firewall

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
    local LINE_1="    ____               __        ___            __      __                    "
    local LINE_2="   / __/_______  _____/ /_      /   |  ________/ /___  / /   ( )___  __  ___  __"
    local LINE_3="  / /_/ ___/ _ \/ ___/ __ \    / /| | / ___/ ___/ __ \/ /   / / __ \/ / / / |/_/"
    local LINE_4=" / __/ /  /  __(__  ) / / /   / ___ |/ /  / /__/ / / / /___/ / / / / /_/ />  <  "
    local LINE_5="/_/ /_/   \___/____/_/ /_/   /_/  |_/_/   \___/_/ /_/_____/_/_/ /_/\__,_/_/|_|  "
    clear
    printf "\033[38;2;94;189;230m%s\033[0m\n" "$LINE_1"
    printf "\033[38;2;23;147;209m%s\033[0m\n" "$LINE_2"
    printf "\033[38;2;18;122;173m%s\033[0m\n" "$LINE_3"
    printf "\033[38;2;14;95;135m%s\033[0m\n" "$LINE_4"
    printf "\033[38;2;9;66;94m%s\033[0m\n" "$LINE_5"
    echo -e "\nUser: ${YELLOW}$USER${NC}\n"

    echo -e "${BLUE}=== ACTION PLAN ===${NC}"
    echo " 1. Load configuration"
    echo " 2. Setup Rustup & Paru"
    echo " 3. Install packages"
    echo " 4. Configure Early KMS, Nvidia params & NetworkManager"
    echo " 5. Change default shell to zsh"
    echo " 6. Setup dotfiles"
    echo " 7. Enable Daemons (UFW, Pipewire)"
    echo " 8. Clean up"
    echo -e "${BLUE}===================${NC}\n"

    echo -e "${RED}Press ENTER to start the setup, or Ctrl+C to abort...${NC}"
    read -r
    echo -e "\n${GREEN}Here we go! Buckle up...${NC}\n"
}

_log_info() { echo -e "${BLUE}\n[INFO]${NC} $*"; }
_log_ok() { echo -e "${GREEN}\n[OK]${NC} $*"; }
_log_warn() { echo -e "${YELLOW}\n[WARN]${NC} $*"; }
_log_error() { echo -e "${RED}\n[ERROR]${NC} $*"; }

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
        sudo chown -R "$USER":"$USER" /home/"$USER"
        sudo chmod 700 /home/"$USER"
    fi
    _log_ok "Home drive ready."
}

install_rustup() {
    if ! command -v rustup &>/dev/null; then
        _log_info "Installing Rustup..."
        sudo pacman -S --needed --noconfirm rustup
        rustup default stable
        _log_ok "Rustup installed and default toolchain set to stable."
    else
        _log_info "Rustup already installed - skipping."
    fi
}

install_and_setup_paru() {
    if ! command -v paru &>/dev/null; then
        sudo pacman -Syu --needed --noconfirm git base-devel
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
    _log_info "Installing [$label]..."
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

fix_brightness_nvidia() {
    _log_info "Configuring Native Hybrid Early KMS and boot parameters..."
    local config_file="/etc/mkinitcpio.conf"
    local required_modules=("amdgpu" "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm")
    local current_modules

    current_modules=$(grep -oP '^MODULES=\(\K[^)]*' "$config_file")
    for mod in "${required_modules[@]}"; do
        if ! echo "$current_modules" | grep -qw "$mod"; then
            current_modules="$current_modules $mod"
        fi
    done

    current_modules=$(echo "$current_modules" | tr -s ' ' | sed 's/^ //;s/ $//')
    sudo sed -i -E "s|^MODULES=\(.*\)|MODULES=($current_modules)|" "$config_file"
    _log_ok "Updated MODULES in $config_file to: ($current_modules)"

    local params=(
        acpi_backlight=native
        video.brightness_switch_enabled=0
        amdgpu.dcfeaturemask=0x8
        amdgpu.abmlevel=0
        nvidia-drm.modeset=1
        nvidia-drm.fbdev=1
        i2c_hid.polling_mode=1
    )

    _add_kernel_params "${params[@]}"
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

    local current_cmdline
    current_cmdline=$(cat "$cmdline_file")
    local new_cmdline="$current_cmdline"

    for param in "${params[@]}"; do
        local key="${param%%=*}"
        local escaped_key
        escaped_key=$(printf '%s\n' "$key" | sed 's/[][\.*^$+?{}|()]/\\&/g')
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
        nowatchdog        # turns off watchdog (+battery life)
        amd_pstate=active # newer energy management ryzen driver (+battery life)
    )
    _log_info "Configuring base boot parameters (performance, power)..."
    _add_kernel_params "${params[*]}"
}

optimize_mkinitcpio_hooks() {
    local config_file="/etc/mkinitcpio.conf"
    local current_hooks

    current_hooks=$(grep -oP '^HOOKS=\(\K[^)]*' "$config_file")

    if echo "$current_hooks" | grep -qw "udev"; then
        current_hooks=$(echo "$current_hooks" | sed -e 's/\budev\b/systemd/' -e 's/\bkeymap\b/sd-vconsole/' -e 's/\bconsolefont\b//' | tr -s ' ' | sed 's/ $//')

        sudo sed -i -E "s|^HOOKS=\(.*\)|HOOKS=($current_hooks)|" "$config_file"
        _log_ok "Updated HOOKS to: ($current_hooks)"

        _log_info "Rebuilding initramfs..."
        sudo mkinitcpio -P
    else
        _log_ok "systemd hook already present in $config_file."
    fi
}

optimize_bootloader_timeout() {
    local loader_file="/boot/loader/loader.conf"

    if [ ! -f "$loader_file" ]; then
        _log_error "File $loader_file not found. Systemd-boot not detected."
        return 1
    fi

    if grep -q "^timeout" "$loader_file"; then
        sudo sed -i -E "s/^timeout.*/timeout 0/" "$loader_file"
    else
        echo "timeout 0" | sudo tee -a "$loader_file" >/dev/null
    fi

    _log_ok "Bootloader timeout set to 0 in $loader_file."
}

# -- Configuration -----------------------------------------------------------

configure_default_shell() {
    local zsh_path
    zsh_path=$(command -v zsh)
    if [ "$SHELL" != "$zsh_path" ]; then
        _log_info "Changing default shell to zsh for $USER..."
        if [ -n "$zsh_path" ]; then
            sudo chsh -s "$zsh_path" "$USER"
            _log_ok "Default shell changed to zsh."
        else
            _log_warn "Zsh is not installed. Skipping shell change."
        fi
    else
        _log_info "Zsh is already the default shell."
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
        _log_info "Dotfiles directory already exists. Pulling latest changes..."
        git -C ~/.files pull || _log_warn "Failed to pull latest dotfiles updates."
    fi

    cd ~/.files || {
        _log_error "Cannot enter ~/.files"
        return 1
    }
    chmod +x ./install.sh
    ./install.sh
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
        ufw.service            # firewall
        NetworkManager.service # do i need this?
        bluetooth.service      # do i need this?
        cups.socket            # for printing
        avahi-daemon.socket    # for printing
        pcscd.socket           # for YubiKey support
    )

    local sys_mask=(
        getty@tty1.service                 # tty1 is managed by ly dm
        systemd-tpm2-setup-early.service   # encryption support
        systemd-tpm2-setup.service         # encryption support
        watchdog.service                   # for battery saving
        wpa_supplicant.service             # default nm backend is iwd
        NetworkManager-wait-online.service # don't wait for wifi connect on startup
    )

    local usr_enable=(
        psd.service             # profile-sync-daemon (puts browser profile to RAM)
        pipewire.service        # audio
        pipewire-pulse.service  # audio
        hyprpolkitagent.service # for password popups
        rclone-sync.timer       # my own cloud sync daemon
    )

    local usr_mask=(
        at-spi-dbus-bus.service
    )

    _log_info "Enabling system daemons..."

    sudo systemctl disable "${sys_disable[@]}"
    sudo systemctl enable "${sys_enable[@]}"
    sudo systemctl mask "${sys_mask[@]}"

    systemctl --user enable "${usr_enable[@]}"
    systemctl --user mask "${usr_mask[@]}"

    _log_ok "Daemons enabled."
}

configure_firewall() {
    _log_info "Configuring firewall"
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw --force enable
    _log_ok "Firewall configured properly"
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

finished_message() {
    echo ""
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN} INSTALLATION COMPLETED SUCCESSFULLY!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Logs saved to: $LOG_FILE"
    echo "System is primed for Hyprland login. Enjoy the speed."
    echo "Restart is necessary for the installation to finish."
    echo ""
}

main
