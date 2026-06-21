#!/bin/bash
# THEME: miyabi — wallpaper switcher (Terafox). Single wallpaper set.

BG_DIR="$HOME/Pictures"
PRIMARY="eDP-1"
SECONDARY="HDMI-A-1"
WIN_BG="$BG_DIR/miyabi_bg_1.jpeg"

# All slots map to the miyabi wallpaper (add entries here as you add wallpapers)
case $1 in
    1|2|3|4|5|6|7|8|9) FILE="miyabi_bg_1.jpeg" ;;
    *) exit 1 ;;
esac

TARGET="$BG_DIR/$FILE"

# Ensure swww-daemon is alive
if ! pgrep -x "swww-daemon" > /dev/null; then
    swww-daemon &
    sleep 0.5
fi

# Secondary monitor (persistent)
swww img -o "$SECONDARY" "$WIN_BG" --transition-type none

# Primary monitor
pkill mpvpaper
swww img -o "$PRIMARY" "$TARGET" --transition-type wipe --transition-step 255 --transition-fps 240
