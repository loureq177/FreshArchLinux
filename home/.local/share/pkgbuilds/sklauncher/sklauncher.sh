#!/bin/sh
# On the NVIDIA GPU, past the desktop's Vulkan pin to the iGPU (env.lua).
unset VK_DRIVER_FILES VK_ICD_FILENAMES
exec prime-run /opt/sklauncher/SKlauncher.AppImage --no-sandbox "$@"
