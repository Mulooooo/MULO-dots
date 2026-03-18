#!/bin/bash

BG_DIR="$HOME/Pictures/Backgrounds"
PRIMARY="eDP-1"
SECONDARY="HDMI-A-1"
WIN_BG="$BG_DIR/bg_win.jpg"

# Define the file for the primary monitor based on input
case $1 in
    1) FILE="vivian_bg_1.jpg" ;;
    2) FILE="vivian_bg_2.jpg" ;;
    3) FILE="vivian_bg_3.png" ;;
    4) FILE="vivian_bg_4.png" ;;
    5) FILE="vivian_bg_5.mp4" ;;
    6) FILE="bg_win.jpg";;
    *) exit 1 ;;
esac

TARGET="$BG_DIR/$FILE"

# Ensure swww-daemon is alive
if ! pgrep -x "swww-daemon" > /dev/null; then
    swww-daemon &
    sleep 0.5
fi

# 1. Handle the Secondary Monitor (HDMI-A-1)
# This keeps your "win_bg" persistent on the secondary monitor
swww img -o "$SECONDARY" "$WIN_BG" --transition-type none

# 2. Handle the Primary Monitor (eDP-1)
if [[ "$FILE" == *.mp4 ]]; then
    # Kill mpvpaper only for the primary monitor if you want to keep others
    # Or pkill mpvpaper entirely if you only use it on eDP-1
    pkill mpvpaper 
    
    mpvpaper -o "no-audio --loop --vf=scale=iw:-1,pad=iw:ih:(ow-iw)/2:(oh-ih)/2 --panscan=1.0" "$PRIMARY" "$TARGET" &
else
    # If switching back to an image, kill mpvpaper so the image underneath is visible
    pkill mpvpaper
    swww img -o "$PRIMARY" "$TARGET" --transition-type wipe --transition-step 255 --transition-fps 240
fi