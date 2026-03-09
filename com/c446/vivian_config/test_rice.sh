#!/usr/bin/env bash

# --- Configuration ---
SANDBOX_PATH="/tmp/vivian_rice_test"
DISPLAY_NUM=":1"
RESOLUTION="1280x720"
SANDBOX_RUNTIME="$SANDBOX_PATH/runtime"

echo "🚀 Launching Vivian Rice Sandbox..."

# 1. Cleanup
pkill -f "Xephyr $DISPLAY_NUM" || true
rm -rf "$SANDBOX_PATH"
mkdir -p "$SANDBOX_RUNTIME"
chmod 700 "$SANDBOX_RUNTIME"

# 2. Install (Redirection)
export HOME="$SANDBOX_PATH"
if [ -f "./sandbox-install.sh" ]; then
    bash ./sandbox-install.sh
else
    echo "❌ Error: sandbox-install.sh not found!"
    exit 1
fi

# 3. Launch Xephyr
Xephyr -br -ac -noreset -screen "$RESOLUTION" "$DISPLAY_NUM" &
XEPHYR_PID=$!
sleep 2

# 4. Sync Fonts (Fixes X Error 15)
xset -display "$DISPLAY_NUM" +fp /usr/share/fonts/misc,/usr/share/fonts/OTF,/usr/share/fonts/TTF
xset -display "$DISPLAY_NUM" fp rehash

# 5. Launch i3 with Forced Socket Redirection
# 5. Launch i3 with "Inherited" Environment
# Push your host keyboard layout into the sandbox
setxkbmap -display "$DISPLAY_NUM" $(setxkbmap -query | grep layout | awk '{print $2}')
echo "⌨️ Starting i3..."

export I3SOCK="$SANDBOX_RUNTIME/i3-ipc.sock"

# We use 'env' to ensure every child process (terminals, polybar) 
# sees the Sandbox as its true home.
DISPLAY="$DISPLAY_NUM" \
HOME="$SANDBOX_PATH" \
XDG_RUNTIME_DIR="$SANDBOX_RUNTIME" \
XDG_CONFIG_HOME="$SANDBOX_PATH/.config" \
env DISPLAY="$DISPLAY_NUM" \
    HOME="$SANDBOX_PATH" \
    XDG_RUNTIME_DIR="$SANDBOX_RUNTIME" \
    i3 -c "$SANDBOX_PATH/.config/i3/config" -V >> "$SANDBOX_PATH/i3_log.txt" 2>&1 &


echo "---"
echo "✅ Sandbox is live!"
echo "Keyboard Focus: Press Ctrl+Shift inside the window"
echo "---"

wait $XEPHYR_PID