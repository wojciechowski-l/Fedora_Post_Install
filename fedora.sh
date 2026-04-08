#!/bin/bash
set -e

# USAGE

usage() {
    echo "Usage: $0 [option]"
    echo ""
    echo "  full      - Run complete system setup (default if no argument given)"
    echo "  aseprite  - Build and install Aseprite only"
    echo "  proton-ge - Install latest GE-Proton for Steam only"
    exit 1
}

case "${1:-full}" in
    full)      RUN_FULL=true  ; RUN_ASEPRITE=true  ; RUN_PROTON_GE=true  ;;
    aseprite)  RUN_FULL=false ; RUN_ASEPRITE=true  ; RUN_PROTON_GE=false ;;
    proton-ge) RUN_FULL=false ; RUN_ASEPRITE=false ; RUN_PROTON_GE=true  ;;
    *) usage ;;
esac

# FULL SETUP

if [ "$RUN_FULL" = true ]; then

    # 1. Repositories
    sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
        https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
    sudo dnf install -y rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted

    # 2. Secure Boot Support (DO THIS BEFORE NVIDIA)
    sudo dnf install -y kmodtool akmods mokutil openssl
    sudo kmodgenca -a
    sudo mokutil --import /etc/pki/akmods/certs/public_key.der
    # NOTE: Pick a password (e.g., '1234') to enter on the MOK blue screen after reboot.

    # 3. Core Desktop & Apps
    sudo dnf install -y plasma-desktop kwin sddm sddm-kcm plasma-nm plasma-pa bluedevil powerdevil \
        kscreen plasma-workspace polkit-kde xdg-desktop-portal-kde kde-gtk-config breeze-gtk \
        systemsettings dolphin konsole ark git unrar firefox steam discord vlc keepassxc lutris \
        gnome-terminal man-pages rsync irqbalance dotnet-sdk-10.0 btop krita blender \
        p7zip p7zip-plugins \
        fwupd power-profiles-daemon \
        kmod-v4l2loopback obs-studio obs-studio-plugin-vlc-video obs-studio-plugin-vkcapture \
        obs-studio-plugin-webkitgtk obs-studio-plugin-x264

    # 4. Nvidia & Intel Drivers
    sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-cuda-libs \
        nvidia-vaapi-driver nvidia-settings intel-media-driver libva-utils vdpauinfo \
        thermald vulkan-tools vulkan-intel intel-compute-runtime onevpl-intel-gpu
    sudo dnf mark user akmod-nvidia

    # 5. Multimedia Codecs
    sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
    sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
    sudo dnf group install -y multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
    sudo dnf install -y libavcodec-freeworld x264 x265 --allowerasing
    sudo dnf install -y gstreamer1-vaapi dav1d flac gstreamer1-plugins-bad

    # 6. VS Code
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
    sudo dnf install -y code

    # 7. Docker Desktop Install
    sudo dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
    curl -O https://desktop.docker.com/linux/main/amd64/docker-desktop-x86_64.rpm
    sudo dnf install -y ./docker-desktop-x86_64.rpm
    rm docker-desktop-x86_64.rpm

    # 8. Unity Hub
    sudo sh -c 'echo -e "[unityhub]\nname=Unity Hub\nbaseurl=https://hub.unity3d.com/linux/repos/rpm/stable\nenabled=1\ngpgcheck=1\ngpgkey=https://hub.unity3d.com/linux/repos/rpm/stable/repodata/repomd.xml.key\nrepo_gpgcheck=1" > /etc/yum.repos.d/unityhub.repo'
    sudo dnf install -y unityhub

    # 9. PowerShell

    source /etc/os-release
    fedora_ver=$VERSION_ID

    curl -sSL -O https://packages.microsoft.com/config/fedora/$fedora_ver/packages-microsoft-prod.rpm

    sudo rpm -i packages-microsoft-prod.rpm

    rm packages-microsoft-prod.rpm

    sudo dnf update
    sudo dnf install powershell -y

    # 10. ONLYOFFICE Desktop Editors
    sudo dnf install -y cabextract xorg-x11-font-utils fontconfig
    sudo rpm -i --nodigest https://sourceforge.net/projects/mscorefonts2/files/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm || true
    curl -L https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors.x86_64.rpm \
        -o /tmp/onlyoffice-desktopeditors.rpm
    sudo dnf install -y /tmp/onlyoffice-desktopeditors.rpm
    rm /tmp/onlyoffice-desktopeditors.rpm

    # 11. Triggering and Waiting for akmod build
    echo "Starting Nvidia kernel module build..."
    sudo akmods --force
    echo "Nvidia module build complete!"

    # 12. Final Services & Boot Config
    sudo usermod -aG docker $USER
    sudo systemctl set-default graphical.target
    sudo systemctl enable sddm
    sudo systemctl enable --now thermald
    sudo systemctl enable --now power-profiles-daemon
    sudo localectl set-locale \
        LANG=en_US.UTF-8 \
        LC_NUMERIC=C \
        LC_TIME=C \
        LC_MONETARY=C \
        LC_MEASUREMENT=C \
        LC_PAPER=C

    # 13. Kernel Parameters
    sudo grubby --update-kernel=ALL \
        --args="mem_sleep_default=deep intel_pstate=active intel_iommu=on"

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