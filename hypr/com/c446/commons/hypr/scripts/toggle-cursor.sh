#!/usr/bin/env bash
# Dispatch cursor selection to the theme selected by theme-switch.sh.
set -euo pipefail

STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/c446-theme"
THEME_DIR="$(cat "$STATE_FILE" 2>/dev/null || true)"
[ -n "$THEME_DIR" ] || { echo "❌ no active c446 theme" >&2; exit 1; }
exec "$THEME_DIR/hypr/scripts/toggle-cursor.sh" "$@"
