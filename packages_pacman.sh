export PREREQ_PKGS=(
    openssl-1.1
)

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
    envycontrol
    vulkan-radeon
    lib32-vulkan-radeon
    lib32-nvidia-utils
)

export FINGERPRINT_PKGS=(
    fprintd
    libfprint-tod
    libfprint-2-tod1-elan
)

export HYPRLAND_PKGS=(
    hyprland
    hyprcursor
    hypridle
    hyprlock
    hyprpaper
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
    grimblast-git
    mako
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
    x264
    sox
    pwvucontrol
)

export APP_PKGS=(
    visual-studio-code-bin
    neovim
    ghostty
    nautilus
    yt-dlp
    opencode
    steam
)

export CLI_PKGS=(
    7zip
    fwupd
    zip
    unzip
    flatpak
    bun
    bat
    btop
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
    lazygit
    nitch
    nodejs
    python-pynvim
    python-jupyter-client
    ripgrep
    rclone
    stow
    symfony-cli
    wget
    yazi
    zoxide
    man-db
    php
    podman
    profile-sync-daemon
    resvg
    ruff
    satty
    zsh
    zsh-autosuggestions
    zsh-fast-syntax-highlighting
    ncdu
    tlrc
    uv
)

export THEME_PKGS=(
    ttf-jetbrains-mono-nerd
    papirus-icon-theme
    bibata-cursor-git
    starship
    noto-fonts
    noto-fonts-emoji
    noto-fonts-cjk
    sound-theme-freedesktop
)

export MISC_PKGS=(
    asciiquarium
    baobab
    bluetui
    brightnessctl
    gvfs
    gvfs-mtp
    impala
    jre-openjdk
    ollama-cuda
    pastel
    speech-dispatcher
    espeak-ng
    gnome-keyring
    seahorse
)
