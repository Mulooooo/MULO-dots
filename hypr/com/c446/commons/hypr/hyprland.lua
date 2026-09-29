-- Native Hyprland Lua configuration.
-- Hyprland 0.55+ loads this file as the compositor configuration.

require("env")
require("theme")
require("monitors")
require("appearance")
require("input")
require("binds")
require("rules")
require("autostart")

hl.config({
    master = {
        new_status = "master",
        mfact = 0.5,
    },
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
        vrr = 1,
        disable_autoreload = true,
    },
    xwayland = {
        force_zero_scaling =true, 
    },
    cursor = {
        no_hardware_cursors = true,
    },
})
