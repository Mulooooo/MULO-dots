#!/bin/bash
# Manages HDMI-A-1 lifecycle:
#   - starts wl-mirror (onto workspace 10) when monitor connects
#   - kills wl-mirror and exiles orphaned windows to workspace 9 on disconnect

HDMI_MONITOR="HDMI-A-1"
# Workspaces that live on HDMI-A-1 (see monitors.conf)
HDMI_WORKSPACES=(11 12 13 14 15 16 17 18 19 20)
EXILE_WS=9

start_mirror() {
    pkill -x wl-mirror 2>/dev/null
    wl-mirror "$HDMI_MONITOR" &
}

stop_mirror() {
    pkill -x wl-mirror 2>/dev/null
}

exile_windows() {
    sleep 0.3  # let hyprland finish relocating workspaces after disconnect
    for ws in "${HDMI_WORKSPACES[@]}"; do
        hyprctl -j clients 2>/dev/null \
            | jq -r --argjson ws "$ws" '.[] | select(.workspace.id == $ws) | .address' \
            | while IFS= read -r addr; do
                [[ -n "$addr" ]] && hyprctl dispatch movetoworkspacesilent "${EXILE_WS},address:${addr}"
            done
    done
}

# Start mirror immediately if HDMI-A-1 is already connected at launch
if hyprctl -j monitors 2>/dev/null | jq -e --arg m "$HDMI_MONITOR" '.[] | select(.name == $m)' > /dev/null; then
    start_mirror
fi

# Listen for monitor add/remove events
socat - "UNIX-CONNECT:/tmp/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock" \
    | while IFS= read -r line; do
        case "$line" in
            "monitoradded>>$HDMI_MONITOR")
                start_mirror
                ;;
            "monitorremoved>>$HDMI_MONITOR")
                stop_mirror
                exile_windows
                ;;
        esac
    done
