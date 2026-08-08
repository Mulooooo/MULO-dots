#!/usr/bin/env bash
# Dispatch wallpaper selection to the theme selected by theme-switch.sh.
set -euo pipefail

STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/c446-theme"
THEME_DIR="$(cat "$STATE_FILE" 2>/dev/null || true)"
[ -n "$THEME_DIR" ] || { echo "❌ no active c446 theme" >&2; exit 1; }
case "${1:-}" in
    1|2|3|4|5|6|7|8|9|10) ;;
    *) echo "❌ wallpaper slot must be 1-10" >&2; exit 2 ;;
esac
exec "$THEME_DIR/hypr/scripts/set_wallpaper.sh" "$1"
