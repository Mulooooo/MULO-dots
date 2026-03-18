#!/bin/bash

# Récupère le volume actuel
volume=$(pamixer --get-volume)

# Génère une bannière ASCII du volume
ascii_volume=$(figlet -f slant "Volume : $volume%")

# Envoie la notification
dunstify -r 9995 -u normal "$ascii_volume"
