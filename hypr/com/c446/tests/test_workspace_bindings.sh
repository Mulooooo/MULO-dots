#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINDS="$ROOT/commons/hypr/binds.lua"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

grep -Fq 'hl.dsp.window.move({ workspace = workspace, follow = false })' "$BINDS" \
    || fail 'window-to-workspace bindings must move silently'

! grep -Fq 'hl.dsp.window.move({ workspace = workspace })' "$BINDS" \
    || fail 'window-to-workspace bindings must not follow the moved window'

grep -Fq 'move_workspace_bind("SHIFT", key, workspace)' "$BINDS" \
    || fail 'regular workspace move bindings must remain present'

grep -Fq 'move_workspace_bind("SHIFT + CONTROL", key, workspace)' "$BINDS" \
    || fail 'CTRL workspace move bindings must remain present'

printf 'silent workspace binding regression checks passed\n'
