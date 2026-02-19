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
USER mcuser

# ============================================================
# VANILLA
# ============================================================
FROM alpine AS download-vanilla
RUN apk add --no-cache curl jq
ARG MC_VERSION=1.21.1

RUN MANIFEST_URL=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest_v2.json \
        | jq -r --arg v "$MC_VERSION" '.versions[] | select(.id == $v) | .url') \
    && if [ -z "$MANIFEST_URL" ] || [ "$MANIFEST_URL" = "null" ]; then \
        echo "❌ Version $MC_VERSION introuvable !" && exit 1; \
    fi \
    && SERVER_URL=$(curl -s "$MANIFEST_URL" \
        | jq -r '.downloads.server.url') \
    && curl -o /tmp/server.jar "$SERVER_URL"

FROM base AS vanilla
COPY --from=download-vanilla --chown=mcuser:mcuser /tmp/server.jar .
CMD sh -c 'echo "eula=${EULA}" > eula.txt && java -Xms${MEMORY_MIN} -Xmx${MEMORY_MAX} -jar server.jar nogui'

# ============================================================
# SNAPSHOT (même API que Vanilla, type "snapshot" dans le manifest)
# ============================================================
FROM alpine AS download-snapshot
RUN apk add --no-cache curl jq
ARG MC_VERSION=25w07a

RUN MANIFEST_URL=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest_v2.json \
        | jq -r --arg v "$MC_VERSION" '.versions[] | select(.id == $v) | .url') \
    && if [ -z "$MANIFEST_URL" ] || [ "$MANIFEST_URL" = "null" ]; then \
        echo "❌ Snapshot $MC_VERSION introuvable !" && exit 1; \
    fi \
    && SERVER_URL=$(curl -s "$MANIFEST_URL" \
        | jq -r '.downloads.server.url') \
    && curl -o /tmp/server.jar "$SERVER_URL"

FROM base AS snapshot
COPY --from=download-snapshot --chown=mcuser:mcuser /tmp/server.jar .
CMD sh -c 'echo "eula=${EULA}" > eula.txt && java -Xms${MEMORY_MIN} -Xmx${MEMORY_MAX} -jar server.jar nogui'

# ============================================================
# PAPER
# ============================================================
FROM alpine AS download-paper
RUN apk add --no-cache curl jq
ARG MC_VERSION=1.21.1

RUN BUILD=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/${MC_VERSION}/builds" \
        | jq -r '.builds[-1].build') \
    && if [ -z "$BUILD" ] || [ "$BUILD" = "null" ]; then \
        echo "❌ Aucun build Paper pour $MC_VERSION" && exit 1; \
    fi \
    && curl -o /tmp/server.jar \
        "https://api.papermc.io/v2/projects/paper/versions/${MC_VERSION}/builds/${BUILD}/downloads/paper-${MC_VERSION}-${BUILD}.jar"

FROM base AS paper
COPY --from=download-paper --chown=mcuser:mcuser /tmp/server.jar .
CMD sh -c 'echo "eula=${EULA}" > eula.txt && java -Xms${MEMORY_MIN} -Xmx${MEMORY_MAX} -jar server.jar nogui'

# ============================================================
# FABRIC
# ============================================================
FROM alpine AS download-fabric
RUN apk add --no-cache curl jq
ARG MC_VERSION=1.21.1

RUN LOADER=$(curl -s "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}" \
        | jq -r '.[0].loader.version') \
    && INSTALLER=$(curl -s "https://meta.fabricmc.net/v2/versions/installer" \
        | jq -r '.[0].version') \
    && if [ -z "$LOADER" ] || [ "$LOADER" = "null" ]; then \
        echo "❌ Fabric pas dispo pour $MC_VERSION" && exit 1; \
    fi \
    && curl -o /tmp/server.jar \
        "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${LOADER}/${INSTALLER}/server/jar"

FROM base AS fabric
COPY --from=download-fabric --chown=mcuser:mcuser /tmp/server.jar .
CMD sh -c 'echo "eula=${EULA}" > eula.txt && java -Xms${MEMORY_MIN} -Xmx${MEMORY_MAX} -jar server.jar nogui'

# ============================================================
# FORGE
# ============================================================
FROM eclipse-temurin:${JAVA_VERSION}-jre AS download-forge
RUN apt-get update && apt-get install -y curl jq && rm -rf /var/lib/apt/lists/*
ARG MC_VERSION=1.21.1

RUN FORGE_VERSION=$(curl -s "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json" \
        | jq -r --arg v "$MC_VERSION" '.promos[$v + "-recommended"] // .promos[$v + "-latest"]') \
    && if [ -z "$FORGE_VERSION" ] || [ "$FORGE_VERSION" = "null" ]; then \
        echo "❌ Forge pas dispo pour $MC_VERSION" && exit 1; \
    fi \
    && curl -o /tmp/forge-installer.jar \
        "https://maven.minecraftforge.net/net/minecraftforge/forge/${MC_VERSION}-${FORGE_VERSION}/forge-${MC_VERSION}-${FORGE_VERSION}-installer.jar" \
    && mkdir -p /tmp/forge-server \
    && cd /tmp/forge-server \
    && java -jar /tmp/forge-installer.jar --installServer \
    && rm -f /tmp/forge-installer.jar *installer*

FROM base AS forge
COPY --from=download-forge --chown=mcuser:mcuser /tmp/forge-server .
CMD sh -c 'echo "eula=${EULA}" > eula.txt \
    && sed -i "s/-Xm[sx][^ ]*//" user_jvm_args.txt \
    && echo "-Xms${MEMORY_MIN}" >> user_jvm_args.txt \
    && echo "-Xmx${MEMORY_MAX}" >> user_jvm_args.txt \
    && UNIX_ARGS=$(find libraries/net/minecraftforge/forge -name "unix_args.txt" | head -1) \
    && if [ -z "$UNIX_ARGS" ]; then echo "❌ unix_args.txt introuvable" && exit 1; fi \
    && java @user_jvm_args.txt @${UNIX_ARGS} nogui'

# ============================================================
# NEOFORGE
# ============================================================
FROM eclipse-temurin:${JAVA_VERSION}-jre AS download-neoforge
RUN apt-get update && apt-get install -y curl jq && rm -rf /var/lib/apt/lists/*
ARG MC_VERSION=1.21.1

# NeoForge version = MC_VERSION sans le "1." devant (ex: 1.21.1 -> 21.1.x)
RUN NEO_MC=$(echo "$MC_VERSION" | sed 's/^1\.//') \
    && NEO_VERSION=$(curl -s "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml" \
        | grep -o "<version>${NEO_MC}\.[^<]*</version>" \
        | tail -1 \
        | sed 's/<[^>]*>//g') \
    && if [ -z "$NEO_VERSION" ]; then \
        echo "❌ NeoForge pas dispo pour $MC_VERSION" && exit 1; \
    fi \
    && curl -o /tmp/neoforge-installer.jar \
        "https://maven.neoforged.net/releases/net/neoforged/neoforge/${NEO_VERSION}/neoforge-${NEO_VERSION}-installer.jar" \
    && mkdir -p /tmp/neoforge-server \
    && cd /tmp/neoforge-server \
    && java -jar /tmp/neoforge-installer.jar --installServer \
    && rm -f /tmp/neoforge-installer.jar *installer*

FROM base AS neoforge
COPY --from=download-neoforge --chown=mcuser:mcuser /tmp/neoforge-server .
CMD sh -c 'echo "eula=${EULA}" > eula.txt \
    && sed -i "s/-Xm[sx][^ ]*//" user_jvm_args.txt \
    && echo "-Xms${MEMORY_MIN}" >> user_jvm_args.txt \
    && echo "-Xmx${MEMORY_MAX}" >> user_jvm_args.txt \
    && UNIX_ARGS=$(find libraries/net/neoforged/neoforge -name "unix_args.txt" | head -1) \
    && if [ -z "$UNIX_ARGS" ]; then echo "❌ unix_args.txt introuvable" && exit 1; fi \
    && java @user_jvm_args.txt @${UNIX_ARGS} nogui'

# ============================================================
# SPIGOT
# ============================================================
FROM eclipse-temurin:${JAVA_VERSION}-jdk AS download-spigot
RUN apt-get update && apt-get install -y curl git && rm -rf /var/lib/apt/lists/*
ARG MC_VERSION=1.21.1

RUN mkdir -p /tmp/spigot-build \
    && cd /tmp/spigot-build \
    && curl -o BuildTools.jar \
        "https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar" \
    && git config --global --unset core.autocrlf || true \
    && java -jar BuildTools.jar --rev ${MC_VERSION} --output-dir /tmp/spigot-out \
    && mv /tmp/spigot-out/spigot-*.jar /tmp/spigot-out/server.jar

# ⚠️ Spigot nécessite JDK pour BuildTools, mais on repart sur base (JRE) pour le final
FROM base AS spigot
COPY --from=download-spigot --chown=mcuser:mcuser /tmp/spigot-out/server.jar .
CMD sh -c 'echo "eula=${EULA}" > eula.txt && java -Xms${MEMORY_MIN} -Xmx${MEMORY_MAX} -jar server.jar nogui'
