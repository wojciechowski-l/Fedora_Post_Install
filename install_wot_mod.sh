#!/bin/bash

# Configuration
WOT_APPID="1407200"
WOT_REAL_PATH="$HOME/.local/share/Steam/steamapps/common/World of Tanks"
WOT_PREFIX="$HOME/.steam/steam/steamapps/compatdata/$WOT_APPID/pfx"
TEMP_LINK="$HOME/Downloads/WoT_Game_Link"

# Check if an installer was provided
if [ -z "$1" ]; then
    echo "Usage: ./install_wot_mod.sh /path/to/installer.exe"
    exit 1
fi

INSTALLER_PATH=$(realpath "$1")

# 1. Create temporary symlink so the Wine file picker can see the game
echo "Creating temporary link at $TEMP_LINK..."
ln -sfn "$WOT_REAL_PATH" "$TEMP_LINK"

# 2. Run the installer with the correct prefix
echo "Launching installer for AppID $WOT_APPID..."
export WINEPREFIX="$WOT_PREFIX"
export WINEDEBUG=-all
wine "$INSTALLER_PATH"

# 3. Cleanup after the installer closes
echo "Cleaning up temporary link..."
rm "$TEMP_LINK"

echo "Done."
