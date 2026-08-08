hl.monitor({
    output = "eDP-1",
    mode = "2560x1600@240",
    position = "0x0",
    scale = 1.33,
})

hl.monitor({
    output = "HDMI-A-1",
    mode = "2560x1440@59.95",
    position = "-1920x0",
    scale = 1.33,
})

for workspace = 1, 10 do
    hl.workspace_rule({ workspace = workspace, monitor = "eDP-1" })
end

for workspace = 11, 20 do
    if workspace ~= 18 then
        hl.workspace_rule({ workspace = workspace, monitor = "HDMI-A-1" })
    end
end
