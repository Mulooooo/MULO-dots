hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("ANIMA_DIRECTORY","/home/clement/Games/SteamLibrary/steamapps/workshop/content/3474900")

-- Stable udev aliases; Intel is primary, NVIDIA remains available for secondary outputs.
hl.env("AQ_DRM_DEVICES", "/dev/dri/intel-card:/dev/dri/nvidia-card")
-- Do not force the Nvidia GBM backend globally; Intel is the primary DRM device.
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
hl.env("WLR_NO_HARDWARE_CURSORS", "1")

hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

-- At eDP-1 scale 1.33, a 24px logical cursor is 32px for XWayland.
hl.env("HYPRCURSOR_THEME", "Miyabi-Cursors")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Miyabi-Cursors")
hl.env("XCURSOR_SIZE", "32")
