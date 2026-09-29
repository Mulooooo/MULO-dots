#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINDS="$ROOT/commons/hypr/binds.lua"
MUTE_NOTIFIER="$ROOT/commons/hypr/scripts/notify-mute.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

grep -Fq 'notify-mute.sh' "$BINDS" \
    || fail 'mute key must use the mute-state notifier'

grep -Fq 'exec("M", "~/.config/hypr/scripts/notify-mute.sh")' "$BINDS" \
    || fail 'MOD+M must toggle the global sink mute'

grep -Fq 'exec("SHIFT + M", "~/.config/hypr/scripts/mute-focused.sh")' "$BINDS" \
    || fail 'MOD+SHIFT+M must toggle the focused window mute'

! grep -Fq 'exec("M", "~/.config/hypr/scripts/mute-focused.sh")' "$BINDS" \
    || fail 'MOD+M must not use the focused-window mute script'

! grep -Fq 'XF86AudioMute", hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle && ~/.config/hypr/scripts/notify-volume.sh")' "$BINDS" \
    || fail 'mute key must not use the volume notifier'

[[ -x "$MUTE_NOTIFIER" ]] \
    || fail 'mute-state notifier must be executable'

grep -Fq 'Muted 🔇' "$MUTE_NOTIFIER" \
    || fail 'mute-state notifier must report muted state'

grep -Fq 'Unmuted 🔊' "$MUTE_NOTIFIER" \
    || fail 'mute-state notifier must report unmuted state'

printf 'mute notification regression checks passed\n'
