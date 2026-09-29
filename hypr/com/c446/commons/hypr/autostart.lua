local commands = {
    "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE",
    "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE",
    "systemctl --user start hyprland-session.target",
    "systemctl --user start xdg-desktop-portal-hyprland",
    "systemctl --user restart dunst",
    "systemctl start platform-profile@balanced-performance.service",
    "swww-daemon",
    "~/.config/hypr/scripts/wallpaper.sh",
    "~/.config/hypr/scripts/apply-theme.sh",
    "waybar",
    "~/.config/hypr/scripts/set_wallpaper.sh",
    "~/.config/hypr/scripts/monitor-manager.sh apply",
}

for _, command in ipairs(commands) do
    hl.on("hyprland.start", function()
        hl.exec_cmd(command)
    end)
end
