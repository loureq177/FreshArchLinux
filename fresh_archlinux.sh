#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "[ERROR] Failed at line $LINENO: $BASH_COMMAND" >&2' ERR

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/packages.sh"

LOGS="/var/tmp/arch-setup.log"
exec > >(tee >(sed -u 's/\x1b\[[0-9;]*[A-Za-z]//g' >"$LOGS")) 2>&1

# Entry point orchestrating the full Arch Linux setup process.
main() {
    check_user
    welcome_message
    mount_external_home

    # -- Installations ------------
    install_and_setup_paru
    install_packages
    install_dotfiles

    # -- Fixes --------------------
    fix_display_brightness
    fix_fn_keys_lofree
    fix_touchpad

    # -- Optimizations ------------
    optimize_base_boot_params
    optimize_nvidia_rtd3
    optimize_mkinitcpio
    optimize_bootloader_timeout

    # -- Configurations -----------
    configure_default_shell
    configure_uki_preset
    configure_wifi_backend
    configure_daemons
    configure_firewall
    configure_reflector
    configure_hyprland_multigpu
    configure_progressive_webapps
    configure_tty_font
    configure_logind_lid_inhibit
    configure_fingerprint

    sudo mkinitcpio -P

    clean_dot_desktop
    cleanup
    finished_message
}

# Ensures the script runs as a regular user and keeps sudo credentials alive.
check_user() {
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}[ERROR] Please run as normal user.${NC}"
        exit 1
    fi
    sudo -v
    while sudo -n true 2>/dev/null && kill -0 "$$" 2>/dev/null; do sleep 60; done &
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
    echo " 2. Install:   paru, packages, dotfiles"
    echo " 3. Fix:       brightness, lofree fn keys, touchpad"
    echo " 4. Optimize:  boot params, nvidia rtd3, mkinitcpio, bootloader timeout"
    echo " 5. Configure: shell, UKI, wifi, daemons, firewall, reflector, multi-GPU,"
    echo "               web apps, tty font, lid switch, fingerprint"
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

# Mounts an external drive as /home if its UUID matches the expected value.
mount_external_home() {
    local UUID="${EXTERNAL_HOME_UUID:-f49038fe-5540-46a8-82a5-40f6ed890d8d}"
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

    if mountpoint -q /home; then
        _log_info "Home already mounted."
    else
        _log_info "Mounting /home..."
        sudo mount -a
        _log_ok "/home mounted."
    fi
    if [ -d "/home/$USER" ] && [ "$(stat -c '%U' /home/"$USER" 2>/dev/null)" != "$USER" ]; then
        sudo chown -Rh "$USER":"$USER" /home/"$USER"
        sudo chmod 700 /home/"$USER"
    fi
    _log_ok "Home drive ready."
}

install_and_setup_paru() {
    if ! command -v paru &>/dev/null; then
        sudo pacman -S --needed --noconfirm git base-devel rust
        rm -rf /tmp/paru
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
    _log_info "Installing all packages..."
    paru -S --noconfirm --needed "${SYSTEM_PKGS[@]}" "${GPU_PKGS[@]}" "${MISC_PKGS[@]}"
    _log_ok "All packages installed."
}

# Clones dotfiles (unless already present) and runs their installer: packages, stow, /etc files.
install_dotfiles() {
    _log_info "Installing dotfiles..."
    [ -d "$HOME/.files" ] || git clone https://github.com/loureq177/.files.git "$HOME/.files"
    bash "$HOME/.files/install.sh"
    _log_ok "Dotfiles installed."
}

# -- Fixes -------------------------------------------------------------------

fix_display_brightness() {
    _log_info "Configuring EC (nvidia_wmi_ec) backlight parameters..."
    _add_kernel_params "acpi_backlight=nvidia_wmi_ec" "amdgpu.abmlevel=0" "video.brightness_switch_enabled=0"
    _log_ok "Brightness boot parameters applied."
}

# Fixes Lofree keyboard function keys by setting hid_apple fnmode parameter.
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

# Applies udev rules to fix Lenovo Legion touchpad I2C runtime power management issues.
fix_touchpad() {
    _log_info "Fixing Lenovo Legion touchpad (I2C PM bug)..."

    sudo tee /etc/udev/rules.d/50-touchpad-pm.rules >/dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="platform", KERNEL=="AMDI0010:*", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="platform", KERNEL=="CUST0001:*", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="i2c", KERNEL=="*ELAN*", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="i2c", KERNEL=="*CUST*", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="hid", ATTRS{name}=="ELAN06FA:00", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="input", ATTRS{name}=="ELAN06FA:00*", TEST=="power/control", ATTR{power/control}="on"
EOF
    sudo udevadm control --reload-rules

    _log_ok "Touchpad PM udev rules applied."
}

# Adds or replaces kernel boot parameters in /etc/kernel/cmdline.
_add_kernel_params() {
    local -a params=("$@")
    local cmdline_file="/etc/kernel/cmdline"

    if [ ! -f "$cmdline_file" ]; then
        _log_info "Initializing $cmdline_file with root partition..."
        sudo mkdir -p "$(dirname "$cmdline_file")"
        local root_part
        root_part=$(findmnt / -o PARTUUID -n 2>/dev/null || true)
        if [ -n "$root_part" ]; then
            echo "root=PARTUUID=$root_part rw rootfstype=ext4" | sudo tee "$cmdline_file" >/dev/null
        else
            echo "rw" | sudo tee "$cmdline_file" >/dev/null
        fi
    fi

    _log_info "Adding boot parameters: ${params[*]}"

    local -a current kept=()
    local word param
    read -ra current <"$cmdline_file" || true
    for word in "${current[@]}"; do
        for param in "${params[@]}"; do
            [ "${word%%=*}" = "${param%%=*}" ] && continue 2
        done
        kept+=("$word")
    done

    echo "${kept[*]} ${params[*]}" | sudo tee "$cmdline_file" >/dev/null
    _log_ok "Updated parameters in: $cmdline_file"
}

# -- Optimizations ----------------------------------------------------------

# Configures power-saving and performance kernel boot parameters, blacklists TPM.
optimize_base_boot_params() {
    local params=(
        mem_sleep_default=deep
        quiet
        loglevel=3
        rd.systemd.show_status=false
        systemd.show_status=false
        rd.udev.log_level=3
        nowatchdog
        audit=0
        tsc=reliable
        split_lock_detect=off
        mitigations=off
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

# Enables NVIDIA RTD3 dynamic power management and DRM modesetting.
optimize_nvidia_rtd3() {
    _log_info "Configuring NVIDIA RTD3 (Dynamic Power Management)..."
    sudo rm -f /etc/modprobe.d/nvidia-blacklist.conf \
        /etc/modprobe.d/envycontrol.conf
    sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<'EOF'
options nvidia-drm modeset=1
options nvidia NVreg_DynamicPowerManagement=0x02
options nvidia NVreg_RegistryDwords="EnableBrightnessControl=0"
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF
    sudo tee /etc/udev/rules.d/80-nvidia-pm.rules >/dev/null <<'EOF'
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="on"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="on"
# Allow dGPU (and its audio function) to enter D3cold: saves ~8.5W on battery,
# dropping idle from ~17W to ~8W. The Lenovo EC firmware dims the panel on
# D3cold power cut, which is handled in userspace (quickshell SystemStatus.qml)
# by re-applying backlight (+0%) when dGPU transitions to suspended.
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", TEST=="d3cold_allowed", ATTR{d3cold_allowed}="1"
EOF

    sudo udevadm control --reload-rules
    _log_ok "NVIDIA RTD3 configured."
}

# Slims the initramfs: minimal systemd hooks, fast zstd, no module decompression.
optimize_mkinitcpio() {
    _log_info "Writing mkinitcpio drop-in (hooks, compression)..."
    sudo mkdir -p /etc/mkinitcpio.conf.d
    sudo tee /etc/mkinitcpio.conf.d/custom.conf >/dev/null <<'EOF'
MODULES=()
HOOKS=(systemd autodetect microcode modconf sd-vconsole block filesystems)
COMPRESSION="zstd"
COMPRESSION_OPTIONS=(-1 -T0)
MODULES_DECOMPRESS="no"
EOF
    _log_ok "mkinitcpio configured."
}

# Sets systemd-boot menu timeout to 0 for instant boot.
optimize_bootloader_timeout() {
    local loader_file="/boot/loader/loader.conf"
    if ! sudo bootctl is-installed 2>/dev/null; then
        _log_info "Installing systemd-boot..."
        sudo bootctl install
    fi
    sudo mkdir -p "/boot/loader"
    if [ -f "$loader_file" ]; then
        sudo sed -i '/^timeout/d' "$loader_file"
    fi
    echo "timeout 0" | sudo tee -a "$loader_file" >/dev/null
    _log_ok "Bootloader timeout set to 0 in $loader_file."
}

# -- Configuration -----------------------------------------------------------

# Changes the user's default login shell to zsh.
configure_default_shell() {
    local zsh_path="/usr/bin/zsh"
    if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh_path" ]; then
        _log_info "Changing default shell to zsh for $USER..."
        sudo chsh -s "$zsh_path" "$USER"
        _log_ok "Default shell changed to zsh."
    fi
}

# Writes mkinitcpio preset for Unified Kernel Image generation.
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

# Tells NetworkManager to use iwd, since wpa_supplicant gets masked below.
configure_wifi_backend() {
    sudo mkdir -p /etc/NetworkManager/conf.d
    printf '[device]\nwifi.backend=iwd\n' | sudo tee /etc/NetworkManager/conf.d/wifi_backend.conf >/dev/null
    _log_ok "NetworkManager wifi backend set to iwd."
}

# Enables, disables, and masks systemd services for the target system profile.
configure_daemons() {
    local sys_disable=(
        fwupd-refresh.timer               # for firmware updates
        fwupd-refresh.service             # for firmware updates
        NetworkManager-dispatcher.service # runs 0 scripts after nm changes it's state
        systemd-userdbd.socket            # user database (I am the only one)
        remote-fs.target                  # remote filesystems
    )

    local sys_enable=(
        ly@tty1.service
        podman.socket
        ufw.service
        NetworkManager.service
        bluetooth.service
        tailscaled.service
        upower.service
        avahi-daemon.socket # for printer/hostname discovery
        avahi-daemon.service
        pcscd.socket # for YubiKey support
        cups.socket  # for printing (socket activation)
        cups.service # for printing
        sshd.service
        paccache.timer
        nvidia-cdi-refresh.path    # regenerates the CDI spec on driver/toolkit upgrades
        nvidia-cdi-refresh.service # generates the CDI spec on boot
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
        lvm2-monitor.service        # disable if not using LVM
        systemd-udev-settle.service # obsolete, slows down boot
        ModemManager.service        # disable if not using cellular modem
    )

    local usr_enable=(
        psd.service                           # profile-sync-daemon (puts browser profile to RAM)
        pipewire.service                      # audio
        pipewire-pulse.service                # audio
        hypridle.service                      # idle & screen lock daemon
        wayland-pipewire-idle-inhibit.service # idle inhibitor for pipewire audio
        rclone-sync.timer                     # my own cloud sync daemon
    )

    local usr_mask=(
        xdg-user-dirs.service
        at-spi-dbus-bus.service # accessibility features
    )

    _log_info "Enabling system daemons..."

    # One unit per call: a single missing unit would otherwise fail the whole batch.
    _each_unit() {
        local cmd="$1" unit
        shift
        for unit in "$@"; do
            $cmd "$unit" &>/dev/null || _log_warn "Failed: $cmd $unit"
        done
    }
    _each_unit "sudo systemctl disable" "${sys_disable[@]}"
    _each_unit "sudo systemctl enable" "${sys_enable[@]}"
    _each_unit "sudo systemctl mask" "${sys_mask[@]}"
    _each_unit "systemctl --user enable" "${usr_enable[@]}"
    _each_unit "systemctl --user mask" "${usr_mask[@]}"

    _log_ok "Daemons configured."
}

# Enables UFW firewall with default deny incoming and allow outgoing.
configure_firewall() {
    _log_info "Configuring firewall"
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow 53317 comment 'LocalSend'
    sudo ufw allow 631/tcp comment 'IPP printing'
    sudo ufw allow 5353/udp comment 'mDNS discovery'
    sudo ufw allow in on tailscale0 comment 'Tailscale network'
    sudo ufw --force enable

    # Override ufw.service to avoid blocking sysinit.target on boot
    # systemd drop-ins cannot remove dependencies, so we must copy the full unit
    sudo cp /usr/lib/systemd/system/ufw.service /etc/systemd/system/ufw.service
    sudo sed -i 's/Before=sysinit.target/Before=network-pre.target\nWants=network-pre.target/' /etc/systemd/system/ufw.service
    sudo rm -rf /etc/systemd/system/ufw.service.d
    sudo systemctl daemon-reload

    _log_ok "Firewall configured properly"
}

# Configures Reflector mirrorlist updater and enables its weekly systemd timer.
configure_reflector() {
    _log_info "Configuring Reflector..."
    sudo mkdir -p /etc/xdg/reflector
    sudo tee /etc/xdg/reflector/reflector.conf >/dev/null <<'EOF'
--save /etc/pacman.d/mirrorlist
--protocol https
--latest 5
--sort age
EOF

    sudo systemctl enable --now reflector.timer
    _log_ok "Reflector configured and reflector.timer enabled."
}

# Generates desktop entries (launched via firefox-webapp from dotfiles) and downloads icons for my web apps.
configure_progressive_webapps() {
    local desktop_dir="$HOME/.local/share/applications"
    local icon_dir="$HOME/.local/share/icons/hicolor/scalable/apps"

    mkdir -p "$desktop_dir" "$icon_dir"

    _log_info "Downloading app icons..."

    local -A icon_urls
    icon_urls["google-calendar"]="https://upload.wikimedia.org/wikipedia/commons/f/fa/Google_Calendar_icon_%282026%29.svg"
    icon_urls["google-mail"]="https://upload.wikimedia.org/wikipedia/commons/8/8f/Gmail_icon_%282026%29.svg"
    icon_urls["google-tasks"]="https://upload.wikimedia.org/wikipedia/commons/3/3f/Google_Tasks_Logo_05.2026.svg"
    icon_urls["whatsapp-desktop"]="https://upload.wikimedia.org/wikipedia/commons/6/6b/WhatsApp.svg"
    icon_urls["google-gemini"]="https://upload.wikimedia.org/wikipedia/commons/1/1d/Google_Gemini_icon_2025.svg"

    local name
    for name in "${!icon_urls[@]}"; do
        curl -fsSL -o "$icon_dir/$name.svg" "${icon_urls[$name]}" || _log_warn "Failed to download $name icon"
    done

    local apps=(
        "Calendar|https://calendar.google.com|google-calendar|Network;Office;"
        "Gmail|https://mail.google.com|google-mail|Network;Email;"
        "WhatsApp|https://web.whatsapp.com|whatsapp-desktop|Network;InstantMessaging;"
        "Tasks|https://tasks.google.com|google-tasks|Office;Utility;"
        "Gemini|https://gemini.google.com|google-gemini|Network;AI;Google;"
    )

    local class desktop
    for app in "${apps[@]}"; do
        IFS='|' read -r name url icon categories <<<"$app"
        class="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
        desktop="$desktop_dir/$class.desktop"

        cat >"$desktop" <<DESKTOPEOF
[Desktop Entry]
Name=$name
Exec=$HOME/.local/bin/firefox-webapp $class $url
Icon=$icon
Terminal=false
Type=Application
StartupWMClass=webapps
Categories=$categories
DESKTOPEOF
    done

    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

    _log_ok "Progressive web apps configured."
}

# Increases tty font and swaps it to unicode terminus for readability
configure_tty_font() {
    if grep -q "^FONT=" /etc/vconsole.conf; then
        sudo sed -i 's/^FONT=.*/FONT=ter-u20n/' /etc/vconsole.conf
    else
        echo "FONT=ter-u20n" | sudo tee -a /etc/vconsole.conf >/dev/null
    fi
    sudo systemctl restart systemd-vconsole-setup
}

# Configures systemd-logind to honor handle-lid-switch inhibitors (stay awake on lid close).
configure_logind_lid_inhibit() {
    _log_info "Configuring logind lid switch inhibitor..."
    sudo mkdir -p /etc/systemd/logind.conf.d
    sudo tee /etc/systemd/logind.conf.d/lid-inhibit.conf >/dev/null <<'EOF'
[Login]
LidSwitchIgnoreInhibited=no
EOF
    sudo systemctl kill -s HUP systemd-logind 2>/dev/null || true
    _log_ok "Logind lid switch inhibitor enabled."
}

# Wires pam_fprintd (sufficient, so password stays as fallback) and enrolls a finger.
configure_fingerprint() {
    _log_info "Configuring fingerprint reader & PAM..."

    _pam_add_fprintd() {
        local file="$1" after="$2"
        local entry='auth       sufficient   pam_fprintd.so'
        [ -f "$file" ] || return 0
        sudo sed -i '/pam_fprintd\.so/d' "$file"
        if grep -qE "$after" "$file"; then
            sudo sed -i -E "/$after/a $entry" "$file"
        else
            sudo sed -i "1i $entry" "$file"
        fi
    }
    [ -f /etc/pam.d/polkit-1 ] || sudo cp /usr/lib/pam.d/polkit-1 /etc/pam.d/polkit-1
    _pam_add_fprintd /etc/pam.d/sudo '^#%PAM-1\.0'
    _pam_add_fprintd /etc/pam.d/su 'pam_rootok\.so'
    _pam_add_fprintd /etc/pam.d/hyprlock '^#%PAM-1\.0'
    _pam_add_fprintd /etc/pam.d/polkit-1 '^#%PAM-1\.0'

    # fprintd is D-Bus activated; give it a moment to claim the reader.
    sudo systemctl start fprintd.service 2>/dev/null || true
    local devices=""
    for _ in {1..20}; do
        devices=$(fprintd-list "$USER" 2>/dev/null) && break
        sleep 0.5
    done
    if ! grep -q "Using device" <<<"$devices"; then
        _log_warn "No fingerprint reader claimed — PAM wired, skipping enroll."
        return 0
    fi

    local enrolled
    enrolled=$(grep -cE '^\s*-\s*#[0-9]+:' <<<"$devices" || true)
    if [ "$enrolled" -gt 0 ]; then
        if [ "${FPRINT_REENROLL:-0}" != "1" ]; then
            _log_ok "Fingerprint PAM configured ($enrolled print(s) already enrolled; FPRINT_REENROLL=1 to redo)."
            return 0
        fi
        _log_info "Re-enrolling: removing $enrolled old print(s)..."
        if ! fprintd-delete "$USER"; then
            _log_warn "Could not delete old prints — keeping them."
            return 0
        fi
    fi

    _log_info "Enroll your finger (press firmly, don't swipe; several times)..."
    if ! fprintd-enroll; then
        _log_warn "Enroll failed/cancelled — password auth unaffected."
        return 0
    fi
    if fprintd-verify; then
        _log_ok "Fingerprint enrolled and verified (sudo/su/polkit-1/hyprlock)."
    else
        _log_warn "Enrolled, but verify did not match (often just a bad scan). Check with 'fprintd-verify' or rerun with FPRINT_REENROLL=1."
    fi
}

# Hides unnecessary desktop entries via user-scope XDG override.
clean_dot_desktop() {
    local override_dir="$HOME/.local/share/applications"
    mkdir -p "$override_dir"
    _log_info "Hiding desktop icons..."

    local apps=(
        libreoffice-startcenter
        libreoffice-draw libreoffice-math
        libreoffice-base avahi-discover bssh bvnc cmake-gui
        com.prusa3d.PrusaSlicer.GCodeViewer nvidia-settings
        assistant designer linguist qdbusviewer
    )

    local app
    for app in "${apps[@]}"; do
        printf '[Desktop Entry]\nType=Application\nHidden=true\n' >"$override_dir/$app.desktop"
    done
    update-desktop-database "$override_dir" 2>/dev/null || true
    _log_ok "Desktop files hidden."
}

# Runs the sysclean script to remove orphaned packages and package cache.
cleanup() {
    _log_info "Cleaning up..."
    local PATH="$HOME/.local/bin:$PATH"
    if command -v sysclean &>/dev/null; then
        sysclean
        _log_ok "System cleanup complete."
    else
        _log_warn "sysclean not found — skipping."
    fi
}

# Creates udev symlinks for AMD iGPU and NVIDIA dGPU for Hyprland multi-GPU setups.
configure_hyprland_multigpu() {
    _log_info "Configuring Hyprland multi-GPU (AMD primary, NVIDIA for external)..."

    local amd_pci_id nvidia_pci_id
    amd_pci_id=$(lspci -d ::03xx | awk '/AMD/ && !n++ {print $1}')
    nvidia_pci_id=$(lspci -d ::03xx | awk '/NVIDIA/ && !n++ {print $1}')

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

# Prints the final success message with post-install instructions.
finished_message() {
    printf '\n'
    printf '%b========================================%b\n' "${GREEN}" "${NC}"
    printf '%b INSTALLATION COMPLETED SUCCESSFULLY!%b\n' "${GREEN}" "${NC}"
    printf '%b========================================%b\n' "${GREEN}" "${NC}"
    printf '\n'
    printf 'Logs saved to: %s\n' "$LOGS"
    printf 'System is primed for Hyprland login. Enjoy the speed.\n'
    printf 'Restart is necessary for the installation to finish.\n\n'
    printf 'Remember to setup tailscale manually after reboot with:\n'
    printf 'sudo tailscale up\n'
}

main
