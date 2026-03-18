#!/usr/bin/env bash
USERNAME="tester"
USER_HOME="/home/$USERNAME"
SHELL="/usr/bin/fish"  # Change if you want bash/zsh

if id "$USERNAME" &>/dev/null; then
    echo "User '$USERNAME' already exists."
    exit 1
fi

sudo useradd -m -s "$SHELL" "$USERNAME"

sudo passwd "$USERNAME"

sudo cp /home/clement/Documents/Github/MULO-dots/hypr/com/c446/vivian-hypr/ /home/tester/Documents -r

echo "User '$USERNAME' created with home at $USER_HOME"
echo "You can now 'sudo su - $USERNAME' to enter their environment."