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

@test "no package is listed both here and in the dotfiles" {
    local dotfiles="$HOME/.files/archlinux"
    [[ -d "$dotfiles" ]] || skip "dotfiles are not checked out at ~/.files"
    local both
    both="$(comm -12 \
        <(bash -c 'source "$1"; printf "%s\n" "${SYSTEM_PKGS[@]}" "${GPU_PKGS[@]}" "${APP_PKGS[@]}" "${MISC_PKGS[@]}"' _ "$REPO/packages.sh" | sort -u) \
        <(grep -hvE '^\s*(#|$)' "$dotfiles"/{packages.txt,packages-laptop.txt,aur.txt} | sort -u))"
    [[ -z "$both" ]] || fail "also installed by the dotfiles:" "$both"
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
