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

# Entry point orchestrating the full Arch Linux setup process.
main() {
    check_user
    welcome_message
    mount_external_home

    # -- Installations ------------
    install_and_setup_paru
    install_packages

    # -- Fixes --------------------
    fix_display_brightness
    fix_fn_keys_lofree
    fix_touchpad
    fix_external_monitor_74hz

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
    configure_reflector
    configure_nvidia_cdi
    configure_hyprland_multigpu
    configure_progressive_webapps
    configure_tty_font

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
    # Background loop refreshing sudo timestamp until the script exits.
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

# Prints the ASCII banner, action plan, and waits for user confirmation before proceeding.
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
    echo " 3. Fix:       touchpad, brightness (ec+d3hot), lofree fn keys, iiyama 74Hz EDID"
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

# Installs the paru AUR helper if missing and performs a full system upgrade.
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
    source "$SCRIPT_DIR/packages.sh"
    _log_info "Installing all packages..."
    paru -S --noconfirm --needed "${SYSTEM_PKGS[@]}" "${GPU_PKGS[@]}" "${MISC_PKGS[@]}"
    _log_ok "All packages installed."
}

# -- Fixes -------------------------------------------------------------------

# Fixes brightness control on hybrid AMD-NVIDIA Legion laptops by routing it
# through the EC firmware (nvidia_wmi_ec). This panel's real level lives in
# the EC: reads/writes anywhere else are theater, and any dGPU power
# transition makes the EC re-apply its dim while the OS value stays put (hence
# "unplug dims, any keypress restores" — the keypress only worked via its GPU
# wake-up side effect). Forcing acpi_backlight=nvidia_wmi_ec is what keeps this
# a SINGLE writer: amdgpu skips its decorative amdgpu_bl node and
# nvidia-modeset defers instead of registering a fighting nvidia_0 node, so
# every tool targets the same EC-backed device. Coarse 0-100 steps are the
# accepted tradeoff for stability. dGPU RTD3 D3cold is enabled for maximum
# battery life (~8W idle vs ~17W in D3hot); quickshell SystemStatus restores
# the backlight level (+0%) when dGPU enters D3cold to counter EC dimming.
# amdgpu.abmlevel=0 disables content-adaptive dimming (also looks like jumps),
# video.brightness_switch_enabled=0 leaves keys to userspace (quickshell OSD) only.
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

    # Keep runtime PM disabled ONLY for the touchpad path: the AMD I2C
    # controller (AMDI0010), its ELAN/CUST client, and the HID/input layers
    # on top of it. A bare SUBSYSTEM=="i2c" match would pin every I2C bus to
    # "on", including the AMD eDP AUX channels and the NVIDIA I2C buses,
    # which blocks NVIDIA RTD3 autosuspend and panel power management. Each
    # aborted/retried suspend re-probes the backlight (see nvidia-modeset
    # "attempting to use ACPI backlight" spam), so the over-broad rule shows
    # up as jumping brightness.
    #
    # NOTE: there are no "i2c_hid"/"i2c_hid_acpi" buses (see /sys/bus), so
    # rules matching those subsystems never fire. i2c_hid_acpi is just the
    # DRIVER bound to the SUBSYSTEM=="i2c" client (i2c-ELAN06FA:00), and the
    # touchpad itself lives at SUBSYSTEM=="hid" (DRIVER=="hid-multitouch")
    # with SUBSYSTEM=="input" children. Match those instead, scoped by the
    # parent's name so other HID devices keep their default PM policy.
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

# Overclocks external iiyama ProLite PL2792Q monitor from 60Hz to 74Hz (2560x1440).
# The monitor's HDMI 1.4 EDID block advertises a 59.95Hz Detailed Timing Descriptor
# and a conservative 89 kHz horizontal sync limit, causing nvidia-drm atomic modesetting
# to reject custom modelines with -EINVAL. However, the panel natively supports up to
# 75Hz (TMDS clock ~298 MHz, H-sync ~110 kHz) without dropped frames or artifacts.
# Because nvidia-drm ignores drm.edid_firmware kernel parameters, this fix installs
# a patched EDID binary (whose PREFERRED timing already IS 2560x1440@74, so
# Hyprland `preferred` resolves to 74Hz once the override is active) and an
# automated systemd/udev mechanism to inject the EDID into the DRM debugfs
# override nodes whenever the iiyama display is connected.
#
# CAUTION (Oct 2026 post-mortem, kernel panic "System is deadlocked on memory"):
# forcing `2560x1440@74` in Hyprland BEFORE this override lands on the active
# connector makes nvidia-modeset spin on "Error while waiting for GPU progress",
# leaking kmalloc-128 (~14 GB observed) until OOM -> DRM panic blue screen.
# The override MUST therefore (a) actually run on hotplug (the old
# ACTION=="add|change" rule never matched anything - `|` is literal in udev),
# (b) cover every GPU (USB-C DP alt-mode on this Legion enumerates on the AMD
# iGPU, not only 0x10de), and (c) be flock-serialized + SHA-guarded so the
# edid_override + trigger_hotplug pulse fires exactly once. Hyprland configs
# must use `preferred` (== 74Hz once patched) instead of a hardcoded @74 so a
# not-yet-overridden hotplug safely falls back to 60Hz instead of panicking.
fix_external_monitor_74hz() {
    _log_info "Configuring 74Hz EDID override for iiyama PL2792Q external monitor..."

    # 1. Install patched 74Hz EDID binary (256 bytes) to standard firmware path
    sudo mkdir -p /usr/lib/firmware/edid
    base64 -d <<'EOF' | sudo tee /usr/lib/firmware/edid/iiyama_pl2792q_74hz.bin >/dev/null
AP///////wAmzTBmkAcAAA4fAQOAPCJ46gydq1VMoCQNUlQlSwCVAKnAqUCzANHA0QDhAAEBcXQAoKCgKVAwIDUAVVAhAAAaAAAA/wAxMTUyMDExNDAxOTM2AAAA/QAyTB5zIgAKICAgICAgAAAA/ABQTDI3OTJRCiAgICAgASYCAyTxTxAFBAMCARESExQGBxUWHyMJBweDAQAAZwMMABAAOEQCOoAYcTgtQFgsRQBVUCEAAB4BHYAYcRwWIFgsJQBVUCEAAJ4BHQByUdAeIG4oVQBVUCEAAB6MCtCKIOAtEBA+lgBVUCEAABgAAAAAAAAAAAAAAAAAAAAAAAAATQ==
EOF
    sudo chmod 644 /usr/lib/firmware/edid/iiyama_pl2792q_74hz.bin

    # 2. Install runtime injection helper script.
    # Serialize with flock (udev fires one event per DRM connector -> storm),
    # match by EDID content on ANY gpu (no vendor filter: USB-C DP alt-mode
    # lands on amdgpu here), wait briefly for the EDID to appear after
    # hotplug, and pulse trigger_hotplug exactly once per needed change.
    sudo tee /usr/local/bin/apply-iiyama-edid.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

EDID_FILE="/usr/lib/firmware/edid/iiyama_pl2792q_74hz.bin"
TARGET_SHA="40afcfcd7edc070860262f4ecbb5b7f130c8a84b3b4439319ad62cdb31f1547d"
LOCK_FILE="/run/lock/apply-iiyama-edid.lock"

[ -f "$EDID_FILE" ] || exit 0
[ -d /sys/kernel/debug/dri ] || exit 0
mkdir -p /run/lock 2>/dev/null || true
exec 9>"$LOCK_FILE" 2>/dev/null || exit 0
flock -n 9 || exit 0

for conn in /sys/class/drm/card*-*; do
    [ -d "$conn" ] || continue
    [ -f "$conn/status" ] || continue

    base=$(basename "$conn")
    card_num=$(echo "$base" | sed -E 's/card([0-9]+)-.*/\1/')
    conn_name=$(echo "$base" | sed -E 's/card[0-9]+-(.*)/\1/')
    [ -n "$card_num" ] && [ -n "$conn_name" ] || continue

    override_path="/sys/kernel/debug/dri/$card_num/$conn_name/edid_override"
    hotplug_path="/sys/kernel/debug/dri/$card_num/$conn_name/trigger_hotplug"
    [ -e "$override_path" ] || continue

    status=$(cat "$conn/status" 2>/dev/null || echo "unknown")
    if [ "$status" = "connected" ]; then
        # EDID can lag behind the hotplug event (dock/hub enumeration);
        # poll briefly instead of acting on an empty file.
        edid_ok=0
        for _ in 1 2 3 4 5 6; do
            if [ -s "$conn/edid" ]; then
                edid_ok=1
                break
            fi
            sleep 0.5
        done
        [ "$edid_ok" = "1" ] || continue
        if grep -q "PL2792Q" "$conn/edid" 2>/dev/null; then
            current_sha=$(head -c 256 "$conn/edid" 2>/dev/null | sha256sum | cut -d' ' -f1 || true)
            if [ "$current_sha" != "$TARGET_SHA" ]; then
                if cat "$EDID_FILE" > "$override_path" 2>/dev/null; then
                    # Single reprobe pulse; the SHA guard above makes a
                    # re-triggered udev event a no-op instead of a loop.
                    [ -e "$hotplug_path" ] && echo 1 > "$hotplug_path" 2>/dev/null || true
                    logger -t apply-iiyama-edid "applied 74Hz EDID override on $base" 2>/dev/null || true
                fi
            fi
        fi
    elif [ "$status" = "disconnected" ]; then
        # Drop a stale override so a different monitor on the same port is
        # not masked by it. Cheap and idempotent; serialized by flock.
        echo -n reset > "$override_path" 2>/dev/null || true
    fi
done
EOF
    sudo chmod 755 /usr/local/bin/apply-iiyama-edid.sh

    # 3. Systemd oneshot service for boot-time application
    sudo tee /etc/systemd/system/iiyama-edid-override.service >/dev/null <<'EOF'
[Unit]
Description=Apply 74Hz EDID override for iiyama PL2792Q monitor
Wants=sys-kernel-debug.mount
After=sys-kernel-debug.mount systemd-udevd.service
RequiresMountsFor=/sys/kernel/debug
Before=display-manager.service ly@tty1.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/apply-iiyama-edid.sh

[Install]
WantedBy=multi-user.target
EOF

    # 4. Udev rules for hotplug application. NOTE: `|` is literal in udev
    # match syntax, so ACTION=="add|change" NEVER fires - one line per action.
    sudo tee /etc/udev/rules.d/98-iiyama-edid.rules >/dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="drm", KERNEL=="card[0-9]*", RUN+="/usr/local/bin/apply-iiyama-edid.sh"
ACTION=="change", SUBSYSTEM=="drm", KERNEL=="card[0-9]*", RUN+="/usr/local/bin/apply-iiyama-edid.sh"
EOF

    sudo udevadm control --reload-rules
    sudo systemctl daemon-reload
    sudo systemctl enable iiyama-edid-override.service 2>/dev/null || true
    sudo /usr/local/bin/apply-iiyama-edid.sh 2>/dev/null || true

    _log_ok "74Hz EDID override configured for iiyama PL2792Q."
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

optimize_mkinitcpio_hooks() {
    local config_file="/etc/mkinitcpio.conf"
    _log_info "Updating mkinitcpio modules and hooks..."
    sudo sed -i -E 's|^MODULES=\(.*\)|MODULES=()|' "$config_file"
    sudo sed -i -E 's|^HOOKS=\(.*\)|HOOKS=(systemd autodetect microcode modconf sd-vconsole block filesystems)|' "$config_file"
    _log_ok "Updated hooks in $config_file"
}

# Sets initramfs compression to zstd with fast compression level.
optimize_mkinitcpio_compression() {
    local conf="/etc/mkinitcpio.conf"
    _log_info "Optimizing initramfs size and compression..."

    sudo sed -i -e '/^COMPRESSION=/d' -e '/^COMPRESSION_OPTIONS=/d' -e '/^MODULES_DECOMPRESS=/d' "$conf"

    echo 'COMPRESSION="zstd"' | sudo tee -a "$conf" >/dev/null
    echo 'COMPRESSION_OPTIONS=(-1 -T0)' | sudo tee -a "$conf" >/dev/null
    echo 'MODULES_DECOMPRESS="no"' | sudo tee -a "$conf" >/dev/null

    _log_ok "Initramfs compression optimized (zstd, no module decompression)."
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

# Clones dotfiles from GitHub and runs install.sh to symlink configs.
configure_dotfiles() {
    _log_info "Downloading and linking dotfiles..."
    if [ ! -d "$HOME/.files" ]; then
        git clone https://github.com/loureq177/.files.git ~/.files
    else
        _log_warn "Dotfiles directory already exists. Skipping."
        return 0
    fi

    if [ -f ~/.files/install.sh ]; then
        chmod +x ~/.files/install.sh
        ~/.files/install.sh
    else
        _log_error "No install.sh found in dotfiles."
        exit 1
    fi
    _log_ok "Dotfiles installed."
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
        pcscd.socket        # for YubiKey support
        cups.socket         # for printing (socket activation)
        cups.service        # for printing
        sshd.service
        paccache.timer
        iiyama-edid-override.service
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
        psd.service             # profile-sync-daemon (puts browser profile to RAM)
        pipewire.service        # audio
        pipewire-pulse.service  # audio
        hyprpolkitagent.service # for password popups
        hypridle.service                      # idle & screen lock daemon
        wayland-pipewire-idle-inhibit.service # idle inhibitor for pipewire audio
        rclone-sync.timer                     # my own cloud sync daemon
    )

    local usr_mask=(
        xdg-user-dirs.service
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

# Generates desktop entries and downloads icons for Google Calendar, Gmail, WhatsApp, Tasks, and Gemini PWAs.
configure_progressive_webapps() {
    local desktop_dir="$HOME/.local/share/applications"
    local icon_dir="$HOME/.local/share/icons/hicolor/scalable/apps"

    mkdir -p "$desktop_dir" "$icon_dir"

    _log_info "Downloading app icons..."

    local -A icon_urls
    icon_urls[google-calendar]="https://upload.wikimedia.org/wikipedia/commons/f/fa/Google_Calendar_icon_%282026%29.svg"
    icon_urls[google-mail]="https://upload.wikimedia.org/wikipedia/commons/8/8f/Gmail_icon_%282026%29.svg"
    icon_urls[google-tasks]="https://upload.wikimedia.org/wikipedia/commons/3/3f/Google_Tasks_Logo_05.2026.svg"
    icon_urls[whatsapp-desktop]="https://upload.wikimedia.org/wikipedia/commons/6/6b/WhatsApp.svg"
    icon_urls[google-gemini]="https://upload.wikimedia.org/wikipedia/commons/1/1d/Google_Gemini_icon_2025.svg"

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

        # Clean up legacy launcher script in ~/.local/bin if present
        rm -f "$HOME/.local/bin/$class" "$desktop"

        cat >"$desktop" <<DESKTOPEOF
[Desktop Entry]
Name=$name
Exec=chromium --ozone-platform-hint=auto --enable-extensions --class=$class --app=$url
Icon=$icon
Terminal=false
Type=Application
StartupWMClass=$class
Categories=$categories
DESKTOPEOF
    done

    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

    _log_ok "Progressive web apps configured (2026 icons)."
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

# Hides unnecessary desktop entries via user-scope XDG override.
clean_dot_desktop() {
    local override_dir="$HOME/.local/share/applications"
    mkdir -p "$override_dir"
    _log_info "Hiding desktop icons..."

    local search_dirs=(
        "$HOME/.local/share/flatpak/exports/share/applications"
        "/var/lib/flatpak/exports/share/applications"
        "/usr/local/share/applications"
        "/usr/share/applications"
    )

    local apps=(
        libreoffice-startcenter
        libreoffice-draw libreoffice-math
        libreoffice-base avahi-discover bssh bvnc cmake-gui
        com.prusa3d.PrusaSlicer.GCodeViewer nvidia-settings
    )

    # Un-hide Writer / Calc / Impress in case a previous run hid them:
    # leftover NoDisplay=true overrides would keep them invisible otherwise.
    rm -f "$override_dir"/libreoffice-writer.desktop \
        "$override_dir"/libreoffice-calc.desktop \
        "$override_dir"/libreoffice-impress.desktop

    for app in "${apps[@]}"; do
        for dir in "${search_dirs[@]}"; do
            local sys_file="${dir}/${app}.desktop"
            if [ -f "$sys_file" ]; then
                cp "$sys_file" "$override_dir/"
                grep -q '^NoDisplay=true$' "$override_dir/${app}.desktop" || sed -i '/^\[Desktop Entry\]$/a\NoDisplay=true\nHidden=true' "$override_dir/${app}.desktop"
                break
            fi
        done
    done
    update-desktop-database "$override_dir" 2>/dev/null || true
    _log_ok "Desktop files hidden."
}

# Runs the sysclean script to remove orphaned packages and package cache.
cleanup() {
    _log_info "Cleaning up..."
    if command -v sysclean &>/dev/null; then
        sysclean
        _log_ok "System cleanup complete."
    elif [ -x "$HOME/.local/bin/sysclean" ]; then
        "$HOME/.local/bin/sysclean"
        _log_ok "System cleanup complete."
    else
        _log_warn "sysclean not found — skipping."
    fi
}

configure_nvidia_cdi() {
    _log_info "Generating NVIDIA CDI spec..."
    if [ -f /etc/systemd/system/nvidia-cdi-generate.service ]; then
        _log_info "Removing legacy nvidia-cdi-generate systemd service..."
        sudo systemctl disable --now nvidia-cdi-generate.service 2>/dev/null || true
        sudo rm -f /etc/systemd/system/nvidia-cdi-generate.service
    fi
    sudo mkdir -p /etc/cdi
    sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
    _log_ok "NVIDIA CDI spec generated."
}

# Creates udev symlinks for AMD iGPU and NVIDIA dGPU for Hyprland multi-GPU setups.
configure_hyprland_multigpu() {
    _log_info "Configuring Hyprland multi-GPU (AMD primary, NVIDIA for external)..."

    local amd_pci_id nvidia_pci_id
    amd_pci_id=$(lspci -d ::03xx | grep -i 'AMD' | head -1 | cut -f1 -d' ')
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
