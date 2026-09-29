#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINDS="$ROOT/commons/hypr/binds.lua"
APPEARANCE="$ROOT/commons/hypr/appearance.lua"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

grep -Fq 'layout = "master"' "$APPEARANCE" \
    || fail 'the shared Hyprland layout must remain master'

for direction in \
    'H = "l"' 'J = "d"' 'K = "u"' 'L = "r"' \
    'LEFT = "l"' 'DOWN = "d"' 'UP = "u"' 'RIGHT = "r"'; do
    grep -Fq "$direction" "$BINDS" \
        || fail "direction mapping is missing: $direction"
done

grep -Fq 'bind("SHIFT + " .. key, hl.dsp.window.move({ direction = direction }))' "$BINDS" \
    || fail 'shifted direction keys must move the focused window'

! grep -Fq 'hl.dsp.layout("togglesplit")' "$BINDS" \
    || fail 'master layout must not use the dwindle-only togglesplit message'

! grep -Fq 'playerctl -p spotify previous' "$BINDS" \
    || fail 'MOD+H must remain available for directional focus'

! grep -Fq 'playerctl -p spotify next' "$BINDS" \
    || fail 'MOD+L must remain available for directional focus'

printf 'master layout binding regression checks passed\n'
