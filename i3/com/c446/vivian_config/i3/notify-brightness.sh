#!/bin/bash

# Récupère la luminosité actuelle
brightness=$(brightnessctl get)
max_brightness=$(brightnessctl max)
brightness_percent=$((brightness * 100 / max_brightness))

# Génère une bannière ASCII de la luminosité
ascii_brightness=$(figlet -f slant "Bright : $brightness_percent%")

# Envoie la notification
dunstify -r 9995 -u normal "$ascii_brightness"

