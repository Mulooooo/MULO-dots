-- Load the selected palette directly from the theme-switcher's state file.
local home = os.getenv("HOME") or ""
local cache_home = os.getenv("XDG_CACHE_HOME") or (home .. "/.cache")
local state_file = cache_home .. "/c446-theme"
local state = io.open(state_file, "r")
local theme_dir = state and state:read("*l") or nil
if state then state:close() end

if theme_dir and theme_dir ~= "" then
    local ok, err = pcall(dofile, theme_dir .. "/hypr/theme.lua")
    if not ok then
        print("c446: failed to load theme " .. theme_dir .. ": " .. tostring(err))
    end
end

-- Keep the base config valid when started before the boot guard.
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_SIZE", "24")
