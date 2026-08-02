-- Hyprland Lua entrypoint.
--
-- The individual legacy fragments are intentionally loaded through hyprctl
-- while this tree is migrated. This keeps theme-switch.sh, transparency.sh,
-- and gamemode.sh compatible during the transition: Hyprland now starts from
-- Lua, while the existing fragments retain their tested ordering and values.
--
-- Hyprland resolves this file before hyprland.conf when both are present.

local fragments = {
    "env.conf",
    "theme.conf",
    "monitors.conf",
    "appearance.conf",
    "input.conf",
    "binds.conf",
    "rules.conf",
    "autostart.conf",
}

local config_dir = os.getenv("XDG_CONFIG_HOME")
if config_dir == nil or config_dir == "" then
    config_dir = os.getenv("HOME") .. "/.config"
end

local hypr_dir = config_dir .. "/hypr"
for _, fragment in ipairs(fragments) do
    hl.exec_cmd("hyprctl keyword source " .. hypr_dir .. "/" .. fragment)
end
