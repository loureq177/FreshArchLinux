#!/usr/bin/env bats
# The installer itself only runs on a fresh machine; this keeps it parseable.

load helpers

@test "scripts parse and pass shellcheck" {
    bash -n "$REPO/fresh_archlinux.sh"
    bash -n "$REPO/packages.sh"
    need shellcheck
    local shell_scripts
    mapfile -t shell_scripts < <(grep -l '^#!.*bash' "$REPO"/home/.local/bin/*)
    # Sourced files are only known at run time (packages.sh, backup.conf).
    shellcheck -e SC1090,SC1091 "$REPO/fresh_archlinux.sh" "${shell_scripts[@]}"
}

@test "python scripts compile" {
    local f
    for f in $(grep -l '^#!.*python3' "$REPO"/home/.local/bin/*); do
        python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$f"
    done
}

@test "package arrays have no duplicates" {
    local dups
    dups="$(bash -c 'source "$1"; printf "%s\n" "${SYSTEM_PKGS[@]}" "${GPU_PKGS[@]}" "${APP_PKGS[@]}" "${MISC_PKGS[@]}"' _ "$REPO/packages.sh" | sort | uniq -d)"
    [[ -z "$dups" ]] || fail "listed more than once:" "$dups"
}

@test "no package is listed both here and in the desktop" {
    local dotfiles="$HOME/Projects/desktop"
    [[ -d "$dotfiles" ]] || skip "desktop is not checked out at ~/Projects/desktop"
    local both
    both="$(comm -12 \
        <(bash -c 'source "$1"; printf "%s\n" "${SYSTEM_PKGS[@]}" "${GPU_PKGS[@]}" "${APP_PKGS[@]}" "${MISC_PKGS[@]}"' _ "$REPO/packages.sh" | sort -u) \
        <(grep -hvE '^\s*(#|$)' "$dotfiles"/{packages.txt,packages-laptop.txt,aur.txt} | sort -u))"
    [[ -z "$both" ]] || fail "also installed by the desktop:" "$both"
}

@test "every unit fresh_archlinux.sh enables from home/ exists there, and the other way round" {
    local unit
    for unit in "$REPO"/home/.config/systemd/user/*.timer; do
        grep -q "${unit##*/}" "$REPO/fresh_archlinux.sh" || fail "${unit##*/} is never enabled"
        [[ -f "${unit%.timer}.service" ]] || fail "no service for ${unit##*/}"
        script="$(sed -n 's|^ExecStart=%h/.local/bin/||p' "${unit%.timer}.service")"
        [[ -x "$REPO/home/.local/bin/$script" ]] || fail "${unit##*/} runs '$script', which is not in home/.local/bin"
    done
}

@test "this laptop's local.lua loads in the desktop's Hyprland config" {
    local dotfiles="$HOME/Projects/desktop/home/.config/hypr"
    [[ -f "$dotfiles/hyprland.lua" ]] || skip "desktop is not checked out at ~/Projects/desktop"
    need Hyprland
    local home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$home/.config"
    cp -r "$dotfiles" "$home/.config/hypr"
    cp "$REPO/home/.config/hypr/local.lua" "$home/.config/hypr/local.lua"
    run env HOME="$home" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" timeout 30 Hyprland --verify-config --config "$home/.config/hypr/hyprland.lua"
    [[ "$output" == *"config ok"* ]] || fail "$output"
}

@test "the weather location is one the shell can read" {
    jq -e '(.name | type == "string") and (.latitude | type == "number") and (.longitude | type == "number")' "$REPO/home/.config/weather.json" >/dev/null
}
