#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINDS="$ROOT/commons/hypr/binds.lua"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

grep -Fq 'bind("P", function()' "$BINDS" \
    || fail 'SUPER+P must run the pin callback'

grep -Fq 'hl.dsp.window.float({ action = "set" })' "$BINDS" \
    || fail 'SUPER+P must make the focused window floating'

grep -Fq 'hl.dsp.window.pin({ action = "toggle" })' "$BINDS" \
    || fail 'SUPER+P must toggle pinning'

grep -Fq 'exec("CTRL + P", "~/.config/hypr/scripts/start-hdmi.sh")' "$BINDS" \
    || fail 'HDMI startup must move to SUPER+CTRL+P'

! grep -Fq 'exec("P", "~/.config/hypr/scripts/start-hdmi.sh")' "$BINDS" \
    || fail 'HDMI startup must no longer use SUPER+P'

printf 'pin binding regression checks passed\n'
