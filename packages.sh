export PKG_GROUPS=(SYSTEM GPU HYPRLAND AUDIO GUI CLI TUI THEME MISC GNOME AUR)

export SYSTEM_PKGS=(
    amd-ucode
    linux-headers
    ca-certificates
    bluez
    bluez-utils
    udiskie
    ufw
    zram-generator
    libcamera
)

export GPU_PKGS=(
    cuda
    cudnn
    nvidia-container-toolkit
    nvidia-dkms
    nvidia-utils
    nvidia-settings
    libva-nvidia-driver
    vulkan-radeon
    lib32-vulkan-radeon
    lib32-nvidia-utils
)

export HYPRLAND_PKGS=(
    hyprland
    hyprcursor
    hypridle
    hyprlock
    hyprpicker
    hyprpolkitagent
    hyprsunset
    hyprshutdown
    ly
    xdg-desktop-portal
    xdg-desktop-portal-gtk
    xdg-desktop-portal-hyprland
    qt5-wayland
    qt5ct
    qt6-wayland
    qt6ct
    waybar
    rofi
    rofi-emoji
    cliphist
    wl-clipboard
    wtype
    mako
    swaybg
    satty
)

export AUDIO_PKGS=(
    pipewire
    pipewire-alsa
    pipewire-audio
    pipewire-jack
    pipewire-pulse
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    gst-plugins-ugly
    sox
)

export GUI_PKGS=(
    ghostty
    steam
    libreoffice-fresh
    libreoffice-fresh-pl
)

export CLI_PKGS=(
    ttyd
    7zip
    fwupd
    zip
    unzip
    flatpak
    bun
    bat
    cmatrix
    eza
    fastfetch
    fd
    fzf
    git
    git-delta
    github-cli
    hyperfine
    jq
    nodejs
    python-pynvim
    python-jupyter-client
    ripgrep
    rclone
    stow
    wget
    zoxide
    man-db
    php
    podman
    profile-sync-daemon
    resvg
    ruff
    shellcheck
    starship
    zsh
    zsh-autosuggestions
    uv
)

export TUI_PKGS=(
    neovim
    opencode
    bluetui
    impala
    ncdu
    btop
    yazi
    lazygit
)

export THEME_PKGS=(
    ttf-jetbrains-mono-nerd
    terminus-font
    papirus-icon-theme
    noto-fonts
    noto-fonts-emoji
    noto-fonts-cjk
    sound-theme-freedesktop
)

export MISC_PKGS=(
    asciiquarium
    brightnessctl
    espeak-ng
    jre-openjdk
    speech-dispatcher
    x264
)

export GNOME_PKGS=(
    gnome-calculator
    gnome-clocks
    gnome-keyring
    baobab
    loupe
    nautilus
    seahorse
    showtime
    snapshot
)

export AUR_PKGS=(
    grimblast-git
    bibata-cursor-git
    nitch
    pwvucontrol
    tlrc
    zsh-fast-syntax-highlighting
)
