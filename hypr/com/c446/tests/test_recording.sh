#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECORDER="$ROOT/commons/hypr/scripts/record.zsh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

grep -Fq 'REPLY=' "$RECORDER" \
    || fail 'random keyword selection must return through shared state'

! grep -Fq 'first="$(random_keyword)"' "$RECORDER" \
    || fail 'random keyword selection must not fork for each word'

! grep -Fq 'second="$(random_keyword)"' "$RECORDER" \
    || fail 'random keyword selection must not fork for each word'

! grep -Fq 'third="$(random_keyword)"' "$RECORDER" \
    || fail 'random keyword selection must not fork for each word'

printf 'recording regression checks passed\n'
