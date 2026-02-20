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
  CONTAINER="mc-test-$$"  # nom unique pour éviter conflits

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
      # Cleanup l'image
      docker rmi "mc-test-img" 2>/dev/null
    fi
    continue
  fi

  # --- Test normal (doit réussir) ---
  if [ $BUILD_EXIT -ne 0 ]; then
    echo "❌ Build FAILED"
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

  # === RUN AVEC EULA ===
  echo "🚀 Démarrage serveur..."
  docker run -d --name "$CONTAINER" \
    -e EULA=true \
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
  LOGS=$(docker logs "$CONTAINER" 2>&1 | tail -5)

  if $STARTED; then
    echo "✅ Serveur démarré en ${START_DURATION}s"
    START_RESULT="✅ PASS (${START_DURATION}s)"
    ((PASS++))
  else
    echo "❌ Serveur pas démarré"
    START_RESULT="❌ FAIL (${START_DURATION}s)"
    ((FAIL++))
    # Plus de logs pour debug
    LOGS=$(docker logs "$CONTAINER" 2>&1 | tail -20)
  fi

  # Écrire rapport
  echo "--- [$TARGET] MC=$MC_VERSION ---" >> "$REPORT"
  echo "BUILD:   ✅ PASS (${BUILD_TIME}s)" >> "$REPORT"
  echo "EULA:    $EULA_RESULT" >> "$REPORT"
  echo "START:   $START_RESULT" >> "$REPORT"
  echo "LOGS:" >> "$REPORT"
  echo "$LOGS" >> "$REPORT"
  echo "" >> "$REPORT"

  # === CLEANUP APRÈS CHAQUE TEST ===
  echo "🧹 Cleanup..."
  docker stop "$CONTAINER" >/dev/null 2>&1
  docker rm -f "$CONTAINER" >/dev/null 2>&1
  docker rmi "mc-test-img" 2>/dev/null

  echo "✅ Nettoyé"
done

# Résumé
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 RÉSUMÉ : $PASS/$TOTAL PASS | $FAIL FAIL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "=============================" >> "$REPORT"
echo " RÉSUMÉ: $PASS/$TOTAL PASS | $FAIL FAIL" >> "$REPORT"
echo "=============================" >> "$REPORT"

echo "📄 Rapport : cat $REPORT"
