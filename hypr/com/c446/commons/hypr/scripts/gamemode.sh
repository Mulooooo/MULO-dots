#!/usr/bin/env sh
# Toggle "gamemode": strip visual effects + switch to the performance profile.
#
# State is derived from animations:enabled. On enable we turn effects off via
# `hyprctl --batch` (no temp file to write/source/clean up); on disable we
# `hyprctl reload` to restore the committed config. This is what makes the
# toggle work back & forth: the enable branch actually flips animations to 0,
# so the next press is detected as the disable branch.

SCRIPT_DIR=$(dirname "$0")
ANIMATIONS=$(hyprctl getoption animations:enabled | awk 'NR==1{print $2}')
DUNST_ID=2002  # fixed replace id so toggling updates one dunst notification

if [ "$ANIMATIONS" = 1 ]; then
    # --- Enable gamemode ---
    hyprctl --batch "\
        keyword animations:enabled 0;\
        keyword decoration:blur:enabled 0;\
        keyword decoration:shadow:enabled 0;\
        keyword decoration:rounding 0;\
        keyword general:gaps_in 0;\
        keyword general:gaps_out 0"
    "$SCRIPT_DIR/set-power-profile.sh" performance --silent
    dunstify -a Gamemode -r "$DUNST_ID" -u normal -i controller \
        "Gamemode Enabled" "Effects off · Performance profile"
else
    # --- Disable gamemode ---
    hyprctl reload
    "$SCRIPT_DIR/set-power-profile.sh" balanced --silent
    dunstify -a Gamemode -r "$DUNST_ID" -u normal -i display \
        "Gamemode Disabled" "Effects restored · Balanced profile"
fi
