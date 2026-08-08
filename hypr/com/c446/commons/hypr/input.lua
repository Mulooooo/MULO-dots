hl.config({
    input = {
        kb_layout = "fr",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = false,
            tap_to_click = true,
            disable_while_typing = true,
        },
    },
})

hl.device({
    name = "epic-mouse-v1",
    sensitivity = -0.5,
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.config({
    gestures = {
        workspace_swipe_distance = 250,
        workspace_swipe_invert = false,
        workspace_swipe_forever = true,
    },
})
