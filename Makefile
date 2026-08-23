SHELL := /bin/bash
.DEFAULT_GOAL := help
.PHONY: help preflight local-up local-down local-logs local-ps smoke traces bench gcp-up gcp-down aws-up aws-down clean

help: ## Muestra esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "};{printf "  \033[36m%-14s\033[0m %s\n",$$1,$$2}'

preflight: ## Verifica prerequisitos locales
	@bash scripts/preflight-local.sh

local-up: ## Levanta el stack completo (8 contenedores)
	@docker compose up -d --build
	@echo "Jaeger    http://localhost:16686"
	@echo "Grafana   http://localhost:3000  (admin/admin)"
	@echo "Promethe. http://localhost:9090"

local-down: ## Baja el stack y borra volumenes
	@docker compose down -v

local-ps: ## Estado de los contenedores
	@docker compose ps

local-logs: ## Logs en vivo
	@docker compose logs -f --tail=100

smoke: ## Genera trafico de prueba (exito, error y lento)
	@bash scripts/smoke-test.sh

traces: ## Entrega los trace_id listos para capturar (Fase 3)
	@bash scripts/pick-traces.sh

bench: ## Corre el benchmark de overhead (Fase 4)
	@bash benchmark/run-benchmark.sh

gcp-up: ## Despliega en GCP (verifica budget antes)
	@bash scripts/check-budget-gcp.sh && cd iac/gcp && terraform init && terraform apply

gcp-down: ## Destruye todo en GCP
	@cd iac/gcp && terraform destroy -auto-approve

aws-up: ## Despliega en AWS (verifica budget antes)
	@bash scripts/check-budget-aws.sh && cd iac/aws && terraform init && terraform apply

aws-down: ## Destruye todo en AWS - CORRER SIEMPRE AL TERMINAR
	@cd iac/aws && terraform destroy -auto-approve

clean: local-down ## Limpia todo lo local
	@docker system prune -f
