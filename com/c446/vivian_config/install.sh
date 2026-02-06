#!/bin/bash

read -p "Enter your username: " USR

THEME_DIR="/home/$USR/.local/share/themes"
USER_HOME="/home/$USR"

# Make sure directories exist
mkdir -p "$THEME_DIR"
mkdir -p "$USER_HOME/.config/gtk-3.0"
mkdir -p "$USER_HOME/.config/picom"
mkdir -p "$USER_HOME/.config/i3"
mkdir -p "$USER_HOME/.config/kitty"
mkdir -p "$USER_HOME/.config/fastfetch"
mkdir -p "$USER_HOME/.config/polybar"
mkdir -p "$USER_HOME/.icons"
mkdir -p "$USER_HOME/Pictures"

# Copy polybar config (likely you want to copy TO /etc, not from it)
sudo cp ./polybar/config.ini /etc/polybar/config.ini
# sudo cp /etc/polybar/config.ini ./polybar/  # if you really want to copy from /etc → ./polybar/

# Unzip theme
sudo unzip ./themes/Arc-Darkest-Tangerine-2.2.3.zip -d /usr/share/themes/

# GTK settings
cp ./themes/settings.ini "$USER_HOME/.config/gtk-3.0/settings.ini"

# picom
cp ./picom/picom.conf "$USER_HOME/.config/picom/picom.conf"

# i3 configs
cp ./i3/* "$USER_HOME/.config/i3/"

# Kitty configs
cp ./kitty/* "$USER_HOME/.config/kitty/"

# Images
cp ./themes/*.png "$USER_HOME/Pictures/"

# Cursor theme (must be recursive!)
cp -r ./Vivian-Cursors/ "$USER_HOME/.icons/"

# Fastfetch
cp ./fastfetch/* "$USER_HOME/.config/fastfetch/"

# Polybar configs
cp ./polybar/* "$USER_HOME/.config/polybar/"
