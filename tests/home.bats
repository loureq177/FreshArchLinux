#!/usr/bin/env bats
# bedtime, rclone-sync: the personal scripts stowed from home/

load helpers

setup() {
    sandbox_setup
    stub qs
    stub notify-send
    # Something to back up: rclone-sync refuses to mirror an empty home.
    mkdir -p "$HOME/Documents"
}

# --- bedtime -----------------------------------------------------------------

wifi() {
    echo "$1" >"$SANDBOX/wifi"
    stub nmcli "[[ \"\$*\" == 'radio wifi' ]] && cat '$SANDBOX/wifi'; true"
}
BED_MARKER() { echo "$HOME/.local/state/bedtime/wifi-off"; }

@test "bedtime 21:50: warns and leaves wifi alone" {
    fake_time 21 50
    wifi enabled
    sut "$BIN/bedtime"
    assert_status 0
    assert_call_like "WiFi will turn off in 10 minutes."
    refute_call_like "nmcli radio wifi off"
}

@test "bedtime 22:00: turns wifi off, announces it and remembers doing so" {
    fake_time 22 00
    wifi enabled
    sut "$BIN/bedtime"
    assert_status 0
    assert_call "nmcli radio wifi off"
    assert_call_like "WiFi has been turned off."
    [[ -f "$(BED_MARKER)" ]]
}

@test "bedtime 23:30: turns wifi off without another notification" {
    fake_time 23 30
    wifi enabled
    sut "$BIN/bedtime"
    assert_status 0
    assert_call "nmcli radio wifi off"
    refute_call_like "notify-send"
}

@test "bedtime 22:00: does not claim a wifi the user had already switched off" {
    fake_time 22 00
    wifi disabled
    sut "$BIN/bedtime"
    assert_status 0
    refute_call_like "nmcli radio wifi off"
    [[ ! -e "$(BED_MARKER)" ]]
}

@test "bedtime 07:00: turns wifi back on only if bedtime turned it off" {
    fake_time 07 00
    wifi disabled
    sut "$BIN/bedtime"
    assert_status 0
    refute_call_like "nmcli radio wifi on"

    mkdir -p "$(dirname "$(BED_MARKER)")"
    : >"$(BED_MARKER)"
    sut "$BIN/bedtime"
    assert_status 0
    assert_call "nmcli radio wifi on"
    [[ ! -e "$(BED_MARKER)" ]]
}

@test "bedtime: copes with 08 and 09 (not octal)" {
    fake_time 08 09
    wifi enabled
    sut "$BIN/bedtime"
    assert_status 0
}

@test "bedtime: survives a missing NetworkManager" {
    fake_time 22 00
    stub nmcli 'exit 1'
    sut "$BIN/bedtime"
    assert_status 0
    [[ ! -e "$(BED_MARKER)" ]]
}

# --- rclone-sync -------------------------------------------------------------

@test "rclone-sync: syncs the home dir to the default remote, skipping dotfiles and build dirs" {
    stub rclone
    sut "$BIN/rclone-sync"
    assert_status 0
    assert_call_like "rclone sync $HOME google-drive-backup:mlorenc-backup --exclude=.*/** --exclude=.* --exclude=node_modules/**"
    assert_call_like "--drive-use-trash=true"
    refute_call_like "--progress"
    refute_call_like "notify-send"
}

@test "rclone-sync: backup.conf overrides source and remote" {
    stub rclone
    mkdir -p "$HOME/.config/rclone"
    mkdir -p "$HOME/My Docs/letters"
    printf 'RCLONE_BACKUP_SOURCE="%s/My Docs"\nRCLONE_BACKUP_REMOTE="b2:bucket"\n' "$HOME" >"$HOME/.config/rclone/backup.conf"
    sut "$BIN/rclone-sync"
    assert_status 0
    assert_call_like "rclone sync $HOME/My Docs b2:bucket --exclude"
}

@test "rclone-sync: the example config is a valid starting point" {
    stub rclone
    mkdir -p "$HOME/.config/rclone"
    cp "$REPO/home/.config/rclone/backup.conf.example" "$HOME/.config/rclone/backup.conf"
    sut "$BIN/rclone-sync"
    assert_status 0
    assert_call_like "rclone sync "
}

@test "rclone-sync: never mirrors an empty or unmounted home over the backup" {
    stub rclone
    rmdir "$HOME/Documents"
    sut "$BIN/rclone-sync"
    assert_status 1
    assert_call_like "Backup skipped"
    refute_call_like "rclone sync"
}

@test "rclone-sync: a failed sync notifies and keeps rclone's exit code" {
    stub rclone 'exit 7'
    sut "$BIN/rclone-sync"
    assert_status 7
    assert_call_like "Rclone Sync failed"
}

@test "rclone-sync: does not start twice" {
    stub rclone
    exec 9>"$XDG_RUNTIME_DIR/rclone-sync.lock"
    flock -n 9
    sut "$BIN/rclone-sync"
    exec 9>&-
    assert_status 0
    assert_output_like "already running"
    refute_call_like "rclone"
}


# --- legion-backlight --------------------------------------------------------

@test "legion-backlight --once: nudges the level down and back, twice" {
    stub brightnessctl '[[ "$*" == *get* ]] && echo 100; true'
    sut "$BIN/legion-backlight" --once
    assert_status 0
    [[ "$(call_count "brightnessctl -q -c backlight set 99")" -eq 2 ]] || fail "$(calls)"
    [[ "$(call_count "brightnessctl -q -c backlight set 100")" -eq 2 ]] || fail "$(calls)"
}

@test "legion-backlight --once: nudges upwards from zero" {
    stub brightnessctl '[[ "$*" == *get* ]] && echo 0; true'
    sut "$BIN/legion-backlight" --once
    assert_status 0
    assert_call "brightnessctl -q -c backlight set 1"
    assert_call "brightnessctl -q -c backlight set 0"
}

# --- mesa-egl / dgpu-run -----------------------------------------------------

@test "mesa-egl: runs the command with its arguments and exit status" {
    sut env -u AQ_DRM_DEVICES -u __EGL_VENDOR_LIBRARY_FILENAMES "$BIN/mesa-egl" sh -c 'echo "$1|$2|${__EGL_VENDOR_LIBRARY_FILENAMES-unset}"; exit 7' _ "a b" c
    assert_status 7
    [[ "$output" == "a b|c|unset" ]] || fail "$output"
}

@test "mesa-egl: keeps an EGL vendor the user chose and ignores unknown cards" {
    sut env AQ_DRM_DEVICES=/dev/dri/card1 __EGL_VENDOR_LIBRARY_FILENAMES=/custom.json "$BIN/mesa-egl" sh -c 'echo "$__EGL_VENDOR_LIBRARY_FILENAMES"'
    assert_status 0
    [[ "$output" == /custom.json ]]

    sut env -u __EGL_VENDOR_LIBRARY_FILENAMES AQ_DRM_DEVICES=/dev/dri/no-such-card "$BIN/mesa-egl" sh -c 'echo "${__EGL_VENDOR_LIBRARY_FILENAMES-unset}"'
    assert_status 0
    [[ "$output" == unset ]] || fail "$output"
}

@test "dgpu-run: drops the iGPU Vulkan pin before handing over to prime-run" {
    stub prime-run "echo \"prime-env \${VK_DRIVER_FILES-unset} \${VK_ICD_FILENAMES-unset}\" >>'$CALLS'"
    sut env VK_DRIVER_FILES=/igpu.json VK_ICD_FILENAMES=/igpu.json "$BIN/dgpu-run" game --flag "two words"
    assert_status 0
    assert_call "prime-run game --flag two words"
    assert_call "prime-env unset unset"
}
