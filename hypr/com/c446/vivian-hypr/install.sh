#!/usr/bin/env bash

set -e

read -p "Enter your username: " USR

USER_HOME="/home/$USR"
CONFIG_DIR="$USER_HOME/.config"
ICON_DIR="$USER_HOME/.icons"

echo "Installing configuration for $USR..."

# Create required directories

mkdir -p "$CONFIG_DIR"/{gtk-3.0,picom,i3,kitty,fastfetch,polybar,rofi,fish,vesktop/themes}
mkdir -p "$ICON_DIR/default"
mkdir -p "$USER_HOME/Pictures"

# -------------------------

# GTK

# -------------------------

cp ./gtk/settings.ini "$CONFIG_DIR/gtk-3.0/settings.ini"

# install GTK themes system-wide

sudo mkdir -p /usr/share/themes
sudo unzip -o ./gtk/gtk_themes.zip -d /usr/share/themes/

# install cursor theme

unzip -o ./gtk/Vivian-Cursors.zip -d "$ICON_DIR/"

# -------------------------

# i3

# -------------------------

cp ./i3/* "$CONFIG_DIR/i3/"

# -------------------------

# Picom

# -------------------------

cp ./picom/picom.conf "$CONFIG_DIR/picom/picom.conf"

# -------------------------

# Kitty

# -------------------------

cp ./kitty/* "$CONFIG_DIR/kitty/"

KITTY_CONFIG="$CONFIG_DIR/kitty/kitty.conf"
sed -i "s|/home/clement|$USER_HOME|g" "$KITTY_CONFIG"

# -------------------------

# Polybar

# -------------------------

cp ./polybar/config.ini "$CONFIG_DIR/polybar/config.ini"

# -------------------------

# Fastfetch

# -------------------------

cp ./fastfetch/config.jsonc "$CONFIG_DIR/fastfetch/config.jsonc"

# -------------------------

# Fish

# -------------------------

cp ./fish/config.fish "$CONFIG_DIR/fish/config.fish"

# -------------------------

# Rofi

# -------------------------

cp ./rofi/config.rasi "$CONFIG_DIR/rofi/config.rasi"
cp -r ./rofi/themes "$CONFIG_DIR/rofi/"

ROFI_CONFIG="$CONFIG_DIR/rofi/config.rasi"
ROFI_THEME="$CONFIG_DIR/rofi/themes/material.rasi"

# Replace /home/users with /home/clement
sed -i "s|/home/clement|$USER_HOME|g" "$ROFI_CONFIG"

# -------------------------

# Vesktop

# -------------------------

cp ./vesktop/themes/sys-24-vivian.css "$CONFIG_DIR/vesktop/themes/"
mkdir -p "$CONFIG_DIR/vesktop/themes/assets"
cp ./vesktop/themes/assets/* "$CONFIG_DIR/vesktop/themes/assets/"

# -------------------------

# Wallpapers

# -------------------------

cp -r ./assets/Pictures/* "$USER_HOME/Pictures/"

# -------------------------

# Cursor default theme

# -------------------------

cp ./X/index.theme "$ICON_DIR/default/index.theme"

# Fix permissions

chown -R "$USR:$USR" "$USER_HOME/.config"
chown -R "$USR:$USR" "$ICON_DIR"
chown -R "$USR:$USR" "$USER_HOME/Pictures"

echo "Installation complete!"
