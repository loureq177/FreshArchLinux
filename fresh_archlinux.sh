#! /usr/bin/env bash
set -euo pipefail
# TODO: check if the script is idempotent

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
GREEN='\033[0;32m'
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
# TODO: make sure that I don't override my home everytime
# (ensure that it happens only if external drive not yet mounted)
log_info "Configuring 512 GB drive..."
UUID="688f55cd-90c1-4766-b4f9-5e1a812fe16a"
if ! grep -q "$UUID" /etc/fstab; then
    sudo sed -i '/[[:space:]]\/home[[:space:]]/d' /etc/fstab
    echo "UUID=$UUID /home ext4 defaults 0 2" | sudo tee -a /etc/fstab >/dev/null
fi
sudo mount -a
if [ "$(stat -c '%U' /home/$USER 2>/dev/null)" != "$USER" ]; then
    sudo chown -R $USER:$USER /home/$USER
    sudo chmod 700 /home/$USER
fi
log_ok "Home drive ready."

# =========================[ DRIVER UPDATE ]========================= #
# TODO: How do I update drivers on archlinux?
# log_info "Updating drivers..."
# log_ok "Drivers updated check complete!"

# =====================[ JETBRAINS MONO NERD FONT ]===================== #
log_info "Installing JetBrains Mono Nerd Font..."

FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
FONT_DIR="/usr/share/fonts/JetBrainsMonoNerd"

if [ ! -d "$FONT_DIR" ]; then
    sudo mkdir -p "$FONT_DIR"
    curl -fLo /tmp/JetBrainsMono.zip "$FONT_URL" &&
        sudo unzip -qo /tmp/JetBrainsMono.zip -d "$FONT_DIR" &&
        sudo fc-cache -f -v &&
        log_ok "JetBrains Mono Nerd Font installed." ||
        log_warn "Failed to install JetBrains Mono Nerd Font."
else
    log_info "JetBrains Mono Nerd Font already installed — skipping."
fi

# =====================[ GNOME CONFIGURATION ]===================== #
log_info "Configuring GNOME environment..."
log_info "Applying GNOME preferences..."
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || log_warn "GTK theme failed"
gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
gsettings set org.gnome.desktop.interface accent-color "blue"
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || log_warn "Color scheme failed"
gsettings set org.gnome.desktop.interface font-name 'Adwaita Sans 12'
gsettings set org.gnome.desktop.interface document-font-name 'Adwaita Sans 12'
gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font Mono 12' &&
    log_ok "Default monospace font set to JetBrainsMono Nerd Font Mono." ||
    log_warn "Failed to set JetBrains Mono Nerd Font as default."
gsettings set org.gnome.desktop.interface text-scaling-factor 1
gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
gsettings set org.gnome.desktop.interface show-battery-percentage true
gsettings set org.gnome.desktop.wm.preferences auto-raise true
gsettings set org.gnome.desktop.input-sources xkb-options "['caps:escape']"
gsettings set org.gnome.desktop.interface clock-format '24h'
gsettings set org.gnome.desktop.peripherals.keyboard delay 200
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 2
# TODO: add region
# TODO: add celsius as default
log_ok "GNOME settings applied."

# =====================[ AUDIO ]===================== #
log_info "Setting microphone volume..."
wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 0.3 && log_ok "Microphone set to 30%" || log_warn "Could not set volume"

# =====================[ YAY SETUP ]===================== #
# TODO: only if not yet done
# sudo pacman -S --needed git base-devel
# git clone https://aur.archlinux.org/yay-bin.git
# cd yay-bin
# makepkg -si
# yay -Syu --devel
# yay -Y --devel --save
# rm -rf yay-bin
# cd

# =====================[ PACMAN CONFIG ]===================== #
# TODO: uncomment if not yet done
# pacman.conf uncomment # Colors
# pacman.conf uncomment # "multilib and below Include (for 32-bit steam)

# =====================[ UPDATE ]===================== #
log_info "Upgrading system packages..."
sudo pacman -Syu
log_ok "System packages upgraded."

# =====================[ REMOVE PACKAGES ]===================== #
# TODO: throws an error when no package found
log_info "Removing unnecessary applications and dependencies..."
sudo pacman -Rs --noconfirm \
    htop \
    nano \
    orca \
    gnome-calendar \
    gnome-weather \
    gnome-console \
    gnome-contacts \
    gnome-tour \
    gnome-system-monitor \
    >/dev/null
log_ok "Unnecessary applications removed."

# =====================[ INSTALL PACKAGES ]===================== #
yay --sync --noconfirm --needed \
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
    git \
    git-lfs \
    lazygit \
    man-db \
    neovim \
    obsidian \
    ollama \
    pinta \
    prusa-slicer \
    python-pip \
    python-virtualenv \
    rclone \
    rclone-browser \
    ripgrep \
    sox \
    stacer \
    stow \
    tldr \
    tmux \
    traceroute \
    tree-sitter \
    tree-sitter-cli \
    ufw \
    uv \
    wl-clipboard \
    yazi \
    zen-browser-bin \
    zoxide \
    zsh \
    zsh-autosuggestions \
    zsh-syntax-highlighting || true
log_ok "Essential applications installed."

# =====================[ GIT SETUP ]=================== #
log_info "Setting up git..."
git config --global init.defaultBranch main
CURRENT_NAME=$(git config --global --get user.name || true)
CURRENT_EMAIL=$(git config --global --get user.email || true)
if [[ -n "$CURRENT_NAME" ]] && [[ -n "$CURRENT_EMAIL" ]]; then
    log_info "Git is already configured as: $CURRENT_NAME <$CURRENT_EMAIL> — skipping setup."
else
    if [[ -z "$CURRENT_NAME" ]]; then
        read -p "Enter your nick for git config --global user.name: " username
        git config --global user.name "$username"
    fi

    if [[ -z "$CURRENT_EMAIL" ]]; then
        read -p "Enter your email for git config --global user.email: " email
        git config --global user.email "$email"
    fi

    log_ok "Git has been correctly set up."
fi

# =====================[ LAZYVIM SETUP ]===================== #
# TODO:do only if NOT .config/nvim/ exists?

# git clone https://github.com/LazyVim/start
# er ~/.config/nvim
# rm -rf ~/.config/nvim/.git

# =====================[ BROWSER & SHELL SETUP ]===================== #
# TODO: no idea how to do this on archlinux

# log_info "Setting Zen Browser as default..."
# xdg-settings set default-web-browser app.zen_browser.zen.desktop
# log_ok "Zen Browser set as default."

# =====================[ FIREWALL ]===================== #
log_info "Configuring firewall"
sudo systemctl enable --now ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
log_ok "Firewall configured properly"

# =====================[ FIX LOFREE KEYBOARD ]===================== #
# TODO: I don't use grub anymore, now on systemd-boot. how to configure?

# log_info "Fixing Lofree keyboard (Function keys)..."
# sudo modprobe hid_apple
# if [ -d "/sys/module/hid_apple/parameters" ]; then
#   echo 2 | sudo tee /sys/module/hid_apple/parameters/fnmode >/dev/null
#   log_ok "hid_apple module configured."
# else
#   log_warn "hid_apple module not found. Is the keyboard connected?"
# fi
# sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="hid_apple.fnmode=2 /' /etc/default/grub
# sudo update-grub

# =====================[ ENABLE STARSHIP PROMPT ]===================== #
STARSHIP_INIT="eval '$(starship init zsh)'"
if ! grep -qF "$STARSHIP_INIT" "$HOME/.zshrc"; then
    echo "" >>"$HOME/.zshrc"
    echo "$STARSHIP_INIT" >>"$HOME/.zshrc"
    log_ok "Added Starship init to .zshrc"
else
    log_info "Starship already configured in .zshrc — skipping."
fi

# =====================[ SET ZSH AS DEFAULT ]===================== #
log_info "Setting ZSH as default shell..."
if [ "$SHELL" != "$(which zsh)" ]; then
    sudo chsh -s "$(which zsh)" "$USER"
    log_ok "Shell changed to ZSH. It will take effect after logout/login."
else
    log_info "ZSH is already your default shell."
fi

# =====================[ CLEANUP ]===================== #
log_info "Cleaning up..."
sudo pacman -Scc
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
