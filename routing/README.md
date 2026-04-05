# Routing

This is the part that made the platform feel like more than two disconnected clusters. Each cluster owns its own public hostname, Azure Traffic Manager sits in front of both, and external-dns keeps the DNS records current from inside the clusters.

I picked DNS-based routing on purpose. The app already had a working Istio mesh for east-west traffic, but public entry still needed something simple that could survive one cluster going away without adding another global proxy tier.

## How it works

- `api.platform.haleops.net` is a public CNAME that points at the Azure Traffic Manager profile FQDN.
- Traffic Manager answers with either the GKE or AKS public hostname based on weights and health.
- `gke-api.platform.haleops.net` is owned by the GKE side and written by external-dns into Cloud DNS.
- `aks-api.platform.haleops.net` is owned by the AKS side and written by external-dns into Azure DNS.
- Both Istio ingress gateways expose `/healthz`, so Traffic Manager can make routing calls without guessing.

I kept the weights at 70 for GKE and 30 for AKS. GKE is where the central monitoring stack lives, so giving it the bigger share kept the cross-cloud write path a little quieter during normal traffic.

## Failover procedure

1. Verify both cluster-specific hosts answer on `/healthz`.
2. Verify the shared host returns a mix of GKE and AKS over a small sample.
3. Scale the GKE ingress gateway to zero replicas.
4. Wait for Traffic Manager to mark the GKE endpoint unhealthy and stop returning it.
5. Keep probing the shared hostname until traffic lands on AKS only.
6. Scale GKE back up and wait for the weighted mix to come back.

With a 30 second TTL and fast health probes, I usually saw the switchover finish in roughly 30 to 60 seconds. Cached DNS answers can drag that out a little on some clients, so the scripts retry instead of expecting a single clean cutover.

## external-dns notes

I kept one external-dns release per cluster and made it watch `service`, `istio-gateway`, and `istio-virtualservice` sources. The Istio sources matter here because the hostnames live with the mesh ingress config, not just raw Services.

GKE uses Workload Identity through a Kubernetes service account annotation. AKS uses Azure Workload Identity plus a mounted `azure.json` secret because the Azure provider still expects that file path.

The extra ClusterRole in `external-dns/clusterrole.yaml` is there because I hit permission errors the first time I turned on the Istio sources and forgot that the default chart RBAC didn't know about those CRDs.

## What I watch during cutovers

- `dig api.platform.haleops.net`
- `curl -I https://api.platform.haleops.net/healthz`
- `kubectl --context gke -n istio-system get svc istio-ingressgateway`
- `kubectl --context aks -n istio-system get svc istio-ingressgateway`
- `./routing/scripts/traffic-split-test.sh`
- `./routing/scripts/test-failover.sh`

## File map

- `external-dns/values-gke.yaml` sets the Cloud DNS side.
- `external-dns/values-aks.yaml` sets the Azure DNS side.
- `traffic-manager/` holds the Terraform for the public weighted profile.
- `health-checks/` has the in-cluster and outside-in probes.
- `scripts/` is the stuff I kept re-running while this was flaky.
