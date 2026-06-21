#!/usr/bin/env bash

# --- Configuration ---
BUILD_DIR="/tmp/vivian_build"
mkdir -p "$BUILD_DIR"

# --- 1. Build MediaCtlApplet (C++/GTKmm) ---
echo "📂 Building MediaCtlApplet..."
if cd "$BUILD_DIR"; then
    git clone https://github.com/clcment446/MediaCtlApplet.git
    cd MediaCtlApplet
    
    echo "  -> Compiling..."
    make all
    
    echo "  -> Installing..."
    sudo bash install.sh
    cd ..
fi

# --- Cleanup ---
rm -rf "$BUILD_DIR"
echo "✅ Custom applications built and installed."