#!/bin/bash
# test-all.sh — Build + run + smoke test tous les targets DockRaft

REPORT="test-results.txt"
TIMEOUT=120

# Format : "target|MC_VERSION|JAVA_VERSION|expect_fail"
TESTS=(
  # --- Tests valides ---
  "vanilla|1.21.1|21|false"
  "snapshot|25w14craftmine|21|false"
  "paper|1.21.1|21|false"
  "fabric|1.21.1|21|false"
  "forge|1.21.1|21|false"
  "neoforge|1.21.1|21|false"
  "spigot|1.21.1|21|false"
  # --- Tests invalides (doivent FAIL au build) ---
  "vanilla|1.99.9|21|true"
  "paper|1.99.9|21|true"
  "fabric|1.99.9|21|true"
  "forge|1.99.9|21|true"
  "neoforge|1.99.9|21|true"
  "spigot|1.99.9|21|true"
  "snapshot|99w99a|21|true"
)

# Reset rapport
echo "=============================" > "$REPORT"
echo " DockRaft Test Report" >> "$REPORT"
echo " $(date)" >> "$REPORT"
echo "=============================" >> "$REPORT"
echo "" >> "$REPORT"

PASS=0
FAIL=0
TOTAL=${#TESTS[@]}

for entry in "${TESTS[@]}"; do
  IFS='|' read -r TARGET MC_VERSION JAVA_VERSION EXPECT_FAIL <<< "$entry"
  CONTAINER="mc-test-$$"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [ "$EXPECT_FAIL" = "true" ]; then
    echo "🧪 [$TARGET] MC=$MC_VERSION (SHOULD FAIL)"
  else
    echo "🔨 [$TARGET] MC=$MC_VERSION"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # === CLEANUP avant chaque test ===
  docker rm -f "$CONTAINER" 2>/dev/null

  # === BUILD ===
  echo "📦 Build..."
  BUILD_START=$(date +%s)

  BUILD_OUTPUT=$(DOCKER_BUILDKIT=1 docker build --target "$TARGET" \
    --build-arg MC_VERSION="$MC_VERSION" \
    --build-arg JAVA_VERSION="$JAVA_VERSION" \
    --no-cache \
    -t "mc-test-img" . 2>&1)
  BUILD_EXIT=$?

  BUILD_END=$(date +%s)
  BUILD_TIME=$((BUILD_END - BUILD_START))

  # --- Si on ATTEND un fail ---
  if [ "$EXPECT_FAIL" = "true" ]; then
    if [ $BUILD_EXIT -ne 0 ]; then
      echo "✅ Build a FAIL comme prévu"
      echo "--- [$TARGET] MC=$MC_VERSION (EXPECT FAIL) ---" >> "$REPORT"
      echo "BUILD:   ✅ CORRECTLY FAILED (${BUILD_TIME}s)" >> "$REPORT"
      echo "ERROR (last 5 lines):" >> "$REPORT"
      echo "$BUILD_OUTPUT" | tail -5 >> "$REPORT"
      echo "" >> "$REPORT"
      ((PASS++))
    else
      echo "❌ Build a RÉUSSI alors qu'il devait FAIL"
      echo "--- [$TARGET] MC=$MC_VERSION (EXPECT FAIL) ---" >> "$REPORT"
      echo "BUILD:   ❌ SHOULD HAVE FAILED BUT PASSED" >> "$REPORT"
      echo "" >> "$REPORT"
      ((FAIL++))
      docker rmi "mc-test-img" 2>/dev/null
    fi
    continue
  fi

  # --- Si on attend un succès mais build fail ---
  if [ $BUILD_EXIT -ne 0 ]; then
    echo "❌ Build FAIL"
    echo "--- [$TARGET] MC=$MC_VERSION ---" >> "$REPORT"
    echo "BUILD:   ❌ FAIL (${BUILD_TIME}s)" >> "$REPORT"
    echo "ERROR (last 10 lines):" >> "$REPORT"
    echo "$BUILD_OUTPUT" | tail -10 >> "$REPORT"
    echo "" >> "$REPORT"
    ((FAIL++))
    continue
  fi

  echo "✅ Build OK (${BUILD_TIME}s)"

  # === TEST EULA REFUSÉ ===
  echo "🔒 Test refus EULA..."
  EULA_OUTPUT=$(docker run --rm "mc-test-img" 2>&1)
  if echo "$EULA_OUTPUT" | grep -qi "eula"; then
    EULA_RESULT="✅ PASS"
    echo "✅ EULA refusé correctement"
  else
    EULA_RESULT="⚠️  Pas de message EULA"
    echo "⚠️  Pas de message EULA détecté"
  fi

  # === RUN AVEC EULA + DIFFICULTY pour test env ===
  echo "🚀 Démarrage serveur..."
  docker run -d --name "$CONTAINER" \
    -e EULA=true \
    -e DIFFICULTY=hard \
    -p 25565:25565 \
    --memory=2g \
    "mc-test-img" >/dev/null 2>&1

  # Attendre "Done"
  echo "⏳ Attente démarrage (max ${TIMEOUT}s)..."
  START_TIME=$(date +%s)
  STARTED=false

  while true; do
    ELAPSED=$(( $(date +%s) - START_TIME ))

    if docker logs "$CONTAINER" 2>&1 | grep -q "Done"; then
      STARTED=true
      break
    fi

    if ! docker ps --format '{{.Names}}' | grep -q "$CONTAINER"; then
      echo "💀 Container mort"
      break
    fi

    if [ $ELAPSED -ge $TIMEOUT ]; then
      echo "⏰ Timeout"
      break
    fi

    sleep 3
  done

  START_DURATION=$(( $(date +%s) - START_TIME ))

  if $STARTED; then
    echo "✅ Serveur démarré en ${START_DURATION}s"
    START_RESULT="✅ PASS (${START_DURATION}s)"
    ((PASS++))
  else
    echo "❌ Serveur pas démarré"
    START_RESULT="❌ FAIL (${START_DURATION}s)"
    ((FAIL++))
    LOGS=$(docker logs "$CONTAINER" 2>&1 | tail -20)

    echo "--- [$TARGET] MC=$MC_VERSION ---" >> "$REPORT"
    echo "BUILD:   ✅ PASS (${BUILD_TIME}s)" >> "$REPORT"
    echo "EULA:    $EULA_RESULT" >> "$REPORT"
    echo "START:   $START_RESULT" >> "$REPORT"
    echo "LOGS:" >> "$REPORT"
    echo "$LOGS" >> "$REPORT"
    echo "" >> "$REPORT"

    docker stop "$CONTAINER" >/dev/null 2>&1
    docker rm -f "$CONTAINER" >/dev/null 2>&1
    docker rmi "mc-test-img" 2>/dev/null
    continue
  fi

  # ═══════════════════════════════════════
  # 4 NOUVEAUX TESTS (serveur running)
  # ═══════════════════════════════════════

  # --- TEST 1 : User non-root ---
  echo "👤 Test user non-root..."
  RUNNING_USER=$(docker exec "$CONTAINER" whoami 2>&1)
  if [ "$RUNNING_USER" != "root" ] && [ -n "$RUNNING_USER" ]; then
    USER_RESULT="✅ PASS (user=$RUNNING_USER)"
    echo "✅ Tourne en tant que '$RUNNING_USER'"
  else
    USER_RESULT="❌ FAIL (user=$RUNNING_USER)"
    echo "❌ Tourne en ROOT !"
  fi

  # --- TEST 2 : server.properties respecte les env ---
  echo "⚙️  Test DIFFICULTY=hard dans server.properties..."
  DIFF_LINE=$(docker exec "$CONTAINER" cat /minecraft/server.properties 2>/dev/null | grep "^difficulty=")
  if echo "$DIFF_LINE" | grep -q "difficulty=hard"; then
    ENV_RESULT="✅ PASS ($DIFF_LINE)"
    echo "✅ $DIFF_LINE"
  else
    ENV_RESULT="❌ FAIL (got: $DIFF_LINE)"
    echo "❌ Attendu difficulty=hard, trouvé: $DIFF_LINE"
  fi

  # --- TEST 3 : Port 25565 écoute ---
  echo "🌐 Test port 25565..."
  if nc -z -w 5 127.0.0.1 25565 2>/dev/null; then
    PORT_RESULT="✅ PASS"
    echo "✅ Port 25565 ouvert"
  else
    PORT_RESULT="❌ FAIL"
    echo "❌ Port 25565 fermé"
  fi

  # --- TEST 4 : Graceful shutdown ---
  echo "🛑 Test graceful shutdown..."
  docker stop -t 30 "$CONTAINER" >/dev/null 2>&1
  EXIT_CODE=$(docker inspect "$CONTAINER" --format='{{.State.ExitCode}}' 2>/dev/null)

  if [ "$EXIT_CODE" = "0" ] || [ "$EXIT_CODE" = "143" ]; then
    GRACEFUL_RESULT="✅ PASS (exit=$EXIT_CODE)"
    echo "✅ Arrêt propre (exit code $EXIT_CODE)"
  elif [ "$EXIT_CODE" = "137" ]; then
    GRACEFUL_RESULT="❌ FAIL (exit=137 = SIGKILL)"
    echo "❌ SIGKILL — le serveur n'a pas capté SIGTERM"
  else
    GRACEFUL_RESULT="⚠️  UNCLEAR (exit=$EXIT_CODE)"
    echo "⚠️  Exit code: $EXIT_CODE"
  fi

  # === ÉCRIRE RAPPORT ===
  LOGS=$(docker logs "$CONTAINER" 2>&1 | tail -5)

  echo "--- [$TARGET] MC=$MC_VERSION ---" >> "$REPORT"
  echo "BUILD:     ✅ PASS (${BUILD_TIME}s)" >> "$REPORT"
  echo "EULA:      $EULA_RESULT" >> "$REPORT"
  echo "START:     $START_RESULT" >> "$REPORT"
  echo "USER:      $USER_RESULT" >> "$REPORT"
  echo "ENV:       $ENV_RESULT" >> "$REPORT"
  echo "PORT:      $PORT_RESULT" >> "$REPORT"
  echo "SHUTDOWN:  $GRACEFUL_RESULT" >> "$REPORT"
  echo "LOGS:" >> "$REPORT"
  echo "$LOGS" >> "$REPORT"
  echo "" >> "$REPORT"

  # === CLEANUP ===
  echo "🧹 Cleanup..."
  docker rm -f "$CONTAINER" >/dev/null 2>&1
  docker rmi "mc-test-img" 2>/dev/null
  echo "✅ Nettoyé"

done

# === RÉSUMÉ ===
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 RÉSUMÉ : $PASS/$TOTAL PASS | $FAIL FAIL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "=============================" >> "$REPORT"
echo " RÉSUMÉ: $PASS/$TOTAL PASS | $FAIL FAIL" >> "$REPORT"
echo "=============================" >> "$REPORT"

echo "📄 Rapport : cat $REPORT"
