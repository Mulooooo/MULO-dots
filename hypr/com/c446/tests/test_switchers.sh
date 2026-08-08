#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINDS="$ROOT/commons/hypr/binds.lua"
WORKSPACE_CONFIG="$ROOT/commons/waybar/config"
WORKSPACE_SCRIPT="$ROOT/commons/waybar/workspace.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

grep -Fq '["code:19"] = 10' "$BINDS" \
    || fail 'wallpaper submap must expose the 0 key as wallpaper slot 10'

! grep -Fq 'hl.bind(key, hl.dsp.exec_cmd("~/.config/hypr/scripts/set_wallpaper.sh " .. wallpaper), { repeating = true })' "$BINDS" \
    || fail 'wallpaper selection must not use a repeating bind'

grep -Fq '.socket2.sock' "$WORKSPACE_SCRIPT" \
    || fail 'workspace helper must listen for Hyprland workspace events'

! grep -Eq '"custom/ws[0-9]+".*"interval"' "$WORKSPACE_CONFIG" \
    || fail 'workspace modules must not poll Hyprland on an interval'

printf 'switcher regression checks passed\n'
