#!/usr/bin/env bash
# Manifest-driven GTK/icon/cursor theme applier.
# Reads values from the active theme's theme.toml.
#
# Usage:
#   apply-theme.sh [/path/to/theme.toml]
# If no argument is given, the path stored in ~/.cache/c446-theme is used
# (written by theme-switch.sh), then theme.toml inside that dir.

set -euo pipefail

STATE_FILE="$HOME/.cache/c446-theme"

resolve_manifest() {
    if [ "${1:-}" != "" ]; then
        echo "$1"; return
    fi
    if [ -f "$STATE_FILE" ]; then
        echo "$(cat "$STATE_FILE")/theme.toml"; return
    fi
    echo "❌ No theme manifest given and no active theme recorded ($STATE_FILE)." >&2
    exit 1
}

# Minimal TOML reader for simple `key = "value"` lines.
toml_get() {
    local key="$1" file="$2"
    sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"\?\([^\"]*\)\"\?[[:space:]]*$/\1/p" "$file" | head -n1
}

MANIFEST="$(resolve_manifest "${1:-}")"
[ -f "$MANIFEST" ] || { echo "❌ Manifest not found: $MANIFEST" >&2; exit 1; }

GTK_THEME="$(toml_get gtk_theme   "$MANIFEST")"
ICON_THEME="$(toml_get icon_theme "$MANIFEST")"
CURS="$(toml_get cursor           "$MANIFEST")"
CURS_SIZE="$(toml_get cursor_size "$MANIFEST")"; CURS_SIZE="${CURS_SIZE:-24}"
FONT="$(toml_get font             "$MANIFEST")"

apply_gsettings() {
    local SCHEMA="org.gnome.desktop.interface"
    gsettings set "$SCHEMA" gtk-theme    "$GTK_THEME"
    gsettings set "$SCHEMA" icon-theme   "$ICON_THEME"
    gsettings set "$SCHEMA" cursor-theme "$CURS"
    gsettings set "$SCHEMA" font-name    "$FONT"
    gsettings set "$SCHEMA" color-scheme 'prefer-dark'
}

apply_hypr_cursor() {
    command -v hyprctl >/dev/null 2>&1 && hyprctl setcursor "$CURS" "$CURS_SIZE" || true
}

apply_gsettings
apply_hypr_cursor
echo "✅ Applied GTK/icons/cursor from $(basename "$(dirname "$MANIFEST")")"
