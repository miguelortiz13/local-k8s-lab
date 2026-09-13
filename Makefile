SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

CLUSTER       ?= boutique
NAMESPACE     ?= boutique
CHART         ?= oci://us-docker.pkg.dev/online-boutique-ci/charts/onlineboutique
CHART_VERSION ?= 0.10.6
VALUES        ?= values/onlineboutique.yaml
PORT          ?= 8090

export PATH := $(HOME)/.local/bin:$(PATH)

.PHONY: help
help: ## Muestra esta ayuda
	@awk 'BEGIN{FS=":.*## "} /^[a-zA-Z_-]+:.*## /{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

.PHONY: tools
tools: ## Instala kubectl, kind, helm y k9s con versiones fijadas en ~/.local/bin
	@scripts/install-tools.sh

.PHONY: doctor
doctor: ## Verifica herramientas, Docker y recursos disponibles
	@scripts/doctor.sh

.PHONY: up
up: ## Crea el cluster kind (idempotente)
	@if kind get clusters | grep -qx '$(CLUSTER)'; then \
	  echo "Cluster '$(CLUSTER)' ya existe"; \
	else \
	  kind create cluster --name '$(CLUSTER)' --config kind/cluster.yaml --wait 120s; \
	fi
	@kubectl cluster-info --context 'kind-$(CLUSTER)'

.PHONY: deploy
deploy: ## Despliega Online Boutique con Helm y espera a que esté listo
	helm upgrade --install onlineboutique '$(CHART)' --version '$(CHART_VERSION)' \
	  --kube-context 'kind-$(CLUSTER)' --namespace '$(NAMESPACE)' --create-namespace \
	  -f '$(VALUES)' --wait --timeout 10m
	@$(MAKE) --no-print-directory status

.PHONY: status
status: ## Estado de pods y servicios
	@kubectl --context 'kind-$(CLUSTER)' -n '$(NAMESPACE)' get pods,svc

.PHONY: open
open: ## Expone la tienda en http://localhost:$(PORT) (Ctrl+C para cerrar)
	@echo "Tienda en http://localhost:$(PORT)"
	kubectl --context 'kind-$(CLUSTER)' -n '$(NAMESPACE)' port-forward --address 127.0.0.1 svc/frontend '$(PORT):80'

.PHONY: smoke
smoke: ## Prueba de humo: el frontend responde HTTP 200
	@CONTEXT='kind-$(CLUSTER)' NAMESPACE='$(NAMESPACE)' scripts/smoke-test.sh

.PHONY: undeploy
undeploy: ## Elimina la aplicación (conserva el cluster)
	helm uninstall onlineboutique --kube-context 'kind-$(CLUSTER)' -n '$(NAMESPACE)' --ignore-not-found

.PHONY: down
down: ## Destruye el cluster kind
	kind delete cluster --name '$(CLUSTER)'

.PHONY: lint
lint: ## Valida scripts y renderiza el chart con los values
	@if command -v shellcheck > /dev/null; then shellcheck scripts/*.sh; \
	else docker run --rm -v "$$PWD:/mnt" -w /mnt koalaman/shellcheck:stable scripts/*.sh; fi
	helm template onlineboutique '$(CHART)' --version '$(CHART_VERSION)' -f '$(VALUES)' > /dev/null
	@echo "lint OK"
