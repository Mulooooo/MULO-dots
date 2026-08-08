#!/usr/bin/env bash

set -euo pipefail

readonly SINK='@DEFAULT_SINK@'

pactl set-sink-mute "$SINK" toggle

mute_state="$(pactl get-sink-mute "$SINK" | awk -F': ' '/Mute:/ { print $2; exit }')"

case "$mute_state" in
    yes)
        notify-send -a "mute" "Muted 🔇" "System audio muted" 2>/dev/null || true
        ;;
    no)
        notify-send -a "mute" "Unmuted 🔊" "System audio unmuted" 2>/dev/null || true
        ;;
    *)
        notify-send -a "mute" "Mute state unavailable" "Could not determine system audio state" 2>/dev/null || true
        exit 1
        ;;
esac
