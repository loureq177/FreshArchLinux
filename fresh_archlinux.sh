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

fix_external_monitor_74hz() {
    _log_info "Configuring 74Hz EDID override for iiyama PL2792Q external monitor..."

    # 1. Install patched 74Hz EDID binary (256 bytes) to standard firmware path
    sudo mkdir -p /usr/lib/firmware/edid
    base64 -d <<'EOF' | sudo tee /usr/lib/firmware/edid/iiyama_pl2792q_74hz.bin >/dev/null
AP///////wAmzTBmkAcAAA4fAQOAPCJ46gydq1VMoCQNUlQlSwCVAKnAqUCzANHA0QDhAAEBcXQAoKCgKVAwIDUAVVAhAAAaAAAA/wAxMTUyMDExNDAxOTM2AAAA/QAyTB5zIgAKICAgICAgAAAA/ABQTDI3OTJRCiAgICAgASYCAyTxTxAFBAMCARESExQGBxUWHyMJBweDAQAAZwMMABAAOEQCOoAYcTgtQFgsRQBVUCEAAB4BHYAYcRwWIFgsJQBVUCEAAJ4BHQByUdAeIG4oVQBVUCEAAB6MCtCKIOAtEBA+lgBVUCEAABgAAAAAAAAAAAAAAAAAAAAAAAAATQ==
EOF
    sudo chmod 644 /usr/lib/firmware/edid/iiyama_pl2792q_74hz.bin

    sudo tee /usr/local/bin/apply-iiyama-edid.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Applies the patched 74Hz EDID ONLY to the physical iiyama PL2792Q.
# Safety (Oct 2026 panic post-mortem): while an override is staged,
# $conn/edid reads back the OVERRIDE, so `grep PL2792Q` alone
# false-positives on any foreign monitor (e.g. HP) plugged into the same
# port -> invalid modeset -> nvidia-modeset spin -> kmalloc-128 OOM -> panic.
# Rules: reset on disconnect (never inherit), verify-by-reset when staged
# but unverified, SHA guard + per-connector state stamps to avoid hotplug
# self-loops. Failures always degrade to stock EDID (safe), never to a
# wrong EDID.
EDID_FILE="/usr/lib/firmware/edid/iiyama_pl2792q_74hz.bin"
TARGET_SHA="40afcfcd7edc070860262f4ecbb5b7f130c8a84b3b4439319ad62cdb31f1547d"
EMPTY_SHA="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
LOCK_FILE="/run/lock/apply-iiyama-edid.lock"
STATE_DIR="/run/iiyama-edid"
# The dGPU idles in RTD3 D3cold for battery life, so its debugfs nodes only
# exist while nvidia-drm is resumed. Wait for the node instead of skipping
# instantly - an instant skip is exactly how the override silently never
# landed (service exit 0, Hyprland stuck at stock 60Hz, zero journal lines).
WAIT_NODE_SECS=20

[ -f "$EDID_FILE" ] || exit 0
[ -d /sys/kernel/debug/dri ] || exit 0
mkdir -p /run/lock "$STATE_DIR" 2>/dev/null || true
exec 9>"$LOCK_FILE" 2>/dev/null || exit 0
flock -n 9 || exit 0

# At boot this service can run before the GPUs probe (no card* in sysfs
# yet): an empty glob would silently do nothing. Wait for DRM devices.
for _ in $(seq 1 60); do
    ls /sys/class/drm/card[0-9] >/dev/null 2>&1 && break
    sleep 0.5
done

wait_for_node() { # $1 = path; waits up to WAIT_NODE_SECS for it to appear
    for _ in $(seq 1 $((WAIT_NODE_SECS * 2))); do
        [ -e "$1" ] && return 0
        sleep 0.5
    done
    return 1
}

log() {
    logger -t apply-iiyama-edid "$1" 2>/dev/null || true
}

edid_bytes() {
    head -c 256 "$1" 2>/dev/null | wc -c
}

edid_sha() {
    head -c 256 "$1" 2>/dev/null | sha256sum | cut -d' ' -f1 || true
}

staged_sha() {
    cat "$1" 2>/dev/null | sha256sum | cut -d' ' -f1 || true
}

is_iiyama_edid() {
    grep -q "PL2792Q" "$1" 2>/dev/null
}

pulse_hotplug() { # $1 = trigger_hotplug path
    [ -e "$1" ] && echo 1 > "$1" 2>/dev/null || true
}

for conn in /sys/class/drm/card*-*; do
    [ -d "$conn" ] || continue
    [ -f "$conn/status" ] || continue

    base=$(basename "$conn")
    card_num=$(echo "$base" | sed -E 's/card([0-9]+)-.*/\1/')
    conn_name=$(echo "$base" | sed -E 's/card[0-9]+-(.*)/\1/')
    [ -n "$card_num" ] && [ -n "$conn_name" ] || continue

    override_path="/sys/kernel/debug/dri/$card_num/$conn_name/edid_override"
    hotplug_path="/sys/kernel/debug/dri/$card_num/$conn_name/trigger_hotplug"
    state_file="$STATE_DIR/$base"
    if ! wait_for_node "$override_path"; then
        # Node missing (dGPU asleep): drop the stamp so the next event
        # with the node present re-verifies instead of trusting it.
        rm -f "$state_file"
        log "skip $base: no edid_override node (dGPU asleep?)"
        continue
    fi

    status=$(cat "$conn/status" 2>/dev/null || echo "unknown")
    staged="$(staged_sha "$override_path")"
    [ -n "$staged" ] || staged="$EMPTY_SHA"

    if [ "$status" = "disconnected" ]; then
        # Never carry an override to the next monitor on this port.
        # The kernel probes the fresh plug BEFORE udev re-runs, so a
        # sticky override would make the new panel inherit iiyama modes.
        rm -f "$state_file"
        if [ "$staged" != "$EMPTY_SHA" ]; then
            if echo -n reset > "$override_path" 2>/dev/null; then
                log "reset EDID override on $base (disconnected)"
            else
                log "FAILED to reset EDID override on $base (disconnected)"
            fi
        fi
        continue
    fi

    if [ "$status" != "connected" ]; then
        continue
    fi

    # EDID can lag behind the hotplug event (dock/hub enumeration);
    # poll briefly instead of acting on an empty file. NOTE: this MUST
    # test read bytes, not `[ -s ]`: sysfs reports st_size=0 for
    # nvidia-drm EDID files even when they read fine, so a stat-size
    # test is never true and the override silently never applies.
    edid_ok=0
    for _ in 1 2 3 4 5 6; do
        if [ "$(edid_bytes "$conn/edid")" -gt 0 ]; then
            edid_ok=1
            break
        fi
        sleep 0.5
    done
    if [ "$edid_ok" != "1" ]; then
        log "skip $base: unreadable EDID after hotplug wait"
        continue
    fi

    if is_iiyama_edid "$conn/edid"; then
        if [ "$staged" = "$TARGET_SHA" ]; then
            # $conn/edid mirrors the staged override, so this match may be
            # our own stale EDID shadowing a foreign panel (e.g. HP on the
            # same port after a fast replug). Re-probe once per plug.
            cur="$(edid_sha "$conn/edid")"
            if [ -f "$state_file" ] && [ "$(cat "$state_file" 2>/dev/null)" = "iiyama:$cur" ]; then
                continue # duplicate udev event, already verified
            fi
            if echo -n reset > "$override_path" 2>/dev/null; then
                sleep 0.5
                pulse_hotplug "$hotplug_path"
                sleep 1
                if [ "$(edid_bytes "$conn/edid")" -gt 0 ] && is_iiyama_edid "$conn/edid"; then
                    if cat "$EDID_FILE" > "$override_path" 2>/dev/null; then
                        pulse_hotplug "$hotplug_path"
                        sleep 1
                        if [ "$(edid_sha "$conn/edid")" = "$TARGET_SHA" ]; then
                            echo "iiyama:$TARGET_SHA" > "$state_file" 2>/dev/null || true
                            log "applied 74Hz EDID override on $base (verified)"
                        else
                            rm -f "$state_file"
                            log "FAILED to apply 74Hz EDID override on $base (verify mismatch)"
                        fi
                    else
                        rm -f "$state_file"
                        log "FAILED to write edid_override on $base"
                    fi
                else
                    rm -f "$state_file"
                    pulse_hotplug "$hotplug_path"
                    log "cleared stale 74Hz EDID override on $base (foreign panel was shadowed)"
                fi
            else
                log "FAILED to reset edid_override on $base (verify)"
            fi
            continue
        fi
        # No override staged and the real panel reads as iiyama: apply once.
        # The SHA read-back below makes a re-triggered udev event a no-op
        # instead of a hotplug loop.
        if cat "$EDID_FILE" > "$override_path" 2>/dev/null; then
            pulse_hotplug "$hotplug_path"
            sleep 1
            if [ "$(edid_sha "$conn/edid")" = "$TARGET_SHA" ]; then
                echo "iiyama:$TARGET_SHA" > "$state_file" 2>/dev/null || true
                log "applied 74Hz EDID override on $base"
            else
                rm -f "$state_file"
                log "FAILED to apply 74Hz EDID override on $base"
            fi
        else
            log "FAILED to write edid_override on $base"
        fi
        continue
    fi

    # Foreign panel: real EDID (no OUR override can be staged, otherwise it
    # would read back as PL2792Q above). Drop any stray override instead of
    # inheriting it.
    rm -f "$state_file"
    if [ "$staged" != "$EMPTY_SHA" ]; then
        if echo -n reset > "$override_path" 2>/dev/null; then
            pulse_hotplug "$hotplug_path"
            log "cleared foreign/stale EDID override on $base"
        else
            log "FAILED to clear foreign EDID override on $base"
        fi
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

    # Only the boot service + drm "add" (physical plug / boot probe).
    # Deliberately NO "change" and NO nvidia "bind" triggers here:
    # - "bind" fires on every dGPU RTD3 power transition (suspend/resume),
    #   i.e. exactly while a USB-C dock re-trains its MST link. The script
    #   then pokes edid_override / trigger_hotplug mid-training and the
    #   second stream (e.g. second HP on the dock) ends up with a CRTC but
    #   a black panel. Plug-and-play must not depend on GPU power cycles.
    # - "change" fires on every modeset/HDCP event and adds nothing for a
    #   stationary iiyama (boot service + "add" cover it).
    sudo tee /etc/udev/rules.d/98-iiyama-edid.rules >/dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="drm", KERNEL=="card[0-9]*", RUN+="/usr/local/bin/apply-iiyama-edid.sh"
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
        pcscd.socket # for YubiKey support
        cups.socket  # for printing (socket activation)
        cups.service # for printing
        sshd.service
        paccache.timer
        iiyama-edid-override.service
        # NOTE: no fprintd.service here — its unit is static (D-Bus
        # activated), `enable` is a no-op. configure_fingerprint() only
        # starts it / waits for the device.
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

    sudo systemctl disable "${sys_disable[@]}" 2>/dev/null || true
    sudo systemctl enable "${sys_enable[@]}" 2>/dev/null || true
    sudo systemctl mask "${sys_mask[@]}" 2>/dev/null || true

    systemctl --user enable "${usr_enable[@]}" 2>/dev/null || true
    systemctl --user mask "${usr_mask[@]}" 2>/dev/null || true

    # Quickshell owns the polkit agent slot (PolkitDialog.qml): a second agent
    # steals registration ("already exists") and its dialog shadows the
    # Quickshell one. Never enable hyprpolkitagent; undo older runs.
    systemctl --user disable --now hyprpolkitagent.service org.hyprland.hyprpolkitagent.service 2>/dev/null || true

    # Add user to hardware device groups
    sudo usermod -aG plugdev "$USER" 2>/dev/null || true

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

# Installs fprintd, enables the service, wires PAM
# (sudo/su/polkit-1/hyprlock) with password fallback, and enrolls a finger.
# Elan 04f3:0c4b needs the proprietary TOD stack (touch): with upstream
# libfprint (swipe) enroll completes but verify never matches. Proven set
# (used here since Jun 2026): fprintd + libfprint-tod + libfprint-2-tod1-elan.
# login/ly are intentionally left on password: greeter fingerprint is
# unreliable across DMs. To opt login in later:
#   sudo sed -i '1i auth       sufficient   pam_fprintd.so' /etc/pam.d/login
configure_fingerprint() {
    _log_info "Configuring fingerprint reader & PAM..."

    if ! lsusb 2>/dev/null | grep -qi "04f3:0c4b"; then
        _log_warn "Elan reader (04f3:0c4b) not detected over USB — wiring PAM anyway, skipping enroll prompt."
    fi

    # libfprint-tod provides/conflicts vanilla libfprint; the Elan TOD blob
    # pulls openssl-1.1 from AUR. Templates are driver-specific, so swapping
    # drivers forces a fresh enroll below.
    if pacman -Q libfprint &>/dev/null && ! pacman -Q libfprint-tod &>/dev/null; then
        _log_info "Replacing upstream libfprint with Elan TOD stack..."
        paru -Rdd --noconfirm libfprint
        FPRINT_REENROLL=1
    fi
    if ! pacman -Q fprintd &>/dev/null || ! pacman -Q libfprint-tod &>/dev/null || ! pacman -Q libfprint-2-tod1-elan &>/dev/null; then
        _log_info "Installing fingerprint stack (fprintd + Elan TOD)..."
        paru -S --noconfirm --needed fprintd libfprint-tod libfprint-2-tod1-elan
        sudo systemctl restart fprintd.service 2>/dev/null || true
    fi

    # fprintd's unit is static (D-Bus activated): `enable` is a no-op.
    # Just make sure the daemon is up before probing the device.
    sudo systemctl start fprintd.service 2>/dev/null || true
    local i
    for i in $(seq 1 20); do
        if fprintd-list "$USER" >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done

    if command -v fprintd-list &>/dev/null && fprintd-list "$USER" 2>/dev/null | grep -q "Using device"; then
        _log_ok "Reader claimed by libfprint."
    else
        _log_warn "No fingerprint device claimed — enroll will likely fail."
    fi

    # Idempotent PAM wiring: `sufficient` means finger success skips the
    # password, finger failure falls through to password — never a lockout.
    # Self-healing: drop any previous pam_fprintd.so line first, so a
    # re-run also repairs the position (after the header, and after
    # pam_rootok in su so root keeps passwordless `su`).
    _pam_add_fprintd() {
        local file="$1"
        local after="$2"
        [ -f "$file" ] || return 0
        sudo sed -i '/pam_fprintd\.so/d' "$file"
        local entry='auth       sufficient   pam_fprintd.so'
        if [ -n "$after" ] && grep -qE "$after" "$file"; then
            sudo sed -i -E "/$after/a $entry" "$file"
        else
            sudo sed -i "1i $entry" "$file"
        fi
    }
    _pam_add_fprintd /etc/pam.d/sudo '^#%PAM-1\.0'
    _pam_add_fprintd /etc/pam.d/su 'pam_rootok\.so'
    _pam_add_fprintd /etc/pam.d/hyprlock '^#%PAM-1\.0'
    # polkit goes through the Quickshell agent (PolkitDialog.qml) —
    # fingerprint first, password fallback. hyprpolkitagent must stay
    # disabled: two agents fight over one registration slot ("already
    # exists") and its dialog shadows the Quickshell one.
    if [ ! -f /etc/pam.d/polkit-1 ]; then
        sudo tee /etc/pam.d/polkit-1 >/dev/null <<'EOF'
#%PAM-1.0
auth       sufficient   pam_fprintd.so
auth       include      system-auth
account    include      system-auth
password   include      system-auth
session    include      system-auth
EOF
    else
        _pam_add_fprintd /etc/pam.d/polkit-1 '^#%PAM-1\.0'
    fi

    # Idempotent enrollment: never wipe a working print on a re-run.
    # fprintd-list prints one " - #N: finger-name" line per enrolled finger.
    local enrolled=0
    if command -v fprintd-list &>/dev/null; then
        enrolled=$(fprintd-list "$USER" 2>/dev/null | grep -cE '^\s*-\s*#[0-9]+:' || true)
    fi
    if [ "$enrolled" -gt 0 ]; then
        if [ "${FPRINT_REENROLL:-0}" != "1" ]; then
            _log_ok "Fingerprint service & PAM configured ($enrolled print(s) already enrolled, skipping enroll; FPRINT_REENROLL=1 to redo)."
            return 0
        fi
        _log_info "Re-enrolling: removing $enrolled old print(s)..."
        if ! fprintd-delete "$USER"; then
            _log_warn "Could not delete old prints — aborting re-enroll, keeping PAM as-is."
            return 0
        fi
    fi

    _log_info "Enroll your finger (press firmly, don't swipe; several times)..."
    if ! fprintd-enroll; then
        _log_warn "Enroll failed/cancelled — password auth unaffected."
        return 0
    fi
    if fprintd-verify; then
        _log_ok "Fingerprint service & PAM configured (sudo/su/polkit-1/hyprlock), enroll verified."
    else
        _log_warn "Enroll finished but verify said no-match (often just a bad scan: dry skin, angle, partial press). Password auth unaffected — verify manually with 'fprintd-verify' or rerun with FPRINT_REENROLL=1."
    fi
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
        assistant designer linguist qdbusviewer
    )

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
