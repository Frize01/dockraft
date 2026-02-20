═══════════════════════════════════════════════════════════
  ACCÉDER À LA CONSOLE MINECRAFT DANS UN CONTENEUR DOCKER
═══════════════════════════════════════════════════════════

❌ docker exec -it conteneur /bin/bash
   → Te donne un shell LINUX, pas la console Minecraft

❌ docker exec -it conteneur "list"
   → N'envoie PAS la commande au serveur Minecraft

✅ docker attach conteneur
   → Attache au stdin du process principal (la console MC)
   → ⚠️ Ctrl+C = KILL le serveur ! Utiliser Ctrl+P Ctrl+Q pour détacher

✅ RCON (la vraie solution propre)
   → Protocole intégré à Minecraft pour commandes à distance
   → Nécessite dans server.properties :
      enable-rcon=true
      rcon.password=ton_mdp
      rcon.port=25575
   → Client : rcon-cli, mcrcon, ou même un script Python
   → Exemple : mcrcon -H localhost -P 25575 -p ton_mdp "list"

═══════════════════════════════════════════════════════════
  À IMPLÉMENTER DANS L'IMAGE :
  - Variable d'env ENABLE_RCON=true/false
  - Variable d'env RCON_PASSWORD
  - Variable d'env RCON_PORT (défaut 25575)
  - Exposer le port 25575
  - Installer mcrcon dans l'image pour usage interne
═══════════════════════════════════════════════════════════
