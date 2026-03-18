#!/usr/bin/env bash

# Exit on error
set -e

# --- Environment Setup ---
# If HOME is not already redirected by our launcher script, 
# we default to /tmp/rice_sandbox
SANDBOX_HOME="${HOME:-/tmp/rice_sandbox}"
CONFIG_DIR="$SANDBOX_HOME/.config"
ICON_DIR="$SANDBOX_HOME/.icons"
THEME_DIR="$SANDBOX_HOME/.local/share/themes"

echo "--- 🛠️ SANDBOX INSTALL STARTING ---"
echo "Targeting: $SANDBOX_HOME"

# 1. Create directory structure (All inside Sandbox)
mkdir -p "$CONFIG_DIR"/{gtk-3.0,picom,i3,kitty,fastfetch,polybar,rofi,fish,vesktop/themes/assets}
mkdir -p "$ICON_DIR/default"
mkdir -p "$THEME_DIR"
mkdir -p "$SANDBOX_HOME/Pictures"

# 2. GTK & Themes
# We install themes locally to ~/.local/share/themes to avoid 'sudo'
cp ./gtk/settings.ini "$CONFIG_DIR/gtk-3.0/settings.ini"
unzip -q -o ./gtk/gtk_themes.zip -d "$THEME_DIR/"
unzip -q -o ./gtk/Vivian-Cursors.zip -d "$ICON_DIR/"

# 3. Copy Configurations
cp ./i3/* "$CONFIG_DIR/i3/"
cp ./picom/picom.conf "$CONFIG_DIR/picom/picom.conf"
cp ./kitty/* "$CONFIG_DIR/kitty/"
cp ./polybar/config.ini "$CONFIG_DIR/polybar/config.ini"
cp ./fastfetch/config.jsonc "$CONFIG_DIR/fastfetch/config.jsonc"
cp ./fish/config.fish "$CONFIG_DIR/fish/config.fish"
cp ./rofi/config.rasi "$CONFIG_DIR/rofi/config.rasi"
cp -r ./rofi/themes "$CONFIG_DIR/rofi/"
cp ./vesktop/themes/sys-24-vivian.css "$CONFIG_DIR/vesktop/themes/"
cp ./vesktop/themes/assets/* "$CONFIG_DIR/vesktop/themes/assets/"
cp -r ./assets/Pictures/* "$SANDBOX_HOME/Pictures/"
cp ./X/index.theme "$ICON_DIR/default/index.theme"

# 4. The Path Fixer (CRITICAL FOR SANDBOX)
# This searches all config files and replaces your old home with the sandbox home
echo "Adjusting internal config paths..."
find "$CONFIG_DIR" -type f -exec sed -i "s|/home/clement|$SANDBOX_HOME|g" {} +

# 5. Fix Script Permissions
find "$CONFIG_DIR/i3/" -name "*.sh" -exec chmod +x {} +

echo "--- ✅ SANDBOX PREP COMPLETE ---"