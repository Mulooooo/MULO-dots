#!/usr/bin/env bash
# One-time prune of NVIDIA driver-compiled shader caches for Zenless Zone Zero,
# deferred until the game is closed (driver changed 595 -> 610, old caches stale).
# Driven by zzz-prune-shaders.timer; self-disables after it runs once.
set -euo pipefail

SENTINEL="$HOME/.cache/zzz-shader-prune.done"
LOG="$HOME/.cache/zzz-shader-prune.log"
CACHES=(
    "$HOME/.var/app/app.twintaillauncher.ttl/cache/nvidia/GLCache"
    "$HOME/.cache/nvidia/GLCache"
)

disable_self() {
    systemctl --user disable --now zzz-prune-shaders.timer >/dev/null 2>&1 || true
}

# already done on a previous tick -> make sure the timer is off and stop
if [ -f "$SENTINEL" ]; then disable_self; exit 0; fi

# game (or its proton/wine wrappers) still running -> try again next tick
if pgrep -x ZenlessZoneZero >/dev/null 2>&1; then exit 0; fi

ts="$(date -Is)"
total=0
for d in "${CACHES[@]}"; do
    if [ -d "$d" ]; then
        sz="$(du -sm "$d" 2>/dev/null | cut -f1 || echo 0)"
        rm -rf -- "$d"
        printf '%s pruned %s (~%s MB)\n' "$ts" "$d" "$sz" >> "$LOG"
        total=$((total + sz))
    fi
done
printf '%s done — freed ~%s MB, driver %s\n' \
    "$ts" "$total" "$(cat /sys/module/nvidia/version 2>/dev/null || echo '?')" >> "$LOG"

touch "$SENTINEL"
disable_self
