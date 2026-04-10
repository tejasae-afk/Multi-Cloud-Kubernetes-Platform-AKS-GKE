SHELL := /bin/bash

TF_DIR ?= terraform
TF_BACKEND_BUCKET ?=
TF_BACKEND_PREFIX ?= multi-cloud-k8s/dev

GKE_CLUSTER_NAME ?= mc-k8s-gke-cluster
GKE_REGION ?= us-central1
GKE_ZONE ?= us-central1-a

AKS_CLUSTER_NAME ?= mc-k8s-aks
AKS_RESOURCE_GROUP ?= mc-k8s-aks-rg
AKS_LOCATION ?= eastus

ISTIO_VERSION ?= 1.29.1
KUBE_PROM_STACK_VERSION ?= 82.14.1
GRAFANA_CHART_VERSION ?= 10.5.15
CERT_MANAGER_CHART_VERSION ?= 1.20.0

.PHONY: init plan-gke plan-aks apply-all deploy-app mesh-install monitoring-up traffic-test destroy-all clean

init:
	@test -n "$(TF_BACKEND_BUCKET)" || (echo "set TF_BACKEND_BUCKET before init" && exit 1)
	# echo "debug: $(TF_BACKEND_BUCKET) $(TF_BACKEND_PREFIX)"
	terraform -chdir=$(TF_DIR) init -upgrade \
		-backend-config="bucket=$(TF_BACKEND_BUCKET)" \
		-backend-config="prefix=$(TF_BACKEND_PREFIX)"

plan-gke:
	terraform -chdir=$(TF_DIR) plan -lock-timeout=20m -target=module.gke -out=tfplan-gke

plan-aks:
	terraform -chdir=$(TF_DIR) plan -lock-timeout=20m -target=module.aks -out=tfplan-aks

apply-all:
	terraform -chdir=$(TF_DIR) apply -lock-timeout=20m

deploy-app:
	# retrieve kube creds from outputs if context switching gets annoying
	kubectl apply -k kubernetes/base
	kubectl apply -k kubernetes/overlays/shared

mesh-install:
	helm repo add istio https://istio-release.storage.googleapis.com/charts
	helm repo update
	helm upgrade --install istio-base istio/base \
		--namespace istio-system \
		--create-namespace \
		--version $(ISTIO_VERSION)
	helm upgrade --install istiod istio/istiod \
		--namespace istio-system \
		--version $(ISTIO_VERSION)
	helm upgrade --install istio-eastwest istio/gateway \
		--namespace istio-eastwest \
		--create-namespace \
		--version $(ISTIO_VERSION)

monitoring-up:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo add jetstack https://charts.jetstack.io
	helm repo update
	helm upgrade --install cert-manager jetstack/cert-manager \
		--namespace cert-manager \
		--create-namespace \
		--version $(CERT_MANAGER_CHART_VERSION) \
		--set crds.enabled=true
	helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
		--namespace monitoring \
		--create-namespace \
		--version $(KUBE_PROM_STACK_VERSION) \
		--set grafana.enabled=false
	helm upgrade --install grafana grafana/grafana \
		--namespace monitoring \
		--create-namespace \
		--version $(GRAFANA_CHART_VERSION)

traffic-test:
	@test -n "$(HOST)" || (echo "set HOST=platform.dev.acmeops.net" && exit 1)
	# good enough for now
	curl -skI https://$(HOST)
	dig +short $(HOST)

destroy-all:
	terraform -chdir=$(TF_DIR) destroy -lock-timeout=20m

clean:
	# TODO: this assumes one working directory and one env, which is fine while this repo is still small
	rm -rf $(TF_DIR)/.terraform tfplan-gke tfplan-aks $(TF_DIR)/.terraform.lock.hcl
