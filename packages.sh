export PKG_GROUPS=(SYSTEM GPU MISC)

export SYSTEM_PKGS=(
    amd-ucode
    avahi
    bluez
    bluez-utils
    ca-certificates
    cups
    cups-filters
    cups-pdf
    cups-pk-helper
    dmidecode
    dosfstools
    git
    libcamera
    libfido2
    linux-firmware
    linux-headers
    nss-mdns
    pam-u2f
    pciutils
    sof-firmware
    stow
    system-config-printer
    udiskie
    ufw
    wayland-pipewire-idle-inhibit
    yubikey-manager
    zram-generator
)

export GPU_PKGS=(
    cuda
    cudnn
    lib32-nvidia-utils
    lib32-vulkan-radeon
    libva-nvidia-driver
    mesa-utils
    nvidia-container-toolkit
    nvidia-open-dkms
    nvidia-prime
    nvidia-settings
    nvidia-utils
    vulkan-radeon
    vulkan-tools
)

export MISC_PKGS=(
    acpid
    asciiquarium
    botsay
    cowsay
    dnsmasq
    espeak-ng
    jre-openjdk
    libvirt
    speech-dispatcher
    valkey
    x264
)
