#!/bin/bash
set -e

# ---- EULA ----
if [ "$EULA" = "true" ]; then
    echo "eula=true" > eula.txt
else
    echo "⚠️  EULA non accepté. Lance avec -e EULA=true"
    echo "📖 https://aka.ms/MinecraftEULA"
    exit 1
fi

# ---- Forge / NeoForge (système @args) ----
if [ -f "user_jvm_args.txt" ]; then
    # Nettoyer les anciens flags mémoire
    sed -i 's/-Xm[sx][^ ]*//' user_jvm_args.txt
    sed -i '/^$/d' user_jvm_args.txt
    echo "-Xms${MEMORY_MIN}" >> user_jvm_args.txt
    echo "-Xmx${MEMORY_MAX}" >> user_jvm_args.txt

    # Chercher unix_args.txt (Forge ou NeoForge)
    UNIX_ARGS=$(find libraries/ -name "unix_args.txt" 2>/dev/null | head -1)
    if [ -z "$UNIX_ARGS" ]; then
        echo "❌ unix_args.txt introuvable"
        exit 1
    fi

    # Map variables d'environnement vers server.properties
    setprop "server-port" "${SERVER_PORT:-25565}"
    setprop "motd" "${MOTD}"
    setprop "max-players" "${MAX_PLAYERS}"
    setprop "online-mode" "${ONLINE_MODE}"
    setprop "level-name" "${LEVEL_NAME}"
    setprop "view-distance" "${VIEW_DISTANCE}"
    setprop "difficulty" "${DIFFICULTY}"
    setprop "gamemode" "${GAMEMODE}"
    setprop "white-list" "${WHITE_LIST}"


    echo ">>> Démarrage Forge/NeoForge"
    exec java @user_jvm_args.txt @"${UNIX_ARGS}" nogui

# ---- Standard (Vanilla, Paper, Fabric, Spigot, Snapshot) ----
else
    # Map variables d'environnement vers server.properties
    setprop "server-port" "${SERVER_PORT:-25565}"
    setprop "motd" "${MOTD}"
    setprop "max-players" "${MAX_PLAYERS}"
    setprop "online-mode" "${ONLINE_MODE}"
    setprop "level-name" "${LEVEL_NAME}"
    setprop "view-distance" "${VIEW_DISTANCE}"
    setprop "difficulty" "${DIFFICULTY}"
    setprop "gamemode" "${GAMEMODE}"
    setprop "white-list" "${WHITE_LIST}"

    echo ">>> Démarrage serveur (${MEMORY_MIN} - ${MEMORY_MAX})"
    exec java -Xms${MEMORY_MIN} -Xmx${MEMORY_MAX} -jar server.jar nogui
fi