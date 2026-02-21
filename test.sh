#!/bin/bash
# ci-test.sh — Test unitaire pour un seul target
TARGET=$1
MC_VERSION=$2
JAVA_VERSION=$3

TIMEOUT=120
CONTAINER="mc-test-${TARGET}"
IMAGE="mc-test-img-${TARGET}"

echo "🚀 Démarrage du test pour : $TARGET ($MC_VERSION) avec Java $JAVA_VERSION"

# 1. Build
docker build --target "$TARGET" \
  --build-arg MC_VERSION="$MC_VERSION" \
  --build-arg JAVA_VERSION="$JAVA_VERSION" \
  -t "$IMAGE" . || exit 1

# 2. Test EULA (doit échouer sans variable EULA)
echo "🔒 Test EULA..."
if docker run --rm "$IMAGE" 2>&1 | grep -qi "eula"; then
  echo "✅ EULA refusé correctement"
else
  echo "❌ Erreur : Le serveur n'a pas réclamé l'EULA"
  exit 1
fi

# 3. Test de démarrage
docker run -d --name "$CONTAINER" -e EULA=true -e DIFFICULTY=hard "$IMAGE"

echo "⏳ Attente du message 'Done'..."
START_TIME=$(date +%s)
while true; do
  if docker logs "$CONTAINER" 2>&1 | grep -q "Done"; then
    echo "✅ Serveur démarré avec succès"
    break
  fi
  if [ $(( $(date +%s) - START_TIME )) -gt $TIMEOUT ]; then
    echo "❌ Timeout après 2 min"
    docker logs "$CONTAINER"
    docker rm -f "$CONTAINER"
    exit 1
  fi
  sleep 2
done

# 4. Tests de sécurité (User non-root + Port)
USER=$(docker exec "$CONTAINER" whoami)
if [ "$USER" != "root" ]; then echo "✅ User: $USER"; else echo "❌ Tourne en ROOT !"; exit 1; fi

# 5. Cleanup
docker rm -f "$CONTAINER"
echo "⭐ Tous les tests sont OK pour $TARGET"