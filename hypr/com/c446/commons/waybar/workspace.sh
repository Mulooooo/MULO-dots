#!/usr/bin/env bash
# Emit one workspace button and update it from Hyprland's event socket.
set -uo pipefail

workspace="${1:?workspace id required}"
runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
instance="${HYPRLAND_INSTANCE_SIGNATURE:-}"
if [ -z "$instance" ]; then
    instance="$(find "$runtime_dir/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | head -n1)"
fi
socket="${HYPR_WORKSPACE_SOCKET:-$runtime_dir/hypr/$instance/.socket2.sock}"

emit() {
    local current="$1" class=""
    [ "$current" = "$workspace" ] && class="active"
    printf '{"text":"%s","class":"%s"}\n' "$workspace" "$class"
}

current="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // 0' 2>/dev/null || printf '0')"
emit "$current"

# Waybar keeps this process alive. There is no polling interval: the helper
# only emits after a relevant workspace/focused-monitor event arrives.
[ -S "$socket" ] || exit 0

nc -U "$socket" 2>/dev/null | while IFS= read -r event; do
    next=""
    case "$event" in
        workspace\>\>*|workspacev2\>\>*)
            next="${event#*>>}"
            next="${next%%,*}"
            ;;
        focusedmon\>\>*|focusedmonv2\>\>*)
            next="${event#*>>}"
            next="${next#*,}"
            ;;
    esac

    if [ -n "$next" ] && [ "$next" != "$current" ]; then
        current="$next"
        emit "$current"
    fi
done
