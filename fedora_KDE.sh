#!/bin/bash
set -euo pipefail

# USAGE

usage() {
    echo "Usage: $0 [option]"
    echo ""
    echo "  full      - Run complete system setup (default if no argument given)"
    echo "  base      - Full setup without drivers"
    echo "  drivers   - Install Nvidia/Intel drivers and configure Secure Boot only"
    echo "  aseprite  - Build and install Aseprite only"
    echo "  proton-ge - Install latest GE-Proton for Steam only"
    exit 1
}

case "${1:-full}" in
    full)      RUN_FULL=true  ; RUN_DRIVERS=true  ; RUN_ASEPRITE=true  ; RUN_PROTON_GE=true  ;;
    base)      RUN_FULL=true  ; RUN_DRIVERS=false ; RUN_ASEPRITE=true  ; RUN_PROTON_GE=true  ;;
    drivers)   RUN_FULL=false ; RUN_DRIVERS=true  ; RUN_ASEPRITE=false ; RUN_PROTON_GE=false ;;
    aseprite)  RUN_FULL=false ; RUN_DRIVERS=false ; RUN_ASEPRITE=true  ; RUN_PROTON_GE=false ;;
    proton-ge) RUN_FULL=false ; RUN_DRIVERS=false ; RUN_ASEPRITE=false ; RUN_PROTON_GE=true  ;;
    *) usage ;;
esac

# FULL SETUP

if [ "$RUN_FULL" = true ]; then

    # 1. Repositories
    sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
        https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
    sudo dnf install -y rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted

    # 2. Core Desktop & Apps
    sudo dnf install -y git firefox \
        unrar steam discord vlc keepassxc lutris qbittorrent thunderbird \
        gnome-terminal dotnet-sdk-10.0 btop krita blender \
        p7zip p7zip-plugins strawberry \
        kmod-v4l2loopback obs-studio obs-studio-plugin-vlc-video obs-studio-plugin-vkcapture \
        obs-studio-plugin-webkitgtk obs-studio-plugin-x264

    sudo dnf remove podman podman-docker podman-compose

    # 3. Multimedia Codecs
    sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
    sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
    sudo dnf group install -y multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
    sudo dnf install -y libavcodec-freeworld x264 x265 gstreamer1-vaapi dav1d flac gstreamer1-plugins-bad-freeworld --allowerasing

    # 4. VS Code
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
    sudo dnf install -y code

    # 5. Docker Desktop Install
    sudo dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
    curl -O https://desktop.docker.com/linux/main/amd64/docker-desktop-x86_64.rpm
    sudo dnf install -y ./docker-desktop-x86_64.rpm
    rm docker-desktop-x86_64.rpm
    docker context use desktop-linux

    # 6. Unity Hub
    sudo sh -c 'echo -e "[unityhub]\nname=Unity Hub\nbaseurl=https://hub.unity3d.com/linux/repos/rpm/stable\nenabled=1\ngpgcheck=1\ngpgkey=https://hub.unity3d.com/linux/repos/rpm/stable/repodata/repomd.xml.key\nrepo_gpgcheck=1" > /etc/yum.repos.d/unityhub.repo'
    sudo dnf install -y unityhub

    # 7. PowerShell
    curl -sSL -O https://packages.microsoft.com/config/rhel/9/packages-microsoft-prod.rpm
    sudo rpm -i packages-microsoft-prod.rpm
    rm packages-microsoft-prod.rpm
    sudo dnf update -y
    sudo dnf install powershell -y

    # 8. ONLYOFFICE Desktop Editors
    sudo dnf install -y xorg-x11-font-utils
    sudo rpm -i --nodigest https://sourceforge.net/projects/mscorefonts2/files/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm || true
    curl -L https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors.x86_64.rpm \
        -o /tmp/onlyoffice-desktopeditors.rpm
    sudo dnf install -y /tmp/onlyoffice-desktopeditors.rpm
    rm /tmp/onlyoffice-desktopeditors.rpm

    # 9. ProtonMail Bridge
    BRIDGE_URL=$(curl -s https://api.github.com/repos/ProtonMail/proton-bridge/releases/latest \
    | grep browser_download_url | cut -d'"' -f4 | grep x86_64.rpm)
    sudo dnf install -y "$BRIDGE_URL"

    # 10. Final Services & Boot Config
    sudo usermod -aG docker $USER
    sudo localectl set-locale \
        LANG=en_US.UTF-8 \
        LC_NUMERIC=C \
        LC_TIME=C \
        LC_MONETARY=C \
        LC_MEASUREMENT=C \
        LC_PAPER=C
fi

# DRIVER SETUP

if [ "$RUN_DRIVERS" = true ]; then

    echo "Setting up Secure Boot and GPU drivers..."

    # 1. Secure Boot Support (DO THIS BEFORE NVIDIA)
    sudo kmodgenca -a
    sudo mokutil --import /etc/pki/akmods/certs/public_key.der
    # NOTE: Pick a password (e.g., '1234') to enter on the MOK blue screen after reboot.

    # 2. Nvidia & Intel Drivers
    sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-cuda-libs \
        libva-nvidia-driver nvidia-settings intel-media-driver libva-utils vdpauinfo \
        mesa-vulkan-drivers intel-compute-runtime oneVPL-intel-gpu

    # 3. Trigger and wait for akmod build
    echo "Starting Nvidia kernel module build..."
    sudo akmods --force
    echo "Nvidia module build complete!"

    # 4. Nvidia system services
    sudo systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service

    # 5. KWin / EGL environment for Nvidia
    sudo mkdir -p /etc/environment.d
    echo "KWIN_DRM_USE_EGL_STREAMS=0" | sudo tee /etc/environment.d/kwin-nvidia.conf
    echo "__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json" | sudo tee -a /etc/environment.d/kwin-nvidia.conf

    # 6. Force KWin to use DRM backend on Wayland (required for Nvidia)
    sudo mkdir -p /etc/sddm.conf.d
    sudo tee /etc/sddm.conf.d/kwin-nvidia.conf > /dev/null <<EOF
[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1
EOF

    # 7. Kernel Parameters
    sudo grubby --update-kernel=ALL \
        --args="nvidia-drm.modeset=1 mem_sleep_default=deep intel_pstate=active intel_iommu=on"

    echo "Driver setup complete."

fi

# ASEPRITE BUILD

if [ "$RUN_ASEPRITE" = true ]; then

    echo "Building Aseprite from source..."

    # Build deps
    sudo dnf install -y gcc-c++ clang libcxx-devel cmake ninja-build \
        libX11-devel libXcursor-devel libXi-devel libXrandr-devel \
        mesa-libGL-devel fontconfig-devel curl unzip

    # Fetch latest Aseprite release tag from GitHub API
    ASEPRITE_TAG=$(curl -s https://api.github.com/repos/aseprite/aseprite/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    echo "Latest Aseprite: $ASEPRITE_TAG"

    # Fetch latest Skia prebuilt tag (aseprite maintains their own fork/releases)
    SKIA_TAG=$(curl -s https://api.github.com/repos/aseprite/skia/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    echo "Latest Skia prebuilt: $SKIA_TAG"

    # Set up directories
    ASEPRITE_BUILD_DIR="$HOME/.cache/aseprite-build"
    INSTALL_DIR="$HOME/opt/aseprite"
    SKIA_DIR="$ASEPRITE_BUILD_DIR/deps/skia"
    mkdir -p "$ASEPRITE_BUILD_DIR/src" "$SKIA_DIR" "$INSTALL_DIR"

    # Download and extract Skia prebuilt
    curl -L "https://github.com/aseprite/skia/releases/download/${SKIA_TAG}/Skia-Linux-Release-x64.zip" \
        -o "$ASEPRITE_BUILD_DIR/skia.zip"
    unzip -o "$ASEPRITE_BUILD_DIR/skia.zip" -d "$SKIA_DIR"
    rm "$ASEPRITE_BUILD_DIR/skia.zip"

    # Download and extract Aseprite source
    curl -L "https://github.com/aseprite/aseprite/releases/download/${ASEPRITE_TAG}/Aseprite-${ASEPRITE_TAG}-Source.zip" \
        -o "$ASEPRITE_BUILD_DIR/aseprite-src.zip"
    unzip -o "$ASEPRITE_BUILD_DIR/aseprite-src.zip" -d "$ASEPRITE_BUILD_DIR/src"
    rm "$ASEPRITE_BUILD_DIR/aseprite-src.zip"

    # Build
    mkdir -p "$ASEPRITE_BUILD_DIR/src/build"
    cd "$ASEPRITE_BUILD_DIR/src/build"

    export CC=clang
    export CXX=clang++

    cmake \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_CXX_FLAGS:STRING=-stdlib=libstdc++ \
        -DCMAKE_EXE_LINKER_FLAGS:STRING=-stdlib=libstdc++ \
        -DLAF_BACKEND=skia \
        -DSKIA_DIR="$SKIA_DIR" \
        -DSKIA_LIBRARY_DIR="$SKIA_DIR/out/Release-x64" \
        -DSKIA_LIBRARY="$SKIA_DIR/out/Release-x64/libskia.a" \
        -DENABLE_UPDATER=OFF \
        -G Ninja \
        ..

    ninja aseprite

    # Install to ~/opt/aseprite
    cp -r bin/* "$INSTALL_DIR/"
    cp -r ../data "$INSTALL_DIR/data"
    cd ~

    # Add to PATH if not already there
    if ! grep -q 'opt/aseprite' "$HOME/.bashrc"; then
        echo 'export PATH="$HOME/opt/aseprite:$PATH"' >> "$HOME/.bashrc"
    fi

    # Create .desktop entry
    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/aseprite.desktop" <<EOF
[Desktop Entry]
Name=Aseprite
Exec=$HOME/opt/aseprite/aseprite %U
Terminal=false
Type=Application
Icon=$HOME/opt/aseprite/data/icons/ase256.png
Comment=Animated sprite editor & pixel art tool
Categories=Graphics;2DGraphics;RasterGraphics;
StartupWMClass=aseprite
EOF
    update-desktop-database "$HOME/.local/share/applications/"

    # Clean up build artifacts
    rm -rf "$ASEPRITE_BUILD_DIR/src/build"

    echo "Aseprite $ASEPRITE_TAG installed to $INSTALL_DIR"
    unset CC CXX

fi

# PROTON GE INSTALL

if [ "$RUN_PROTON_GE" = true ]; then

    echo "Installing latest GE-Proton for Steam..."

    if [ ! -d "$HOME/.steam/steam" ]; then
        # Launch Steam silently in the background
        steam -silent &
        STEAM_PID=$!

        # Wait for Steam to finish updating (login screen = ready)
        echo "Waiting for Steam to initialize..."
        until pgrep -f "steamwebhelper" > /dev/null 2>&1; do
            sleep 2
        done

        # Give it a few extra seconds to finish writing directories
        sleep 5

        # Kill Steam and all its child processes
        kill $STEAM_PID || true
        pkill -f steam || true
        pkill -f steamwebhelper || true
    fi

    PROTON_TMP=/tmp/proton-ge-custom
    rm -rf "$PROTON_TMP"
    mkdir -p "$PROTON_TMP"
    cd "$PROTON_TMP"

    # Download latest tarball
    tarball_url=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest \
        | grep browser_download_url | cut -d\" -f4 | grep .tar.gz)
    tarball_name=$(basename "$tarball_url")
    echo "Downloading $tarball_name..."
    curl -L "$tarball_url" -o "$tarball_name" --no-progress-meter

    # Download and verify checksum
    checksum_url=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest \
        | grep browser_download_url | cut -d\" -f4 | grep .sha512sum)
    checksum_name=$(basename "$checksum_url")
    echo "Downloading checksum $checksum_name..."
    curl -L "$checksum_url" -o "$checksum_name" --no-progress-meter

    echo "Verifying checksum..."
    sha512sum -c "$checksum_name"

    # Extract to Steam compatibility tools
    mkdir -p ~/.steam/steam/compatibilitytools.d
    echo "Extracting to Steam compatibility tools folder..."
    tar -xf "$tarball_name" -C ~/.steam/steam/compatibilitytools.d/

    # Clean up
    cd ~
    rm -rf "$PROTON_TMP"

    echo "GE-Proton installed. Restart Steam and enable it under Settings → Compatibility."

fi

if [ "$RUN_FULL" = true ]; then
    sudo dnf clean all
    echo ""
    echo "Setup complete. Please REBOOT now to enroll the MOK key and activate drivers."
fi