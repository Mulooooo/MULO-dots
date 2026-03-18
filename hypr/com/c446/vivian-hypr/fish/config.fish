source /usr/share/cachyos-fish-config/cachyos-config.fish
alias spotify="~/.cargo/bin/spotify_player"

function fish_greeting
    set -l queue_dir ~/.cache/fastfetch_queue
    mkdir -p $queue_dir
    
    # 1. Look for snaps
    set -l snaps $queue_dir/*.ansi
    
    if test (count $snaps) -eq 0
        /usr/bin/fastfetch
        fish -c "bake_fastfetch_queue" >/dev/null 2>&1 &
        return
    end

    # 2. ATOMIC SELECTION: Try to move the first snap to a unique local name
    # This prevents the "No such file" error if another terminal grabs it first
    set -l my_snap /tmp/current_ff_(random).ansi
    if mv $snaps[1] $my_snap >/dev/null 2>&1
        cat $my_snap
        rm $my_snap
    else
        # If the move failed (another terminal took it), just run fastfetch normally
        /usr/bin/fastfetch
    end

    # 3. Threaded Regeneration
    if test (count $snaps) -le 3
        fish -c "bake_fastfetch_queue" >/dev/null 2>&1 &
    end
end

function bake_fastfetch_queue
    set -l lockfile /tmp/fastfetch_bake.lock
    test -f $lockfile; and return; touch $lockfile

    set -l assets_dir ~/Pictures/fastfetch_assets
    set -l queue_dir ~/.cache/fastfetch_queue

    # 1. Get RAW paths only (no ls -l metadata)
    # We use printf to get one path per line, then shuffle
    set -l random_images (printf "%s\n" $assets_dir/* | shuf -n 5)

    for img in $random_images
        set -l timestamp (date +%s%N)
        
        # 2. Use quotes around $img in case paths have spaces
        nice -n 19 env COLUMNS=120 LINES=40 script -q -c "fastfetch --logo-source '$img' --logo-width 40 --logo-height 0" $queue_dir/snap_$timestamp.ansi.tmp > /dev/null
        
        if test -f $queue_dir/snap_$timestamp.ansi.tmp
            sed -i '1d;$d' $queue_dir/snap_$timestamp.ansi.tmp
            mv $queue_dir/snap_$timestamp.ansi.tmp $queue_dir/snap_$timestamp.ansi
        end
        
        ln -sf "$img" ~/.config/fastfetch/fastfetch_cur
    end

    rm $lockfile
end

function unlock
    rm /tmp/fastfetch_bake.lock
end

alias fastfetch=fish_greeting
alias fclear="/sbin/clear"
alias clear="clear && fish_greeting"
alias restartSound="systemctl --user restart pipewire pipewire-pulse wireplumber"