# multi-cloud-k8s-platform

## What this is
I built this as a platform project that let me work through the pieces I actually care about: infra, traffic, identity, observability, and failure recovery. It runs the same small app stack on GKE and AKS, wires the clusters together with Istio, and keeps metrics in one Grafana on the GKE side.

## Architecture at a glance
```text
                                   +----------------------+
                                   | Cloud DNS            |
                                   | Azure TrafficManager |
                                   +----------+-----------+
                                              |
                                     public traffic + health
                                              |
                +-----------------------------+-----------------------------+
                |                                                           |
                v                                                           v
      +---------------------+                                     +---------------------+
      | GKE / us-central1   |                                     | AKS / East US       |
      | network1 / cluster1 |                                     | network2 / cluster2 |
      +----------+----------+                                     +----------+----------+
                 |                                                           |
     +-----------+-----------+                                   +-----------+-----------+
     | Istio ingress gateway |                                   | Istio ingress gateway |
     +-----------+-----------+                                   +-----------+-----------+
                 |                                                           |
         +-------+-------+                                           +-------+-------+
         | api-gateway   |                                           | api-gateway   |
         +-------+-------+                                           +-------+-------+
                 |                                                           |
         +-------+-------+                                           +-------+-------+
         | order-service | <==== east-west mTLS over 15443 =====>    | order-service |
         +-------+-------+                                           +-------+-------+
                 |                                                           |
         +-------+-------+                                           +-------+-------+
         | inventory-svc |                                           | inventory-svc |
         +---------------+                                           +---------------+

                 Prometheus                                               Prometheus
                      |                                                        |
                      |                              remote_write               |
                      +-----------------------+<-------------------------------+
                                              |
                                       Thanos Receive
                                              |
                                         Thanos Query
                                              |
                                           Grafana
```

## What works today
- Terraform brings up the cloud side on GKE and AKS
- Helm deploys the app stack to both clusters
- Istio runs multi-primary multi-network with east-west gateways
- Cross-cluster calls work through the mesh
- Azure Traffic Manager handles public weighted routing and failover
- Grafana on GKE shows metrics from both clusters
- GitHub Actions builds, scans, deploys, and runs checks with OIDC auth

## Why I built it this way
I wanted one repo that forced me to deal with tradeoffs instead of hiding them. GKE and AKS do not look the same once you get past the cluster marketing page, so I kept them in separate Terraform modules. The mesh is multi-network because pod IPs stop mattering the second traffic crosses clouds. Monitoring is push-based from AKS to GKE because that plays nicer with NAT and public edges than a pull-only setup.

I also kept failover layered. Public traffic moves at DNS, which is slower but simple. Inside the mesh, outlier detection reacts faster once requests are already moving. That split made the whole platform easier to reason about.

## Main pieces
| Area | Version / shape | Notes |
| --- | --- | --- |
| Terraform | 1.14.8 | Root module with separate `gke/`, `aks/`, and `dns/` modules |
| GCP provider | `hashicorp/google` 7.25.0 | GKE, VPC, firewall, Cloud DNS |
| Azure provider | `hashicorp/azurerm` 4.66.0 | AKS, VNet, NSG, Traffic Manager |
| Kubernetes | GKE Regular channel, AKS current GA | I stopped hard-pinning 1.29 once GKE aged past support |
| Istio | 1.29.1 | Multi-primary, multi-network with east-west gateways |
| Helm | 4.1.3 | App chart, monitoring installs, external-dns |
| Go | 1.22.x | `api-gateway` and `order-service` |
| Python | 3.12.x / Flask 3.1.x | `inventory-service` |
| Monitoring | kube-prometheus-stack 82.10.3, Thanos Receive + Query, Grafana 10.7.0 chart | One Grafana view over both clusters |
| CI | GitHub Actions + OIDC | No static cloud keys in GitHub |

## Repo map
- `terraform/` builds the cloud side
- `app/` has the three services and local `docker-compose`
- `helm/` installs the app stack on both clusters
- `mesh/` sets up multi-cluster Istio and traffic policy
- `monitoring/` handles Prometheus, Thanos, Grafana, and alerts
- `routing/` handles external-dns, Traffic Manager, and failover checks
- `tests/` holds smoke, integration, load, and policy checks
- `docs/` is where I kept the reference docs, ADRs, runbooks, notes, and interview prep

## Full project tree
```text
.
├── .github
│   ├── actions
│   │   └── setup-kubeconfig
│   │       └── action.yml
│   ├── workflows
│   │   ├── build-push.yml
│   │   ├── deploy.yml
│   │   ├── mesh-verify.yml
│   │   ├── nightly-tests.yml
│   │   ├── terraform-apply.yml
│   │   └── terraform-plan.yml
│   ├── CODEOWNERS
│   └── PULL_REQUEST_TEMPLATE.md
├── .vscode
│   └── settings.json
├── app
│   ├── api-gateway
│   │   ├── Dockerfile
│   │   ├── go.mod
│   │   ├── main.go
│   │   └── README.md
│   ├── inventory-service
│   │   ├── __init__.py
│   │   ├── app.py
│   │   ├── Dockerfile
│   │   ├── gunicorn.conf.py
│   │   ├── README.md
│   │   └── requirements.txt
│   ├── order-service
│   │   ├── Dockerfile
│   │   ├── go.mod
│   │   ├── main.go
│   │   └── README.md
│   ├── docker-compose.yml
│   └── README.md
├── costs
│   ├── estimate.md
│   └── optimization-notes.md
├── docs
│   ├── adr
│   │   ├── 001-multi-cloud-strategy.md
│   │   ├── 002-service-mesh-selection.md
│   │   ├── 003-monitoring-architecture.md
│   │   ├── 004-traffic-routing.md
│   │   └── 005-cicd-strategy.md
│   ├── architecture
│   │   ├── disaster-recovery.md
│   │   ├── mesh-architecture.md
│   │   ├── networking.md
│   │   ├── observability.md
│   │   └── overview.md
│   ├── images
│   │   └── README.md
│   ├── runbooks
│   │   ├── cluster-failover.md
│   │   ├── incident-response.md
│   │   ├── mesh-troubleshooting.md
│   │   └── scaling.md
│   ├── git-history.txt
│   ├── interview-prep.md
│   └── NOTES.md
├── helm
│   ├── charts
│   │   ├── api-gateway
│   │   │   ├── templates
│   │   │   │   ├── _helpers.tpl
│   │   │   │   ├── configmap.yaml
│   │   │   │   ├── deployment.yaml
│   │   │   │   ├── hpa.yaml
│   │   │   │   ├── pdb.yaml
│   │   │   │   ├── service.yaml
│   │   │   │   └── serviceaccount.yaml
│   │   │   ├── Chart.yaml
│   │   │   └── values.yaml
│   │   ├── inventory-service
│   │   │   ├── templates
│   │   │   │   ├── _helpers.tpl
│   │   │   │   ├── configmap.yaml
│   │   │   │   ├── deployment.yaml
│   │   │   │   ├── hpa.yaml
│   │   │   │   ├── pdb.yaml
│   │   │   │   ├── service.yaml
│   │   │   │   └── serviceaccount.yaml
│   │   │   ├── Chart.yaml
│   │   │   └── values.yaml
│   │   └── order-service
│   │       ├── templates
│   │       │   ├── _helpers.tpl
│   │       │   ├── configmap.yaml
│   │       │   ├── deployment.yaml
│   │       │   ├── hpa.yaml
│   │       │   ├── pdb.yaml
│   │       │   ├── service.yaml
│   │       │   └── serviceaccount.yaml
│   │       ├── Chart.yaml
│   │       └── values.yaml
│   ├── Chart.yaml
│   ├── README.md
│   ├── values-aks.yaml
│   ├── values-gke.yaml
│   └── values.yaml
├── mesh
│   ├── certs
│   │   ├── output
│   │   │   └── .gitkeep
│   │   ├── .gitignore
│   │   ├── .gitkeep
│   │   └── generate-certs.sh
│   ├── istio
│   │   ├── east-west-gw-aks.yaml
│   │   ├── east-west-gw-gke.yaml
│   │   ├── expose-services-aks.yaml
│   │   ├── expose-services-gke.yaml
│   │   ├── install-aks.yaml
│   │   ├── install-gke.yaml
│   │   └── peer-authentication.yaml
│   ├── scripts
│   │   ├── debug-mesh.sh
│   │   ├── setup-mesh.sh
│   │   └── verify-mesh.sh
│   ├── traffic
│   │   ├── canary-routing.yaml
│   │   ├── destination-rule.yaml
│   │   ├── gateway.yaml
│   │   └── virtual-service.yaml
│   └── README.md
├── monitoring
│   ├── alerts
│   │   ├── app-alerts.yaml
│   │   ├── cluster-alerts.yaml
│   │   └── mesh-alerts.yaml
│   ├── grafana
│   │   ├── dashboards
│   │   │   ├── app-metrics.json
│   │   │   ├── infrastructure.json
│   │   │   ├── istio-mesh.json
│   │   │   └── multi-cluster-overview.json
│   │   ├── datasources.yaml
│   │   └── values.yaml
│   ├── prometheus
│   │   ├── alerting-rules.yaml
│   │   ├── servicemonitor-app.yaml
│   │   ├── thanos-receive.yaml
│   │   ├── values-aks.yaml
│   │   └── values-gke.yaml
│   ├── scripts
│   │   ├── generate-traffic.sh
│   │   ├── install-monitoring.sh
│   │   └── port-forward-grafana.sh
│   └── README.md
├── routing
│   ├── external-dns
│   │   ├── clusterrole.yaml
│   │   ├── values-aks.yaml
│   │   └── values-gke.yaml
│   ├── health-checks
│   │   ├── connectivity-check.yaml
│   │   └── synthetic-monitor.sh
│   ├── scripts
│   │   ├── dns-verify.sh
│   │   ├── test-failover.sh
│   │   └── traffic-split-test.sh
│   ├── traffic-manager
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   └── README.md
├── scripts
│   └── quick-test.sh
├── terraform
│   ├── aks
│   │   ├── iam.tf
│   │   ├── main.tf
│   │   ├── nsg.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
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
│   ├── backend.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   ├── variables.tf
│   └── versions.tf
├── tests
│   ├── integration
│   │   ├── test_cross_cluster.sh
│   │   ├── test_failover.sh
│   │   └── test_mesh_routing.sh
│   ├── load
│   │   ├── load-test.js
│   │   └── run-load-test.sh
│   ├── policy
│   │   ├── opa-policies
│   │   │   ├── no-privileged.rego
│   │   │   ├── require-labels.rego
│   │   │   └── resource-limits.rego
│   │   └── conftest.yaml
│   └── smoke
│       ├── test_endpoints.sh
│       └── test_metrics.sh
├── .editorconfig
├── .gitignore
├── .pre-commit-config.yaml
├── CHANGELOG.md
├── Justfile
├── LICENSE
├── Makefile
└── README.md
```

## Quick start
I don't use this README like a tutorial. This is the shortest path I actually take.

1. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars`.
2. Fill in the cloud, registry, and DNS values.
3. Run `make init TF_BACKEND_BUCKET=<bucket> TF_BACKEND_PREFIX=multi-cloud-k8s/dev`.
4. Run `make plan-gke` and `make plan-aks`.
5. Run `make apply-all`.
6. Build and push the images, then deploy the Helm chart to both clusters.
7. Run `./mesh/scripts/setup-mesh.sh --gke-context <gke-context> --aks-context <aks-context>`.
8. Run `./monitoring/scripts/install-monitoring.sh --gke-context <gke-context> --aks-context <aks-context>`.
9. Run `./routing/scripts/dns-verify.sh`, `./routing/scripts/test-failover.sh`, and `./scripts/quick-test.sh`.

## Costs
The always-on lab shape lands around **$675/month** with on-demand nodes, public edges, central monitoring, and both clusters up all the time. Most of the bill is still just the node pools. The detail is in `costs/estimate.md`.

## Known gaps
- I propagate tracing headers, but I never added Jaeger or Tempo, so I still don't store spans anywhere.
- The dashboards work fine, but I would still clean up some JSON and panel layout if I kept this repo alive longer.
- The platform is always on right now. Night scale-down and cheaper node choices are still on the list if I care more about cost than convenience.

## Docs I keep open most often
- `docs/architecture/overview.md`
- `docs/architecture/mesh-architecture.md`
- `docs/architecture/observability.md`
- `docs/runbooks/cluster-failover.md`
- `docs/runbooks/mesh-troubleshooting.md`
- `docs/interview-prep.md`
- `docs/NOTES.md`

## Release markers
- `0.1.0` infra
- `0.2.0` app + Helm
- `0.3.0` mesh
- `0.4.0` monitoring
- `0.5.0` routing
- `0.9.0` CI and tests
- `1.0.0` docs and polish
