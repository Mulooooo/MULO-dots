#!/usr/bin/env sh
# Toggle transparency mode without creating or sourcing a Hyprland config file.

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr_transparency.enabled"

if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE"
    hyprctl reload
    exit 0
fi

touch "$STATE_FILE"

# The persistent configuration remains entirely Lua-based; dynamic rules are
# installed through Hyprland's official Lua evaluator.
hyprctl eval 'hl.window_rule({ name = "transparency-mode-global", match = { class = ".*" }, opacity = "0.875 override 0.8 override", no_blur = false, force_rgbx = false, opaque = false })'
hyprctl keyword animations:enabled 0
hyprctl eval 'hl.window_rule({ name = "temp-target-firefox", match = { class = "^(firefox|chromium|brave|vivaldi|microsoft-edge)$" }, opacity = "1.0 override 1.0 override 1.0 override", no_blur = true, force_rgbx = true, opaque = true })'
