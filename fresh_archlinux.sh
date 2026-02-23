#! /usr/bin/env bash
set -euo pipefail

# =====================[ USER CHECK ]===================== #
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

# =====================[ COLORS & LOGGING ]===================== #
RED='\033[0;31m'
GREEN='\032[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

LOG_FILE="/tmp/arch-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log_info() {
    echo -e "${BLUE}[INFO]${NC}  $*"
    sleep 2
}
log_ok() {
    echo -e "${GREEN}[OK]${NC}    $*"
    sleep 2
}
log_warn() {
    echo -e "${YELLOW}[WARN]${NC}  $*"
    sleep 2
}
log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
    sleep 2
}

log_info "Running setup for user: $USER"
log_info "Home directory: $HOME"

# =====================[ MOUNTING EXTERNAL HOME ]===================== #
log_info "Configuring 512 GB drive..."
UUID="688f55cd-90c1-4766-b4f9-5e1a812fe16a"
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

# =====================[ SYSTEMD-BOOT TIMEOUT ]===================== #
LOADER_CONF="/boot/loader/loader.conf"
if [ -f "$LOADER_CONF" ]; then
    if grep -q "^timeout" "$LOADER_CONF"; then
        sudo sed -i 's/^timeout.*/timeout 0/' "$LOADER_CONF"
        log_ok "Updated timeout to 0 in $LOADER_CONF"
    else
        echo "timeout 0" >>"$LOADER_CONF"
        log_ok "Added timeout 0 to $LOADER_CONF"
    fi
else
    log_error "Error: Could not find $LOADER_CONF. Is systemd-boot installed?"
fi

# =====================[ GNOME CONFIGURATION ]===================== #
log_info "Configuring GNOME environment..."
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || log_warn "GTK theme failed"
gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
gsettings set org.gnome.desktop.interface accent-color "blue"
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || log_warn "Color scheme failed"
gsettings set org.gnome.desktop.interface font-name 'Adwaita Sans 12'
gsettings set org.gnome.desktop.interface document-font-name 'Adwaita Sans 12'
gsettings set org.gnome.desktop.interface show-battery-percentage true
gsettings set org.gnome.desktop.interface text-scaling-factor 1
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
log_ok "GNOME settings applied."

# =====================[ AUDIO ]===================== #
log_info "Setting microphone volume..."
wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 0.3 && log_ok "Microphone set to 30%" || log_warn "Could not set volume"

# =====================[ YAY SETUP ]===================== #
if ! command -v yay &>/dev/null; then
    sudo pacman -Syu --needed git base-devel
    cd /tmp
    git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    makepkg -si --noconfirm
    yay -Syu --devel
    yay -Y --devel --save
    cd /
    rm -rf /tmp/yay-bin
    log_ok "yay installed."
else
    log_info "yay already installed - skipping."
fi

# =====================[ PACMAN CONFIG ]===================== #
log_info "Configuring pacman.conf..."
sudo sed -i 's/^#Color$/Color/' /etc/pacman.conf
sudo sed -i '/^#\[multilib\]/,/^#Include = .*mirrorlist/ s/^#//' /etc/pacman.conf
log_ok "Pacman configured (Color, multilib)."

# =====================[ UPDATE ]===================== #
log_info "Upgrading system packages..."
sudo pacman -Syu --noconfirm
log_ok "System packages upgraded."

# =====================[ REMOVE PACKAGES ]===================== #
log_info "Removing unnecessary applications and dependencies..."
for pkg in epiphany gnome-calendar gnome-weather gnome-console gnome-contacts gnome-connections gnome-maps gnome-tour gnome-shell-extensions gnome-system-monitor gnome-software htop nano orca; do
    if pacman -Qs "^${pkg}$" &>/dev/null; then
        sudo pacman -Rs --noconfirm "$pkg" 2>/dev/null || true
    fi
done
log_ok "Unnecessary applications removed."

# =====================[ INSTALL PACKAGES ]===================== #
yay -Syu --noconfirm --needed \
    amd-ucode \
    asciiquarium \
    bat \
    btop \
    ca-certificates \
    cbonsai \
    cmatrix \
    code \
    discord \
    docker \
    extension-manager \
    eza \
    fastfetch \
    fd \
    flatpak \
    fzf \
    gcc \
    gnome-shell-extensions \
    gnome-tweaks \
    github-cli \
    git-lfs \
    lazygit \
    localsend \
    man-db \
    neovim \
    obsidian \
    ollama \
    opencode \
    pinta \
    prusa-slicer \
    python-pip \
    python-virtualenv \
    rclone \
    rclone-browser \
    ripgrep \
    ruff \
    sox \
    stacer \
    starship \
    stow \
    tldr \
    tmux \
    traceroute \
    tree-sitter \
    tree-sitter-cli \
    ttf-jetbrains-mono-nerd \
    ufw \
    uv \
    valent \
    wl-clipboard \
    yazi \
    zen-browser-bin \
    zoxide \
    zsh \
    zsh-autosuggestions \
    zsh-syntax-highlighting || true
log_ok "Essential applications installed."

# =====================[ REMOVE ORPHANS ]=================== #
yay -R --noconfirm "$(pacman -Qdtq)"

# =====================[ FIX BRIGHTNESS ]=================== #
sed -i -E '/^options/ {
  s/ *(acpi_backlight|nvidia\.NVreg_PreserveVideoMemoryAllocations)=[^ ]*//g
  s/$/ acpi_backlight=nvidia_wmi_ec nvidia.NVreg_PreserveVideoMemoryAllocations=1/
}' /boot/loader/entries/*.conf

# =====================[ LAZYVIM SETUP ]===================== #
log_info "Setting up LazyVim..."
if [ ! -d "$HOME/.config/nvim" ]; then
    git clone https://github.com/LazyVim/starter ~/.config/nvim
    rm -rf ~/.config/nvim/.git
    log_ok "LazyVim installed."
else
    log_info "LazyVim already exists — skipping."
fi

# =====================[ BROWSER & SHELL SETUP ]===================== #
log_info "Setting Zen Browser as default..."
if command -v zen &>/dev/null || command -v zen-browser &>/dev/null; then
    xdg-settings set default-web-browser app.zen_browser.zen.desktop 2>/dev/null || log_warn "Could not set Zen Browser as default"
    log_ok "Zen Browser set as default."
else
    log_warn "Zen Browser not installed — skipping."
fi

# =====================[ FIREWALL ]===================== #
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

# =====================[ FIX LOFREE KEYBOARD ]===================== #
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

# =====================[ SET ZSH AS DEFAULT ]===================== #
log_info "Setting ZSH as default shell..."
if [ "$SHELL" != "$(which zsh)" ]; then
    sudo chsh -s "$(which zsh)" "$USER"
    log_ok "Shell changed to ZSH. It will take effect after logout/login."
else
    log_info "ZSH is already your default shell."
fi

# =====================[ DOTFILES SETUP ]===================== #
log_info "Downloading and linking dotfiles..."
git clone https://github.com/TwojNick/dotfiles.git ~/.files
cd ~/.files
stow */
log_ok "Dotfiles installed."

# =====================[ CLEANUP ]===================== #
log_info "Cleaning up..."
sudo pacman -Scc --noconfirm
log_ok "System cleanup complete."

# =====================[ FINISH ]===================== #
echo ""
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} INSTALLATION COMPLETED SUCCESSFULLY!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Logs saved to: $LOG_FILE"
echo ""
