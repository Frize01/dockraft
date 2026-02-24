# ============================================================
# VARIABLES
# ============================================================
VARIANT       ?= vanilla
MC_VERSION    ?= 1.21.1
JAVA_VERSION  ?= 21
MEMORY_MIN    ?= 1G
MEMORY_MAX    ?= 2G
RCON_PASSWORD ?= minecraft
RCON_PORT     ?= 25575
CONTAINER     ?= mc-$(VARIANT)
IMAGE         ?= minecraft-$(VARIANT):$(MC_VERSION)

# ============================================================
# BUILD
# ============================================================
.PHONY: build
build:
	docker build \
	    --target $(VARIANT) \
	    --build-arg MC_VERSION=$(MC_VERSION) \
	    --build-arg JAVA_VERSION=$(JAVA_VERSION) \
	    -t $(IMAGE) .

# ============================================================
# RUN / STOP / RESTART
# ============================================================
.PHONY: run
run:
	docker run -d \
	    --name $(CONTAINER) \
	    -p 25565:25565 \
	    -p $(RCON_PORT):$(RCON_PORT) \
	    -e EULA=true \
	    -e MEMORY_MIN=$(MEMORY_MIN) \
	    -e MEMORY_MAX=$(MEMORY_MAX) \
	    -e RCON_PASSWORD=$(RCON_PASSWORD) \
	    -e RCON_PORT=$(RCON_PORT) \
	    $(IMAGE)
	@echo "✅ $(CONTAINER) lancé"

.PHONY: stop
stop:
	docker stop $(CONTAINER) && docker rm $(CONTAINER)
	@echo "🛑 $(CONTAINER) arrêté et supprimé"

.PHONY: restart
restart: stop run

# ============================================================
# LOGS
# ============================================================
.PHONY: logs
logs:
	docker logs -f $(CONTAINER)

# ============================================================
# RCON
# ============================================================
.PHONY: console
console:
	@docker exec -it $(CONTAINER) rcon-cli \
	    --host localhost --port $(RCON_PORT) --password $(RCON_PASSWORD)

.PHONY: rcon
rcon:
	@docker exec $(CONTAINER) rcon-cli \
	    --host localhost --port $(RCON_PORT) --password $(RCON_PASSWORD) "$(CMD)"

.PHONY: say
say:
	@docker exec $(CONTAINER) rcon-cli \
	    --host localhost --port $(RCON_PORT) --password $(RCON_PASSWORD) "say $(MSG)"

# ============================================================
# CLEAN
# ============================================================
.PHONY: clean
clean:
	-docker stop $(CONTAINER) 2>/dev/null
	-docker rm $(CONTAINER) 2>/dev/null
	-docker rmi $(IMAGE) 2>/dev/null
	@echo "🧹 Nettoyé"

# ============================================================
# HELP
# ============================================================
.PHONY: help
help:
	@echo ""
	@echo "  make build                          Build l'image"
	@echo "  make run                            Lance le serveur"
	@echo "  make stop                           Arrête et supprime"
	@echo "  make restart                        Redémarre"
	@echo "  make logs                           Affiche les logs (follow)"
	@echo "  make console                        Console RCON interactive"
	@echo "  make rcon CMD=\"op Kali\"              Exécute une commande RCON"
	@echo "  make say MSG=\"Hello tout le monde\"   Envoie un message en jeu"
	@echo "  make clean                          Supprime conteneur + image"
	@echo ""
	@echo "  Variables : VARIANT=vanilla MC_VERSION=1.21.1 JAVA_VERSION=21"
	@echo ""
