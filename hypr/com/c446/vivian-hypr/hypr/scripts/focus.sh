#!/usr/bin/env sh
# File path for our temporary override
REMOVE_TRANSP_CONF="/tmp/hypr_remove_transparency.conf"

# Check if our override is currently active
ACTIVE=$(hyprctl getoption animations:enabled | awk 'NR==1{print $2}')

if [ "$ACTIVE" = 1 ]; then
    # 1. Create a temporary config to remove transparency and blur
    cat <<EOF > "$REMOVE_TRANSP_CONF"
animations {
    enabled = 0
}
decoration {
    shadow {
        enabled = false
    }
    blur {
        enabled = false
    }
}
# Force all windows fully opaque and no blur
windowrule = opacity 1 override 1 override 1 override, match:class ^(.*)$
windowrule = no_blur on, match:class ^(.*)$
EOF

    hyprctl keyword source "$REMOVE_TRANSP_CONF"
else
    rm -f "$REMOVE_TRANSP_CONF"
    hyprctl reload
fi