#!/usr/bin/env bash

# Cursor theme switcher for Hyprland
# Usage: ./toggle-cursor.sh [vivian|capitaine|toggle]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_CONF="$SCRIPT_DIR/env.conf"

VIVIAN="Vivian-Cursors"
CAPITAINE="capitaine-cursors-light"

# Get current cursor theme from env.conf
get_current_cursor() {
    grep "^env = HYPRCURSOR_THEME," "$ENV_CONF" | sed 's/.*,//' | tr -d ' '
}

# Set cursor theme in env.conf
set_cursor_in_conf() {
    local theme=$1
    local size=${2:-24}

    # Update HYPRCURSOR_THEME
    sed -i "s/^env = HYPRCURSOR_THEME,.*/env = HYPRCURSOR_THEME,$theme/" "$ENV_CONF"

    # Update XCURSOR_THEME
    sed -i "s/^env = XCURSOR_THEME,.*/env = XCURSOR_THEME,$theme/" "$ENV_CONF"

    # Update XCURSOR_SIZE if needed
    sed -i "s/^env = XCURSOR_SIZE,.*/env = XCURSOR_SIZE,$size/" "$ENV_CONF"
}

# Apply cursor via hyprctl
apply_cursor_live() {
    local theme=$1
    local size=${2:-24}

    if command -v hyprctl &> /dev/null; then
        hyprctl setcursor "$theme" "$size" 2>/dev/null
    fi
}

# Apply cursor via gsettings (for GTK apps)
apply_cursor_gsettings() {
    local theme=$1

    if command -v gsettings &> /dev/null; then
        gsettings set org.gnome.desktop.interface cursor-theme "$theme" 2>/dev/null
    fi
}

# Show notification (if notify-send available)
notify_cursor_change() {
    local theme=$1

    if command -v notify-send &> /dev/null; then
        notify-send "Cursor Theme" "Switched to $theme" -u low
    fi
}

# Main logic
current=$(get_current_cursor)
target=""

case "$1" in
    vivian)
        target="$VIVIAN"
        ;;
    capitaine)
        target="$CAPITAINE"
        ;;
    toggle|"")
        if [[ "$current" == "$VIVIAN" ]]; then
            target="$CAPITAINE"
        else
            target="$VIVIAN"
        fi
        ;;
    status)
        echo "Current cursor: $current"
        exit 0
        ;;
    *)
        echo "Usage: $0 [vivian|capitaine|toggle|status]"
        echo ""
        echo "  vivian    - Switch to Vivian-Cursors"
        echo "  capitaine - Switch to capitaine-cursors-light"
        echo "  toggle    - Toggle between themes (default)"
        echo "  status    - Show current theme"
        exit 1
        ;;
esac

if [[ "$current" == "$target" ]]; then
    echo "Already using $target"
    exit 0
fi

echo "Switching cursor from $current to $target..."

set_cursor_in_conf "$target"
apply_cursor_live "$target"
apply_cursor_gsettings "$target"
notify_cursor_change "$target"

echo "Cursor theme switched to $target"
echo "Restart Hyprland or reload to see changes (hyprctl reload)"
