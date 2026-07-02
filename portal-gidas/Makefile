# ============================================================
# Makefile — Portal GIDAS
# ============================================================

APP_NAME := portal-gidas
PORT := 80

.PHONY: help deps run docker-build docker-run stop logs clean

help:
	@echo "Comandos disponibles:"
	@echo "  make deps         — Instalar dependencias Python"
	@echo "  make run           — Ejecutar con uvicorn (desarrollo)"
	@echo "  make docker-build  — Construir imagen Docker"
	@echo "  make docker-run    — Ejecutar container Docker"
	@echo "  make stop          — Detener container Docker"
	@echo "  make logs          — Ver logs del container"
	@echo "  make clean         — Limpiar archivos temporales"

deps:
	pip install -r requirements.txt

run:
	@[ -n "$$LDAP_BIND_PASSWORD" ] || (echo "ERROR: LDAP_BIND_PASSWORD no está definida. Creá un archivo .env con: LDAP_BIND_PASSWORD=tu_password"; exit 1)
	JWT_SECRET="$$(openssl rand -hex 32)" \
	LDAP_BIND_PASSWORD="$$LDAP_BIND_PASSWORD" \
	uvicorn app.main:app --host 0.0.0.0 --port $(PORT) --reload

docker-build:
	docker build -t $(APP_NAME) .

docker-run:
	@[ -n "$$LDAP_BIND_PASSWORD" ] || (echo "ERROR: LDAP_BIND_PASSWORD no está definida."; exit 1)
	docker run -d --name $(APP_NAME) \
		-p $(PORT):80 \
		-e JWT_SECRET="$$(openssl rand -hex 32)" \
		-e LDAP_BIND_PASSWORD="$$LDAP_BIND_PASSWORD" \
		-v "$$(pwd)/config.yaml:/app/config.yaml:ro" \
		--restart unless-stopped \
		$(APP_NAME)

stop:
	docker stop $(APP_NAME) 2>/dev/null || true
	docker rm $(APP_NAME) 2>/dev/null || true

logs:
	docker logs -f $(APP_NAME)

clean: stop
	docker rmi $(APP_NAME) 2>/dev/null || true
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
