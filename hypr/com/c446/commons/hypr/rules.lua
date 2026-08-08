hl.layer_rule({ match = { namespace = "^(notifications|waybar)$" }, blur = true })
hl.layer_rule({ match = { namespace = "^(notifications|waybar)$" }, ignore_alpha = 0.5 })

local ide = "^(code-url-handler|code|jetbrains-idea|jetbrains-pycharm-ce)$"

hl.window_rule({
    name = "global-defaults",
    match = { class = ".*" },
    opacity = "1.0 override 1.0 override 1.0 override",
    no_blur = true,
    force_rgbx = true,
    opaque = true,
})

hl.window_rule({
    name = "generic-ide",
    match = { class = ide },
    workspace = "3 silent",
})

hl.window_rule({
    name = "generic-opaque",
    match = { class = "^(xfreerdp|firefox)$" },
    opacity = "1.0 override 1.0 override 1.0 override",
    no_blur = true,
    force_rgbx = true,
    opaque = true,
})
hl.window_rule({ name = "firefox-workspace", match = { class = "^firefox$" }, workspace = "1 silent" })
hl.window_rule({ name = "spotify-workspace", match = { class = "^(spotify|Spotify)$" }, workspace = "2 silent" })
hl.window_rule({name="ides_in_workspace_3", match={class=ide}, workspace="3"})
hl.window_rule({ name = "steam-client", match = { class = "^(steam)$" }, workspace = "5" })
hl.window_rule({ name = "xfreerdp-workspace", match = { class = "^xfreerdp$" }, workspace = "6 silent" })

hl.window_rule({
    name = "zenless-no-modeset-thrash",
    match = { class = "^(steam_app_4162040)$" },
    suppress_event = "fullscreen maximize",
})
