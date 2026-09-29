#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# theme-switch.sh — activate a palette across the c446 dotfiles.
#
#   ./theme-switch.sh <name>     Activate themes/<name>
#   ./theme-switch.sh --list     List available themes
#
# Mechanism: "active-dir indirection" for application configs, with Hyprland
# theme selection handled inside hyprland.lua from ~/.cache/c446-theme.
#   - active/<app> is rebuilt as a tree of symlinks for non-Hyprland apps.
#   - ~/.config/hypr points directly at commons/hypr and is never swapped.
#   - ~/.config/<app> points at active/<app> (set once, idempotent), so editing
#     a source file in the repo is reflected live.
# -----------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMONS="$ROOT/commons"
THEMES="$ROOT/themes"
ACTIVE="$ROOT/active"
CONFIG="$HOME/.config"
STATE_FILE="$HOME/.cache/c446-theme"

# Apps whose ~/.config/<app> is a clean directory symlink we manage.
LINKED_APPS=(hypr waybar kitty rofi dunst)
# Apps assembled into active/ (linked or deployed separately).
ALL_APPS=(waybar kitty rofi fish fastfetch textfox dunst)

c_ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
c_warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
c_step() { printf '\033[1;35m▸ %s\033[0m\n' "$*"; }

toml_get() { # key file
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\?\([^\"]*\)\"\?[[:space:]]*$/\1/p" "$2" | head -n1
}

list_themes() {
    echo "Available themes:"
    for d in "$THEMES"/*/; do [ -d "$d" ] && echo "  - $(basename "$d")"; done
}

# Build active/<app> = commons overlaid by the theme, as absolute symlinks.
# Hyprland is deliberately excluded: its config path is stable and its Lua
# theme module reads STATE_FILE on every reload.
build_active() {
    c_step "Building active/ tree"
    mkdir -p "$ACTIVE"
    local app dest tmp
    for app in "${ALL_APPS[@]}"; do
        dest="$ACTIVE/$app"; tmp="$ACTIVE/.$app.tmp.$$"
        rm -rf "$tmp"; mkdir -p "$tmp"
        [ -d "$COMMONS/$app" ] && cp -as "$COMMONS/$app/." "$tmp/" 2>/dev/null
        [ -d "$TDIR/$app" ]    && cp -asf "$TDIR/$app/." "$tmp/" 2>/dev/null
        rm -rf "$dest"; mv "$tmp" "$dest"
        c_ok "active/$app"
    done
}

# Point ~/.config/<app> at active/<app> for apps we fully manage.
link_config() {
    c_step "Linking ~/.config"
    local app target link
    for app in "${LINKED_APPS[@]}"; do
        target="$ACTIVE/$app"; link="$CONFIG/$app"
        [ "$app" = hypr ] && target="$COMMONS/hypr"
        if [ "$(readlink -f "$link" 2>/dev/null)" = "$target" ]; then
            c_ok "~/.config/$app (already linked)"
        elif [ -L "$link" ] || [ ! -e "$link" ]; then
            if ! rm -f "$link" || ! ln -sfn "$target" "$link"; then
                c_warn "could not link ~/.config/$app → $target"
                return 1
            fi
            c_ok "~/.config/$app → $target"
        else
            c_warn "~/.config/$app is a real dir — backing up to $app.pre-c446"
            if ! mv "$link" "$link.pre-c446" || ! ln -sfn "$target" "$link"; then
                c_warn "could not link ~/.config/$app → $target"
                return 1
            fi
        fi
    done
}

# fish / fastfetch: only link if symlink or absent (avoid clobbering real data).
link_optional() {
    local app target link
    for app in fish fastfetch; do
        target="$ACTIVE/$app"; link="$CONFIG/$app"
        if [ "$(readlink -f "$link" 2>/dev/null)" = "$target" ]; then c_ok "~/.config/$app (already linked)"
        elif [ -L "$link" ] || [ ! -e "$link" ]; then rm -f "$link"; ln -sfn "$target" "$link"; c_ok "~/.config/$app → active/$app"
        else c_warn "~/.config/$app exists (real dir) — left untouched"; fi
    done
}

# Install + enable a systemd user service that runs `--ensure` before the
# compositor session, guaranteeing the selected theme state exists at login.
install_boot_guard() {
    command -v systemctl >/dev/null 2>&1 || { c_warn "systemctl missing — boot guard skipped"; return; }
    local unit_dir="$CONFIG/systemd/user" unit="c446-active.service"
    mkdir -p "$unit_dir"
    cat > "$unit_dir/$unit" <<EOF
[Unit]
Description=c446 — rebuild active/ theme tree before the Hyprland session
Before=graphical-session-pre.target
PartOf=graphical-session-pre.target

[Service]
Type=oneshot
ExecStart=$ROOT/theme-switch.sh --ensure

[Install]
WantedBy=graphical-session-pre.target
EOF
    systemctl --user daemon-reload >/dev/null 2>&1
    systemctl --user enable "$unit" >/dev/null 2>&1 && c_ok "boot guard enabled ($unit)" \
        || c_warn "could not enable $unit"
}

[ $# -eq 1 ] || { echo "usage: $0 <name> | --ensure | --list"; exit 1; }
[ "$1" = "--list" ] && { list_themes; exit 0; }

# --ensure: lightweight boot guard. Rebuild active/ + relink ~/.config from the
# last-used theme, then exit — no reloads, no Firefox/GTK/wallpaper deploy. Runs
# before the compositor so Hyprland always finds a real config at startup.
if [ "$1" = "--ensure" ]; then
    TDIR="$(cat "$STATE_FILE" 2>/dev/null)"
    if [ -z "$TDIR" ] || [ ! -d "$TDIR" ]; then
        for d in "$THEMES"/*/; do [ -d "$d" ] && { TDIR="${d%/}"; break; }; done
    fi
    [ -d "$TDIR" ] || { echo "❌ no theme available for --ensure"; exit 1; }
    mkdir -p "$(dirname "$STATE_FILE")"
    printf '%s\n' "$TDIR" > "$STATE_FILE"
    build_active
    link_config || exit 1
    link_optional
    exit 0
fi

THEME="$1"
TDIR="$THEMES/$THEME"
MANIFEST="$TDIR/theme.toml"
[ -d "$TDIR" ]      || { echo "❌ Unknown theme '$THEME'"; list_themes; exit 1; }
[ -f "$MANIFEST" ]  || { echo "❌ Missing $MANIFEST"; exit 1; }

echo "🎨 Switching to theme: $THEME"
mkdir -p "$ACTIVE" "$(dirname "$STATE_FILE")"
echo "$TDIR" > "$STATE_FILE"

# --- 1. Build active/ + link ~/.config ----------------------------------------
build_active
link_config || exit 1
link_optional

# --- 1b. Boot guard: ensure active/ exists before the next login's compositor --
c_step "Boot guard"
install_boot_guard

# --- 3. GTK / icons / cursor --------------------------------------------------
c_step "GTK / icons / cursor"
mkdir -p "$HOME/.themes" "$HOME/.icons"
GTK_THEME="$(toml_get gtk_theme "$MANIFEST")"
CURS="$(toml_get cursor "$MANIFEST")"
if [ -n "$GTK_THEME" ] && [ ! -d "$HOME/.themes/$GTK_THEME" ]; then
    for z in "$TDIR"/gtk/*.zip; do [ -e "$z" ] && unzip -oq "$z" -d "$HOME/.themes/" && c_ok "unzipped $(basename "$z")"; done
fi
if [ -n "$CURS" ] && [ ! -d "$HOME/.icons/$CURS" ]; then
    for z in "$TDIR"/gtk/*Cursor*.zip "$TDIR"/gtk/*ursor*.zip; do [ -e "$z" ] && unzip -oq "$z" -d "$HOME/.icons/"; done
fi
# Make the active cursor the system default so Xwayland apps (e.g. Spotify)
# stop falling back to the wrong/big X cursor. This is the canonical fix.
if [ -n "$CURS" ]; then
    mkdir -p "$HOME/.icons/default"
    printf '[Icon Theme]\nName=Default\nComment=Active c446 cursor\nInherits=%s\n' "$CURS" > "$HOME/.icons/default/index.theme"
    c_ok "~/.icons/default inherits $CURS (Xwayland/Spotify cursor fix)"
    HYPRCURSOR_DIR="$TDIR/gtk/${CURS}-Hypr"
    [ -d "$HYPRCURSOR_DIR" ] || HYPRCURSOR_DIR="$THEMES/miyabi/gtk/${CURS}-Hypr"
    if [ -d "$HYPRCURSOR_DIR" ]; then
        mkdir -p "$HOME/.local/share/icons/$CURS"
        cp -rf "$HYPRCURSOR_DIR/." "$HOME/.local/share/icons/$CURS/"
        c_ok "~/.local/share/icons/$CURS (native Hyprcursor)"
    fi
fi
bash "$COMMONS/hypr/scripts/apply-theme.sh" "$MANIFEST" || c_warn "apply-theme.sh failed (gsettings/hyprctl unavailable?)"

# --- 4. Wallpapers ------------------------------------------------------------
# Mount the theme's wallpapers into ~/Pictures/{Backgrounds,fastfetch_assets}
# as per-file symlinks (no copying — avoids duplicating large videos/images).
c_step "Wallpapers"
mount_wall() { # <wallpapers-subdir>  — mounts commons then theme (theme overlays)
    local sub="$1" dest="$HOME/Pictures/$1" n=0 base wallpaper_theme wallpaper_dir
    wallpaper_theme="$(toml_get wallpaper_theme "$MANIFEST")"
    wallpaper_dir="$TDIR"
    [ -n "$wallpaper_theme" ] && [ -d "$THEMES/$wallpaper_theme" ] && wallpaper_dir="$THEMES/$wallpaper_theme"
    mkdir -p "$dest"
    for base in "$COMMONS/wallpapers/$sub" "$wallpaper_dir/wallpapers/$sub"; do
        [ -d "$base" ] || continue
        for f in "$base"/*; do
            [ -e "$f" ] && ln -sfn "$f" "$dest/$(basename "$f")" && n=$((n+1))
        done
    done
    c_ok "~/Pictures/$1 ($n file(s) mounted)"
}
mount_wall Backgrounds
mount_wall fastfetch_assets
FF_IMG="$(toml_get fastfetch_image "$MANIFEST")"
if [ -n "$FF_IMG" ] && [ -e "$HOME/Pictures/$FF_IMG" ]; then
    mkdir -p "$CONFIG/fastfetch"
    ln -sfn "$HOME/Pictures/$FF_IMG" "$CONFIG/fastfetch/fastfetch_cur" && c_ok "fastfetch_cur → ~/Pictures/$FF_IMG"
fi
bash "$COMMONS/hypr/scripts/apply-theme-extras.sh" "$MANIFEST" "$TDIR" "$COMMONS" "$CONFIG" || c_warn "apply-theme-extras.sh failed"

# --- 5. Vesktop (Discord) -----------------------------------------------------
c_step "Vesktop"
if [ -d "$TDIR/vesktop" ]; then
    mkdir -p "$CONFIG/vesktop/themes/assets"
    for css in "$TDIR"/vesktop/*.css; do
        [ -f "$css" ] || continue
        [ "$(basename "$css")" = "sys-24-miyabi-light.css" ] && continue
        dest="$CONFIG/vesktop/themes/$(basename "$css")"
        cp -f "$css" "$dest" && c_ok "vesktop theme deployed"
    done
    [ -d "$TDIR/vesktop/assets" ] && cp -rf "$TDIR/vesktop/assets/." "$CONFIG/vesktop/themes/assets/" 2>/dev/null
fi

# --- 6. Firefox / textfox -----------------------------------------------------
c_step "Firefox / textfox"
FF_ROOT="$HOME/.mozilla/firefox"
# Prefer the profile Firefox actually launches (profiles.ini [Install*] Default=),
# falling back to *.default-release, then any *.default*.
FF_PROFILE=""
if [ -f "$FF_ROOT/profiles.ini" ]; then
    rel="$(awk -F= '/^\[Install/{i=1} i&&/^Default=/{print $2; exit}' "$FF_ROOT/profiles.ini")"
    [ -n "$rel" ] && [ -d "$FF_ROOT/$rel" ] && FF_PROFILE="$FF_ROOT/$rel"
fi
[ -z "$FF_PROFILE" ] && FF_PROFILE="$(find "$FF_ROOT" -maxdepth 1 -type d -name '*.default-release' 2>/dev/null | head -n1)"
[ -z "$FF_PROFILE" ] && FF_PROFILE="$(find "$FF_ROOT" -maxdepth 1 -type d -name '*.default*' 2>/dev/null | head -n1)"
if [ -n "$FF_PROFILE" ]; then
    chrome="$FF_PROFILE/chrome"
    # Rebuild chrome/ from scratch. A prior deploy may have left symlinks here;
    # copying/bundling onto those would write THROUGH them into the repo source.
    # chrome/ is fully managed by this script, so a clean slate is safe.
    rm -rf "$chrome"; mkdir -p "$chrome"
    # Deploy REAL files (-L dereferences the active/ symlinks) so assets (icons/,
    # user.js) land in chrome/ and config.css resolves to the active theme.
    cp -rfL "$ACTIVE/textfox/." "$chrome/" 2>/dev/null && c_ok "textfox deployed → $chrome"
    # Flatten the @import trees into monoliths. about:newtab/about:home apply a
    # strict CSP that blocks @import'd sheets, so config.css / content/newtab.css
    # never reach the newtab as imports — bundling leaves no imports to block.
    bundler="$ROOT/scripts/css-bundle.py"
    if [ -f "$bundler" ] && command -v python3 >/dev/null 2>&1; then
        for entry in userContent.css userChrome.css; do
            if [ -f "$ACTIVE/textfox/$entry" ]; then
                python3 "$bundler" "$ACTIVE/textfox/$entry" "$chrome/$entry" \
                    && c_ok "bundled $entry" || c_warn "bundle failed: $entry"
            fi
        done
    else
        c_warn "css-bundle.py / python3 missing — chrome CSS left as @import (newtab unstyled)"
    fi
else
    c_warn "no Firefox default profile under ~/.mozilla/firefox — skipped"
fi

# --- 7. VS Code ---------------------------------------------------------------
c_step "VS Code"
VS_EXT="$(toml_get vscode_ext "$MANIFEST")"
VS_THEME="$(toml_get vscode_theme "$MANIFEST")"
if command -v code >/dev/null 2>&1; then
    [ -n "$VS_EXT" ] && code --install-extension "$VS_EXT" --force >/dev/null 2>&1 && c_ok "ext $VS_EXT"
    VS_SETTINGS="$CONFIG/Code/User/settings.json"
    if [ -n "$VS_THEME" ]; then
        mkdir -p "$(dirname "$VS_SETTINGS")"; [ -f "$VS_SETTINGS" ] || echo '{}' > "$VS_SETTINGS"
        python3 - "$VS_SETTINGS" "$VS_THEME" <<'PY' && c_ok "workbench.colorTheme = $VS_THEME"
import json, sys
p, theme = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(p))
except Exception:
    d = {}
d["workbench.colorTheme"] = theme
json.dump(d, open(p, "w"), indent=2)
PY
    fi
else
    c_warn "'code' CLI not found — set VS Code theme manually: $VS_THEME"
fi

# --- 8. IntelliJ is applied by apply-theme-extras.sh --------------------------

# --- 9. Reload running apps ---------------------------------------------------
c_step "Reloading"
command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 && c_ok "hyprland"
if command -v waybar >/dev/null 2>&1; then killall -SIGUSR2 waybar >/dev/null 2>&1 || true; c_ok "waybar"; fi
command -v kitty >/dev/null 2>&1 && kill -SIGUSR1 $(pgrep kitty) >/dev/null 2>&1 || true
if command -v dunst >/dev/null 2>&1; then
    systemctl --user restart dunst >/dev/null 2>&1 || { killall dunst >/dev/null 2>&1; setsid dunst >/dev/null 2>&1 & }
    c_ok "dunst"
fi

echo "✅ Theme '$THEME' active."
