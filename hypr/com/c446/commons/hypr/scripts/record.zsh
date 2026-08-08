#!/usr/bin/env zsh

# Records the currently focused Hyprland window for 30 seconds, then
# compresses it to remain below 10 MiB.
#
# Required:
#   hyprctl jq wf-recorder ffmpeg ffprobe timeout
#
# Optional notifications:
#   notify-send gdbus

set -u
setopt PIPE_FAIL

readonly DURATION_SECONDS=30
readonly MAX_BYTES=$((10 * 1024 * 1024))
readonly TARGET_BYTES=$((9 * 1024 * 1024))
readonly OUTPUT_DIR="$HOME/Videos/screen_recording"
readonly PASSLOG="${TMPDIR:-/tmp}/focused-recording-${$}"

readonly -a KEYWORDS=(
    amber ancient arcane autumn azure
    blazing blue bright bronze celestial
    cloud cobalt cosmic crimson crystal
    dawn deep divine drifting dusk
    echo ember eternal falling frozen
    ghost golden hidden hollow jade
    lunar mist moon night obsidian
    orbit pale quiet radiant red
    rising royal silent silver solar
    spectral star storm summer swift
    thunder twilight violet wandering white
    wild winter
)

notification_daemon_running() {
    command -v gdbus >/dev/null 2>&1 || return 1
    command -v notify-send >/dev/null 2>&1 || return 1

    gdbus call \
        --session \
        --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.NameHasOwner \
        org.freedesktop.Notifications 2>/dev/null |
        grep -q 'true'
}

notify() {
    notification_daemon_running || return 0
    notify-send --app-name="Window Recorder" "$1" "${2:-}"
}

fail() {
    notify "Recording failed" "$1"
    print -u2 -- "Error: $1"
    exit 1
}

random_keyword() {
    REPLY="${KEYWORDS[$((RANDOM % ${#KEYWORDS[@]} + 1))]}"
}

generate_output_path() {
    local timestamp
    local first
    local second
    local third
    local candidate

    while true; do
        timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
        random_keyword
        first="$REPLY"
        random_keyword
        second="$REPLY"
        random_keyword
        third="$REPLY"

        # Avoid duplicate words inside the same filename.
        [[ "$first" == "$second" ||
           "$first" == "$third" ||
           "$second" == "$third" ]] && continue

        candidate="${OUTPUT_DIR}/${timestamp}_${first}-${second}-${third}.mp4"

        [[ ! -e "$candidate" ]] && {
            print -r -- "$candidate"
            return 0
        }
    done
}

mkdir -p -- "$OUTPUT_DIR" || {
    print -u2 -- "Error: could not create output directory: $OUTPUT_DIR"
    exit 1
}

readonly OUTPUT_FILE="$(generate_output_path)"
readonly RAW_FILE="${OUTPUT_FILE:r}.raw.mkv"

cleanup() {
    rm -f -- \
        "$RAW_FILE" \
        "${PASSLOG}-0.log" \
        "${PASSLOG}-0.log.mbtree"
}

trap cleanup EXIT INT TERM

required_commands=(
    hyprctl
    jq
    wf-recorder
    ffmpeg
    ffprobe
    timeout
)

missing_commands=()

for command_name in "${required_commands[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 ||
        missing_commands+=("$command_name")
done

if (( ${#missing_commands[@]} > 0 )); then
    message="Missing dependencies: ${(j:, :)missing_commands}"
    notify "Cannot record window" "$message"
    print -u2 -- "$message"
    exit 1
fi

window_json="$(hyprctl activewindow -j 2>/dev/null)" ||
    fail "Could not query the focused Hyprland window."

window_address="$(jq -r '.address // empty' <<< "$window_json")"
window_x="$(jq -r '.at[0] // empty' <<< "$window_json")"
window_y="$(jq -r '.at[1] // empty' <<< "$window_json")"
window_width="$(jq -r '.size[0] // empty' <<< "$window_json")"
window_height="$(jq -r '.size[1] // empty' <<< "$window_json")"
window_title="$(jq -r '.title // "focused window"' <<< "$window_json")"

[[ -n "$window_address" && "$window_address" != "0x0" ]] ||
    fail "No focused window was found."

[[ "$window_x" == <-> || "$window_x" == -<-> ]] ||
    fail "Hyprland returned an invalid horizontal coordinate."

[[ "$window_y" == <-> || "$window_y" == -<-> ]] ||
    fail "Hyprland returned an invalid vertical coordinate."

[[ "$window_width" == <-> && "$window_height" == <-> ]] ||
    fail "Hyprland returned an invalid window size."

(( window_width > 0 && window_height > 0 )) ||
    fail "The focused window has an invalid size."

# H.264 requires even dimensions.
(( window_width % 2 != 0 )) && (( window_width-- ))
(( window_height % 2 != 0 )) && (( window_height-- ))

geometry="${window_x},${window_y} ${window_width}x${window_height}"

notify \
    "Recording started" \
    "\"${window_title}\" for ${DURATION_SECONDS} seconds"

# SIGINT lets wf-recorder finalize the Matroska container cleanly.
timeout \
    --signal=INT \
    --kill-after=5s \
    "${DURATION_SECONDS}s" \
    wf-recorder \
        --geometry "$geometry" \
        --file "$RAW_FILE" \
        --codec libx264 \
        --pixel-format yuv420p

record_status=$?

# timeout normally returns 124 after terminating wf-recorder.
if (( record_status != 0 && record_status != 124 )); then
    fail "wf-recorder exited with status ${record_status}."
fi

[[ -s "$RAW_FILE" ]] ||
    fail "The recording produced no video."

actual_duration="$(
    ffprobe \
        -v error \
        -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 \
        "$RAW_FILE" 2>/dev/null
)"

[[ "$actual_duration" == <->(|.<->) ]] ||
    fail "Could not determine the recording duration."

# Reserve some space for MP4 container overhead.
video_bitrate_kbps="$(
    awk \
        -v bytes="$TARGET_BYTES" \
        -v duration="$actual_duration" \
        'BEGIN {
            bitrate = ((bytes * 8) / duration / 1000) * 0.97;

            if (bitrate < 150) {
                bitrate = 150;
            }

            printf "%d", bitrate;
        }'
)"

encode_video() {
    local bitrate_kbps="$1"

    rm -f -- \
        "${PASSLOG}-0.log" \
        "${PASSLOG}-0.log.mbtree"

    ffmpeg -y \
        -v error \
        -i "$RAW_FILE" \
        -map 0:v:0 \
        -an \
        -vf "scale='min(iw,1920)':-2:flags=lanczos" \
        -c:v libx264 \
        -preset slow \
        -b:v "${bitrate_kbps}k" \
        -maxrate "${bitrate_kbps}k" \
        -bufsize "$((bitrate_kbps * 2))k" \
        -pass 1 \
        -passlogfile "$PASSLOG" \
        -f mp4 \
        /dev/null &&
    ffmpeg -y \
        -v error \
        -i "$RAW_FILE" \
        -map 0:v:0 \
        -an \
        -vf "scale='min(iw,1920)':-2:flags=lanczos" \
        -c:v libx264 \
        -preset slow \
        -b:v "${bitrate_kbps}k" \
        -maxrate "${bitrate_kbps}k" \
        -bufsize "$((bitrate_kbps * 2))k" \
        -pass 2 \
        -passlogfile "$PASSLOG" \
        -movflags +faststart \
        -pix_fmt yuv420p \
        "$OUTPUT_FILE"
}

encode_video "$video_bitrate_kbps" ||
    fail "FFmpeg could not compress the recording."

output_size="$(stat -c '%s' "$OUTPUT_FILE")"
attempt=0

# Retry with a lower bitrate if the resulting MP4 exceeds 10 MiB.
while (( output_size >= MAX_BYTES && attempt < 3 )); do
    (( attempt++ ))
    video_bitrate_kbps=$((video_bitrate_kbps * 85 / 100))

    encode_video "$video_bitrate_kbps" ||
        fail "FFmpeg compression retry ${attempt} failed."

    output_size="$(stat -c '%s' "$OUTPUT_FILE")"
done

(( output_size < MAX_BYTES )) ||
    fail "Could not reduce the recording below 10 MiB."

size_mib="$(
    awk -v bytes="$output_size" 'BEGIN {
        printf "%.2f", bytes / 1024 / 1024
    }'
)"

notify \
    "Recording saved" \
    "${OUTPUT_FILE:t} — ${size_mib} MiB"

print -r -- "$OUTPUT_FILE"
