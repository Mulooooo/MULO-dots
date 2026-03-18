#!/usr/bin/env bash

set -e

# --- 1. Configuration & Setup ---
read -p "Enter your username to install for: " USR

if ! id "$USR" &>/dev/null; then
    echo "❌ Error: User '$USR' does not exist."
    exit 1
fi

USER_HOME="/home/$USR"
CONFIG="$USER_HOME/.config"
ICONS="$USER_HOME/.icons"
THEMES="$USER_HOME/.themes"
PICS="$USER_HOME/Pictures"

echo "🚀 Installing Vivian-Rice (User-space Edition) for $USR..."

# --- 2. The DRY Helper Function (Fixed for Assets & Configs) ---
deploy() {
    local src="$1"
    local dest="$2"
    local desc="$3"

    if [ -e "$src" ]; then
        echo "  -> Deploying $desc..."
        
        if [ -d "$src" ]; then
            # Ensure the destination folder exists
            mkdir -p "$dest"
            # Copy contents of src into dest
            cp -r "$src/." "$dest/"
        else
            # It's a single file; ensure parent directory exists
            mkdir -p "$(dirname "$dest")"
            cp "$src" "$dest"
        fi
    else
        echo "  ⚠️  Skipping $desc (Source not found: $src)"
    fi
}

# --- 3. Resource Mapping ---
# Note: For directories, $dest is the FOLDER where contents will live.
# For files, $dest is the full PATH to the file.
mappings=(
    "./hypr:$CONFIG/hypr:Hyprland Core"
    "./waybar:$CONFIG/waybar:Waybar"
    "./kitty:$CONFIG/kitty:Kitty"
    "./fish/config.fish:$CONFIG/fish/config.fish:Fish Shell"
    "./fastfetch:$CONFIG/fastfetch:Fastfetch"
    "./vesktop/themes:$CONFIG/vesktop/themes:Vesktop Styling"
    "./assets/Pictures/Backgrounds:$PICS/Backgrounds:Wallpapers"
    "./assets/Pictures/fastfetch_assets:$PICS/fastfetch_assets:Fastfetch Assets"
)

for entry in "${mappings[@]}"; do
    IFS=":" read -r src dest desc <<< "$entry"
    deploy "$src" "$dest" "$desc"
done

# --- 4. Assets & Themes ---

# Ensure scripts within the hypr directory are executable
if [ -d "$CONFIG/hypr/scripts" ]; then
    chmod +x "$CONFIG/hypr/scripts/"*.sh
fi

# Cursors
if [ -f "./gtk-3.0/Vivian-Cursors.zip" ]; then
    echo "  -> Installing Cursors to ~/.icons..."
    mkdir -p "$ICONS/default"
    unzip -o ./gtk-3.0/Vivian-Cursors.zip -d "$ICONS/"
    [ -f "./gtk-3.0/index.theme" ] && cp ./gtk-3.0/index.theme "$ICONS/default/index.theme"
fi

# Oomox-Gigavolt GTK Theme
if [ -f "./gtk-3.0/oomox-Gigavolt.zip" ]; then
    echo "  -> Installing oomox-Gigavolt to ~/.themes..."
    mkdir -p "$THEMES"
    # This unzip creates the 'oomox-Gigavolt' folder inside ~/.themes
    unzip -o ./gtk-3.0/oomox-Gigavolt.zip -d "$THEMES/"
fi

# --- 5. Global Path Patching ---
echo "  -> Patching hardcoded paths (/home/clement -> $USER_HOME)..."
find "$CONFIG" -type f -not -path '*/.*' -exec sed -i "s|/home/clement|$USER_HOME|g" {} +

# Force GTK3 apps to respect Light mode by default
if [ -f "$CONFIG/gtk-3.0/settings.ini" ]; then
    echo "  -> Forcing GTK3 to prefer-dark-theme = false..."
    sed -i 's/gtk-application-prefer-dark-theme=true/gtk-application-prefer-dark-theme=false/g' "$CONFIG/gtk-3.0/settings.ini"
fi

# --- 6. Ownership ---
echo "  -> Finalizing permissions..."
chown -R "$USR:$USR" "$CONFIG" "$ICONS" "$THEMES" "$PICS"

echo "✅ Done! All assets (including backgrounds) are in the correct location for $USR."