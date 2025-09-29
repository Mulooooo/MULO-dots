#!/bin/bash

# Prevent duplicate startups
pgrep -x picom     || picom --config ~/.config/picom/picom.conf &
pgrep -x nm-applet || nm-applet &
pgrep -x blueman-applet || blueman-applet &
pgrep -x dunst     || dunst &
pgrep -x volumeicon || volumeicon &
pgrep -x flameshot || flameshot &
pgrep -x polybar || polybar &
pgrep -x picom || picom &