#!/usr/bin/env bash
set -euo pipefail

# === CONFIG ===
TARGET="${1:-vanilla}"
MC_VERSION="${2:-1.21.1}"
JAVA_VERSION="${3:-21}"
REPORT="test-report.txt"
PASS=0
FAIL=0
TOTAL=0

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 TEST: target=$TARGET MC=$MC_VERSION JAVA=$JAVA_VERSION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# === CLEANUP PRÉVENTIF ===
docker rm -f mc-test 2>/dev/null || true
docker rmi mc-test-img 2>/dev/null || true

# --- TEST 1 : Build ---
((TOTAL++))
echo "🔨 Build de l'image..."
BUILD_START=$(date +%s)
if docker build --target "$TARGET" \
  --build-arg MC_VERSION="$MC_VERSION" \
  --build-arg JAVA_VERSION="$JAVA_VERSION" \
  -t mc-test-img . ; then
  BUILD_END=$(date +%s)
  BUILD_TIME=$((BUILD_END - BUILD_START))
  BUILD_RESULT="✅ PASS (${BUILD_TIME}s)"
  echo "✅ Build OK en ${BUILD_TIME}s"
  ((PASS++))
else
  BUILD_RESULT="❌ FAIL"
  echo "❌ Build échoué"
  ((FAIL++))
  echo "--- [$TARGET] MC=$MC_VERSION JAVA=$JAVA_VERSION ---" >> "$REPORT"
  echo "BUILD: $BUILD_RESULT" >> "$REPORT"
  echo ""
  echo "📊 RÉSUMÉ : $PASS/$TOTAL PASS | $FAIL FAIL"
  exit 1
fi

# --- TEST 2 : EULA refusé = crash attendu ---
((TOTAL++))
echo "📜 Test EULA=false (doit crasher)..."
docker run --rm --name mc-test-eula \
  -e EULA=false \
  mc-test-img > /dev/null 2>&1 &
EULA_PID=$!
sleep 5

if ! kill -0 $EULA_PID 2>/dev/null; then
  wait $EULA_PID || true
  EULA_RESULT="✅ PASS (crash attendu)"
  echo "✅ Le serveur refuse de démarrer sans EULA"
  ((PASS++))
else
  docker rm -f mc-test-eula 2>/dev/null || true
  EULA_RESULT="❌ FAIL (aurait dû crasher)"
  echo "❌ Le serveur a démarré sans EULA !"
  ((FAIL++))
fi

# --- TEST 3 : Démarrage normal ---
((TOTAL++))
echo "🚀 Démarrage du serveur (EULA=true)..."
CONTAINER=$(docker run -d --name mc-test \
  -e EULA=true \
  -e DIFFICULTY=hard \
  -e RCON_PASSWORD=minecraft \
  -e RCON_PORT=25575 \
  -p 25565:25565 \
  -p 25575:25575 \
  mc-test-img)

echo "⏳ Attente du démarrage (120s max)..."
STARTED=false
for i in $(seq 1 120); do
  LOGS=$(docker logs "$CONTAINER" 2>&1)
  if echo "$LOGS" | grep -q "Done"; then
    STARTED=true
    START_RESULT="✅ PASS (${i}s)"
    echo "✅ Serveur prêt en ${i}s"
    ((PASS++))
    break
  fi
  sleep 1
done

if [ "$STARTED" = false ]; then
  START_RESULT="❌ FAIL (timeout 120s)"
  echo "❌ Le serveur n'a pas démarré en 120s"
  ((FAIL++))
  echo "📋 Derniers logs :"
  docker logs --tail 20 "$CONTAINER" 2>&1
fi

# --- TEST 4 : Non-root ---
((TOTAL++))
echo "👤 Test user non-root..."
RUNNING_USER=$(docker exec "$CONTAINER" whoami 2>/dev/null || echo "unknown")
if [ "$RUNNING_USER" != "root" ]; then
  USER_RESULT="✅ PASS (user=$RUNNING_USER)"
  echo "✅ Tourne en tant que '$RUNNING_USER'"
  ((PASS++))
else
  USER_RESULT="❌ FAIL (user=$RUNNING_USER)"
  echo "❌ Tourne en ROOT !"
  ((FAIL++))
fi

# --- TEST 5 : server.properties respecte les env ---
((TOTAL++))
echo "⚙️  Test DIFFICULTY=hard dans server.properties..."
DIFF_LINE=$(docker exec "$CONTAINER" cat /minecraft/server.properties 2>/dev/null | grep "^difficulty=" || echo "")
if echo "$DIFF_LINE" | grep -q "difficulty=hard"; then
  ENV_RESULT="✅ PASS ($DIFF_LINE)"
  echo "✅ $DIFF_LINE"
  ((PASS++))
else
  ENV_RESULT="❌ FAIL (got: $DIFF_LINE)"
  echo "❌ Attendu difficulty=hard, trouvé: $DIFF_LINE"
  ((FAIL++))
fi

# --- TEST 6 : Port 25565 écoute ---
((TOTAL++))
echo "🌐 Test port 25565..."
if nc -z -w 5 127.0.0.1 25565 2>/dev/null; then
  PORT_RESULT="✅ PASS"
  echo "✅ Port 25565 ouvert"
  ((PASS++))
else
  PORT_RESULT="❌ FAIL"
  echo "❌ Port 25565 fermé"
  ((FAIL++))
fi

# --- TEST 7 : RCON fonctionnel ---
((TOTAL++))
echo "🎮 Test RCON..."
RCON_RESPONSE=$(docker exec "$CONTAINER" rcon-cli --host localhost --port 25575 --password minecraft "list" 2>&1)
if echo "$RCON_RESPONSE" | grep -qi "players"; then
  RCON_RESULT="✅ PASS ($RCON_RESPONSE)"
  echo "✅ RCON répond : $RCON_RESPONSE"
  ((PASS++))
else
  RCON_RESULT="❌ FAIL (response: $RCON_RESPONSE)"
  echo "❌ RCON ne répond pas : $RCON_RESPONSE"
  ((FAIL++))
fi

# --- TEST 8 : Graceful shutdown ---
((TOTAL++))
echo "🛑 Test graceful shutdown..."
docker stop -t 30 "$CONTAINER" >/dev/null 2>&1
EXIT_CODE=$(docker inspect "$CONTAINER" --format='{{.State.ExitCode}}' 2>/dev/null)

if [ "$EXIT_CODE" = "0" ] || [ "$EXIT_CODE" = "143" ]; then
  GRACEFUL_RESULT="✅ PASS (exit=$EXIT_CODE)"
  echo "✅ Arrêt propre (exit code $EXIT_CODE)"
  ((PASS++))
elif [ "$EXIT_CODE" = "137" ]; then
  GRACEFUL_RESULT="❌ FAIL (exit=137 = SIGKILL)"
  echo "❌ SIGKILL — le serveur n'a pas capté SIGTERM"
  ((FAIL++))
else
  GRACEFUL_RESULT="⚠️  UNCLEAR (exit=$EXIT_CODE)"
  echo "⚠️  Exit code: $EXIT_CODE"
  ((FAIL++))
fi

# === RAPPORT ===
LOGS=$(docker logs "$CONTAINER" 2>&1 | tail -5)

echo "--- [$TARGET] MC=$MC_VERSION JAVA=$JAVA_VERSION ---" >> "$REPORT"
echo "BUILD:     $BUILD_RESULT" >> "$REPORT"
echo "EULA:      $EULA_RESULT" >> "$REPORT"
echo "START:     $START_RESULT" >> "$REPORT"
echo "USER:      $USER_RESULT" >> "$REPORT"
echo "ENV:       $ENV_RESULT" >> "$REPORT"
echo "PORT:      $PORT_RESULT" >> "$REPORT"
echo "RCON:      $RCON_RESULT" >> "$REPORT"
echo "SHUTDOWN:  $GRACEFUL_RESULT" >> "$REPORT"
echo "LOGS:" >> "$REPORT"
echo "$LOGS" >> "$REPORT"
echo "" >> "$REPORT"

# === CLEANUP ===
echo "🧹 Cleanup..."
docker rm -f "$CONTAINER" >/dev/null 2>&1
docker rmi mc-test-img 2>/dev/null || true
echo "✅ Nettoyé"

# === RÉSUMÉ ===
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 RÉSUMÉ : $PASS/$TOTAL PASS | $FAIL FAIL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📄 Rapport : cat $REPORT"
