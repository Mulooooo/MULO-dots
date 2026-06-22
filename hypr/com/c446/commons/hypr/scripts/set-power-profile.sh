#!/usr/bin/env sh
# Switch the ACPI platform profile via the privileged helper service.
#
# The platform-profile@.service writes to /sys/firmware/acpi/platform_profile
# as root. Its own notify-send fails under systemd (no session bus) and, with
# `set -e`, that poisons the service exit code even though the sysfs write
# succeeded. So we ignore the service exit code and verify by reading the
# profile back, then emit the notification from this (session) context.

PROFILE="$1"
SILENT="$2"  # pass --silent to suppress notifications (e.g. from gamemode.sh)
PROFILE_PATH="/sys/firmware/acpi/platform_profile"
# Fixed replace id so repeated switches update one dunst notification.
DUNST_ID=2001

notify() {
    # notify "<summary>" "<body>" "<icon>" "<urgency>"
    [ "$SILENT" = "--silent" ] && return 0
    dunstify -a "Power Profile" -r "$DUNST_ID" -u "$4" -i "$3" "$1" "$2"
}

case "$PROFILE" in
    quiet)       LABEL="Quiet";       ICON="battery" ;;
    balanced)    LABEL="Balanced";    ICON="display" ;;
    performance) LABEL="Performance"; ICON="controller" ;;
    *)
        notify "Power Profile" "Unknown profile: $PROFILE" dialog-error critical
        exit 1
        ;;
esac

systemctl start "platform-profile@${PROFILE}.service" 2>/dev/null || true

CURRENT=$(cat "$PROFILE_PATH" 2>/dev/null)
if [ "$CURRENT" = "$PROFILE" ]; then
    notify "Power Profile" "Switched to $LABEL" "$ICON" normal
else
    notify "Power Profile" "Failed to switch to $LABEL (now: ${CURRENT:-unknown})" dialog-error critical
    exit 1
fi
