ARG JAVA_VERSION=21

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


# ---- Stage téléchargement Vanilla ----
FROM alpine AS download-vanilla

RUN apk add --no-cache curl jq

ARG MC_VERSION=1.21.11

RUN MANIFEST_URL=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest_v2.json \
        | jq -r --arg v "$MC_VERSION" '.versions[] | select(.id == $v) | .url') \
    && if [ -z "$MANIFEST_URL" ] || [ "$MANIFEST_URL" = "null" ]; then \
        echo "❌ Version $MC_VERSION introuvable !" && exit 1; \
    fi \
    && SERVER_URL=$(curl -s "$MANIFEST_URL" \
        | jq -r '.downloads.server.url') \
    && if [ -z "$SERVER_URL" ] || [ "$SERVER_URL" = "null" ]; then \
        echo "❌ Pas de server.jar pour $MC_VERSION" && exit 1; \
    fi \
    && curl -o /tmp/server.jar "$SERVER_URL"

# ---- Stage final Vanilla ----
FROM base AS vanilla
COPY --from=download-vanilla --chown=mcuser:mcuser /tmp/server.jar .
CMD sh -c 'echo "eula=${EULA}" > eula.txt && java -Xms${MEMORY_MIN} -Xmx${MEMORY_MAX} -jar server.jar nogui'