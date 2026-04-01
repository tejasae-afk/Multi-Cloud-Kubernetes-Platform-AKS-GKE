# multi-cloud-k8s-platform

## What this is
I built this repo as the infra base for a small multi-cloud Kubernetes platform that runs the same services on GKE and AKS. This phase is just the repo shape and the cloud plumbing, so the app code, mesh policy, and dashboards are still coming in behind it.

I kept GKE and AKS as separate Terraform modules because the resource models are different enough that one shared cluster module got ugly fast. I also kept both clouds in one GCS state because this is a single-operator project right now, and I care more about one clean graph than splitting state too early.

Security-wise, I turned on Workload Identity on GKE and managed identity plus OIDC on AKS so I don't have to park long-lived cloud keys in the repo, in CI, or in cluster secrets. I skipped GKE Autopilot for this one. DaemonSets aren't the blocker by themselves, but Istio CNI on Autopilot still pushes me toward privilege exceptions and a messier install path than I want.

I checked current release pages before I pinned anything. The last 1.29 patches I found were 1.29.14-gke.1132000 on GKE and 1.29.15 on AKS, but GKE 1.29 is already out of support now, so I left the version pins optional and kept the GKE cluster on the Regular channel so this repo still applies in March 2026.

## Architecture
```text
User
  |
  v
Cloud DNS / Azure Traffic Manager
  ├── GKE Cluster -> Istio -> [api-gw, order-svc, inventory-svc] -> Prometheus
  └── AKS Cluster -> Istio -> [api-gw, order-svc, inventory-svc] -> Prometheus
                                                                         |
                                                                         v
                                                                   Grafana (unified)
```

## Why multi-cloud
I wanted this for three reasons. First, I don't like tying a platform story to one vendor when the traffic edge, identity model, and network bits all fail in different ways. Second, splitting the same stack across GKE and AKS gives me a smaller blast radius when one side has a bad day. Third, I wanted real hands-on time in both ecosystems instead of treating one cloud as a footnote.

## Tech stack
| Tool | Version | What it does |
| --- | --- | --- |
| Terraform | 1.14.8 | Builds the infra and keeps state in GCS |
| hashicorp/google | 7.25.0 | Creates the GKE cluster, VPC, firewall rules, and Cloud DNS |
| hashicorp/azurerm | 4.66.0 | Creates the AKS cluster, VNet, managed identity, NSG, and Traffic Manager |
| Kubernetes | GKE Regular channel / AKS current GA by default | Runs the services and keeps the repo apply-safe after GKE 1.29 aged out |
| Istio | 1.29.1 | Handles mesh policy and cross-cloud traffic routing |
| Helm | 4.1.3 | Installs mesh and monitoring charts |
| kube-prometheus-stack | 82.14.1 | Brings up Prometheus, Alertmanager, exporters, and the operator |
| Grafana chart | 10.5.15 | Installs Grafana as a separate release |
| cert-manager | 1.20.0 | Issues cluster certificates |
| kubectl | 1.35.3 | Talks to both clusters |
| Google Cloud CLI | 562.0.0 | Auth and kubeconfig for GKE |
| Azure CLI | 2.84.0 | Auth and kubeconfig for AKS |

## Prerequisites
- Terraform 1.14.8 or newer
- Google Cloud CLI 562.0.0 or newer
- Azure CLI 2.84.0 or newer
- kubectl 1.35.3 or newer
- Helm 4.1.3 or newer
- A GCP project with billing on and these APIs enabled: Kubernetes Engine, Compute Engine, Cloud DNS, Cloud Resource Manager
- An Azure subscription with rights to create AKS, VNets, managed identities, public IPs, and Traffic Manager profiles
- CLI auth that can create cloud resources. I don't keep static credentials anywhere in this repo.

## Quick start
1. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars`.
2. Fill in the GCP project ID, Azure subscription ID, domain, and a unique Traffic Manager relative name.
3. Run `make init TF_BACKEND_BUCKET=<gcs-bucket> TF_BACKEND_PREFIX=multi-cloud-k8s/dev`.
4. Run `make plan-gke`.
5. Run `make plan-aks`.
6. Run `make apply-all`.
7. After the clusters are up, run `make mesh-install` and `make monitoring-up`.

## Project tree
This is the shape I'm aiming for once the app, mesh, and monitoring phases land.

```text
.
├── .editorconfig
├── .github
│   ├── CODEOWNERS
│   └── workflows
│       ├── ci.yml
│       ├── lint.yml
│       ├── plan.yml
│       └── release-images.yml
├── .gitignore
├── .pre-commit-config.yaml
├── LICENSE
├── Makefile
├── README.md
├── go.mod
├── go.sum
├── cmd
│   ├── api-gw
│   │   └── main.go
│   ├── inventory-svc
│   │   └── main.go
│   ├── loadgen
│   │   └── main.go
│   └── order-svc
│       └── main.go
├── deploy
│   ├── cert-manager
│   │   └── issuer.yaml
│   ├── istio
│   │   ├── destination-rules.yaml
│   │   ├── eastwest-gateway.yaml
│   │   ├── peer-authentication.yaml
│   │   ├── service-entries.yaml
│   │   └── virtual-services.yaml
│   ├── monitoring
│   │   ├── grafana-values.yaml
│   │   └── kube-prom-values.yaml
│   └── traffic
│       ├── aks-gateway-service.yaml
│       └── gke-gateway-service.yaml
├── docs
│   ├── decisions
│   │   ├── 001-separate-cloud-modules.md
│   │   ├── 002-single-remote-state.md
│   │   ├── 003-gke-standard-over-autopilot.md
│   │   └── 004-no-static-cloud-creds.md
│   ├── runbooks
│   │   ├── aks-upgrade.md
│   │   ├── gke-upgrade.md
│   │   ├── mesh-rollout.md
│   │   └── traffic-failover.md
│   └── screenshots
│       ├── grafana-home.png
│       ├── traffic-manager.png
│       └── topology.png
├── hack
│   ├── bootstrap-kind.sh
│   ├── lint-all.sh
│   └── reset-contexts.sh
├── internal
│   ├── config
│   │   └── config.go
│   ├── httpx
│   │   ├── health.go
│   │   ├── middleware.go
│   │   └── server.go
│   ├── inventory
│   │   ├── model.go
│   │   ├── repository.go
│   │   └── service.go
│   ├── orders
│   │   ├── model.go
│   │   ├── repository.go
│   │   └── service.go
│   ├── platform
│   │   ├── cloud
│   │   │   ├── aks.go
│   │   │   └── gke.go
│   │   ├── log
│   │   │   └── logger.go
│   │   └── telemetry
│   │       ├── metrics.go
│   │       └── tracing.go
│   └── routing
│       ├── failover.go
│       └── locality.go
├── kubernetes
│   ├── base
│   │   ├── api-gw
│   │   │   ├── deployment.yaml
│   │   │   ├── kustomization.yaml
│   │   │   └── service.yaml
│   │   ├── inventory-svc
│   │   │   ├── deployment.yaml
│   │   │   ├── kustomization.yaml
│   │   │   └── service.yaml
│   │   ├── order-svc
│   │   │   ├── deployment.yaml
│   │   │   ├── kustomization.yaml
│   │   │   └── service.yaml
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   └── serviceaccounts.yaml
│   └── overlays
│       ├── aks
│       │   ├── kustomization.yaml
│       │   ├── patch-workload-identity.yaml
│       │   └── patch-zone-affinity.yaml
│       ├── gke
│       │   ├── kustomization.yaml
│       │   ├── patch-workload-identity.yaml
│       │   └── patch-zone-affinity.yaml
│       └── shared
│           ├── hpa.yaml
│           ├── kustomization.yaml
│           └── pdb.yaml
├── monitoring
│   ├── alerts
│   │   ├── latency.rules.yaml
│   │   ├── mesh.rules.yaml
│   │   └── saturation.rules.yaml
│   ├── dashboards
│   │   ├── api-gw-overview.json
│   │   ├── cluster-capacity.json
│   │   ├── cross-cloud-routing.json
│   │   ├── inventory-svc.json
│   │   ├── istio-control-plane.json
│   │   └── order-svc.json
│   └── recording-rules
│       ├── http.rules.yaml
│       └── slo.rules.yaml
├── scripts
│   ├── auth
│   │   ├── aks-login.sh
│   │   └── gke-login.sh
│   ├── load
│   │   ├── inventory_seed.py
│   │   └── order_storm.py
│   ├── pricing
│   │   └── monthly_floor.py
│   ├── traffic
│   │   ├── failover-check.sh
│   │   └── test-route.sh
│   └── validate
│       ├── check-cluster-versions.sh
│       ├── check-dns.sh
│       └── check-mesh-ports.sh
├── terraform
│   ├── aks
│   │   ├── iam.tf
│   │   ├── main.tf
│   │   ├── nsg.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── backend.tf
│   ├── dns
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── gke
│   │   ├── firewall.tf
│   │   ├── iam.tf
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   ├── variables.tf
│   └── versions.tf
└── tests
    ├── smoke
    │   ├── aks_health_test.go
    │   ├── gke_health_test.go
    │   └── traffic_shift_test.go
    └── unit
        ├── inventory_service_test.go
        ├── order_service_test.go
        └── router_test.go
```

## Known issues / TODOs
- I'm pinning Istio 1.29.1 for now because the install story, CNI behavior, and docs are aligned there across both clouds. I don't want to chase a newer minor until the mesh phase is in and stable.
- The Grafana dashboard JSON still needs cleanup. I have duplicate panel IDs in my scratch exports and too much copied legend text.
- I still need an idle-hours cost pass. Two always-on clusters plus mesh plus monitoring is fine for learning, but it's not a cheap baseline.

## Monthly cost estimate
I treated this as the always-on floor for dev, not a fully loaded bill.

| Item | Qty | Est. monthly |
| --- | --- | ---: |
| GKE `e2-standard-4` nodes | 2 | $195.68 |
| GKE cluster fee | 1 | $73.00 |
| AKS `Standard_D4s_v3` nodes | 2 | $280.32 |
| Total floor |  | $549.00 |

That number does **not** include disks, load balancers, Traffic Manager, Cloud DNS query volume, log retention, or cross-cloud egress. I also left the AKS control plane surcharge out of the floor number because the public pricing page didn't render a clean text value when I pulled notes for this repo, and I didn't want to fake precision.
