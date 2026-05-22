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
    set_systemd_boot_sleep
    set_microphone_volume
    configure_firewall
    configure_pacman
    setup_paru
    remove_unwanted_packages
    install_packages
    fix_brightness_nvidia
    lazyvim_setup
    fix_keyboard_lofree
    configure_base_boot_params
    setup_browser
    setup_dotfiles
    enable_daemons
    configure_gtk_wayland
    configure_lid_switch
    cleanup
    finished_message
}

check_user() {
    if [ "$EUID" -eq 0 ]; then
        echo -e "\033[0;31m[ERROR] Please run as normal user (DO NOT USE SUDO to start script)"
        exit 1
    fi
    sudo -v
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" || exit
    done 2>/dev/null &
}

LINE_1="    ____                __        ___            __      __                      "
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
    echo " 2. Mount external /home drive"
    echo " 3. Tweak systemd-boot & mic volume"
    echo " 4. Setup pacman & install PARU"
    echo " 5. Install system packages (Hyprland workflow)"
    echo " 6. Configure Native Hybrid Early KMS"
    echo " 7. Enable UFW firewall rules"
    echo " 8. Setup LazyVim & Zen Browser"
    echo " 9. Download & link dotfiles via Stow"
    echo "10. Configure GTK/Wayland settings (gsettings)"
    echo "11. Clean up & remove orphans"
    echo -e "${BLUE}===================${NC}\n"

    echo -e "${RED}Press ENTER to start the setup, or Ctrl+C to abort...${NC}"
    read -r
    echo -e "\n${GREEN}Here we go! Buckle up...${NC}\n"
}

log_info() {
    echo -e "${BLUE}[INFO]${BLUE}  $*"
}
log_ok() {
    echo -e "${GREEN}[OK]${GREEN}     $*"
}
log_warn() {
    echo -e "${YELLOW}[WARN]${YELLOW}  $*"
}
log_error() {
    echo -e "${RED}[ERROR]${RED} $*"
}

mount_external_home() {
    log_info "Configuring external drive with UUID: $UUID"

    if ! blkid -U "$UUID" >/dev/null; then
        log_warn "Drive with UUID $UUID not found. Skipping mount."
        return 0
    fi

    if ! grep -q "$UUID" /etc/fstab; then
        if ! grep -q "^[^#]*[[:space:]]/home[[:space:]]" /etc/fstab; then
            echo "UUID=$UUID /home ext4 defaults 0 2" | sudo tee -a /etc/fstab >/dev/null
            log_ok "Added $UUID to /etc/fstab"
        else
            log_warn "/home is already defined in /etc/fstab by another device. Skipping."
            return 0
        fi
    fi

    sudo mount -a
    if [ "$(stat -c '%U' /home/"$USER" 2>/dev/null)" != "$USER" ]; then
        sudo chown -R "$USER":"$USER" /home/"$USER"
        sudo chmod 700 /home/"$USER"
    fi
    log_ok "Home drive ready."
}

set_systemd_boot_sleep() {
    if sudo test -f "$LOADER_CONF"; then
        if sudo grep -q "^timeout" "$LOADER_CONF"; then
            sudo sed -i "s/^timeout.*/timeout $BOOT_TIMEOUT/" "$LOADER_CONF"
            log_ok "Updated timeout to $BOOT_TIMEOUT in $LOADER_CONF"
        else
            echo "timeout $BOOT_TIMEOUT" | sudo tee -a "$LOADER_CONF" >/dev/null
            log_ok "Added timeout $BOOT_TIMEOUT to $LOADER_CONF"
        fi
    else
        log_error "Error: Could not find $LOADER_CONF. Is systemd-boot installed?"
    fi
}

set_microphone_volume() {
    log_info "Setting microphone volume..."
    wpctl set-volume @DEFAULT_AUDIO_SOURCE@ $MICROPHONE_VOLUME && log_ok "Microphone set to 30%" || log_warn "Could not set volume"
}

configure_pacman() {
    log_info "Configuring pacman.conf..."
    sudo sed -i 's/^#Color$/Color/' /etc/pacman.conf
    sudo sed -i '/^#\[multilib\]/,/^#Include = .*mirrorlist/ s/^#//' /etc/pacman.conf
    log_ok "Pacman configured (Color, multilib)."
}

setup_paru() {
    if ! command -v paru &>/dev/null; then
        sudo pacman -Syu --needed git base-devel
        (
            cd /tmp
            git clone https://aur.archlinux.org/paru-bin.git
            cd paru-bin
            makepkg -si --noconfirm
        )
        paru -Syu --devel
        paru -G --save
        rm -rf /tmp/paru-bin
        log_ok "paru installed."
    else
        log_info "paru already installed - skipping."
    fi
}

remove_unwanted_packages() {
    log_info "Removing unnecessary packages..."
    if [ -f "unwanted_packages.txt" ]; then
        pkgs_to_remove=$(cat unwanted_packages.txt)
        if [ -n "$pkgs_to_remove" ]; then
            sudo pacman -Rs --noconfirm $pkgs_to_remove 2>/dev/null || true
        fi
    fi
    log_ok "Unnecessary packages removed."
}

install_packages() {
    log_info "Installing essential applications..."
    if [ -f "packages.txt" ]; then
        paru -S --noconfirm --needed rustup
        rustup default stable
        grep -v '^#' packages.txt | xargs paru -S --noconfirm --needed
        log_ok "Essential applications installed."
    else
        log_warn "packages.txt not found. Skipping installation."
    fi
}

fix_brightness_nvidia() {
    log_info "Configuring Native Hybrid Early KMS and boot parameters..."

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
    log_ok "Updated MODULES in $config_file to: ($current_modules)"

    add_kernel_params "acpi_backlight=nvidia_wmi_ec amdgpu.dcfeaturemask=0x8 amdgpu.abmlevel=0 nvidia-drm.modeset=1 nvidia-drm.fbdev=1"

    log_info "Rebuilding initramfs (this might take a moment)..."
    if sudo mkinitcpio -P >/dev/null; then
        log_ok "Initramfs rebuilt successfully."
    else
        log_error "Failed to rebuild initramfs!"
    fi
}

add_kernel_params() {
    local params="$*"
    log_info "Dodawanie parametrów startowych: $params"

    if [ -f /etc/kernel/cmdline ]; then
        local current_cmdline=$(cat /etc/kernel/cmdline)
        local new_cmdline="$current_cmdline"
        for param in $params; do
            local key="${param%%=*}"
            new_cmdline=$(echo "$new_cmdline" | sed -E "s/ *$key(=[^ ]+)?//g")
        done
        echo "$new_cmdline $params" | tr -s ' ' | sudo tee /etc/kernel/cmdline >/dev/null
    else
        local current_cmdline=$(cat /proc/cmdline)
        local new_cmdline="$current_cmdline"
        for param in $params; do
            local key="${param%%=*}"
            new_cmdline=$(echo "$new_cmdline" | sed -E "s/ *$key(=[^ ]+)?//g")
        done
        echo "$new_cmdline $params" | tr -s ' ' | sudo tee /etc/kernel/cmdline >/dev/null
    fi

    local entries
    entries=$(ls /boot/loader/entries/*.conf 2>/dev/null || true)

    if [ -n "$entries" ]; then
        for conf_file in $entries; do
            local current_options
            current_options=$(sudo grep "^options" "$conf_file" || true)
            if [ -n "$current_options" ]; then
                local base_options="${current_options#options }"

                for param in $params; do
                    local key="${param%%=*}"
                    base_options=$(echo "$base_options" | sed -E "s/ *$key(=[^ ]+)?//g")
                done

                local new_options="options $base_options $params"
                new_options=$(echo "$new_options" | tr -s ' ')

                sudo sed -i -E "s|^options.*|$new_options|" "$conf_file"
                log_ok "Zaktualizowano parametry w $(basename "$conf_file")"
            fi
        done
    else
        log_warn "Brak plików .conf w /boot/loader/entries/. Parametry dodano tylko do /etc/kernel/cmdline"
    fi
}

configure_base_boot_params() {
    log_info "Konfiguracja podstawowych parametrów systemowych (wydajność, zasilanie, debug)..."
    add_kernel_params "zswap.enabled=0 mem_sleep_default=deep quiet loglevel=3 nowatchdog vsyscall=emulate"
}

lazyvim_setup() {
    log_info "Setting up LazyVim..."
    if [ ! -d "$HOME/.config/nvim" ]; then
        git clone https://github.com/LazyVim/starter ~/.config/nvim
        rm -rf ~/.config/nvim/.git
        log_ok "LazyVim installed."
    else
        log_info "LazyVim already exists — skipping."
    fi
}

configure_firewall() {
    log_info "Configuring firewall"
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow 1714:1764/tcp comment 'KDE Connect / Valent TCP'
    sudo ufw allow 1714:1764/udp comment 'KDE Connect / Valent UDP'
    sudo ufw allow 53317/tcp comment 'LocalSend TCP'
    sudo ufw allow 53317/udp comment 'LocalSend UDP'
    sudo ufw --force enable
    log_ok "Firewall configured properly"
}

fix_keyboard_lofree() {
    log_info "Fixing Lofree keyboard (Function keys)..."
    if [ -d "/sys/module/hid_apple" ]; then
        echo 2 | sudo tee /sys/module/hid_apple/parameters/fnmode >/dev/null
        log_ok "hid_apple fnmode set to 2 (runtime)"
    else
        log_warn "hid_apple module not loaded. Is the keyboard connected?"
    fi

    add_kernel_params "hid_apple.fnmode=2"
}

setup_browser() {
    log_info "Setting Zen Browser as default..."
    if command -v zen &>/dev/null || command -v zen-browser &>/dev/null; then
        if xdg-settings set default-web-browser app.zen_browser.zen.desktop 2>/dev/null; then
            log_ok "Zen Browser set as default."
        else
            log_warn "Could not set Zen Browser as default. (Desktop file might be named differently)"
        fi
    else
        log_warn "Zen Browser not installed — skipping."
    fi
}

setup_dotfiles() {
    log_info "Downloading and linking dotfiles..."
    if [ ! -d "$HOME/.files" ]; then
        git clone https://github.com/loureq176/dotfiles.git ~/.files
    else
        log_info "Dotfiles directory already exists. Pulling latest changes..."
        git -C ~/.files pull || log_warn "Failed to pull latest dotfiles updates."
    fi

    cd ~/.files
    stow */ || log_warn "Stow encountered an issue (maybe conflicts?)"
    log_ok "Dotfiles installed."
}

enable_daemons() {
    sudo systemctl enable --now sshd geoclue ufw
    systemctl --user enable --now psd wireplumber xdg-user-dirs ydotool gnome-keyring-daemon.socket p11-kit-server.socket pipewire-pulse.socket pipewire.socket
}

configure_gtk_wayland() {
    log_info "Configuring default GTK/Wayland aesthetics for standalone WM..."
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || log_warn "GTK theme failed"
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || log_warn "Color scheme failed"
    gsettings set org.gnome.desktop.interface font-name 'Adwaita Sans 12'
    gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font Mono 14'
    gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
    gsettings set org.gnome.desktop.input-sources xkb-options "['caps:escape']"
    gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'pl')]"
    gsettings set org.gnome.desktop.interface clock-format '24h'
    log_ok "GTK preferences applied via gsettings."
}

configure_lid_switch() {
    sudo sed -i 's/^.*HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
    sudo systemctl restart systemd-logind
}

cleanup() {
    log_info "Cleaning up..."
    sudo pacman -Scc --noconfirm
    log_ok "System cleanup complete."
    ORPHANS=$(pacman -Qdtq || true)
    if [ -n "$ORPHANS" ]; then
        paru -Rns --noconfirm $ORPHANS
        log_ok "Orphans removed."
    else
        log_info "No orphan packages to remove."
        sudo journalctl --vacuum-time=2weeks
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
    echo ""
}

main "$@"
