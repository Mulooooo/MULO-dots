#!/usr/bin/env bash
# start-hdmi.sh — force HDMI-A-1 (projector) to turn on and render.
#
# Use this before a presentation if the projector is plugged in but stays dark.
# It re-enables the output and applies a mode the projector actually advertises,
# preferring its native/preferred mode and falling back to safe modes if needed.
#
# Run manually:  ~/.config/hypr/scripts/start-hdmi.sh
# (or bound to a key — see binds.conf)

set -uo pipefail

HDMI="HDMI-A-1"
POS="-1924x0"   # just left of the scaled eDP-1 (2560x1600 @ 1.33)
SCALE="1"

notify() { command -v notify-send >/dev/null && notify-send "Projector" "$1"; }

# Is the monitor present at all?
if ! hyprctl -j monitors all | jq -e --arg m "$HDMI" '.[] | select(.name==$m)' >/dev/null; then
    notify "$HDMI not detected — check the cable."
    echo "$HDMI not detected. Connected outputs:"
    hyprctl -j monitors all | jq -r '.[].name'
    exit 1
fi

# Try preferred first, then a list of conservative fallbacks every projector supports.
CANDIDATES=(
    "preferred"
    "1920x1080@60"
    "1280x800@60"
    "1280x720@60"
    "1024x768@60"
    "highrr"
)

for mode in "${CANDIDATES[@]}"; do
    echo "Trying $HDMI -> $mode"
    if hyprctl keyword monitor "$HDMI,$mode,$POS,$SCALE"; then
        sleep 0.5
        # Confirm it actually came up (non-zero resolution).
        active=$(hyprctl -j monitors | jq -r --arg m "$HDMI" \
            '.[] | select(.name==$m) | "\(.width)x\(.height)@\(.refreshRate)"')
        if [[ -n "$active" && "$active" != "0x0"* ]]; then
            notify "$HDMI on: $active"
            echo "Active: $active"
            exit 0
        fi
    fi
done

notify "$HDMI failed to come up — try SUPER+P to cycle modes."
echo "Could not bring up $HDMI. Available modes:"
hyprctl -j monitors all | jq -r --arg m "$HDMI" '.[] | select(.name==$m) | .availableModes[]'
exit 1
