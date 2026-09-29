#!/usr/bin/env bash
set -euo pipefail
# THEME: miyabi — wallpaper switcher (Terafox). Uses awww (swww fork).

BG_DIR="$HOME/Pictures/Backgrounds"
PRIMARY="${2:-eDP-1}"
FOCUSED_OUTPUT="${2:-}"
SECONDARY="HDMI-A-1"
WIN_BG="$BG_DIR/bg_win.jpg"
MIYABI_WALLPAPERS=(
    "miyabi_bg_1"
    "miyabi_bg_2"
    "miyabi_bg_3"
    "miyabi_bg_4"
    "miyabi_bg_5"
    "miyabi_bg_6"
)

# Slot 1 is always bg_win; slots 2-10 cycle through all four Miyabi wallpapers.
case "${1:-}" in
    1)     FILE="bg_win.jpg" ;;
    2|3|4|5|6|7|8|9|10)
        INDEX=$((($1 - 2) % ${#MIYABI_WALLPAPERS[@]}))
        PREFIX="${MIYABI_WALLPAPERS[$INDEX]}"
        ;;
    *) exit 1 ;;
esac

if [[ -n "${PREFIX:-}" ]]; then
    FILE=""
    for candidate in "$BG_DIR/$PREFIX".*; do
        if [[ -f "$candidate" ]]; then
            FILE="${candidate##*/}"
            break
        fi
    done
    [[ -n "$FILE" ]] || {
        echo "❌ Miyabi wallpaper not found: $PREFIX.*" >&2
        exit 1
    }
fi

TARGET="$BG_DIR/$FILE"

# Ensure the daemon is alive
if ! pgrep -x "awww-daemon" > /dev/null; then
    awww-daemon &
    sleep 0.5
fi

# Secondary monitor keeps the windows bg persistently when it is connected.
if [[ -z "${2:-}" ]] && hyprctl monitors | grep -q "Monitor $SECONDARY ("; then
    awww img -o "$SECONDARY" "$WIN_BG" --transition-type none
fi

stop_video_wallpaper() {
    if [[ -z "$FOCUSED_OUTPUT" ]]; then
        pkill mpvpaper 2>/dev/null || true
        return
    fi

    local pid
    while IFS= read -r pid; do
        if tr '\0' '\n' < "/proc/$pid/cmdline" | grep -Fxq "$PRIMARY"; then
            kill "$pid" 2>/dev/null || true
        fi
    done < <(pgrep -x mpvpaper || true)
}

stop_video_wallpaper
if [[ "$FILE" == *.mp4 ]]; then
    mpvpaper -o "no-audio --loop --vf=scale=iw:-1,pad=iw:ih:(ow-iw)/2:(oh-ih)/2 --panscan=1.0" "$PRIMARY" "$TARGET" &
else
    awww img -o "$PRIMARY" "$TARGET" --transition-type none
fi
