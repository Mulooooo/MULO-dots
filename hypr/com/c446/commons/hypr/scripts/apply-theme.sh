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

# Upsert a `key=value` line (gtk-3.0/4.0 settings.ini, [Settings] section).
upsert_ini() { # file key value
    local f="$1" k="$2" v="$3"
    [ -f "$f" ] || { mkdir -p "$(dirname "$f")"; printf '[Settings]\n' > "$f"; }
    if grep -q "^${k}=" "$f"; then
        sed -i "s|^${k}=.*|${k}=${v}|" "$f"
    elif grep -q '^\[Settings\]' "$f"; then
        sed -i "/^\[Settings\]/a ${k}=${v}" "$f"
    else
        printf '%s=%s\n' "$k" "$v" >> "$f"
    fi
}

# Upsert a quoted `gtk-key="value"` line (~/.gtkrc-2.0). Numeric size stays unquoted.
upsert_gtkrc() { # file key value quoted(0|1)
    local f="$1" k="$2" v="$3" q="$4" line
    [ -f "$f" ] || touch "$f"
    [ "$q" = 1 ] && line="${k}=\"${v}\"" || line="${k}=${v}"
    if grep -q "^${k}=" "$f"; then
        sed -i "s|^${k}=.*|${line}|" "$f"
    else
        printf '%s\n' "$line" >> "$f"
    fi
}

# Many GTK apps (incl. Electron/Spotify on Xwayland) read settings.ini / gtkrc
# directly and ignore gsettings, so keep all of them in sync with the theme.
apply_gtk_files() {
    for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
        upsert_ini "$f" gtk-cursor-theme-name "$CURS"
        upsert_ini "$f" gtk-cursor-theme-size "$CURS_SIZE"
        upsert_ini "$f" gtk-theme-name        "$GTK_THEME"
        upsert_ini "$f" gtk-icon-theme-name   "$ICON_THEME"
    done
    local rc="$HOME/.gtkrc-2.0"
    upsert_gtkrc "$rc" gtk-cursor-theme-name "$CURS"       1
    upsert_gtkrc "$rc" gtk-cursor-theme-size "$CURS_SIZE"  0
    upsert_gtkrc "$rc" gtk-theme-name        "$GTK_THEME"  1
    upsert_gtkrc "$rc" gtk-icon-theme-name   "$ICON_THEME" 1
}

apply_hypr_cursor() {
    command -v hyprctl >/dev/null 2>&1 || return 0
    hyprctl setcursor "$CURS" "$CURS_SIZE" >/dev/null 2>&1 || true
    # Update session env so newly launched (Xwayland) apps inherit the right cursor
    hyprctl keyword env "XCURSOR_THEME,$CURS" >/dev/null 2>&1 || true
    hyprctl keyword env "XCURSOR_SIZE,$CURS_SIZE" >/dev/null 2>&1 || true
    if command -v dbus-update-activation-environment >/dev/null 2>&1; then
        XCURSOR_THEME="$CURS" XCURSOR_SIZE="$CURS_SIZE" \
            dbus-update-activation-environment --systemd XCURSOR_THEME XCURSOR_SIZE >/dev/null 2>&1 || true
    fi
}

apply_gsettings
apply_gtk_files
apply_hypr_cursor
echo "✅ Applied GTK/icons/cursor from $(basename "$(dirname "$MANIFEST")")"
