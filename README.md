# FreshArchLinux

**WARNING:** Running this on your hardware can damage your system. Review before
executing.

This is my personal post-install script for Arch Linux. I use it to quickly
deploy my environment on my specific hardware.

It is the private part of my setup. The public parts are

- [`loureq177/.files`](https://github.com/loureq177/.files) (terminal configs)
- [`loureq177/desktop`](https://github.com/loureq177/desktop) (the Hyprland
  desktop).

## Features

- **Installations:** enables `multilib`, clones `.files` and `desktop` and runs
  their installers, links `home/` into `~`, then installs `packages.sh`,
  SKlauncher and kanata from `home/.local/share/pkgbuilds` (no AUR).
- **Fixes:** Kernel parameters for Lenovo Legion touchpads, Lofree Fn keys, and NVIDIA/AMD hybrid brightness.
- **Optimizations:** Kernel boot parameters, a slim `mkinitcpio` (with `vfat`
  inside, so `/boot` does not stall the boot, `nvme` loaded by name, and its
  udevd stopped without waiting), the UKI
  started by the firmware itself (systemd-boot stays as the second boot entry),
  reboots through kexec (no firmware start in between),
  the tty font set by the kernel
  instead of `systemd-vconsole-setup`, a copy of `amdgpu` without its ftrace
  records (the kernel spends ~4 s of every boot checking them), NVIDIA RTD3
  for power saving, and boots without the dGPU (the login ~1.3 s sooner; the
  desktop's power menu reboots with it for the dock and back).
- **Configurations:** Daemons, UFW firewall, UKI presets, kanata
  (`.files`' `kanata.kbd`, shared with the Mac),
  a faster shutdown, a wait for both GPUs before the tty1 autologin, and the
  user manager started with the system (linger), before the network is up.

## `home/`

A [GNU Stow](https://www.gnu.org/software/stow/) package, linked into `~` next
to the links of `.files` and `desktop`:

- `rclone-sync` and its timer: mirrors `~` to my cloud remote once a day. Source
  and remote can be overridden in `~/.config/rclone/backup.conf` (see
  `backup.conf.example`). It refuses to run when the source is empty, because a
  mirror of an unmounted home would empty the backup.
- `legion-backlight` and its service: the firmware dims the panel when the dGPU
  powers down or the platform profile changes; this writes the brightness again.
  `legion-backlight --once` does it by hand.
- `hypr/local.lua`: this laptop for the desktop's Hyprland config: Polish layout
  with Alt and Super swapped, the panel and the monitors at home and at work.
- `bedtime` and its timer: Wi-Fi goes off at 21:30 (the shell's settings change it,
  `bedtime set HH:MM`) and comes back at 07:00.
- `mesa-egl` and `dgpu-run`: the session's shell keeps to the iGPU's EGL
  (`quickshell.service.d/mesa-egl.conf` starts it through `mesa-egl`), and
  `dgpu-run` runs a program on the NVIDIA card despite the iGPU pin of the
  desktop's `env.lua`.

After changing what is in `home/`:

```bash
stow --dir ~/Projects/FreshArchLinux --target ~ --restow home
```

## Usage

```bash
chmod +x fresh_archlinux.sh
./fresh_archlinux.sh
```

To re-apply some steps on an installed system (the UKIs are rebuilt only if
those steps changed their inputs):

```bash
./fresh_archlinux.sh optimize_base_boot_params optimize_mkinitcpio configure_tty_font
```
