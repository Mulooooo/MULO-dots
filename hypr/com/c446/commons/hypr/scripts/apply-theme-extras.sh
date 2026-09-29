#!/usr/bin/env bash
# Apply theme-owned adapters that are not part of active/.
set -euo pipefail

MANIFEST="$1"
THEME_DIR="$2"
COMMONS="$3"
CONFIG="$4"

toml_get() {
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\?\([^\"]*\)\"\?[[:space:]]*$/\1/p" "$2" | head -n1
}

upsert_section_ini() { # file section key value
    local file="$1" section="$2" key="$3" value="$4"
    [ -f "$file" ] || printf '[%s]\n' "$section" > "$file"
    if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    elif grep -q "^\[${section}\]" "$file"; then
        sed -i "/^\[${section}\]/a ${key}=${value}" "$file"
    else
        printf '\n[%s]\n%s=%s\n' "$section" "$key" "$value" >> "$file"
    fi
}

apply_gtk_css() {
    local version source target
    for version in 3.0 4.0; do
        source="$COMMONS/gtk/gtk-$version/gtk.css"
        [ -f "$THEME_DIR/gtk/gtk-$version/gtk.css" ] && source="$THEME_DIR/gtk/gtk-$version/gtk.css"
        [ -f "$source" ] || continue
        target="$HOME/.config/gtk-$version/gtk.css"
        mkdir -p "$(dirname "$target")"
        cp -f "$source" "$target"
    done
}

apply_qt() {
    local scheme style icons palette toolkit source target kvantum
    scheme="$(toml_get qt_color_scheme "$MANIFEST")"
    style="$(toml_get qt_style "$MANIFEST")"
    icons="$(toml_get qt_icon_theme "$MANIFEST")"
    palette="$(toml_get qt_custom_palette "$MANIFEST")"
    kvantum="$(toml_get qt_kvantum_theme "$MANIFEST")"
    [ -n "$scheme$style$icons$kvantum" ] || return 0

    for toolkit in qt5ct qt6ct; do
        target="$CONFIG/$toolkit/$toolkit.conf"
        if [ -n "$scheme" ]; then
            source="$THEME_DIR/qt/$toolkit/colors/$scheme.conf"
            [ -f "$source" ] || continue
            mkdir -p "$CONFIG/$toolkit/colors"
            cp -f "$source" "$CONFIG/$toolkit/colors/$scheme.conf"
            upsert_section_ini "$target" Appearance color_scheme_path "$CONFIG/$toolkit/colors/$scheme.conf"
        fi
        [ -n "$palette" ] && upsert_section_ini "$target" Appearance custom_palette "$palette"
        [ -n "$icons" ] && upsert_section_ini "$target" Appearance icon_theme "$icons"
        [ -n "$style" ] && upsert_section_ini "$target" Appearance style "$style"
    done
    if [ -n "$kvantum" ] && [ -f "$THEME_DIR/qt/Kvantum/kvantum.kvconfig" ]; then
        mkdir -p "$CONFIG/Kvantum"
        cp -f "$THEME_DIR/qt/Kvantum/kvantum.kvconfig" "$CONFIG/Kvantum/kvantum.kvconfig"
    fi
}

apply_vscode() {
    command -v code >/dev/null 2>&1 || return 0
    local theme colors background settings
    theme="$(toml_get vscode_theme "$MANIFEST")"
    colors="$(toml_get vscode_colors "$MANIFEST")"
    background="$(toml_get vscode_background "$MANIFEST")"
    [ -n "$theme" ] || return 0
    settings="$CONFIG/Code/User/settings.json"
    mkdir -p "$(dirname "$settings")"
    [ -f "$settings" ] || printf '{}\n' > "$settings"
    python3 - "$settings" "$theme" "$THEME_DIR/$colors" "$HOME/Pictures/$background" <<'PY'
import json
import os
import sys

settings_path, theme, colors_path, background_path = sys.argv[1:]
try:
    with open(settings_path) as fh:
        settings = json.load(fh)
except (OSError, ValueError):
    settings = {}
settings["workbench.colorTheme"] = theme
if os.path.isfile(colors_path):
    with open(colors_path) as fh:
        settings.update(json.load(fh))
else:
    settings.pop("workbench.colorCustomizations", None)
if os.path.isfile(background_path):
    settings.setdefault("background.editor", {})["images"] = [background_path]
with open(settings_path, "w") as fh:
    json.dump(settings, fh, indent=2)
    fh.write("\n")
PY
}

apply_intellij() {
    local laf scheme source product options
    laf="$(toml_get intellij_laf "$MANIFEST")"
    scheme="$(toml_get intellij_color_scheme "$MANIFEST")"
    [ -n "$laf$scheme" ] || return 0
    source="$THEME_DIR/intellij/colors/Miyabi Light.icls"
    while IFS= read -r -d '' options; do
        product="$(dirname "$options")"
        [ -f "$source" ] && { mkdir -p "$product/colors"; cp -f "$source" "$product/colors/Miyabi Light.icls"; }
        python3 - "$options" "$laf" "$scheme" <<'PY'
import pathlib
import re
import sys

options = pathlib.Path(sys.argv[1])
laf, scheme = sys.argv[2:]

colors = options / "colors.scheme.xml"
text = colors.read_text() if colors.exists() else "<application>\n</application>\n"
component = f'  <component name="EditorColorsManagerImpl">\n    <global_color_scheme name="{scheme}" />\n  </component>'
if "global_color_scheme" in text:
    text = re.sub(r'  <component name="EditorColorsManagerImpl">.*?</component>', component, text, flags=re.S)
else:
    text = text.replace("</application>", f"{component}\n</application>")
colors.write_text(text)

laf_file = options / "laf.xml"
text = laf_file.read_text() if laf_file.exists() else "<application>\n</application>\n"
line = f'    <laf themeId="{laf}" />'
if '<laf themeId=' in text:
    text = re.sub(r'    <laf themeId="[^"]+" />', line, text, count=1)
else:
    block = f'  <component name="LafManager">\n{line}\n  </component>\n'
    text = text.replace("</application>", f"{block}</application>")
laf_file.write_text(text)
PY
    done < <(find "$CONFIG/JetBrains" -type d -name options -print0 2>/dev/null)
}

apply_spicetify() {
    command -v spicetify >/dev/null 2>&1 || return 0
    local theme scheme source target
    theme="$(toml_get spicetify_theme "$MANIFEST")"
    scheme="$(toml_get spicetify_scheme "$MANIFEST")"
    [ -n "$theme" ] || return 0
    source="$THEME_DIR/spicetify"
    [ -f "$source/color.ini" ] && [ -f "$source/user.css" ] || return 0
    target="$HOME/.config/spicetify/Themes/$theme"
    mkdir -p "$target"
    cp -f "$source/color.ini" "$source/user.css" "$target/"
    spicetify config current_theme "$theme" color_scheme "${scheme:-$theme}" >/dev/null
    spicetify apply >/dev/null 2>&1
}

apply_gtk_css
apply_qt
apply_vscode
apply_intellij
apply_spicetify
