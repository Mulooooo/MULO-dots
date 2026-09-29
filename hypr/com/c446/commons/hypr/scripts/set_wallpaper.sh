#!/usr/bin/env bash
# Dispatch wallpaper selection to the theme selected by theme-switch.sh.
set -euo pipefail

STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/c446-theme"
WALLPAPER_STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/c446-wallpaper-slot"
THEME_DIR="$(cat "$STATE_FILE" 2>/dev/null || true)"
[ -n "$THEME_DIR" ] || { echo "❌ no active c446 theme" >&2; exit 1; }
WALLPAPER_DIR="$THEME_DIR"
if [ ! -f "$WALLPAPER_DIR/hypr/scripts/set_wallpaper.sh" ]; then
    wallpaper_theme="$(sed -n 's/^[[:space:]]*wallpaper_theme[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$THEME_DIR/theme.toml" 2>/dev/null | head -n1)"
    if [ -n "$wallpaper_theme" ]; then
        WALLPAPER_DIR="$(dirname "$THEME_DIR")/$wallpaper_theme"
    fi
fi
WALLPAPER_SCRIPT="$WALLPAPER_DIR/hypr/scripts/set_wallpaper.sh"
[ -f "$WALLPAPER_SCRIPT" ] || { echo "❌ no wallpaper setter for active theme: $THEME_DIR" >&2; exit 1; }

slot="${1:-}"
if [ -z "$slot" ]; then
    slot="$(cat "$WALLPAPER_STATE_FILE" 2>/dev/null || true)"
    slot="${slot:-1}"
fi

case "$slot" in
    1|2|3|4|5|6|7|8|9|10) ;;
    *) echo "❌ wallpaper slot must be 1-10" >&2; exit 2 ;;
esac

target_monitor=""
case "${2:-}" in
    "") ;;
    --focused)
        target_monitor="$(hyprctl -j activeworkspace | jq -er '.monitor')" || {
            echo "❌ could not determine the focused workspace monitor" >&2
            exit 1
        }
        hyprctl -j monitors | jq -e --arg monitor "$target_monitor" 'any(.[]; .name == $monitor)' >/dev/null || {
            echo "❌ focused workspace monitor is not active: $target_monitor" >&2
            exit 1
        }
        ;;
    *) echo "❌ usage: set_wallpaper.sh [1-10] [--focused]" >&2; exit 2 ;;
esac

theme_args=("$slot")
if [ -n "$target_monitor" ]; then
    theme_args+=("$target_monitor")
fi

if "$WALLPAPER_SCRIPT" "${theme_args[@]}"; then
    mkdir -p "$(dirname "$WALLPAPER_STATE_FILE")"
    printf '%s\n' "$slot" > "$WALLPAPER_STATE_FILE"
else
    exit $?
fi
