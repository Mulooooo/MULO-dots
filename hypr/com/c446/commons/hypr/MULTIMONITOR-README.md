# Automatic multi-monitor changes

This version replaces the HDMI-A-1-specific hotplug stack with `scripts/monitor-manager.sh`.

## Automatic behavior

- `eDP-1` remains the primary display at your existing `2560x1600@240`, scale `1.33`.
- Any unknown external output gets Hyprland's fallback rule: `preferred`, `auto-center-left`, scale `1`.
- Native Hyprland Lua events call the Bash reconciler after monitor add/remove and config reload events; there is no extra socket watcher process.
- Workspaces 1-10 stay on the primary. Workspaces 11-20 follow the selected external monitor. On unplug they move back to the primary; on reconnect they move back out.
- If multiple externals exist, the manager remembers the preferred external by EDID description. Without history it prefers HDMI, then DP, then other outputs.
- No `wl-mirror` is started automatically. Native Hyprland mirroring is available as a toggle.

## Keys kept/reworked

- `SUPER+CTRL+P`: recover/re-enable the current external using preferred mode, then safe advertised modes if necessary.
- `SUPER+SHIFT+P`: cycle the selected external's actual advertised modes.
- `SUPER+ALT+P`: toggle native Hyprland mirroring / extended desktop.
- `SUPER+P`: unchanged (your pin-window action).

The duplicate/hard-coded `SUPER+9` bindings were removed. Your normal workspace-9 binding from the workspace loop remains.

## Useful commands

```bash
~/.config/hypr/scripts/monitor-manager.sh status
~/.config/hypr/scripts/monitor-manager.sh apply
~/.config/hypr/scripts/monitor-manager.sh recover
~/.config/hypr/scripts/monitor-manager.sh focus-secondary
~/.config/hypr/scripts/monitor-manager.sh prefer-focused
```

## Optional physical-monitor profiles

Edit `~/.config/hypr/monitor-profiles.tsv` if one display needs a special mode/scale/position. Matching uses the EDID description as well as the connector, so a dock changing `DP-3` to `DP-5` does not break the profile.

Format (TAB-separated):

```text
REGEX    MODE    POSITION    SCALE
```

Example:

```text
Dell.*U2723QE    3840x2160@60    auto-center-left    1.5
```

## Old scripts

`hdmi-events.sh`, `start-hdmi.sh`, and `cycle-hdmi-mode.sh` are left in the folder only as rollback/reference files. They are no longer started or bound.
