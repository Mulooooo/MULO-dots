#!/bin/bash

STATE_FILE="/tmp/roundrobin_paste_state"

state=$(cat "$STATE_FILE" 2>/dev/null || echo 0)

if [ "$state" -eq 0 ]; then
    wtype "!delete"
    echo 1 > "$STATE_FILE"
else
    wtype "!start"
    echo 0 > "$STATE_FILE"
fi
