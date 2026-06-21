#!/usr/bin/env bash

# Constants
THEME="oomox-Gigavolt"
ICONS="Yaru-prussiangreen"
CURS="Vivian-Cursors"
FONT="MesloLGL Nerd Font Mono 20"

# Apply via GSettings
apply_gsettings() {
    local SCHEMA="org.gnome.desktop.interface"
    gsettings set "$SCHEMA" gtk-theme "$THEME"
    gsettings set "$SCHEMA" icon-theme "$ICONS"
    gsettings set "$SCHEMA" cursor-theme "$CURS"
    gsettings set "$SCHEMA" font-name "$FONT"
    gsettings set "$SCHEMA" color-scheme 'prefer-dark'
}

# Fix for Hyprland cursor loading
apply_hypr_cursor() {
    hyprctl setcursor "$CURS" 24
}

apply_gsettings
apply_hypr_cursor