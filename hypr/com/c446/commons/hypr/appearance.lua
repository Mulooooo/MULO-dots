hl.config({
    general = {
        gaps_in = 2,
        gaps_out = 4,
        border_size = 2,
        layout = "master",
    },
    decoration = {
        rounding = 0,
        blur = {
            enabled = true,
            size = 6,
            passes = 3,
            new_optimizations = true,
            ignore_opacity = true,
            noise = 0.05,
            brightness = 1,
        },
        shadow = {
            enabled = false,
        },
    },
    animations = {
        enabled = true,
    },
    render = {
        direct_scanout = 2,
    },
})

hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "myBezier", style = "popin 80%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 5, bezier = "myBezier", style = "popin 80%" })
hl.animation({ leaf = "border", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "fade", enabled = true, speed = 5, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "default", style = "slide 0%" })
