#!/bin/bash
set -e

# ---- Fonction sed compatible volumes Docker ----
safe_sed() {
    local expression="$1" file="$2"
    local tmp="${file}.tmp"
    sed "$expression" "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

# ---- EULA ----
if [ "$EULA" = "true" ]; then
    echo "eula=true" > eula.txt
else
    echo "⚠️  EULA non accepté. Lance avec -e EULA=true"
    echo "📖 https://aka.ms/MinecraftEULA"
    exit 1
fi

# ---- Activer RCON dans server.properties ----
if [ -f "server.properties" ]; then
    safe_sed "s/^enable-rcon=.*/enable-rcon=true/" server.properties
    safe_sed "s/^rcon\.port=.*/rcon.port=${RCON_PORT}/" server.properties
    safe_sed "s/^rcon\.password=.*/rcon.password=${RCON_PASSWORD}/" server.properties

    grep -q "^enable-rcon=" server.properties || echo "enable-rcon=true" >> server.properties
    grep -q "^rcon\.port=" server.properties || echo "rcon.port=${RCON_PORT}" >> server.properties
    grep -q "^rcon\.password=" server.properties || echo "rcon.password=${RCON_PASSWORD}" >> server.properties
else
    cat > server.properties <<EOF
enable-rcon=true
rcon.port=${RCON_PORT}
rcon.password=${RCON_PASSWORD}
EOF
fi

echo ">>> RCON activé sur le port ${RCON_PORT}"

# ---- Propriétés du serveur via ENV ----
apply_prop() {
    local key="$1" value="$2"
    if [ -n "$value" ]; then
        if grep -q "^${key}=" server.properties 2>/dev/null; then
            safe_sed "s/^${key}=.*/${key}=${value}/" server.properties
        else
            echo "${key}=${value}" >> server.properties
        fi
    fi
}

apply_prop "difficulty" "$DIFFICULTY"
apply_prop "gamemode" "$GAMEMODE"
apply_prop "max-players" "$MAX_PLAYERS"
apply_prop "motd" "$MOTD"
apply_prop "pvp" "$PVP"
apply_prop "online-mode" "$ONLINE_MODE"
apply_prop "server-port" "$SERVER_PORT"
apply_prop "level-seed" "$LEVEL_SEED"
apply_prop "view-distance" "$VIEW_DISTANCE"
apply_prop "spawn-protection" "$SPAWN_PROTECTION"

echo ">>> Propriétés appliquées"

# ---- Forge / NeoForge (système @args) ----
if [ -f "user_jvm_args.txt" ]; then
    safe_sed 's/-Xm[sx][^ ]*//' user_jvm_args.txt
    safe_sed '/^$/d' user_jvm_args.txt
    echo "-Xms${MEMORY_MIN}" >> user_jvm_args.txt
    echo "-Xmx${MEMORY_MAX}" >> user_jvm_args.txt

    UNIX_ARGS=$(find libraries/ -name "unix_args.txt" 2>/dev/null | head -1)
    if [ -z "$UNIX_ARGS" ]; then
        echo "❌ unix_args.txt introuvable"
        exit 1
    fi

    echo ">>> Démarrage Forge/NeoForge"
    exec java @user_jvm_args.txt @"${UNIX_ARGS}" nogui

# ---- Standard (Vanilla, Paper, Fabric, Spigot, Snapshot) ----
else
    echo ">>> Démarrage serveur (${MEMORY_MIN} - ${MEMORY_MAX})"
    exec java -Xms${MEMORY_MIN} -Xmx${MEMORY_MAX} -jar server.jar nogui
fi
