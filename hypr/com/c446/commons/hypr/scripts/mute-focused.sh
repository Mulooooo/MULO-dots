#!/usr/bin/env bash

# Toggle mute on the audio stream(s) belonging to the currently focused window.
# Audio streams are often owned by a child process (browser tab, game engine),
# so we match the focused window's PID *and* all of its descendants.

set -euo pipefail

win_pid="$(hyprctl activewindow -j | jq -r '.pid // empty')"
if [[ -z "$win_pid" || "$win_pid" == "-1" ]]; then
    notify-send -a "mute" "Mute focused" "No focused window" 2>/dev/null || true
    exit 0
fi

# Collect win_pid + every descendant PID (breadth-first via pgrep -P).
collect_descendants() {
    local frontier="$1" all="$1" next p k
    while [[ -n "$frontier" ]]; do
        next=""
        for p in $frontier; do
            for k in $(pgrep -P "$p" 2>/dev/null || true); do
                case " $all " in
                    *" $k "*) ;;                       # already seen
                    *) all+=" $k"; next+=" $k" ;;
                esac
            done
        done
        frontier="$next"
    done
    printf '%s' "$all"
}

pids=" $(collect_descendants "$win_pid") "

# Find sink-input indices whose owning PID is in our set.
mapfile -t indices < <(
    pactl -f json list sink-inputs \
        | jq -r --arg pids "$pids" '
            ($pids | split(" ") | map(select(length > 0))) as $set
            | .[]
            | select((.properties."application.process.id" // "x") as $p | $set | index($p))
            | .index'
)

if [[ ${#indices[@]} -eq 0 ]]; then
    notify-send -a "mute" "Mute focused" "Focused window has no audio stream" 2>/dev/null || true
    exit 0
fi

# Toggle each matching stream; report the resulting state of the first one.
for idx in "${indices[@]}"; do
    pactl set-sink-input-mute "$idx" toggle
done

state="$(pactl -f json list sink-inputs \
    | jq -r --argjson i "${indices[0]}" '.[] | select(.index == $i) | .mute')"

if [[ "$state" == "true" ]]; then
    notify-send -a "mute" "Muted 🔇" "Focused window audio muted" 2>/dev/null || true
else
    notify-send -a "mute" "Unmuted 🔊" "Focused window audio unmuted" 2>/dev/null || true
fi
