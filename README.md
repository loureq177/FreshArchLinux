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
  their installers (the desktop's builds `paru` and installs its package lists),
  then installs `packages.sh` and links `home/` into `~`.
- **Fixes:** Kernel parameters for Lenovo Legion touchpads, Lofree Fn keys (and
  its volume knob, through keyd), and NVIDIA/AMD hybrid brightness.
- **Optimizations:** Kernel boot parameters, a slim `mkinitcpio` (with `vfat`
  inside, so `/boot` does not stall the boot), the tty font set by the kernel
  instead of `systemd-vconsole-setup`, and NVIDIA RTD3 for power saving.
- **Configurations:** Daemons, UFW firewall, UKI presets, fingerprint auth, keyd,
  a faster shutdown, and a wait for both GPUs before the tty1 autologin.

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
  with Alt and Super swapped, the GPU order (the dGPU first while it drives a
  display at login), the panel and the monitors at home and at work.
- `bedtime` and its timer: Wi-Fi goes off at 22:00 and comes back at 07:00.
- `mesa-egl` and `dgpu-run`: the session's shell keeps to the iGPU's EGL
  (`quickshell.service.d/mesa-egl.conf` starts it through `mesa-egl`), and
  `dgpu-run` runs a program on the NVIDIA card despite the iGPU pin of
  `local.lua`.

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
