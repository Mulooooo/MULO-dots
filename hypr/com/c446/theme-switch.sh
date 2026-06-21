#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# theme-switch.sh — activate a palette across the c446 dotfiles.
#
#   ./theme-switch.sh <name>     Activate themes/<name>
#   ./theme-switch.sh --list     List available themes
#
# Mechanism: "active-dir indirection".
#   - active/<app> is rebuilt as a tree of symlinks: commons/<app> overlaid by
#     themes/<name>/<app> (theme wins on filename collision).
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
LINKED_APPS=(hypr waybar kitty rofi)
# Apps assembled into active/ (linked or deployed separately).
ALL_APPS=(hypr waybar kitty rofi fish fastfetch textfox)

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

[ $# -eq 1 ] || { echo "usage: $0 <name> | --list"; exit 1; }
[ "$1" = "--list" ] && { list_themes; exit 0; }

THEME="$1"
TDIR="$THEMES/$THEME"
MANIFEST="$TDIR/theme.toml"
[ -d "$TDIR" ]      || { echo "❌ Unknown theme '$THEME'"; list_themes; exit 1; }
[ -f "$MANIFEST" ]  || { echo "❌ Missing $MANIFEST"; exit 1; }

echo "🎨 Switching to theme: $THEME"
mkdir -p "$ACTIVE" "$(dirname "$STATE_FILE")"
echo "$TDIR" > "$STATE_FILE"

# --- 1. Build active/ (commons overlaid by theme, as absolute symlinks) -------
c_step "Building active/ tree"
for app in "${ALL_APPS[@]}"; do
    dest="$ACTIVE/$app"
    rm -rf "$dest"; mkdir -p "$dest"
    [ -d "$COMMONS/$app" ] && cp -as "$COMMONS/$app/." "$dest/" 2>/dev/null
    [ -d "$TDIR/$app" ]    && cp -asf "$TDIR/$app/." "$dest/" 2>/dev/null
    c_ok "active/$app"
done

# --- 2. Point ~/.config/<app> at active/<app> (idempotent, safe) --------------
c_step "Linking ~/.config"
for app in "${LINKED_APPS[@]}"; do
    target="$ACTIVE/$app"; link="$CONFIG/$app"
    if [ "$(readlink -f "$link" 2>/dev/null)" = "$target" ]; then
        c_ok "~/.config/$app (already linked)"
    elif [ -L "$link" ] || [ ! -e "$link" ]; then
        rm -f "$link"; ln -sfn "$target" "$link"; c_ok "~/.config/$app → active/$app"
    else
        c_warn "~/.config/$app is a real dir — backing up to $app.pre-c446"
        mv "$link" "$link.pre-c446"; ln -sfn "$target" "$link"
    fi
done
# fish / fastfetch: only link if symlink or absent (avoid clobbering real data)
for app in fish fastfetch; do
    target="$ACTIVE/$app"; link="$CONFIG/$app"
    if [ "$(readlink -f "$link" 2>/dev/null)" = "$target" ]; then c_ok "~/.config/$app (already linked)"
    elif [ -L "$link" ] || [ ! -e "$link" ]; then rm -f "$link"; ln -sfn "$target" "$link"; c_ok "~/.config/$app → active/$app"
    else c_warn "~/.config/$app exists (real dir) — left untouched"; fi
done

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
fi
bash "$COMMONS/hypr/scripts/apply-theme.sh" "$MANIFEST" || c_warn "apply-theme.sh failed (gsettings/hyprctl unavailable?)"

# --- 4. Wallpapers ------------------------------------------------------------
c_step "Wallpapers"
if [ -d "$TDIR/wallpapers" ]; then
    mkdir -p "$HOME/Pictures"
    cp -rf "$TDIR/wallpapers/." "$HOME/Pictures/" && c_ok "deployed wallpapers → ~/Pictures"
    FF_IMG="$(toml_get fastfetch_image "$MANIFEST")"
    [ -n "$FF_IMG" ] && [ -e "$HOME/Pictures/$FF_IMG" ] && ln -sfn "$HOME/Pictures/$FF_IMG" "$CONFIG/fastfetch/fastfetch_cur" 2>/dev/null
fi

# --- 5. Vesktop (Discord) -----------------------------------------------------
c_step "Vesktop"
if [ -d "$TDIR/vesktop" ]; then
    mkdir -p "$CONFIG/vesktop/themes/assets"
    cp -f "$TDIR"/vesktop/*.css "$CONFIG/vesktop/themes/" 2>/dev/null && c_ok "vesktop theme deployed"
    [ -d "$TDIR/vesktop/assets" ] && cp -rf "$TDIR/vesktop/assets/." "$CONFIG/vesktop/themes/assets/" 2>/dev/null
fi

# --- 6. Firefox / textfox -----------------------------------------------------
c_step "Firefox / textfox"
FF_PROFILE="$(find "$HOME/.mozilla/firefox" -maxdepth 1 -type d -name '*.default*' 2>/dev/null | head -n1)"
if [ -n "$FF_PROFILE" ]; then
    chrome="$FF_PROFILE/chrome"; mkdir -p "$chrome"
    cp -rf "$ACTIVE/textfox/." "$chrome/" 2>/dev/null && c_ok "textfox deployed → $chrome"
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

# --- 8. IntelliJ (best-effort, skipped if no clean path) ----------------------
INTELLIJ_NOTE="IntelliJ: set the editor scheme manually (Settings → Appearance)."
c_warn "$INTELLIJ_NOTE"

# --- 9. Reload running apps ---------------------------------------------------
c_step "Reloading"
command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 && c_ok "hyprland"
if command -v waybar >/dev/null 2>&1; then killall -SIGUSR2 waybar >/dev/null 2>&1 || true; c_ok "waybar"; fi
command -v kitty >/dev/null 2>&1 && kill -SIGUSR1 $(pgrep kitty) >/dev/null 2>&1 || true

echo "✅ Theme '$THEME' active."
