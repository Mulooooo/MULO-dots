#!/bin/bash

# Seuils de notification
LOW_THRESHOLD=20
CRITICAL_THRESHOLD=15

# Chemin vers les informations de la batterie
BATTERY_PATH="/sys/class/power_supply/BAT0"

# Vérifie si le répertoire de la batterie existe
if [ ! -d "$BATTERY_PATH" ]; then
    echo "Répertoire de la batterie introuvable : $BATTERY_PATH"
    exit 1
fi

# Boucle infinie
while true; do
    # Récupère le pourcentage de la batterie et son état
    BATTERY_LEVEL=$(cat "$BATTERY_PATH/capacity")
    BATTERY_STATUS=$(cat "$BATTERY_PATH/status")

    # Si la batterie est en décharge
    if [ "$BATTERY_STATUS" = "Discharging" ] || [ "$BATTERY_STATUS" = "Not charging" ]; then
        if [ "$BATTERY_LEVEL" -le "$CRITICAL_THRESHOLD" ]; then
            dunstify -u critical -r 9995 "⚠️ Batterie Critique" \
                "Niveau de batterie : ${BATTERY_LEVEL}%\nVeuillez brancher le chargeur immédiatement."
        elif [ "$BATTERY_LEVEL" -le "$LOW_THRESHOLD" ]; then
            dunstify -u normal -r 9995 "🔋 Batterie Faible" \
                "Niveau de batterie : ${BATTERY_LEVEL}%\nPensez à brancher le chargeur."
        fi
    fi

    # Attendre avant de vérifier à nouveau (par ex. toutes les 60 secondes)
    sleep 60
done
