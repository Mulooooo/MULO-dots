#!/usr/bin/env bash
# Hyprland 0.55+ automatic multi-monitor manager (Lua config aware).
#
# Goals:
#   * keep the laptop panel as the stable primary display
#   * automatically enable and place any external display
#   * route workspaces 1-10 to the primary and 11-20 to the secondary
#   * move those workspaces back safely when the secondary disappears
#   * use native Hyprland mirroring instead of an always-running wl-mirror
#   * provide a manual recovery/mode-cycle path for fussy TVs/projectors
#
# Dependencies: hyprctl, jq, flock (util-linux)
# Optional: notify-send

set -Eeuo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
HYPR_CONFIG_DIR="${CONFIG_HOME}/hypr"
STATE_DIR="${STATE_HOME}/hypr-monitor-manager"
PROFILE_FILE="${HYPR_CONFIG_DIR}/monitor-profiles.tsv"
mkdir -p "$STATE_DIR"

# Your current built-in panel. If this connector ever changes, the script also
# auto-detects eDP/LVDS/DSI connectors.
PRIMARY_HINT="${HYPR_PRIMARY_MONITOR:-eDP-1}"

# Safe defaults for unknown/random external displays. These intentionally match
# Hyprland's recommended "preferred + automatic placement" approach.
DEFAULT_EXTERNAL_MODE="${HYPR_EXTERNAL_MODE:-preferred}"
DEFAULT_EXTERNAL_POSITION="${HYPR_EXTERNAL_POSITION:-auto-center-left}"
DEFAULT_EXTERNAL_SCALE="${HYPR_EXTERNAL_SCALE:-1}"

PRIMARY_WS_START=1
PRIMARY_WS_END=10
SECONDARY_WS_START=11
SECONDARY_WS_END=20

log() {
    printf '[hypr-monitor-manager] %s\n' "$*" >&2
}

notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a "Hyprland displays" "Displays" "$*"
}

die() {
    log "ERROR: $*"
    notify "$*"
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

lua_string() {
    # Monitor names/descriptions are normally ASCII, but this safely escapes the
    # characters relevant to a Lua double-quoted string.
    local s=${1-}
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    printf '"%s"' "$s"
}

lua_scale() {
    local value=$1
    if [[ "$value" == "auto" ]]; then
        printf '"auto"'
    elif [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf '%s' "$value"
    else
        log "Invalid scale '$value'; falling back to 1"
        printf '1'
    fi
}

hypr_eval() {
    local code=$1 out
    if ! out=$(hyprctl eval "$code" 2>&1); then
        log "hyprctl eval failed: $out"
        return 1
    fi
    if [[ "$out" != "ok" && -n "$out" ]]; then
        log "hyprctl: $out"
    fi
}

all_monitors_json() {
    hyprctl -j monitors all 2>/dev/null | jq -c '[.[] | select(.name != "FALLBACK")]'
}

active_monitors_json() {
    hyprctl -j monitors 2>/dev/null | jq -c '[.[] | select(.name != "FALLBACK")]'
}

primary_monitor() {
    local all=$1
    local primary

    primary=$(jq -r --arg p "$PRIMARY_HINT" '.[] | select(.name == $p) | .name' <<<"$all" | head -n1)
    if [[ -n "$primary" ]]; then
        printf '%s\n' "$primary"
        return 0
    fi

    primary=$(jq -r '.[] | select(.name | test("^(eDP|LVDS|DSI)-")) | .name' <<<"$all" | head -n1)
    if [[ -n "$primary" ]]; then
        printf '%s\n' "$primary"
        return 0
    fi

    # Desktop / unusual connector fallback.
    jq -r '.[0].name // empty' <<<"$all"
}

monitor_description() {
    local all=$1 name=$2
    jq -r --arg n "$name" '.[] | select(.name == $n) | .description // .name' <<<"$all" | head -n1
}

secondary_monitor() {
    local all=$1 primary=$2
    local saved_desc candidate
    saved_desc=""
    [[ -f "$STATE_DIR/preferred-secondary" ]] && saved_desc=$(<"$STATE_DIR/preferred-secondary")

    if [[ -n "$saved_desc" ]]; then
        candidate=$(jq -r --arg p "$primary" --arg d "$saved_desc" \
            '.[] | select(.name != $p and (.description // "") == $d) | .name' <<<"$all" | head -n1)
        if [[ -n "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi

    # If there are several external screens, prefer HDMI for the "secondary"
    # workspace bank (useful for TVs/projectors), then DP/USB-C, then anything.
    candidate=$(jq -r --arg p "$primary" \
        '[.[] | select(.name != $p)] | sort_by(
            if (.name | startswith("HDMI")) then 0
            elif (.name | startswith("DP")) then 1
            else 2 end,
            .name
        ) | .[0].name // empty' <<<"$all")
    printf '%s\n' "$candidate"
}

profile_for() {
    # Output: MODE<TAB>POSITION<TAB>SCALE
    local all=$1 name=$2 description line match mode position scale
    description=$(monitor_description "$all" "$name")

    if [[ -f "$PROFILE_FILE" ]]; then
        while IFS=$'\t' read -r match mode position scale _; do
            [[ -z "${match// }" || "$match" == \#* ]] && continue
            if [[ "$name" =~ $match || "$description" =~ $match ]]; then
                printf '%s\t%s\t%s\n' \
                    "${mode:-$DEFAULT_EXTERNAL_MODE}" \
                    "${position:-$DEFAULT_EXTERNAL_POSITION}" \
                    "${scale:-$DEFAULT_EXTERNAL_SCALE}"
                return 0
            fi
        done < "$PROFILE_FILE"
    fi

    printf '%s\t%s\t%s\n' \
        "$DEFAULT_EXTERNAL_MODE" "$DEFAULT_EXTERNAL_POSITION" "$DEFAULT_EXTERNAL_SCALE"
}

set_monitor() {
    local name=$1 mode=$2 position=$3 scale=$4 mirror=${5-}
    local mirror_expr
    if [[ -n "$mirror" ]]; then
        mirror_expr=", mirror = $(lua_string "$mirror")"
    else
        # Explicit empty mirror clears a previous runtime mirror rule.
        mirror_expr=', mirror = ""'
    fi

    hypr_eval "hl.monitor({ output = $(lua_string "$name"), disabled = false, mode = $(lua_string "$mode"), position = $(lua_string "$position"), scale = $(lua_scale "$scale")${mirror_expr} })"
}

is_active() {
    local name=$1
    hyprctl -j monitors 2>/dev/null | jq -e --arg n "$name" 'any(.[]; .name == $n)' >/dev/null
}

apply_workspace_rules() {
    local primary=$1 secondary=${2-} target ws code=""
    target=${secondary:-$primary}

    # Dynamic rules are temporary, so the Lua event hooks reapply them after
    # config reloads. One eval keeps IPC overhead low.
    for ((ws=PRIMARY_WS_START; ws<=PRIMARY_WS_END; ws++)); do
        code+="hl.workspace_rule({ workspace = $(lua_string "$ws"), monitor = $(lua_string "$primary") });"
    done
    for ((ws=SECONDARY_WS_START; ws<=SECONDARY_WS_END; ws++)); do
        code+="hl.workspace_rule({ workspace = $(lua_string "$ws"), monitor = $(lua_string "$target") });"
    done
    hypr_eval "$code" || true
}

move_existing_workspace_bank() {
    local target=$1 start=$2 end=$3 ws existing code=""
    existing=$(hyprctl -j workspaces 2>/dev/null || printf '[]')

    for ((ws=start; ws<=end; ws++)); do
        if jq -e --argjson ws "$ws" 'any(.[]; .id == $ws)' <<<"$existing" >/dev/null; then
            # Moving the workspace moves all of its windows with it, so we do not
            # need to "exile" individual client addresses on disconnect.
            code+="hl.dispatch(hl.dsp.workspace.move({ workspace = $(lua_string "$ws"), monitor = $(lua_string "$target") }));"
        fi
    done
    [[ -z "$code" ]] || hypr_eval "$code" || true
}

apply_extend() {
    local all=$1 primary=$2 secondary=$3 name profile mode position scale description

    # The static Lua config normally owns the primary. Only touch it if it is
    # actually disabled; this avoids an unnecessary modeset/flicker on every hotplug.
    if jq -e --arg n "$primary" '.[] | select(.name == $n and .disabled == true)' <<<"$all" >/dev/null; then
        if [[ "$primary" == "$PRIMARY_HINT" ]]; then
            set_monitor "$primary" "2560x1600@240" "0x0" "1.33" "" || true
        else
            set_monitor "$primary" "preferred" "0x0" "auto" "" || true
        fi
    fi

    while IFS= read -r name; do
        [[ -z "$name" || "$name" == "$primary" ]] && continue
        profile=$(profile_for "$all" "$name")
        IFS=$'\t' read -r mode position scale <<<"$profile"
        set_monitor "$name" "$mode" "$position" "$scale" "" || true
    done < <(jq -r '.[].name' <<<"$all")

    if [[ -n "$secondary" ]]; then
        description=$(monitor_description "$all" "$secondary")
        [[ -n "$description" ]] && printf '%s' "$description" > "$STATE_DIR/preferred-secondary"
        apply_workspace_rules "$primary" "$secondary"
        move_existing_workspace_bank "$primary" "$PRIMARY_WS_START" "$PRIMARY_WS_END"
        move_existing_workspace_bank "$secondary" "$SECONDARY_WS_START" "$SECONDARY_WS_END"
    else
        apply_workspace_rules "$primary" ""
        move_existing_workspace_bank "$primary" "$PRIMARY_WS_START" "$PRIMARY_WS_END"
        move_existing_workspace_bank "$primary" "$SECONDARY_WS_START" "$SECONDARY_WS_END"
    fi
}

apply_mirror() {
    local all=$1 primary=$2 secondary=$3 profile mode position scale
    [[ -n "$secondary" ]] || {
        log "Mirror requested but no external monitor is connected; using extend."
        apply_extend "$all" "$primary" ""
        return 0
    }

    if jq -e --arg n "$primary" '.[] | select(.name == $n and .disabled == true)' <<<"$all" >/dev/null; then
        if [[ "$primary" == "$PRIMARY_HINT" ]]; then
            set_monitor "$primary" "2560x1600@240" "0x0" "1.33" "" || true
        else
            set_monitor "$primary" "preferred" "0x0" "auto" "" || true
        fi
    fi

    profile=$(profile_for "$all" "$secondary")
    IFS=$'\t' read -r mode position scale <<<"$profile"
    set_monitor "$secondary" "$mode" "0x0" "$scale" "$primary" || true

    # A mirrored output does not get a useful independent workspace bank.
    apply_workspace_rules "$primary" ""
    move_existing_workspace_bank "$primary" "$PRIMARY_WS_START" "$SECONDARY_WS_END"
}

reconcile() {
    need hyprctl
    need jq

    exec 9>"$STATE_DIR/reconcile.lock"
    flock -w 3 9 || return 0

    local all primary secondary mode
    all=$(all_monitors_json) || return 1
    [[ $(jq 'length' <<<"$all") -gt 0 ]] || return 0

    primary=$(primary_monitor "$all")
    [[ -n "$primary" ]] || return 0
    secondary=$(secondary_monitor "$all" "$primary")
    mode="extend"
    [[ -f "$STATE_DIR/layout-mode" ]] && mode=$(<"$STATE_DIR/layout-mode")

    case "$mode" in
        mirror) apply_mirror "$all" "$primary" "$secondary" ;;
        *)      apply_extend "$all" "$primary" "$secondary" ;;
    esac

    if [[ -n "$secondary" ]]; then
        log "layout=$mode primary=$primary secondary=$secondary"
    else
        log "layout=single primary=$primary"
    fi
}

recover_secondary() {
    local all primary secondary profile mode position scale candidate
    all=$(all_monitors_json)
    primary=$(primary_monitor "$all")
    secondary=$(secondary_monitor "$all" "$primary")
    [[ -n "$secondary" ]] || die "No external display is detected."

    profile=$(profile_for "$all" "$secondary")
    IFS=$'\t' read -r mode position scale <<<"$profile"

    log "Trying $secondary with preferred mode"
    set_monitor "$secondary" "preferred" "$position" "$scale" ""
    sleep 0.6
    if is_active "$secondary"; then
        notify "$secondary is active (preferred mode)."
        reconcile
        return 0
    fi

    # Conservative modes for TVs/projectors. Only try modes the sink actually
    # advertises; no guessed modelines.
    mapfile -t candidates < <(jq -r --arg n "$secondary" '
        .[] | select(.name == $n) | .availableModes[]? | sub("Hz$"; "")
    ' <<<"$all" | awk '
        /^1920x1080@/ { a[++na]=$0; next }
        /^1280x720@/  { b[++nb]=$0; next }
        { c[++nc]=$0 }
        END {
            for (i=1;i<=na;i++) print a[i]
            for (i=1;i<=nb;i++) print b[i]
            for (i=1;i<=nc;i++) print c[i]
        }')

    for candidate in "${candidates[@]:-}"; do
        [[ -n "$candidate" ]] || continue
        log "Trying $secondary -> $candidate"
        set_monitor "$secondary" "$candidate" "$position" "$scale" "" || continue
        sleep 0.5
        if is_active "$secondary"; then
            notify "$secondary recovered at $candidate"
            reconcile
            return 0
        fi
    done

    die "$secondary was detected but could not be activated. Run '$0 status' to inspect it."
}

cycle_secondary_mode() {
    local all primary secondary profile position scale key state_file idx count mode
    all=$(all_monitors_json)
    primary=$(primary_monitor "$all")
    secondary=$(secondary_monitor "$all" "$primary")
    [[ -n "$secondary" ]] || die "No external display is detected."

    profile=$(profile_for "$all" "$secondary")
    IFS=$'\t' read -r _ position scale <<<"$profile"

    mapfile -t modes < <(jq -r --arg n "$secondary" \
        '.[] | select(.name == $n) | .availableModes[]? | sub("Hz$"; "")' <<<"$all")
    count=${#modes[@]}
    (( count > 0 )) || die "$secondary reports no available modes."

    key=$(printf '%s' "$(monitor_description "$all" "$secondary")" | cksum | awk '{print $1}')
    state_file="$STATE_DIR/mode-index-$key"
    idx=-1
    [[ -f "$state_file" ]] && idx=$(<"$state_file")
    [[ "$idx" =~ ^-?[0-9]+$ ]] || idx=-1
    idx=$(( (idx + 1) % count ))
    printf '%s' "$idx" > "$state_file"

    mode=${modes[$idx]}
    set_monitor "$secondary" "$mode" "$position" "$scale" ""
    printf 'extend' > "$STATE_DIR/layout-mode"
    notify "$secondary: $mode ($((idx + 1))/$count)"
    log "$secondary -> $mode ($((idx + 1))/$count)"
}

toggle_mirror() {
    local current="extend"
    [[ -f "$STATE_DIR/layout-mode" ]] && current=$(<"$STATE_DIR/layout-mode")
    if [[ "$current" == "mirror" ]]; then
        printf 'extend' > "$STATE_DIR/layout-mode"
        notify "Extended desktop enabled."
    else
        printf 'mirror' > "$STATE_DIR/layout-mode"
        notify "Native display mirroring enabled."
    fi
    reconcile
}

focus_secondary() {
    local all primary secondary
    all=$(all_monitors_json)
    primary=$(primary_monitor "$all")
    secondary=$(secondary_monitor "$all" "$primary")
    [[ -n "$secondary" ]] || die "No external display is connected."
    is_active "$secondary" || die "$secondary is detected but is not active. Try '$0 recover'."
    hypr_eval "hl.dispatch(hl.dsp.focus({ monitor = $(lua_string "$secondary") }))"
}

prefer_focused_external() {
    local all primary focused description
    all=$(all_monitors_json)
    primary=$(primary_monitor "$all")
    focused=$(active_monitors_json | jq -r '.[] | select(.focused == true) | .name' | head -n1)
    [[ -n "$focused" && "$focused" != "$primary" ]] || die "Focus an external monitor first."
    description=$(monitor_description "$all" "$focused")
    printf '%s' "$description" > "$STATE_DIR/preferred-secondary"
    notify "$focused is now the preferred secondary display."
    reconcile
}

status() {
    local all primary secondary mode
    all=$(all_monitors_json)
    primary=$(primary_monitor "$all")
    secondary=$(secondary_monitor "$all" "$primary")
    mode="extend"
    [[ -f "$STATE_DIR/layout-mode" ]] && mode=$(<"$STATE_DIR/layout-mode")

    printf 'layout mode: %s\nprimary:     %s\nsecondary:   %s\n\n' \
        "$mode" "${primary:-none}" "${secondary:-none}"
    jq -r '.[] | [
        .name,
        (if .disabled then "disabled" else "enabled" end),
        ((.width|tostring) + "x" + (.height|tostring) + "@" + ((.refreshRate // 0)|tostring)),
        ("pos=" + ((.x // 0)|tostring) + "x" + ((.y // 0)|tostring)),
        ("scale=" + ((.scale // 1)|tostring)),
        ("mirror=" + ((.mirrorOf // "none")|tostring)),
        (.description // "")
    ] | @tsv' <<<"$all"
}


usage() {
    cat <<'USAGE'
Usage: monitor-manager.sh COMMAND

Commands:
  apply             Re-apply the automatic display layout now.
  recover           Re-enable the secondary and try safe advertised modes.
  mode-next         Cycle through the secondary's advertised modes.
  mirror-toggle     Toggle native Hyprland mirroring vs extended desktop.
  focus-secondary   Focus the selected external monitor.
  prefer-focused    Make the currently focused external the preferred secondary.
  status            Show detected outputs and the manager's current selection.

Optional per-monitor overrides:
  ~/.config/hypr/monitor-profiles.tsv
  REGEX<TAB>MODE<TAB>POSITION<TAB>SCALE

Example:
  Dell.*U2723QE<TAB>3840x2160@60<TAB>auto-center-left<TAB>1.5
USAGE
}

case "${1:-}" in
    apply|reconcile) reconcile ;;
    recover)         recover_secondary ;;
    mode-next)       cycle_secondary_mode ;;
    mirror-toggle)   toggle_mirror ;;
    focus-secondary) focus_secondary ;;
    prefer-focused)  prefer_focused_external ;;
    status)          status ;;
    -h|--help|help|"") usage ;;
    *) usage >&2; exit 2 ;;
esac
