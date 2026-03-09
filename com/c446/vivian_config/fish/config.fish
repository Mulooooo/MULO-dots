source /usr/share/cachyos-fish-config/cachyos-config.fish
alias spotify="~/.cargo/bin/spotify_player"

function fish_greeting
    # Get all files in the directory
    set -l images ~/Pictures/fastfetch_assets/*

    # Ensure at least one file exists
    if test (count $images) -eq 0
        /usr/bin/fastfetch
        return
    end

    # Pick a random file
    set -l random_img (random choice $images)

    # Extract extension from selected file
    set -l ext (string split -r -m1 . $random_img)[2]

    # Unique filename
    set -l timestamp (date +%s%N)
    set -l target_file ~/.config/fastfetch/fastfetch_cur_$timestamp.$ext

    # Remove old cached images (any extension)
    rm -f ~/.config/fastfetch/fastfetch_cur_*

    # Copy selected image
    cp $random_img $target_file

    # Update symlink
    ln -sf $target_file ~/.config/fastfetch/fastfetch_cur.$ext
    ln -sf ~/.config/fastfetch/fastfetch_cur.$ext ~/.config/fastfetch/fastfetch_cur

    # Run fastfetch
    /usr/bin/fastfetch
end

alias fastfetch=fish_greeting
alias fclear="/sbin/clear"
alias clear="clear && fish_greeting"
alias restartSound="systemctl --user restart pipewire pipewire-pulse wireplumber"