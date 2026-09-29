-- Stable laptop panel rule.
-- Keep your existing panel mode/scale; the automatic manager handles everything
-- external without hard-coding HDMI-A-1 / DP-* connector names.
hl.monitor({
    output = "eDP-1",
    mode = "2560x1600@240",
    position = "0x0",
    scale = 1.33,
})

-- Hyprland's recommended catch-all pattern for random/hot-plugged displays.
-- Explicit monitor rules (like eDP-1 above) win; everything else gets a safe
-- preferred mode and is placed to the left, centered against the primary.
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto-center-left",
    scale = 1,
})

-- Primary workspace bank is always anchored to the laptop panel.
for workspace = 1, 10 do
    hl.workspace_rule({ workspace = tostring(workspace), monitor = "eDP-1" })
end

-- Workspaces 11-20 are intentionally NOT hard-coded here. monitor-manager.sh
-- binds them to whichever external display is actually connected, and moves them
-- back to the primary when that display disappears.

-- Hyprland 0.55+ exposes native Lua monitor/config events. Use them to trigger
-- the Bash reconciler instead of keeping a second IPC/socat daemon alive.
local function reconcile_monitors()
    hl.exec_cmd("~/.config/hypr/scripts/monitor-manager.sh apply")
end

hl.on("monitor.added", reconcile_monitors)
hl.on("monitor.removed", reconcile_monitors)
hl.on("config.reloaded", reconcile_monitors)
