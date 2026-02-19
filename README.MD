# Dockraft

## ⚙️ Compatibilité Java

| Minecraft Version | JAVA_VERSION |
|---|---|
| 1.8 - 1.16.5 | 8 |
| 1.17 - 1.20.x | 17 |
| 1.21+ | 21 |


⚠️ Note Snapshot : le MC_VERSION doit être le nom exact du snapshot, ex: 25w07a. Tu peux trouver le dernier sur launcher.mojang.com dans la clé latest.snapshot.


## 🎯 Objectif final
Un serveur Minecraft dans Docker, configurable via variables d'env

### Étape 1 — Dockerfile (image de base)
- [ ] `FROM` (image avec Java)
- [ ] `WORKDIR`
- [ ] Télécharger `server.jar`
- [ ] Accepter EULA
- [ ] `ENV MEMORY=2G`
- [ ] `EXPOSE 25565`
- [ ] `CMD`

### Étape 2 — Multi-stage (Vanilla / Forge / Fabric)
- [ ] `FROM base AS vanilla`
- [ ] `FROM base AS forge`
- [ ] `FROM base AS fabric`

### Étape 3 — Docker Compose
- [ ] `compose.yml`
- [ ] Volumes (world, mods, plugins, config)
- [ ] Variables d'environnement
- [ ] Ports

### Étape 4 — CI/CD (GitHub Actions)
- [ ] Build automatique des 3 images
- [ ] Tags (`1.21.1-vanilla`, `1.21.1-fabric`, etc.)
- [ ] Push vers un registry

### Étape 5 — Tester
- [ ] Lancer un serveur vanilla
- [ ] Vérifier que les volumes persistent
- [ ] Se connecter en jeu
