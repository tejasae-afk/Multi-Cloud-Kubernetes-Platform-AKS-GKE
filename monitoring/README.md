# Monitoring

I kept monitoring centered on GKE. That was an arbitrary pick, but once I made it the rest got simpler: GKE runs the local Prometheus stack, Thanos Receive, Thanos Query, and Grafana. AKS keeps its own Prometheus for local scraping and pushes a trimmed metric set back to GKE.

I didn't bother with federation. Pulling across clouds got annoying fast once NAT, separate load balancers, and scrape auth were in the mix. Remote write let AKS push outward and kept the connection pattern boring.

## What lives where

- **GKE**: kube-prometheus-stack, Thanos sidecar on Prometheus, Thanos Receive, Thanos Query, Grafana
- **AKS**: kube-prometheus-stack with `remoteWrite` back to GKE
- **Both clusters**: ServiceMonitors for `api-gateway`, `order-service`, and `inventory-service`, plus the same alert rules

## Install notes

I install the monitoring stack in this order:

1. GKE kube-prometheus-stack
2. GKE Thanos Receive and Query
3. AKS kube-prometheus-stack with remote write pointed at GKE
4. Grafana on GKE
5. Dashboard and datasource ConfigMaps

That install order matters because I want the GKE receive endpoint up before AKS starts shipping samples.

```bash
./monitoring/scripts/install-monitoring.sh \
  --gke-context gke_us_central1_mc-k8s-gke-cluster \
  --aks-context mc-k8s-aks-admin \
  --monitoring-namespace monitoring \
  --app-namespace platform
```

## Grafana access

```bash
./monitoring/scripts/port-forward-grafana.sh \
  --context gke_us_central1_mc-k8s-gke-cluster \
  --namespace monitoring
```

That prints the URL plus the current admin username and password from the cluster secret.

## Datasources

I keep two datasources in Grafana:

- `uid: prometheus` points at the local GKE Prometheus service. I mostly keep it around when I want to compare raw local scrape data.
- `uid: thanos` points at Thanos Query. That's the one the dashboards use for the cross-cluster view because it can see GKE through the sidecar and AKS through Thanos Receive.

## A couple of choices I made on purpose

- I started with just Thanos Receive. That wasn't enough. Grafana still needs a PromQL API, so `prometheus/thanos-receive.yaml` also brings up a tiny Thanos Query deployment.
- I only remote-write the metric families I care about from AKS. Shipping every single series back across clouds got noisy and more expensive than I wanted.
- I kept object storage, compactor, and store gateway out of this phase. Two clusters didn't justify that much machinery yet.
- The receive endpoint uses a shared header token behind a tiny nginx proxy. That's good enough for a dev setup. If I keep this running longer, I'd move it behind private connectivity or a real auth layer.

## Files I keep touching

- `prometheus/values-gke.yaml` and `prometheus/values-aks.yaml` for scrape jobs, rule selectors, and remote write
- `prometheus/thanos-receive.yaml` for Receive, Query, the hashring, and the receive auth proxy
- `grafana/dashboards/*.json` for the four dashboards I actually stare at
- `scripts/generate-traffic.sh` when I want the graphs to look alive instead of flat
