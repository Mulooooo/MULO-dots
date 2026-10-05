local main_mod = "SUPER"
local digit_codes = { [1] = "code:10", [2] = "code:11", [3] = "code:12", [4] = "code:13", [5] = "code:14", [6] = "code:15", [7] = "code:16", [8] = "code:17", [9] = "code:18", [10] = "code:19" }

local function bind(key, dispatcher, flags)
    hl.bind(main_mod .. " + " .. key, dispatcher, flags)
end

local function exec(key, command, flags)
    bind(key, hl.dsp.exec_cmd(command), flags)
end

local function workspace_bind(modifiers, key, workspace)
    local prefix = main_mod
    if modifiers ~= "" then prefix = prefix .. " + " .. modifiers end
    hl.bind(prefix .. " + " .. key, hl.dsp.focus({ workspace = workspace }))
end

local function move_workspace_bind(modifiers, key, workspace)
    local prefix = main_mod
    if modifiers ~= "" then prefix = prefix .. " + " .. modifiers end
    hl.bind(prefix .. " + " .. key, hl.dsp.window.move({ workspace = workspace, follow = false }))
end

for workspace = 1, 10 do
    local key = digit_codes[workspace]
    workspace_bind("", key, workspace)
    move_workspace_bind("SHIFT", key, workspace)
end

for workspace = 11, 20 do
    local key = digit_codes[workspace - 10]
    workspace_bind("CONTROL", key, workspace)
    move_workspace_bind("SHIFT + CONTROL", key, workspace)
end

bind("TAB", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(main_mod .. " + SHIFT + TAB", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(main_mod .. " + SHIFT + E", hl.dsp.exit())

exec("RETURN", "kitty")
exec("E", "kitty yazi")
exec("S", "rofi -show drun")
exec("COMMA", "noctalia msg settings-toggle")
exec("W", "noctalia msg panel-toggle wallpaper")
exec("A", "rofi -show window")
exec("SEMICOLON", "rofi -show emoji")
exec("Z", "rofi -modi emoji -show emoji -emoji-text | wl-copy")
bind("F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
exec("SHIFT + T", "~/.config/hypr/scripts/hypr_mono.sh")
exec("SHIFT + G", "~/.config/hypr/scripts/transparency.sh")
exec("G", "~/.config/hypr/scripts/gamemode.sh")
exec("code:67", "~/.config/hypr/scripts/set-power-profile.sh performance")
exec("code:68", "~/.config/hypr/scripts/set-power-profile.sh quiet")
exec("code:69", "~/.config/hypr/scripts/set-power-profile.sh balanced")
bind("Q", hl.dsp.window.close())
bind("SHIFT + SPACE", hl.dsp.window.float({ action = "toggle" }))
exec("SHIFT + Y", "~/.config/hypr/scripts/record.zsh")

for key, direction in pairs({
    LEFT = "l", RIGHT = "r", UP = "u", DOWN = "d",
    H = "l", J = "d", K = "u", L = "r",
}) do
    bind(key, hl.dsp.focus({ direction = direction }))
    bind("SHIFT + " .. key, hl.dsp.window.move({ direction = direction }))
end

bind("SPACE", hl.dsp.layout("swapwithmaster"))
-- Master layout does not use the dwindle-only togglesplit message.
bind("D", hl.dsp.layout("addmaster"))
bind("SHIFT + D", hl.dsp.layout("removemaster"))

bind("R", hl.dsp.submap("arrange"))
hl.define_submap("arrange", function()
    for key, direction in pairs({
        LEFT = "l", RIGHT = "r", UP = "u", DOWN = "d",
        H = "l", J = "d", K = "u", L = "r",
    }) do
        hl.bind(key, hl.dsp.focus({ direction = direction }))
        hl.bind("SHIFT + " .. key, hl.dsp.window.move({ direction = direction }))
    end
    hl.bind("CTRL + LEFT", hl.dsp.window.resize({ x = -40, y = 0, relative = true }), { repeating = true })
    hl.bind("CTRL + RIGHT", hl.dsp.window.resize({ x = 40, y = 0, relative = true }), { repeating = true })
    hl.bind("CTRL + UP", hl.dsp.window.resize({ x = 0, y = -40, relative = true }), { repeating = true })
    hl.bind("CTRL + DOWN", hl.dsp.window.resize({ x = 0, y = 40, relative = true }), { repeating = true })
    hl.bind("SPACE", hl.dsp.layout("swapwithmaster"))
    hl.bind("A", hl.dsp.layout("addmaster"))
    hl.bind("D", hl.dsp.layout("removemaster"))
    hl.bind("ESCAPE", hl.dsp.submap("reset"))
    hl.bind("RETURN", hl.dsp.submap("reset"))
end)

bind("SHIFT + X", hl.dsp.exec_cmd("hyprlock"))
exec("M", "~/.config/hypr/scripts/notify-mute.sh")
exec("SHIFT + M", "~/.config/hypr/scripts/mute-focused.sh")
-- The Razer BlackWidow Elite volume wheel is faulty; leave its events inert.
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("~/.config/hypr/scripts/notify-mute.sh"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set +5% && ~/.config/hypr/scripts/notify-brightness.sh"), { repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%- && ~/.config/hypr/scripts/notify-brightness.sh"), { repeating = true })

hl.bind(main_mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(main_mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

exec("SHIFT + S", 'grimblast --notify copysave area "$HOME/Pictures/screenshot/$(date +%Y-%m-%d_%H-%M-%S).png"')
exec("PRINT", 'grimblast --notify copysave output "$HOME/Pictures/screenshot/$(date +%Y-%m-%d_%H-%M-%S).png"')
hl.bind("Print", hl.dsp.exec_cmd("c"))
exec("HOME", "grimblast copy active")

bind("P", function()
    hl.dispatch(hl.dsp.window.float({ action = "set" }))
    hl.dispatch(hl.dsp.window.pin({ action = "toggle" }))
end)
exec("CTRL + P", "~/.config/hypr/scripts/monitor-manager.sh recover")
exec("SHIFT + P", "~/.config/hypr/scripts/monitor-manager.sh mode-next")
exec("ALT + P", "~/.config/hypr/scripts/monitor-manager.sh mirror-toggle")

exec("SHIFT + V", "~/.config/hypr/scripts/round-robin-paste.sh")
