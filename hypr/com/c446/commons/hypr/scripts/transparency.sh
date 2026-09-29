#!/usr/bin/env sh
# Toggle transparency mode without creating or sourcing a Hyprland config file.
set -eu

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr_transparency.enabled"

if [ -f "$STATE_FILE" ]; then
    hyprctl reload
    rm -f "$STATE_FILE"
    exit 0
fi

# Firefox opacity is persistent in rules.lua; this toggle only changes the
# temporary global transparency rule.
hyprctl eval 'hl.window_rule({ name = "transparency-mode-global", match = { class = "negative:^firefox$" }, opacity = "0.8 override 0.75 override", no_blur = false, force_rgbx = false, opaque = false })'
touch "$STATE_FILE"
