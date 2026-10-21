# FreshArchLinux

**WARNING:** Running this on your hardware may damage your system. Review before executing.

This is my personal post-install script for Arch Linux. I use it to quickly
deploy my environment on my specific hardware.

It is the private half of my setup. The public half is
[`loureq177/.files`](https://github.com/loureq177/.files): configs and scripts
that make sense on any machine. Everything that is about me or about this
laptop lives here.

## What goes where

| | `.files` | here |
| --- | --- | --- |
| Packages | what its configs and scripts use | hardware, drivers, my applications (`packages.sh`) |
| Home directory | configs, desktop scripts, their units | my own scripts and timers (`home/`) |
| System | autologin, login shell, keyd, zram | kernel parameters, GPU, daemons, firewall, fingerprint |

## Features

- **Installations:** enables `multilib`, runs the dotfiles installer (which
  builds `paru` and installs its own package lists), then installs
  `packages.sh` and links `home/` into `~`.
- **Fixes:** Kernel parameters for Lenovo Legion touchpads, Lofree Fn keys, and
  NVIDIA/AMD hybrid brightness.
- **Optimizations:** Kernel boot parameters, a slim `mkinitcpio` (with `vfat`
  inside, so `/boot` does not stall the boot), the tty font set by the kernel
  instead of `systemd-vconsole-setup`, and NVIDIA RTD3 for power saving.
- **Configurations:** Daemons, UFW firewall, UKI presets, fingerprint auth,
  web app launchers, and a wait for both GPUs before the tty1 autologin.

## `home/`

A [GNU Stow](https://www.gnu.org/software/stow/) package, linked into `~`
next to the dotfiles' own links:

- `bedtime` and its timer: Wi-Fi goes off at 22:00 and comes back at 07:00.
- `rclone-sync` and its timer: mirrors `~` to my cloud remote once a day.
  Source and remote can be overridden in `~/.config/rclone/backup.conf` (see
  `backup.conf.example`). It refuses to run when the source is empty, because
  a mirror of an unmounted home would empty the backup.
- `boot-report`: where the boot time goes, from the journal. Lists every boot
  with its firmware/loader/kernel/initrd/userspace split, the time to the
  desktop and the USB devices plugged in at power-on, groups firmware time by
  those devices and by power-off vs. reboot, and for one boot shows the
  milestones, slow mounts and the stretches in which systemd was waiting.
  `boot-report --diagnose` makes the next boot, once, log every driver probe
  and systemd job (`initcall_debug`, systemd debug); `boot-report` then lists
  the slowest ones and what systemd did while it waited.

After changing what is in `home/`:

```bash
stow --dir ~/Projects/FreshArchLinux --target ~ --restow home
```

## Usage

```bash
chmod +x fresh_archlinux.sh
./fresh_archlinux.sh
```

To re-apply some steps on an installed system (the UKIs are rebuilt after):

```bash
./fresh_archlinux.sh optimize_base_boot_params optimize_mkinitcpio configure_tty_font
```

## Testing

```bash
tests/run
```

Needs `bats`. The scripts in `home/` run against a temporary `$HOME` with every
system command stubbed. The installer itself is only checked for syntax, with
`shellcheck`, and against the dotfiles' package lists for duplicates.
