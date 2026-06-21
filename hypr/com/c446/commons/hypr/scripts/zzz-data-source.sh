#!/usr/bin/env bash
#
# zzz-data-source.sh — switch the Zenless Zone Zero data source used by
# TwintailLauncher between the dedicated ext4 partition (nvme0n1p5, auto-mounted)
# and the on-root backup copy (.bak), without touching the 81 GB of files.
#
# It flips two things that decide where the game actually loads from:
#   1. the Wine prefix "s:" drive symlink (the runtime path the game uses)
#   2. the launcher's recorded install directory (storage.db -> install.directory)
#
# Usage:
#   zzz-data-source.sh            # show current state
#   zzz-data-source.sh status     # show current state
#   zzz-data-source.sh partition  # use the mounted ext4 partition
#   zzz-data-source.sh bak        # use the .bak copy on the btrfs root
#   zzz-data-source.sh toggle     # switch to whichever isn't active
#
set -euo pipefail

# --- fixed paths for this install ---------------------------------------------
PART_DIR="/home/clement/.var/app/app.twintaillauncher.ttl/data/twintaillauncher/games/nap_global/vj6b2j8q4nm1ky2q11xq1pfq"
BAK_DIR="${PART_DIR}.bak"
S_LINK="/home/clement/.var/app/app.twintaillauncher.ttl/data/twintaillauncher/compatibility/prefixes/nap_global/vj6b2j8q4nm1ky2q11xq1pfq/pfx/dosdevices/s:"
DB="/home/clement/.local/share/twintaillauncher/storage.db"
INSTALL_ID="s5uagi27e8jmwi9nx35s3gmf"

die() { printf 'error: %s\n' "$1" >&2; exit 1; }

current_mode() {
    # Decide mode from where the s: drive currently points.
    local tgt
    tgt="$(readlink -f "$S_LINK" 2>/dev/null || true)"
    case "$tgt" in
        "$BAK_DIR")  echo "bak" ;;
        "$PART_DIR") echo "partition" ;;
        *)           echo "unknown" ;;
    esac
}

target_dir_for() {
    case "$1" in
        partition) echo "$PART_DIR" ;;
        bak)       echo "$BAK_DIR" ;;
        *)         die "unknown mode: $1" ;;
    esac
}

set_mode() {
    local mode="$1" dir
    dir="$(target_dir_for "$mode")"

    [ -f "$dir/ZenlessZoneZero.exe" ] \
        || die "target has no ZenlessZoneZero.exe: $dir (is the partition mounted?)"

    # 1) runtime path: repoint the s: drive
    ln -sfn "$dir" "$S_LINK"

    # 2) launcher bookkeeping: update recorded directory (busy timeout = launcher may be open)
    if command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 "$DB" \
            "PRAGMA busy_timeout=8000; UPDATE install SET directory='$dir' WHERE id='$INSTALL_ID';" >/dev/null \
            || printf 'warning: could not update storage.db (launcher writing?). s: drive was still switched.\n' >&2
    else
        printf 'warning: sqlite3 not found; updated s: drive only.\n' >&2
    fi

    printf 'switched ZZZ data source -> %s\n  %s\n' "$mode" "$dir"
    if pgrep -x twintaillauncher >/dev/null 2>&1; then
        printf 'note: launcher is running — relaunch the GAME (not the launcher) for this to take effect.\n'
    fi
}

status() {
    local mode db_dir mnt
    mode="$(current_mode)"
    db_dir="$(sqlite3 "$DB" "SELECT directory FROM install WHERE id='$INSTALL_ID';" 2>/dev/null || echo '?')"
    if mountpoint -q "$PART_DIR"; then mnt="mounted"; else mnt="NOT mounted"; fi

    printf 'ZZZ data source : %s\n' "$mode"
    printf 's: drive        -> %s\n' "$(readlink -f "$S_LINK" 2>/dev/null || echo '?')"
    printf 'launcher db dir -> %s\n' "$db_dir"
    printf 'partition (p5)  : %s at %s\n' "$mnt" "$PART_DIR"
    if [ "$mode" = "unknown" ]; then
        printf 'note: s: points somewhere unexpected — run "partition" or "bak" to fix.\n'
    fi
}

case "${1:-status}" in
    status|"")     status ;;
    partition|part) set_mode partition ;;
    bak|backup)     set_mode bak ;;
    toggle)
        case "$(current_mode)" in
            bak)       set_mode partition ;;
            partition) set_mode bak ;;
            *)         die 'current mode unknown; specify "partition" or "bak" explicitly.' ;;
        esac
        ;;
    -h|--help|help)
        sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) die "unknown command: $1 (use: status | partition | bak | toggle)" ;;
esac
