hl.layer_rule({
    match = { namespace = "^(notifications|waybar)$" },
    blur = true,
})

hl.layer_rule({
    match = { namespace = "^(notifications|waybar)$" },
    ignore_alpha = 0.5,
})

-- Keep defaults conservative.
-- Avoid force_rgbx/opaque globally because they can break popup alpha/shadows.
hl.window_rule({
    name = "global-defaults",
    match = { class = ".*" },
    opacity = "1.0 override 1.0 override 1.0 override",
    no_blur = false,
})

-- Apps that genuinely benefit from being forced opaque.
hl.window_rule({
    name = "xfreerdp-opaque",
    match = { class = "^xfreerdp$" },
    opacity = "1.0 override 1.0 override 1.0 override",
    no_blur = true,
    force_rgbx = true,
    opaque = true,
})

-- ChatGPT pet
hl.window_rule({
    name = "chatgpt-pet-border",
    match = { class = "^Chatgpt$", float = true },
    border_size = 0,
})

hl.window_rule({
    name = "firefox-opaque",
    match = { class = "firefox" },
    opacity = "1.0 override 1.0 override 1.0 override",
    no_blur = true,
    force_rgbx = true,
    opaque = true,
})

-- Prevent fullscreen/maximize event thrashing for Zenless.
hl.window_rule({
    name = "zenless-no-modeset-thrash",
    match = { class = "^steam_app_4162040$" },
    suppress_event = "fullscreen maximize",
})
