source /usr/share/cachyos-fish-config/cachyos-config.fish
alias spotify="~/.cargo/bin/spotify_player"
# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end

function fish_greeting
    # Get all images into an array
    set -l images ~/Pictures/fastfetch_assets/*
    
    # Get a random index
    set -l count (count $images)
    set -l random_index (random 1 $count)
    
    # Select the random image
    set -l random_img $images[$random_index]
    
    # Use a unique filename with timestamp to force kitty to reload
    set -l timestamp (date +%s%N)
    set -l target_file ~/.config/fastfetch/fastfetch_cur_$timestamp.jpg
    
    # Remove old images
    rm -f ~/.config/fastfetch/fastfetch_cur*.jpg
    
    # Copy the new random image with unique name
    cp $random_img $target_file
    
    # Create/update symlink
    ln -sf $target_file ~/.config/fastfetch/fastfetch_cur.jpg
    
    # Run fastfetch
    /usr/bin/fastfetch
end

#random_fetch

alias fastfetch=fish_greeting