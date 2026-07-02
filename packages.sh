export PKG_GROUPS=(SYSTEM GPU MISC)

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
    libfido2
    pam-u2f
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

export MISC_PKGS=(
    asciiquarium
    acpid
    espeak-ng
    jre-openjdk
    speech-dispatcher
    x264
)
