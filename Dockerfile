ARG JAVA_VERSION=21

# ============================================================
# BASE
# ============================================================
FROM eclipse-temurin:${JAVA_VERSION}-jre AS base

RUN useradd --create-home --no-log-init mcuser \
    && mkdir -p /minecraft \
    && chown mcuser:mcuser /minecraft

WORKDIR /minecraft

ENV MEMORY_MIN=1G \
    MEMORY_MAX=2G \
    EULA=false

EXPOSE 25565/tcp

# Copier l'entrypoint AVANT de passer en mcuser
COPY --chmod=755 entrypoint.sh /entrypoint.sh

USER mcuser
CMD ["/entrypoint.sh"]

# ============================================================
# VANILLA
# ============================================================
FROM alpine:3.20 AS download-vanilla
RUN apk add --no-cache curl jq bash

ARG MC_VERSION=1.21.1

RUN set -euo pipefail; \
    echo ">>> Checking Mojang manifest for $MC_VERSION"; \
    MANIFEST_URL=$(curl -fsSL https://launchermeta.mojang.com/mc/game/version_manifest_v2.json \
        | jq -r --arg v "$MC_VERSION" '.versions[] | select(.id == $v) | .url'); \
    [ -n "$MANIFEST_URL" ] || { echo "❌ Version inexistante"; exit 1; }; \
    SERVER_URL=$(curl -fsSL "$MANIFEST_URL" | jq -r '.downloads.server.url'); \
    [ -n "$SERVER_URL" ] || { echo "❌ Pas de serveur pour cette version"; exit 1; }; \
    curl -fLo /tmp/server.jar "$SERVER_URL"; \
    test -s /tmp/server.jar || { echo "❌ JAR vide"; exit 1; }; 
    # SIZE=$(stat -c%s /tmp/server.jar); \
    # [ "$SIZE" -gt 10000000 ] || { echo "❌ JAR trop petit"; exit 1; }; \
    # echo ">>> Download OK ($SIZE bytes)"

FROM base AS vanilla
COPY --from=download-vanilla --chown=mcuser:mcuser /tmp/server.jar .

# ============================================================
# SNAPSHOT
# ============================================================
FROM alpine:3.20 AS download-snapshot
RUN apk add --no-cache curl jq bash

ARG MC_VERSION=25w21a

RUN set -euo pipefail; \
    echo ">>> Checking Mojang manifest for snapshot $MC_VERSION"; \
    VERSION_JSON=$(curl -fsSL https://launchermeta.mojang.com/mc/game/version_manifest_v2.json); \
    MANIFEST_URL=$(echo "$VERSION_JSON" \
        | jq -r --arg v "$MC_VERSION" '.versions[] | select(.id == $v and .type == "snapshot") | .url'); \
    [ -n "$MANIFEST_URL" ] || { echo "❌ Snapshot inexistant"; exit 1; }; \
    SERVER_URL=$(curl -fsSL "$MANIFEST_URL" | jq -r '.downloads.server.url // empty'); \
    [ -n "$SERVER_URL" ] || { echo "❌ Pas de serveur pour ce snapshot"; exit 1; }; \
    curl -fLo /tmp/server.jar "$SERVER_URL"; \
    test -s /tmp/server.jar || { echo "❌ JAR vide"; exit 1; }; 
    # SIZE=$(stat -c%s /tmp/server.jar); \
    # [ "$SIZE" -gt 10000000 ] || { echo "❌ JAR trop petit"; exit 1; }; \
    # echo ">>> Snapshot OK ($SIZE bytes)"

FROM base AS snapshot
COPY --from=download-snapshot --chown=mcuser:mcuser /tmp/server.jar .

# ============================================================
# PAPER
# ============================================================
FROM alpine:3.20 AS download-paper
RUN apk add --no-cache curl jq bash

ARG MC_VERSION=1.21.1

RUN set -euo pipefail; \
    echo ">>> Checking Paper API for $MC_VERSION"; \
    BUILDS_JSON=$(curl -fsSL "https://api.papermc.io/v2/projects/paper/versions/${MC_VERSION}/builds" || true); \
    BUILD=$(echo "$BUILDS_JSON" | jq -r '.builds[-1].build // empty'); \
    [ -n "$BUILD" ] || { echo "❌ Aucun build Paper pour $MC_VERSION"; exit 1; }; \
    curl -fLo /tmp/server.jar \
        "https://api.papermc.io/v2/projects/paper/versions/${MC_VERSION}/builds/${BUILD}/downloads/paper-${MC_VERSION}-${BUILD}.jar"; \
    test -s /tmp/server.jar || { echo "❌ JAR vide"; exit 1; };
    # SIZE=$(stat -c%s /tmp/server.jar); \
    # [ "$SIZE" -gt 10000000 ] || { echo "❌ JAR trop petit"; exit 1; }; \
    # echo ">>> Paper OK ($SIZE bytes)"

FROM base AS paper
COPY --from=download-paper --chown=mcuser:mcuser /tmp/server.jar .

# ============================================================
# FABRIC
# ============================================================
FROM alpine:3.20 AS download-fabric
RUN apk add --no-cache curl jq

ARG MC_VERSION=1.21.1

RUN set -eu; \
    echo ">>> Checking Fabric for $MC_VERSION"; \
    LOADER=$(curl -s "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}" \
        | jq -r '.[0].loader.version'); \
    INSTALLER=$(curl -s "https://meta.fabricmc.net/v2/versions/installer" \
        | jq -r '.[0].version'); \
    if [ -z "$LOADER" ] || [ "$LOADER" = "null" ]; then \
        echo "❌ Fabric pas dispo pour $MC_VERSION" && exit 1; \
    fi; \
    curl -fLo /tmp/server.jar \
        "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${LOADER}/${INSTALLER}/server/jar";
    # SIZE=$(stat -c%s /tmp/server.jar); \
    # echo ">>> Fabric OK ($SIZE bytes)"

FROM base AS fabric
COPY --from=download-fabric --chown=mcuser:mcuser /tmp/server.jar .

# ============================================================
# FORGE
# ============================================================
FROM eclipse-temurin:${JAVA_VERSION}-jre AS download-forge
RUN apt-get update && apt-get install -y curl jq && rm -rf /var/lib/apt/lists/*

ARG MC_VERSION=1.21.1

SHELL ["/bin/bash", "-c"]
RUN set -euo pipefail; \
    echo ">>> Checking Forge for $MC_VERSION"; \
    # 1. On récupère la version de Forge
    FORGE_VERSION=$(curl -fsSL https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json \
        | jq -r --arg v "$MC_VERSION" '.promos[$v + "-recommended"] // .promos[$v + "-latest"] // empty'); \
    [ -n "$FORGE_VERSION" ] || { echo "❌ Forge non dispo"; exit 1; }; \
    \
    # 2. On teste les deux formats d'URL possibles (Standard vs Redondant)
    # Format A (Moderne): MC-FORGE
    # Format B (Legacy): MC-FORGE-MC
    URL_BASE="https://maven.minecraftforge.net/net/minecraftforge/forge/${MC_VERSION}-${FORGE_VERSION}" ; \
    URL_A="${URL_BASE}/forge-${MC_VERSION}-${FORGE_VERSION}-installer.jar" ; \
    URL_B="${URL_BASE}-${MC_VERSION}/forge-${MC_VERSION}-${FORGE_VERSION}-${MC_VERSION}-installer.jar" ; \
    \
    echo ">>> Tentative A: $URL_A"; \
    if ! curl -fsSL -o /tmp/forge-installer.jar "$URL_A"; then \
        echo ">>> Tentative B: $URL_B"; \
        curl -fsSL -o /tmp/forge-installer.jar "$URL_B" || { echo "❌ 404 sur les deux URLs"; exit 1; }; \
    fi; \
    \
    # 3. Installation
    mkdir -p /tmp/forge-server && cd /tmp/forge-server; \
    if java -jar /tmp/forge-installer.jar --installServer; then \
        echo ">>> Installation OK"; \
    else \
        # Fallback pour les TRÈS vieilles versions qui n'ont pas d'installer
        mv /tmp/forge-installer.jar server.jar; \
    fi; \
    rm -f /tmp/forge-installer.jar; \
    \
    # 4. Finalisation pour ton entrypoint
    if [ ! -f "run.sh" ] && [ ! -f "server.jar" ]; then \
        FORGE_JAR=$(ls forge-*.jar | grep -v "installer" | head -n 1 || true); \
        [ -n "$FORGE_JAR" ] && ln -s "$FORGE_JAR" server.jar; \
    fi; \
    echo ">>> Forge OK"

FROM base AS forge
COPY --from=download-forge --chown=mcuser:mcuser /tmp/forge-server .

# ============================================================
# NEOFORGE
# ============================================================
FROM eclipse-temurin:${JAVA_VERSION}-jre AS download-neoforge
RUN apt-get update && apt-get install -y curl jq && rm -rf /var/lib/apt/lists/*
ARG MC_VERSION=1.21.1

SHELL ["/bin/bash", "-c"]
RUN set -euo pipefail; \
    NEO_MC=$(echo "$MC_VERSION" | sed 's/^1\.//'); \
    NEO_VERSION=$(curl -sSL "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml" \
        | sed 's/<[^>]*>/ /g' | tr ' ' '\n' | grep "^${NEO_MC}\." | tail -1); \
    \
    [ -n "$NEO_VERSION" ] || { echo "❌ NeoForge non trouvé"; exit 1; }; \
    \
    curl -fLo /tmp/neoforge-installer.jar \
        "https://maven.neoforged.net/releases/net/neoforged/neoforge/${NEO_VERSION}/neoforge-${NEO_VERSION}-installer.jar"; \
    \
    mkdir -p /tmp/neoforge-server && cd /tmp/neoforge-server; \
    java -jar /tmp/neoforge-installer.jar --installServer; \
    # Sécurité pour les versions de transition (crée un lien server.jar si pas de système d'args)
    if [ ! -f "user_jvm_args.txt" ] && [ ! -f "run.sh" ]; then \
        JAR=$(ls neoforge-*.jar | grep -v "installer" | head -n 1); \
        [ -n "$JAR" ] && ln -s "$JAR" server.jar; \
    fi

FROM base AS neoforge
COPY --from=download-neoforge --chown=mcuser:mcuser /tmp/neoforge-server .

# ============================================================
# SPIGOT (Version Archive Stable)
# ============================================================
FROM eclipse-temurin:${JAVA_VERSION}-jdk AS download-spigot
RUN apt-get update && apt-get install -y curl git && rm -rf /var/lib/apt/lists/*

ARG MC_VERSION=1.21.1

RUN mkdir -p /tmp/spigot-build /tmp/spigot-out \
    && cd /tmp/spigot-build \
    && curl -sSL -o BuildTools.jar \
        "https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar" \
    && git config --global --unset core.autocrlf || true \
    # Logic 1.7.10
    && if [ "$MC_VERSION" = "1.7.10" ]; then \
        echo ">>> Récupération Spigot 1.7.10 via Maven Central (Stable)..."; \
        curl -sSL -f -o /tmp/spigot-out/server.jar \
            "https://oss.sonatype.org/content/repositories/snapshots/org/spigotmc/spigot/1.7.10-R0.1-SNAPSHOT/spigot-1.7.10-R0.1-20141013.210940-104.jar" || \
        { echo "❌ Impossible de récupérer un JAR valide"; exit 1; }; \
    else \
        # Build normal pour 1.8+
        java -jar BuildTools.jar --rev ${MC_VERSION} --output-dir /tmp/spigot-out && \
        mv /tmp/spigot-out/spigot-*.jar /tmp/spigot-out/server.jar; \
    fi

FROM base AS spigot
COPY --from=download-spigot --chown=mcuser:mcuser /tmp/spigot-out/server.jar .