#!/usr/bin/env sh
# Toggle transparency mode on/off.
# Default is opaque; this script temporarily overlays transparent rules.
TRANSP_CONF="/tmp/hypr_transparency.conf"

if [ -f "$TRANSP_CONF" ]; then
    rm -f "$TRANSP_CONF"
    hyprctl reload
else
    cat <<'EOF' > "$TRANSP_CONF"
# Transparency mode — overrides opaque global-defaults

windowrule {
    name = transparency-mode-global
    match:class = .*
    opacity = 0.9 override 0.85 override
    no_blur = off
    force_rgbx = off
    opaque = off
}

$browser=^(firefox|chromium|brave|vivaldi|microsoft-edge)$
animations {
    enabled = 0
}

# Firefox is always opaque — no transparency, no blur
windowrule {
    name = temp-target-firefox
    match:class = $browser
    opacity = 1.0 override 1.0 override 1.0 override
    no_blur = on
    force_rgbx = on
    opaque = on
}

EOF
    hyprctl keyword source "$TRANSP_CONF"
fi