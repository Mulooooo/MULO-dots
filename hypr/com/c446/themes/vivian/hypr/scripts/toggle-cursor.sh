#!/usr/bin/env bash
# Theme-specific cursor toggler for Hyprland.
#
# Lives in themes/<theme>/hypr/scripts/ and derives its theme from its own
# location, so the same script works for every theme. It reads the `cursor`
# (main) and `cursor_secondary` cursors from this theme's theme.toml, toggles
# between them, rewrites this theme's hypr/theme.lua, and applies live.
#
# Usage: toggle-cursor.sh [main|secondary|toggle|status]
#   main      - switch to the theme's main cursor
#   secondary - switch to the theme's secondary cursor
#   toggle    - flip between the two (default)
#   status    - print the current/main/secondary cursors

set -euo pipefail

# Resolve through the active/ symlink so we land in the real themes/<theme> dir.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
THEME_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"   # themes/<theme>
THEME_TOML="$THEME_DIR/theme.toml"
THEME_LUA="$THEME_DIR/hypr/theme.lua"

[ -f "$THEME_TOML" ] || { echo "❌ theme.toml not found: $THEME_TOML" >&2; exit 1; }
[ -f "$THEME_LUA" ] || { echo "❌ theme.lua not found: $THEME_LUA" >&2; exit 1; }

# Minimal TOML reader for simple `key = "value"` lines (matches apply-theme.sh).
toml_get() {
    local key="$1" file="$2"
    sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"\?\([^\"]*\)\"\?[[:space:]]*$/\1/p" "$file" | head -n1
}

MAIN="$(toml_get cursor           "$THEME_TOML")"
SECONDARY="$(toml_get cursor_secondary "$THEME_TOML")"
SIZE="$(toml_get cursor_size      "$THEME_TOML")"; SIZE="${SIZE:-24}"

[ -n "$MAIN" ]      || { echo "❌ 'cursor' not set in $THEME_TOML" >&2; exit 1; }
[ -n "$SECONDARY" ] || { echo "❌ 'cursor_secondary' not set in $THEME_TOML" >&2; exit 1; }

get_current_cursor() {
    grep 'hl.env("HYPRCURSOR_THEME"' "$THEME_LUA" | sed 's/.*,[[:space:]]*"\([^"]*\)".*/\1/'
}

set_cursor_in_lua() {
    local theme=$1 size=${2:-$SIZE}
    sed -i "s/hl.env(\"HYPRCURSOR_THEME\",.*/hl.env(\"HYPRCURSOR_THEME\", \"$theme\")/" "$THEME_LUA"
    sed -i "s/hl.env(\"XCURSOR_THEME\",.*/hl.env(\"XCURSOR_THEME\", \"$theme\")/"       "$THEME_LUA"
    sed -i "s/hl.env(\"HYPRCURSOR_SIZE\",.*/hl.env(\"HYPRCURSOR_SIZE\", \"$size\")/"   "$THEME_LUA"
    sed -i "s/hl.env(\"XCURSOR_SIZE\",.*/hl.env(\"XCURSOR_SIZE\", \"$size\")/"         "$THEME_LUA"
}

apply_cursor_live() {
    local theme=$1 size=${2:-$SIZE}
    command -v hyprctl   >/dev/null 2>&1 && hyprctl setcursor "$theme" "$size" >/dev/null 2>&1 || true
    command -v gsettings >/dev/null 2>&1 && \
        gsettings set org.gnome.desktop.interface cursor-theme "$theme" >/dev/null 2>&1 || true
}

notify_cursor_change() {
    command -v notify-send >/dev/null 2>&1 && \
        notify-send "Cursor Theme" "Switched to $1" -u low || true
}

current="$(get_current_cursor)"

case "${1:-toggle}" in
    main)      target="$MAIN" ;;
    secondary) target="$SECONDARY" ;;
    toggle|"")
        if [[ "$current" == "$MAIN" ]]; then target="$SECONDARY"; else target="$MAIN"; fi
        ;;
    status)
        echo "Theme:     $(basename "$THEME_DIR")"
        echo "Current:   $current"
        echo "Main:      $MAIN"
        echo "Secondary: $SECONDARY"
        exit 0
        ;;
    *)
        echo "Usage: $0 [main|secondary|toggle|status]"
        exit 1
        ;;
esac

if [[ "$current" == "$target" ]]; then
    echo "Already using $target"
    exit 0
fi

echo "Switching cursor from $current to $target..."
set_cursor_in_lua "$target"
apply_cursor_live "$target"
notify_cursor_change "$target"
echo "✅ Cursor switched to $target (size $SIZE) for theme $(basename "$THEME_DIR")"
echo "   (theme.lua updated; takes full effect on next hyprctl reload)"
