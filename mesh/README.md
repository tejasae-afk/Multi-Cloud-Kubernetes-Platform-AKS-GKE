# Cross-cloud mesh notes

I started this phase thinking I could treat GKE and AKS like one big flat cluster. That was wrong fast. Pod IPs don't cross cloud boundaries cleanly here, so I switched to Istio multi-primary on different networks and pushed all cross-cluster traffic through east-west gateways on 15443.

I kept the trust model boring on purpose: one offline root CA, one intermediate per cluster, both mounted into `istiod` as `cacerts`. I didn't pull cert-manager into this part because I wanted fewer moving pieces while I was still figuring out discovery and gateway reachability.

The traffic policy files in `mesh/traffic/` assume the app is running in the `platform` namespace and that both clusters share namespace sameness for `api-gateway`, `order-service`, and `inventory-service`. The weighted route and the header override use the built-in `topology.istio.io/cluster` label, so I can steer traffic at the cluster layer without changing the app chart.

I pinned this repo to Istio `1.29.1`. The awkward bit is that my clusters are still on Kubernetes `1.29.x`, so I treat this as a lab build until I move both clouds forward. It works for what I want, but I wouldn't leave that version skew sitting around forever.

## Topology I stuck with

- Control plane shape: multi-primary
- Network shape: multi-network
- Trust model: shared root CA, one intermediate CA per cluster
- Discovery: remote secrets in both directions
- Cross-cluster path: east-west gateways only
- External entry: standard `istio-ingressgateway` from the default profile

## What I learned

- Single-network multi-primary looked cleaner, but it assumes flat pod routing. GKE and AKS don't give me that here, so it was the wrong shape.
- Namespace sameness matters more than most blog posts make it sound. If the namespace or service names drift, the whole cross-cluster story gets ugly.
- Remote secrets are simple once both control planes are stable. Before that, they just waste time and send me into `timeout` rabbit holes.
- The east-west gateway is not a cute add-on. In a cross-cloud setup like this, it's the path.
- I kept `REGISTRY_ONLY` turned on because I wanted accidental egress to fail loud instead of getting masked during tests.

## Things that broke

1. **AKS east-west gateway never got to a usable state**

   My first pass on AKS exposed the east-west gateway as a plain `LoadBalancer` service with no Azure-specific annotations. I sat there staring at a service that never behaved right. I fixed it by forcing TCP health probes on the east-west ports, then the gateway finally came up the way I expected.

2. **I turned on STRICT mTLS too early**

   I got impatient and applied mesh-wide STRICT before both east-west gateways had addresses and before remote secrets were synced. That gave me flaky readiness and a pile of handshake noise in the proxy logs. The fix was boring: install, wait, exchange secrets, verify discovery, then flip STRICT.

3. **I forgot the network label once**

   I had `istiod` up in both clusters and still only saw local endpoints. The miss was the `topology.istio.io/network` label on `istio-system`. Once I labeled both namespaces correctly and reinstalled the east-west gateways, remote endpoints started showing up.

4. **I almost put a Layer 7 load balancer in the middle**

   That would've been a bad call. The east-west path needs passthrough TLS on `15443`, and once a Layer 7 load balancer starts terminating traffic the whole cross-network story falls apart.

## How I set it up

1. Generate the root and intermediate certs with `mesh/certs/generate-certs.sh`.
2. Make sure both kube contexts exist and point to the right clusters.
3. Run `mesh/scripts/setup-mesh.sh`.
4. Apply `mesh/traffic/gateway.yaml` and `mesh/traffic/destination-rule.yaml`.
5. Apply either `mesh/traffic/virtual-service.yaml` for the normal 70/30 split or `mesh/traffic/canary-routing.yaml` when I want the `x-route-to: aks` header override.

I don't keep `virtual-service.yaml` and `canary-routing.yaml` live at the same time. They use the same `VirtualService` name on purpose so one replaces the other.

## Debug commands I kept running

```bash
istioctl remote-clusters --context "$CTX_GKE"
istioctl remote-clusters --context "$CTX_AKS"

istioctl proxy-status --context "$CTX_GKE"
istioctl proxy-status --context "$CTX_AKS"

kubectl --context "$CTX_GKE" get svc -n istio-system istio-eastwestgateway -o wide
kubectl --context "$CTX_AKS" get svc -n istio-system istio-eastwestgateway -o wide

kubectl --context "$CTX_GKE" logs -n istio-system deploy/istiod --tail=200
kubectl --context "$CTX_AKS" logs -n istio-system deploy/istiod --tail=200

kubectl --context "$CTX_AKS" describe svc -n istio-system istio-eastwestgateway

istioctl pc endpoints deploy/api-gateway -n platform \
  --context "$CTX_GKE" \
  --cluster 'outbound|8081||order-service.platform.svc.cluster.local'

istioctl analyze -A --context "$CTX_GKE"
istioctl analyze -A --context "$CTX_AKS"
```

## Files I actually touch most

- `mesh/scripts/setup-mesh.sh` when I need a clean install or a resumed run
- `mesh/scripts/verify-mesh.sh` when discovery looks weird
- `mesh/scripts/debug-mesh.sh` when I want a dump I can diff later
- `mesh/traffic/canary-routing.yaml` when I want to force traffic to AKS without touching app code
