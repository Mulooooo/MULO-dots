#!/bin/bash
# THEME: miyabi — wallpaper switcher (Terafox). Uses awww (swww fork).

BG_DIR="$HOME/Pictures/Backgrounds"
PRIMARY="eDP-1"
SECONDARY="HDMI-A-1"
WIN_BG="$BG_DIR/bg_win.jpg"

# Slot 1 is always bg_win; the rest map to miyabi wallpapers.
case $1 in
    1) FILE="bg_win.jpg" ;;
    2|3|4|5|6|7|8|9) FILE="miyabi_bg_1.jpeg" ;;
    *) exit 1 ;;
esac

TARGET="$BG_DIR/$FILE"

# Ensure the daemon is alive
if ! pgrep -x "awww-daemon" > /dev/null; then
    awww-daemon &
    sleep 0.5
fi

# Secondary monitor keeps the windows bg persistently
awww img -o "$SECONDARY" "$WIN_BG" --transition-type none

# Primary monitor
if [[ "$FILE" == *.mp4 ]]; then
    pkill mpvpaper
    mpvpaper -o "no-audio --loop --vf=scale=iw:-1,pad=iw:ih:(ow-iw)/2:(oh-ih)/2 --panscan=1.0" "$PRIMARY" "$TARGET" &
else
    pkill mpvpaper
    awww img -o "$PRIMARY" "$TARGET" --transition-type wipe --transition-step 255 --transition-fps 240
fi
