#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "[ERROR] Failed at line $LINENO: $BASH_COMMAND" >&2' ERR

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$HOME/Projects/desktop"

source "$SCRIPT_DIR/packages.sh"

LOGS="/var/tmp/arch-setup.log"
exec > >(tee >(sed -u 's/\x1b\[[0-9;]*[A-Za-z]//g' >"$LOGS")) 2>&1

# Entry point orchestrating the full Arch Linux setup process. Given step names, runs
# only those, e.g. after changing one: ./fresh_archlinux.sh optimize_mkinitcpio
main() {
    if [ $# -gt 0 ]; then
        run_steps "$@"
        return
    fi

    check_user
    welcome_message
    mount_external_home

    # -- Installations ------------
    enable_multilib
    install_dotfiles
    install_packages
    install_personal_home

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
    configure_uki_preset
    configure_wifi_backend
    configure_keyd
    configure_daemons
    configure_gpu_wait
    configure_fast_shutdown
    configure_firewall
    configure_reflector
    configure_hyprland_multigpu
    configure_tty_font
    configure_fingerprint

    sudo mkinitcpio -P

    clean_dot_desktop
    cleanup
    finished_message
}

# Runs the named steps and rebuilds the UKIs only if the steps changed what goes into them.
run_steps() {
    local step before
    for step in "$@"; do
        declare -F "$step" >/dev/null || {
            _log_error "No such step: $step"
            exit 1
        }
    done
    check_user
    before=$(_uki_inputs)
    for step in "$@"; do
        "$step"
    done
    [ "$(_uki_inputs)" = "$before" ] || sudo mkinitcpio -P
}

# Everything mkinitcpio builds the UKIs from; boot parameter order does not matter.
_uki_inputs() {
    { tr -s ' ' '\n' </etc/kernel/cmdline | sort; cat /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d/* \
        /etc/mkinitcpio.d/linux.preset /etc/modprobe.d/*; } 2>/dev/null || true
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
    echo " 2. Install:   .files, desktop (it bootstraps paru), packages, personal scripts and timers"
    echo " 3. Fix:       brightness, lofree fn keys, touchpad"
    echo " 4. Optimize:  boot params, nvidia rtd3, mkinitcpio, bootloader timeout + default"
    echo " 5. Configure: UKI, wifi, keyd, daemons, GPU wait, fast shutdown, firewall,"
    echo "               reflector, multi-GPU, tty font, fingerprint"
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
        if awk '$2 == "/home" {found=1; exit} END {exit !found}' /etc/fstab; then
            _log_warn "/home is already defined in /etc/fstab by another device. Skipping."
            return 0
        fi
        echo "UUID=$UUID /home ext4 defaults 0 2" | sudo tee -a /etc/fstab >/dev/null
        _log_ok "Added $UUID to /etc/fstab"
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

# The lib32-* packages live in multilib, which a fresh pacman.conf ships commented out.
enable_multilib() {
    if pacman-conf --repo-list | grep -qx multilib; then
        _log_info "multilib already enabled - skipping."
        return 0
    fi
    _log_info "Enabling the multilib repository..."
    sudo sed -i '/^#\[multilib\]$/,/^#Include/ s/^#//' /etc/pacman.conf
    sudo pacman -Sy
    _log_ok "multilib enabled."
}

# Clones .files and desktop (unless already present) and runs their installers:
# .files links the terminal configs, desktop installs paru, the packages, /etc
# files, autologin and the login shell. Everything after this step can rely on
# paru and stow.
install_dotfiles() {
    _log_info "Installing .files and desktop..."
    command -v git &>/dev/null || sudo pacman -S --needed --noconfirm git
    [ -d "$HOME/.files" ] || git clone https://github.com/loureq177/.files.git "$HOME/.files"
    [ -d "$DESKTOP_DIR" ] || git clone https://github.com/loureq177/desktop.git "$DESKTOP_DIR"
    bash "$HOME/.files/install.sh"
    bash "$DESKTOP_DIR/install.sh"
    _log_ok ".files and desktop installed."
}

install_packages() {
    _log_info "Installing all packages..."
    paru -S --noconfirm --needed "${SYSTEM_PKGS[@]}" "${GPU_PKGS[@]}" "${APP_PKGS[@]}" "${MISC_PKGS[@]}"
    if command -v flatpak &>/dev/null; then
        flatpak install --user -y --or-update flathub "${FLATPAK_PKGS[@]}"
    fi
    _log_ok "All packages installed."
}

# Links home/ into ~ the way .files and desktop link theirs: my own scripts and timers
# (bedtime, rclone-sync), this laptop's hypr/local.lua and the shell's GPU wrapper,
# which have no place in the public repos.
install_personal_home() {
    _log_info "Linking personal scripts and units..."
    # Real dirs, so stow links the files inside; systemd ignores a symlinked drop-in dir
    mkdir -p "$HOME/.local/bin" "$HOME/.config/rclone" "$HOME/.config/systemd/user/quickshell.service.d"
    # From here: stow reads the .stowrc of the current directory, and the desktop's
    # one leaves local.lua out
    (cd "$SCRIPT_DIR" && stow --target "$HOME" --restow home)
    systemctl --user daemon-reload 2>/dev/null || true
    _log_ok "Personal home linked."
}

# -- Fixes -------------------------------------------------------------------

fix_display_brightness() {
    _log_info "Configuring EC (nvidia_wmi_ec) backlight parameters..."
    _add_kernel_params "acpi_backlight=nvidia_wmi_ec" "amdgpu.abmlevel=0" "video.brightness_switch_enabled=0"
    _log_ok "Brightness boot parameters applied."
}

# Fixes Lofree keyboard function keys by setting hid_apple fnmode parameter,
# and its knob, which sends every notch as two volume key taps: keyd lets
# only the second of each pair through, so a notch is one 5% volume step.
fix_fn_keys_lofree() {
    _log_info "Fixing Lofree function keys..."
    if [ -d "/sys/module/hid_apple" ]; then
        echo 2 | sudo tee /sys/module/hid_apple/parameters/fnmode >/dev/null
        _log_ok "hid_apple fnmode set to 2 (runtime)"
    else
        _log_warn "hid_apple module not loaded. Is the keyboard connected?"
    fi
    _add_kernel_params "hid_apple.fnmode=2"

    # The receiver passes for an Apple keyboard (05ac:024f). A device takes
    # one keyd config only, so this one repeats default.conf's Caps Lock.
    sudo mkdir -p /etc/keyd
    sudo tee /etc/keyd/lofree.conf >/dev/null <<'EOF'
[ids]
05ac:024f

[main]
capslock = overload(control, esc)
volumeup = toggle(knobup)
volumedown = toggle(knobdown)

[knobup]
volumeup = togglem(knobup, volumeup)

[knobdown]
volumedown = togglem(knobdown, volumedown)
EOF
    sudo keyd reload 2>/dev/null || true
    _log_ok "Lofree knob: one volume step a notch."
}

# Applies udev rules to fix Lenovo Legion touchpad I2C runtime power management issues.
fix_touchpad() {
    _log_info "Fixing Lenovo Legion touchpad (I2C PM bug)..."

    sudo tee /etc/udev/rules.d/50-touchpad-pm.rules >/dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="platform", KERNEL=="AMDI0010:*", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="i2c", KERNEL=="*ELAN*", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="hid", ATTRS{name}=="ELAN06FA:00", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="input", ATTRS{name}=="ELAN06FA:00*", TEST=="power/control", ATTR{power/control}="on"
EOF
    sudo udevadm control --reload-rules

    # On 7.2.x the touchpad sometimes NAKs the power-on at resume ("i2c_hid_acpi
    # i2c-ELAN06FA:00: PM: failed to resume async: error -121") and is left
    # half-awake: no multitouch, odd pointer. A fresh probe brings it back, so the
    # driver is rebound after every wake. sleep.target holds the unit through the
    # sleep and stops it on wake, which runs ExecStop. A rebind at the very instant
    # of resume can leave multitouch dead, hence the wait.
    sudo tee /etc/systemd/system/elan-touchpad-resume.service >/dev/null <<'EOF'
[Unit]
Description=Rebind the ELAN touchpad after resume
ConditionPathExists=/sys/bus/i2c/devices/i2c-ELAN06FA:00
Before=sleep.target
StopWhenUnneeded=yes

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/true
ExecStop=/bin/sh -c 'sleep 2; cd /sys/bus/i2c/drivers/i2c_hid_acpi || exit 1; [ ! -e i2c-ELAN06FA:00 ] || echo -n i2c-ELAN06FA:00 >unbind; for i in 1 2 3 4 5; do echo -n i2c-ELAN06FA:00 >bind && exit 0; sleep 1; done; exit 1'

[Install]
WantedBy=sleep.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable elan-touchpad-resume.service || _log_warn "Failed to enable elan-touchpad-resume."

    _log_ok "Touchpad PM udev rules and resume rebind applied."
}

# Adds or replaces kernel boot parameters in /etc/kernel/cmdline.
_add_kernel_params() {
    local cmdline_file="/etc/kernel/cmdline"

    if [ ! -f "$cmdline_file" ]; then
        _log_info "Initializing $cmdline_file with root partition..."
        sudo mkdir -p /etc/kernel
        local root_part
        root_part=$(findmnt / -o PARTUUID -n 2>/dev/null || true)
        if [ -n "$root_part" ]; then
            echo "root=PARTUUID=$root_part rw rootfstype=ext4" | sudo tee "$cmdline_file" >/dev/null
        else
            echo "rw" | sudo tee "$cmdline_file" >/dev/null
        fi
    fi

    _log_info "Adding boot parameters: $*"
    _remove_kernel_params "${@%%=*}"
    echo "$(<"$cmdline_file") $*" | sudo tee "$cmdline_file" >/dev/null
    _log_ok "Updated parameters in: $cmdline_file"
}

# Drops boot parameters by name (the part before '=') from /etc/kernel/cmdline.
_remove_kernel_params() {
    local cmdline_file="/etc/kernel/cmdline"
    [ -f "$cmdline_file" ] || return 0

    local -a current kept=()
    local word name
    read -ra current <"$cmdline_file" || true
    for word in "${current[@]}"; do
        for name in "$@"; do
            [ "${word%%=*}" = "$name" ] && continue 2
        done
        kept+=("$word")
    done
    echo "${kept[*]}" | sudo tee "$cmdline_file" >/dev/null
}

# -- Optimizations ----------------------------------------------------------

# Configures power-saving and performance kernel boot parameters.
optimize_base_boot_params() {
    local params=(
        mem_sleep_default=deep
        quiet
        loglevel=3
        systemd.show_status=false
        rd.udev.log_level=3
        nowatchdog
        audit=0
        tsc=reliable
        split_lock_detect=off
        mitigations=off
        console=tty1
        8250.nr_uarts=0
        # Arch's default minus bpf. systemd attaches a BPF LSM program at start, which turns
        # ftrace on, so every module load then holds text_mutex while ftrace checks each of its
        # functions; for amdgpu that is ~2.8 s, and systemd itself (BPF, seccomp) waits on it.
        # Only RestrictFileSystems= needs BPF LSM, and no unit here sets it.
        "lsm=landlock,lockdown,yama,integrity"
        # systemd stops starting mount units for the rest of a second once it has seen 5 mount
        # table changes in it, and its own early mounts always do that: /sysroot waited ~0.75 s
        # in the initrd, /boot and /home ~0.5 s after switch root. The kernel hands this to PID 1
        # as an environment variable, and PID 1 keeps it across switch root.
        SYSTEMD_DEFAULT_MOUNT_RATE_LIMIT_BURST=100
    )
    _log_info "Configuring base boot parameters (performance, power)..."
    _add_kernel_params "${params[@]}"

    # nowatchdog only stops the kernel's lockup detectors; the chipset's hardware
    # watchdog (sp5100_tco on this AMD board) is a module of its own.
    echo 'blacklist sp5100_tco' | sudo tee /etc/modprobe.d/nowatchdog.conf >/dev/null

    if [ -e /sys/class/tpm/tpm0 ]; then
        _log_warn "TPM is enabled: nothing here uses it, but firmware and systemd-stub measure every boot. Turn it off in the BIOS (Security)."
    fi
}

# Enables NVIDIA RTD3 dynamic power management. The driver's default
# (NVreg_DynamicPowerManagement=0x03) is already fine-grained on an Ampere laptop;
# the udev rules let runtime PM and D3cold reach the dGPU.
optimize_nvidia_rtd3() {
    _log_info "Configuring NVIDIA RTD3 (Dynamic Power Management)..."
    sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<'EOF'
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
# D3cold power cut, which is handled in userspace (legion-backlight) by
# writing the backlight again when the dGPU goes to suspended.
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", TEST=="d3cold_allowed", ATTR{d3cold_allowed}="1"
EOF

    sudo udevadm control --reload-rules
    _log_ok "NVIDIA RTD3 configured."
}

# Slims the initramfs: minimal systemd hooks, max zstd.
# zstd unpacks equally fast at any level, so -19 only shrinks the UKI the firmware has to read and measure.
# vfat is loaded in the initrd: loaded on demand for /boot, it waits behind the GPU drivers'
# module loads and holds local-fs.target, and with it the whole boot, for 2-4 s.
# No sd-vconsole: the kernel sets the console font (configure_tty_font).
optimize_mkinitcpio() {
    _log_info "Writing mkinitcpio drop-in (hooks, compression)..."
    sudo mkdir -p /etc/mkinitcpio.conf.d
    sudo tee /etc/mkinitcpio.conf.d/custom.conf >/dev/null <<'EOF'
MODULES=(vfat)
HOOKS=(systemd autodetect microcode modconf block filesystems)
COMPRESSION="zstd"
COMPRESSION_OPTIONS=(-19 -T0)
EOF
    _log_ok "mkinitcpio configured."
}

# Drops any systemd-boot menu timeout (unset, the menu stays hidden), and pins the default to the UKI:
# without it systemd-boot boots the first entry by sort order, and an extra entry
# (e.g. boot-report --diagnose) can take that place.
# /boot is root-only, so even testing for the file needs sudo.
optimize_bootloader_timeout() {
    local loader_file="/boot/loader/loader.conf"
    if ! sudo bootctl is-installed 2>/dev/null; then
        _log_info "Installing systemd-boot..."
        sudo bootctl install
    fi
    sudo mkdir -p "/boot/loader"
    sudo touch "$loader_file"
    sudo sed -i '/^[[:space:]]*\(timeout\|default\)\b/d' "$loader_file"
    echo 'default arch-linux.efi' | sudo tee -a "$loader_file" >/dev/null
    _log_ok "Bootloader menu hidden and default set to arch-linux.efi in $loader_file."
}

# -- Configuration -----------------------------------------------------------

# Writes mkinitcpio preset for Unified Kernel Image generation.
# No ALL_config: an explicit config (-c) makes mkinitcpio skip /etc/mkinitcpio.conf.d.
configure_uki_preset() {
    _log_info "Configuring UKI presets..."
    sudo mkdir -p /boot/EFI/Linux
    sudo tee /etc/mkinitcpio.d/linux.preset >/dev/null <<EOF
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

# Caps Lock is Esc when tapped and Ctrl when held, on every keyboard.
configure_keyd() {
    sudo mkdir -p /etc/keyd
    sudo tee /etc/keyd/default.conf >/dev/null <<'EOF'
[ids]
*

[main]
capslock = overload(control, esc)
EOF
    sudo systemctl enable --now keyd || _log_warn "Failed to enable keyd."
    sudo keyd reload 2>/dev/null || true
    _log_ok "keyd configured."
}

# Enables, disables, and masks systemd services for the target system profile.
configure_daemons() {
    local sys_disable=(
        fwupd-refresh.timer               # for firmware updates
        systemd-userdbd.socket            # user database (I am the only one)
        remote-fs.target                  # remote filesystems
    )

    local sys_enable=(
        podman.socket
        ufw.service
        NetworkManager.service
        bluetooth.service
        tailscaled.service
        upower.service
        avahi-daemon.socket # for printer/hostname discovery
        avahi-daemon.service
        pcscd.socket # for YubiKey support
        cups.socket # for printing: cupsd starts when something prints
        sshd.service
        paccache.timer
    )

    local sys_mask=(
        systemd-tpm2-setup-early.service   # encryption support
        systemd-tpm2-setup.service         # encryption support
        wpa_supplicant.service             # default nm backend is iwd
        NetworkManager-wait-online.service # don't wait for wifi connect on startup
        systemd-pcrproduct.service         # TPM2 PCR measurement
        systemd-pcrphase-sysinit.service   # TPM2
        systemd-pcrphase-initrd.service    # TPM2
        systemd-pcrphase.service           # TPM2
        nvidia-persistenced.service
    )

    local usr_enable=(
        pipewire.service         # audio
        pipewire-pulse.service   # audio
        rclone-sync.timer        # my own cloud sync daemon (home/)
        bedtime.timer            # wifi curfew (home/)
        legion-backlight.service # undoes the firmware's panel dimming (home/)
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

# Holds the tty1 autologin (set up by the desktop) until both DRM symlinks exist:
# Hyprland starts right after login and would otherwise miss a GPU.
configure_gpu_wait() {
    _log_info "Configuring GPU wait before autologin..."

    sudo tee /usr/local/bin/wait-for-gpus >/dev/null <<'EOF'
#!/bin/sh
links=$(grep -o 'dri/[a-z-]*' /etc/udev/rules.d/99-hyprland-gpus.rules 2>/dev/null | sort -u)
i=0
while [ "$i" -lt 200 ]; do
    ready=1
    for link in $links; do
        [ -e "/dev/$link" ] || ready=0
    done
    [ "$ready" = 1 ] && exit 0
    sleep 0.05
    i=$((i + 1))
done
exit 0
EOF
    sudo chmod 755 /usr/local/bin/wait-for-gpus

    sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
    sudo tee /etc/systemd/system/getty@tty1.service.d/gpu-wait.conf >/dev/null <<'EOF'
[Service]
ExecStartPre=-/usr/local/bin/wait-for-gpus
EOF
    sudo systemctl daemon-reload
    _log_ok "Autologin waits for the GPUs."
}

# Two fixed 1 s waits held every shutdown, and they run side by side, so both have to go:
# `tailscaled --cleanup` tries to upload its logs after the network is gone, then waits 1 s
# for the flush; iwd waits 1 s on SIGTERM to power the radios down, which a reboot does anyway.
configure_fast_shutdown() {
    _log_info "Configuring fast shutdown..."
    sudo mkdir -p /etc/systemd/system/tailscaled.service.d /etc/systemd/system/iwd.service.d
    sudo tee /etc/systemd/system/tailscaled.service.d/no-logs.conf >/dev/null <<'EOF'
[Service]
Environment=TS_NO_LOGS_NO_SUPPORT=true
EOF
    sudo tee /etc/systemd/system/iwd.service.d/fast-stop.conf >/dev/null <<'EOF'
[Service]
KillSignal=SIGKILL
SuccessExitStatus=SIGKILL
EOF
    sudo systemctl daemon-reload
    _log_ok "tailscaled and iwd stop without waiting."
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

# Large Terminus on the ttys, set by the kernel itself (TER16x32 is built in).
# systemd-vconsole-setup would run setfont when the GPU driver takes the console over,
# which is the moment the tty1 autologin starts: the login waited ~0.7 s on it and
# setfont failed anyway. The keymap stays the kernel's default (us).
configure_tty_font() {
    _log_info "Configuring tty font..."
    _add_kernel_params "fbcon=font:TER16x32"
    sudo ln -sf /dev/null /etc/udev/rules.d/90-vconsole.rules
    sudo systemctl mask systemd-vconsole-setup.service
    _log_ok "Kernel sets the tty font; systemd-vconsole-setup masked."
}

# Wires pam_fprintd (sufficient, so password stays as fallback) and enrolls a finger.
configure_fingerprint() {
    _log_info "Configuring fingerprint reader & PAM..."

    # The reader is unreachable with the lid closed: skip pam_fprintd then,
    # otherwise every prompt hangs ~30s on it before accepting the password.
    printf '#!/bin/sh\ngrep -q closed /proc/acpi/button/lid/*/state 2>/dev/null\n' | sudo tee /usr/local/bin/lid-closed >/dev/null
    sudo chmod 755 /usr/local/bin/lid-closed

    _pam_add_fprintd() {
        local file="$1" after="$2"
        local guard='auth       [success=1 default=ignore]   pam_exec.so quiet /usr/local/bin/lid-closed'
        local entry='auth       sufficient   pam_fprintd.so'
        [ -f "$file" ] || return 0
        sudo sed -i -e '/pam_fprintd\.so/d' -e '/lid-closed/d' "$file"
        if grep -qE "$after" "$file"; then
            sudo sed -i -E "/$after/a $guard\\n$entry" "$file"
        else
            sudo sed -i "1i $guard\\n$entry" "$file"
        fi
    }
    [ -f /etc/pam.d/polkit-1 ] || sudo cp /usr/lib/pam.d/polkit-1 /etc/pam.d/polkit-1
    _pam_add_fprintd /etc/pam.d/sudo '^#%PAM-1\.0'
    _pam_add_fprintd /etc/pam.d/su 'pam_rootok\.so'
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
        _log_ok "Fingerprint enrolled and verified (sudo/su/polkit-1)."
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
        libreoffice-base cmake-gui
        PrusaGcodeviewer nvidia-settings
        assistant designer linguist qdbusviewer xdvi
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

    _gpu_rule() { echo "KERNEL==\"card*\", KERNELS==\"0000:$1\", SUBSYSTEM==\"drm\", SUBSYSTEMS==\"pci\", SYMLINK+=\"dri/$2\""; }
    {
        _gpu_rule "$amd_pci_id" amd-igpu
        [ -z "$nvidia_pci_id" ] || _gpu_rule "$nvidia_pci_id" nvidia-dgpu
    } | sudo tee /etc/udev/rules.d/99-hyprland-gpus.rules >/dev/null
    [ -z "$nvidia_pci_id" ] || _log_ok "Detected NVIDIA at PCI: $nvidia_pci_id → /dev/dri/nvidia-dgpu"

    sudo udevadm control --reload
    sudo udevadm trigger --subsystem-match=drm

    _log_ok "Detected AMD at PCI: $amd_pci_id → /dev/dri/amd-igpu"
}

# Prints the final success message with post-install instructions.
finished_message() {
    echo -e "\n${GREEN}========================================"
    echo " INSTALLATION COMPLETED SUCCESSFULLY!"
    echo -e "========================================${NC}\n"
    cat <<EOF
Logs saved to: $LOGS
System is primed for Hyprland login. Enjoy the speed.
Restart is necessary for the installation to finish.

Remember to setup tailscale manually after reboot with:
sudo tailscale up
EOF
}

main "$@"
