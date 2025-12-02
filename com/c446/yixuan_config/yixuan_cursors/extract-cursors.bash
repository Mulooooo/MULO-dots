#!/bin/bash

mkdir -p src/pngs/32x32

for cursor in cursors/*; do
    name=$(basename "$cursor")
    echo "Extracting $name..."
    
    # Extract cursor to temporary directory
    xcur2png "$cursor" "src/pngs/32x32/${name}"
    
    # xcur2png creates files like: name_000_32x32x32.png or name_32x32x32.png
    # Rename to simpler format: name.png or name-frameN.png
    
    # Check if multiple frames exist
    frames=(src/pngs/32x32/${name}_*.png)
    
    if [ ${#frames[@]} -eq 1 ]; then
        # Single frame - rename to simple name
        mv "${frames[0]}" "src/pngs/32x32/${name}.png" 2>/dev/null || true
    else
        # Multiple frames - rename with frame numbers
        frame_num=1
        for frame in "${frames[@]}"; do
            if [ -f "$frame" ]; then
                mv "$frame" "src/pngs/32x32/${name}-frame${frame_num}.png" 2>/dev/null || true
                ((frame_num++))
            fi
        done
    fi
done

echo "Extraction complete!"