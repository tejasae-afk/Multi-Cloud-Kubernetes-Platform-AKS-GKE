# monitoring

I wanted one place to look when traffic started bouncing between GKE and AKS, so I parked the central view in GKE and pushed AKS metrics into it. Prometheus still runs in both clusters. I just stopped pretending a pull model was worth the network pain for two clusters that live behind different cloud load balancers.

## Layout

- GKE runs kube-prometheus-stack, a Thanos sidecar on Prometheus, Thanos Receive, Thanos Query, and Grafana.
- AKS runs kube-prometheus-stack and remote writes into the GKE Thanos Receive service.
- Grafana talks to two datasources:
  - `prometheus` for the local GKE Prometheus
  - `thanos` for the aggregated view across both clusters

I kept the monitoring namespace out of sidecar injection on purpose. Once Istio got into this path, scrape timing and bootstrap noise got harder to reason about than the app traffic I was trying to watch.

## Install notes

I install this stack with `scripts/install-monitoring.sh`. The script does a few annoying things for me:

1. creates the `monitoring` namespace on both clusters
2. installs kube-prometheus-stack on GKE
3. deploys Thanos Receive and Thanos Query on GKE
4. waits for the GKE receive load balancer address
5. creates the basic auth secrets on both sides
6. patches the AKS `remote_write` target with the live GKE address
7. installs kube-prometheus-stack on AKS
8. applies ServiceMonitors, recording rules, and alerts
9. loads Grafana datasources and dashboard ConfigMaps
10. installs Grafana on GKE

I left Grafana out of kube-prometheus-stack because I only wanted one Grafana release, one set of dashboards, and one place to log in.

## Grafana access

I kept access boring:

```bash
./monitoring/scripts/port-forward-grafana.sh
```

That forwards `http://127.0.0.1:3000` to the Grafana service in GKE.

Default lab creds:

- user: `admin`
- password: `admin`

## Datasource config

The datasource ConfigMap lives in `grafana/datasources.yaml`.

- `prometheus` points at `http://mc-kps-gke-prometheus.monitoring.svc.cluster.local:9090`
- `thanos` points at `http://thanos-query.monitoring.svc.cluster.local:9090`

The dashboards use `thanos` by default because I wanted the `cluster` dropdown to filter both GKE and AKS without keeping two copies of every panel around.

## What bit me

- I forgot that Thanos Receive is not the thing Grafana should query. Receive speaks the write path and StoreAPI, so I needed a tiny Query deployment in front of it.
- I had remote write auth half-wired once. Prometheus in AKS just kept retrying and the queue grew until I fixed the secret names on both ends.
- I loaded dashboards before I added external labels on both Prometheus servers. The `cluster` variable came up empty and every panel looked broken.
- I let Istio inject into `monitoring` one time. Nothing exploded, but scrape timings drifted enough that I ripped that back out fast.

## Files I touch the most

- `prometheus/values-gke.yaml`
- `prometheus/values-aks.yaml`
- `prometheus/thanos-receive.yaml`
- `grafana/values.yaml`
- `grafana/datasources.yaml`
- `scripts/install-monitoring.sh`
- `scripts/generate-traffic.sh`

## Quick checks after install

```bash
kubectl --context "$GKE_CONTEXT" -n monitoring get pods
kubectl --context "$AKS_CONTEXT" -n monitoring get pods
kubectl --context "$GKE_CONTEXT" -n monitoring get svc thanos-receive-public
kubectl --context "$AKS_CONTEXT" -n monitoring get secret thanos-remote-write-auth
kubectl --context "$GKE_CONTEXT" -n monitoring logs deploy/thanos-query --tail=50
kubectl --context "$GKE_CONTEXT" -n monitoring logs deploy/thanos-receive -c thanos --tail=50
```

If the dashboards are flat, I run `scripts/generate-traffic.sh` and then check the `thanos` datasource first. That catches most bad wiring in a couple of minutes.
