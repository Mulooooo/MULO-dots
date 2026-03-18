#!/usr/bin/env sh
# File path for our temporary override
GAMEMODE_CONF="/tmp/hypr_gamemode.conf"
HYPRGAMEMODE=$(hyprctl getoption animations:enabled | awk 'NR==1{print $2}')
if [ "$HYPRGAMEMODE" = 1 ] ; then
    # 1. Create a temporary config file with our overrides
    # Using new windowrule syntax
    cat <<EOF > "$GAMEMODE_CONF"
animations {
    enabled = 0
}
decoration {
    shadow {
        enabled = false
    }
    blur {
        enabled = false
    }
}
general {
    gaps_in = 0
    gaps_out = 0
    border_size = 1
}
# This forces EVERYTHING to be 100% opaque and kills blur for VRR
windowrule = opacity 1 override 1 override 1 override, match:class ^(.*)$
windowrule = no_blur on, match:class ^(.*)$
EOF
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
    systemctl start platform-profile@balanced.service
    notify-send "Gamemode Disabled" "Enabling Balanced-Performance profile." -i display
fi