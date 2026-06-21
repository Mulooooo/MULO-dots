#!/usr/bin/env bash
# cycle-hdmi-mode.sh — step through the modes HDMI-A-1 actually advertises.
#
# If the projector is dark or shows a garbled/unsupported picture, tap the
# bound key (SUPER+P) repeatedly: each press applies the next available mode
# and shows a notification with what is now active. Stop when the image looks
# right. State (current index) is kept in /tmp so presses advance in order.

set -uo pipefail

HDMI="HDMI-A-1"
POS="-1924x0"
SCALE="1"
STATE="/tmp/hypr-hdmi-mode-idx"

notify() { command -v notify-send >/dev/null && notify-send "Projector mode" "$1"; }

# Read the modes the projector reports (e.g. "1920x1080@60.00Hz").
mapfile -t MODES < <(hyprctl -j monitors all \
    | jq -r --arg m "$HDMI" '.[] | select(.name==$m) | .availableModes[]')

if [[ ${#MODES[@]} -eq 0 ]]; then
    notify "$HDMI: no modes (not connected?)"
    exit 1
fi

# Advance the saved index (wraps around).
idx=0
[[ -f "$STATE" ]] && idx=$(<"$STATE")
idx=$(( (idx + 1) % ${#MODES[@]} ))
echo "$idx" > "$STATE"

mode="${MODES[$idx]}"
# Strip the trailing "Hz" — hyprctl wants e.g. 1920x1080@60.00
mode="${mode%Hz}"

echo "Applying $HDMI -> $mode  ($((idx+1))/${#MODES[@]})"
if hyprctl keyword monitor "$HDMI,$mode,$POS,$SCALE"; then
    notify "$((idx+1))/${#MODES[@]}: $mode"
else
    notify "Failed: $mode"
fi
