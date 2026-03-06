#! /usr/bin/env bash
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
    configure_pacman
    setup_yay
    remove_unwanted_packages
    install_packages
    fix_brightness_nvidia
    lazyvim_setup
    setup_firewall
    fix_keyboard_lofree
    setup_browser
    setup_dotfiles
    configure_gnome
    setup_ssh
    setup_automatic_timezone
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

welcome_message() {
    clear
    printf "\033[38;2;94;189;230m%s\033[0m\n" "    ____               __       ___             __    __    _                  "
    printf "\033[38;2;23;147;209m%s\033[0m\n" "   / __/_______  _____/ /_     /   |  ________/ /_  / /   (_)___  __  ___  __"
    printf "\033[38;2;18;122;173m%s\033[0m\n" "  / /_/ ___/ _ \/ ___/ __ \   / /| | / ___/ ___/ __ \/ /   / / __ \/ / / / |/_/"
    printf "\033[38;2;14;95;135m%s\033[0m\n" " / __/ /  /  __(__  ) / / /  / ___ |/ /  / /__/ / / / /___/ / / / / /_/ />  <  "
    printf "\033[38;2;9;66;94m%s\033[0m\n" "/_/ /_/   \___/____/_/ /_/  /_/  |_/_/   \___/_/ /_/_____/_/_/ /_/\__,_/_/|_|  "

    echo -e "\nUser: ${YELLOW}$USER${NC}\n"
    echo -e "${BLUE}=== ACTION PLAN ===${NC}"
    echo " 1. Load configuration"
    echo " 2. Mount external /home drive"
    echo " 3. Tweak systemd-boot & mic volume"
    echo " 4. Setup pacman & install YAY"
    echo " 5. Install system packages"
    echo " 6. Configure Nvidia boot params"
    echo " 7. Enable UFW firewall rules"
    echo " 8. Setup LazyVim & Zen Browser"
    echo " 9. Download & link dotfiles"
    echo "10. Tweak GNOME (themes, fonts)"
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
    echo -e "${GREEN}[OK]${GREEN}    $*"
}
log_warn() {
    echo -e "${YELLOW}[WARN]${YELLOW}  $*"
}
log_error() {
    echo -e "${RED}[ERROR]${RED} $*"
}

mount_external_home() {
    log_info "Configuring 512 GB drive..."
    if ! grep -q "$UUID" /etc/fstab; then
        if ! grep -q "^[^#]*[[:space:]]/home[[:space:]]" /etc/fstab; then
            echo "UUID=$UUID /home ext4 defaults 0 2" | sudo tee -a /etc/fstab >/dev/null
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

setup_yay() {
    if ! command -v yay &>/dev/null; then
        sudo pacman -Syu --needed git base-devel
        (
            cd /tmp
            git clone https://aur.archlinux.org/yay-bin.git
            cd yay-bin
            makepkg -si --noconfirm
        )
        yay -Syu --devel
        yay -Y --devel --save
        rm -rf /tmp/yay-bin
        log_ok "yay installed."
    else
        log_info "yay already installed - skipping."
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

        yay -S --noconfirm --needed rustup
        rustup default stable
        yay -S --noconfirm --needed $(cat packages.txt)
        log_ok "Essential applications installed."
    else
        log_warn "packages.txt not found. Skipping installation."
    fi
}

fix_brightness_nvidia() {
    log_info "Configuring Nvidia Early KMS and boot parameters..."

    sudo sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    log_ok "Added Nvidia modules to /etc/mkinitcpio.conf"

    local conf_file
    conf_file=$(ls -1 /boot/loader/entries/*.conf 2>/dev/null | head -1)

    if [ -n "$conf_file" ]; then
        sudo sed -i -E '/^options/ {
            s/ *(acpi_backlight|nvidia\.NVreg_PreserveVideoMemoryAllocations|nvidia-drm\.modeset|nvidia-drm\.fbdev)=[^ ]*//g
            s/$/ acpi_backlight=nvidia_wmi_ec nvidia.NVreg_PreserveVideoMemoryAllocations=1 nvidia-drm.modeset=1 nvidia-drm.fbdev=1/
        }' "$conf_file"
        log_ok "Nvidia boot parameters added to $conf_file"
    else
        log_warn "Could not find systemd-boot entries in /boot/loader/entries/"
    fi

    log_info "Rebuilding initramfs (this might take a moment)..."
    if sudo mkinitcpio -P >/dev/null; then
        log_ok "Initramfs rebuilt successfully."
    else
        log_error "Failed to rebuild initramfs!"
    fi
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

setup_firewall() {
    log_info "Configuring firewall"
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow 1714:1764/tcp comment 'KDE Connect / Valent TCP'
    sudo ufw allow 1714:1764/udp comment 'KDE Connect / Valent UDP'
    sudo ufw allow 53317/tcp comment 'LocalSend TCP'
    sudo ufw allow 53317/udp comment 'LocalSend UDP'
    sudo ufw --force enable
    sudo systemctl enable --now ufw
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
    if ! grep -q "hid_apple.fnmode=2" /boot/loader/entries/*.conf 2>/dev/null; then
        CONF_FILE=$(ls -1 /boot/loader/entries/*.conf 2>/dev/null | head -1)
        if [ -n "$CONF_FILE" ]; then
            if ! grep -q "hid_apple.fnmode=2" "$CONF_FILE"; then
                sudo sed -i 's/options /options hid_apple.fnmode=2 /' "$CONF_FILE"
                log_ok "Added hid_apple.fnmode=2 to $CONF_FILE"
            fi
        else
            log_warn "Could not find systemd-boot entries in /boot/loader/entries/"
        fi
    else
        log_info "hid_apple.fnmode=2 already configured in boot entries."
    fi
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

setup_ssh() {
    sudo systemctl enable --now sshd
}

setup_automatic_timezone() {
    sudo systemctl enable --now geoclue
}

configure_gnome() {
    log_info "Configuring GNOME environment..."
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || log_warn "GTK theme failed"
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || log_warn "Color scheme failed"
    gsettings set org.gnome.desktop.interface font-name 'Adwaita Sans 12'
    gsettings set org.gnome.desktop.interface document-font-name 'Adwaita Sans 12'
    gsettings set org.gnome.desktop.interface show-battery-percentage true
    gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font Mono 12' &&
        log_ok "Default monospace font set to JetBrainsMono Nerd Font Mono." ||
        log_warn "Failed to set JetBrains Mono Nerd Font as default."
    gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
    gsettings set org.gnome.desktop.wm.preferences auto-raise true
    gsettings set org.gnome.desktop.input-sources xkb-options "['caps:escape']"
    gsettings set org.gnome.desktop.interface clock-format '24h'
    gsettings set org.gnome.desktop.peripherals.keyboard delay 200
    gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 2
    gsettings set org.gnome.system.locale region "pl_PL.UTF-8"
    gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'pl')]"
    log_ok "GNOME settings applied."
}

cleanup() {
    log_info "Cleaning up..."
    sudo pacman -Scc --noconfirm
    log_ok "System cleanup complete."
    ORPHANS=$(pacman -Qdtq || true)
    if [ -n "$ORPHANS" ]; then
        yay -Rns --noconfirm $ORPHANS
        log_ok "Orphans removed."
    else
        log_info "No orphan packages to remove."
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
    echo ""
}

main "$@"
