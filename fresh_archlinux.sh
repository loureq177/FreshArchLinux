#!/usr/bin/env bash

set -euo pipefail
source config

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

exec > >(tee -a "$LOG_FILE") 2>&1

main() {
    check_user
    welcome_message
    mount_external_home
    set_microphone_volume
    install_rustup
    install_and_setup_paru
    install_packages
    configure_firewall
    fix_brightness_nvidia
    fix_keyboard_lofree
    configure_base_boot_params
    set_systemd_boot_sleep
    change_shell
    configure_environment
    configure_uki_preset
    setup_dotfiles
    enable_daemons
    configure_lid_switch
    cleanup
    finished_message
}

check_user() {
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}[ERROR] Please run as normal user (DO NOT USE SUDO to start script)${NC}"
        exit 1
    fi
    sudo -v
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" || exit
    done 2>/dev/null &
}

LINE_1="    ____                __        ___            __      __                    "
LINE_2="   / __/_______  _____/ /_      /   |  ________/ /___  / /   ( )___  __  ___  __"
LINE_3="  / /_/ ___/ _ \/ ___/ __ \    / /| | / ___/ ___/ __ \/ /   / / __ \/ / / / |/_/"
LINE_4=" / __/ /  /  __(__  ) / / /   / ___ |/ /  / /__/ / / / /___/ / / / / /_/ />  <  "
LINE_5="/_/ /_/   \___/____/_/ /_/   /_/  |_/_/   \___/_/ /_/_____/_/_/ /_/\__,_/_/|_|  "

welcome_message() {
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
    echo " 5. Tweak systemd-boot timeout"
    echo " 6. Change default shell to zsh"
    echo " 7. Setup dotfiles & Bat Cache"
    echo " 8. Enable Daemons (UFW, Pipewire)"
    echo " 9. Clean up"
    echo -e "${BLUE}===================${NC}\n"

    echo -e "${RED}Press ENTER to start the setup, or Ctrl+C to abort...${NC}"
    read -r
    echo -e "\n${GREEN}Here we go! Buckle up...${NC}\n"
}

_log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
_log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
_log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
_log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

mount_external_home() {
    _log_info "Configuring external drive with UUID: $UUID"

    if ! blkid -U "$UUID" >/dev/null; then
        _log_warn "Drive with UUID $UUID not found. Skipping mount."
        return 0
    fi

    if ! grep -q "$UUID" /etc/fstab; then
        if ! grep -q "^[^#]*[[:space:]]/home[[:space:]]" /etc/fstab; then
            echo "UUID=$UUID /home ext4 defaults 0 2" | sudo tee -a /etc/fstab >/dev/null
            _log_ok "Added $UUID to /etc/fstab"
        else
            _log_warn "/home is already defined in /etc/fstab by another device. Skipping."
            return 0
        fi
    fi

    sudo mount -a
    if [ "$(stat -c '%U' /home/"$USER" 2>/dev/null)" != "$USER" ]; then
        sudo chown -R "$USER":"$USER" /home/"$USER"
        sudo chmod 700 /home/"$USER"
    fi
    _log_ok "Home drive ready."
}

set_microphone_volume() {
    _log_info "Setting microphone volume..."
    wpctl set-volume @DEFAULT_AUDIO_SOURCE@ $MICROPHONE_VOLUME && _log_ok "Microphone set to 30%" || _log_warn "Could not set volume"
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
    _log_info "Installing essential applications..."
    if [ -f "packages.txt" ]; then
        grep -v '^#' packages.txt | xargs paru -S --noconfirm --needed
        _log_ok "Essential applications installed."
    else
        _log_warn "packages.txt not found. Skipping installation."
    fi
}

_add_kernel_params() {
    local params="$*"
    local cmdline_file="/etc/kernel/cmdline"

    if [ ! -f "$cmdline_file" ]; then
        _log_error "$cmdline_file does not exist!"
        return 1
    fi

    _log_info "Adding boot parameters: $params"
    sleep 2

    local current_cmdline
    current_cmdline=$(cat "$cmdline_file")
    local new_cmdline="$current_cmdline"

    for param in $params; do
        local key="${param%%=*}"
        new_cmdline=$(echo "$new_cmdline" | sed -E "s/ *$key(=[^ ]+)?//g")
    done

    echo "$new_cmdline $params" | tr -s ' ' | sudo tee "$cmdline_file" >/dev/null
    _log_ok "Updated parameters in: $cmdline_file"
}

fix_brightness_nvidia() {
    _log_info "Configuring Native Hybrid Early KMS and boot parameters..."
    local config_file="/etc/mkinitcpio.conf"
    local required_modules=("amdgpu" "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm")
    local current_modules

    current_modules=$(grep -E "^MODULES=\(" "$config_file" | sed -E 's/MODULES=\((.*)\)/\1/')

    for mod in "${required_modules[@]}"; do
        if [[ ! " $current_modules " =~ " $mod " ]]; then
            current_modules="$current_modules $mod"
        fi
    done

    current_modules=$(echo "$current_modules" | tr -s ' ' | sed 's/^ //;s/ $//')
    sudo sed -i -E "s|^MODULES=\(.*\)|MODULES=($current_modules)|" "$config_file"
    _log_ok "Updated MODULES in $config_file to: ($current_modules)"

    _add_kernel_params "acpi_backlight=nvidia_wmi_ec amdgpu.dcfeaturemask=0x8 amdgpu.abmlevel=0 nvidia-drm.modeset=1 nvidia-drm.fbdev=1"

    _log_info "Rebuilding initramfs..."
    sudo mkinitcpio -P
    _log_ok "Initramfs rebuilt successfully."
}

fix_keyboard_lofree() {
    _log_info "Fixing Lofree keyboard (Function keys)..."
    if [ -d "/sys/module/hid_apple" ]; then
        echo 2 | sudo tee /sys/module/hid_apple/parameters/fnmode >/dev/null
        _log_ok "hid_apple fnmode set to 2 (runtime)"
    else
        _log_warn "hid_apple module not loaded. Is the keyboard connected?"
    fi
    _add_kernel_params "hid_apple.fnmode=2"
}

configure_base_boot_params() {
    _log_info "Configuring base boot parameters (performance, power, debug)..."
    _add_kernel_params "zswap.enabled=0 mem_sleep_default=deep quiet loglevel=3 nowatchdog vsyscall=emulate amd_pstate=active pcie_aspm=force"
}

set_systemd_boot_sleep() {
    local loader_conf="/boot/loader/loader.conf"
    _log_info "Configuring systemd-boot timeout..."

    if sudo test -f "$loader_conf"; then
        if sudo grep -q "^timeout" "$loader_conf"; then
            sudo sed -i "s/^timeout.*/timeout 0/" "$loader_conf"
        else
            echo "timeout 0" | sudo tee -a "$loader_conf" >/dev/null
        fi
        _log_ok "Updated timeout to 0s in $loader_conf"
    else
        _log_warn "Could not find $loader_conf. Is systemd-boot installed?"
    fi
}

configure_firewall() {
    _log_info "Configuring firewall"
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw --force enable
    _log_ok "Firewall configured properly"
}

change_shell() {
    if [ "$SHELL" != "/usr/bin/zsh" ]; then
        _log_info "Changing default shell to zsh for $USER..."
        if command -v zsh &>/dev/null; then
            sudo chsh -s "$(which zsh)" "$USER"
            _log_ok "Default shell changed to zsh."
        else
            _log_warn "Zsh is not installed. Skipping shell change."
        fi
    else
        _log_info "Zsh is already the default shell."
    fi
}

configure_environment() {
    _log_info "Configuring global environment variables for Nvidia on Wayland..."
    local env_file="/etc/environment"
    local vars=(
        "GBM_BACKEND=nvidia-drm"
        "__GLX_VENDOR_LIBRARY_NAME=nvidia"
        "LIBVA_DRIVER_NAME=nvidia"
        "WLR_NO_HARDWARE_CURSORS=1"
    )

    for var in "${vars[@]}"; do
        if ! grep -q "^$var" "$env_file"; then
            echo "$var" | sudo tee -a "$env_file" >/dev/null
        fi
    done
    _log_ok "Environment variables injected to $env_file"
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

setup_dotfiles() {
    _log_info "Downloading and linking dotfiles..."
    if [ ! -d "$HOME/.files" ]; then
        git clone https://github.com/loureq176/dotfiles.git ~/.files
    else
        _log_info "Dotfiles directory already exists. Pulling latest changes..."
        git -C ~/.files pull || _log_warn "Failed to pull latest dotfiles updates."
    fi

    cd ~/.files || exit
    chmod +x ./install.sh
    ./install.sh
    _log_ok "Dotfiles installed."

    if command -v bat &>/dev/null; then
        _log_info "Building bat cache for custom themes..."
        bat cache --build >/dev/null 2>&1 || _log_warn "Failed to build bat cache."
        _log_ok "Bat cache rebuilt."
    fi
}

enable_daemons() {
    _log_info "Enabling system daemons..."
    sudo systemctl enable --now ufw.service podman.socket NetworkManager.service
    sudo systemctl enable ly.service
    systemctl --user enable --now psd.service pipewire.service pipewire-pulse.service
    _log_ok "Daemons enabled."
}

configure_lid_switch() {
    _log_info "Configuring lid switch behavior..."
    sudo sed -i 's/^.*HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
    sudo systemctl restart systemd-logind
    _log_ok "Lid switch configured."
}

cleanup() {
    _log_info "Cleaning up..."
    sudo pacman -Scc --noconfirm
    _log_ok "System cleanup complete."

    ORPHANS=$(pacman -Qdtq || true)
    if [ -n "$ORPHANS" ]; then
        paru -Rns --noconfirm $ORPHANS
        _log_ok "Orphans removed."
    else
        _log_info "No orphan packages to remove."
    fi
    sudo journalctl --vacuum-time=2weeks
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

main "$@"
