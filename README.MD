# Dockraft

## ⚙️ Compatibilité Java

| Minecraft Version | JAVA_VERSION |
|---|---|
| 1.8 - 1.16.5 | 8 |
| 1.17 - 1.20.x | 17 |
| 1.21+ | 21 |


⚠️ Note Snapshot : le MC_VERSION doit être le nom exact du snapshot, ex: 25w07a. Tu peux trouver le dernier sur launcher.mojang.com dans la clé latest.snapshot.

# VANILLA
DOCKER_BUILDKIT=1 docker build --target vanilla \
  --build-arg MC_VERSION=1.21.1 \
  --build-arg JAVA_VERSION=21 \
  -t mc-vanilla . && \
docker run -d --name mc-vanilla -p 25565:25565 -e EULA=true mc-vanilla

# SNAPSHOT
DOCKER_BUILDKIT=1 docker build --target snapshot \
  --build-arg MC_VERSION=25w14craftmine \
  --build-arg JAVA_VERSION=21 \
  -t mc-snapshot . && \
docker run -d --name mc-snapshot -p 25566:25565 -e EULA=true mc-snapshot

# PAPER
DOCKER_BUILDKIT=1 docker build --target paper \
  --build-arg MC_VERSION=1.21.1 \
  --build-arg JAVA_VERSION=21 \
  -t mc-paper . && \
docker run -d --name mc-paper -p 25567:25565 -e EULA=true mc-paper

# FABRIC
DOCKER_BUILDKIT=1 docker build --target fabric \
  --build-arg MC_VERSION=1.21.1 \
  --build-arg JAVA_VERSION=21 \
  -t mc-fabric . && \
docker run -d --name mc-fabric -p 25568:25565 -e EULA=true mc-fabric

# FORGE
DOCKER_BUILDKIT=1 docker build --target forge \
  --build-arg MC_VERSION=1.21.1 \
  --build-arg JAVA_VERSION=21 \
  -t mc-forge . && \
docker run -d --name mc-forge -p 25569:25565 -e EULA=true mc-forge

# NEOFORGE
DOCKER_BUILDKIT=1 docker build --target neoforge \
  --build-arg MC_VERSION=1.21.1 \
  --build-arg JAVA_VERSION=21 \
  -t mc-neoforge . && \
docker run -d --name mc-neoforge -p 25570:25565 -e EULA=true mc-neoforge

# SPIGOT
DOCKER_BUILDKIT=1 docker build --target spigot \
  --build-arg MC_VERSION=1.21.1 \
  --build-arg JAVA_VERSION=21 \
  -t mc-spigot . && \
docker run -d --name mc-spigot -p 25571:25565 -e EULA=true mc-spigot



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
