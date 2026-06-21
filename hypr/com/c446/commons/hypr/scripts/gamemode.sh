#!/usr/bin/env sh
# File path for our temporary override
GAMEMODE_CONF="/tmp/hypr_gamemode.conf"
HYPRGAMEMODE=$(hyprctl getoption animations:enabled | awk 'NR==1{print $2}')
if [ "$HYPRGAMEMODE" = 1 ] ; then
    bash ~/.config/hypr/scripts/focus.sh
    # 2. Tell Hyprland to source this file
    killall waybar
    hyprctl keyword source "$GAMEMODE_CONF"
    # 3. Performance Profile
    systemctl start platform-profile@performance.service
    notify-send "Gamemode Enabled" "Enabling Performance profile" -i controller
else
    # 1. Remove the temp file
    rm -f "$GAMEMODE_CONF"
    # 2. Reload the main config to wipe the temporary rules
    hyprctl reload
    waybar &
    # 3. Reset profile
    systemctl start platform-profile@balanced-performance.service
    notify-send "Gamemode Disabled" "Enabling Balanced-Performance profile." -i display
fi
