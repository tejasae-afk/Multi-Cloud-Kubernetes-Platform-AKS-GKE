# External routing notes

I kept the public edge boring on purpose. Azure Traffic Manager sits in front as the public weighted entrypoint, each cluster has its own public ingress hostname, and `external-dns` keeps those hostnames pointed at the right load balancers. I didn't try to bolt on a bigger edge stack because two clusters didn't justify it yet.

The split looks like this:

- `api.platform.example.com` -> CNAME -> `mc-k8s-edge.trafficmanager.net`
- `gke.api.platform.example.com` -> managed by `external-dns` in Cloud DNS
- `aks.api.platform.example.com` -> managed by `external-dns` in Azure DNS

Traffic Manager does weighted DNS answers between the two cluster edge names and probes `/healthz`. When one side stops answering, new DNS lookups stop getting that endpoint. Existing connections don't move because Traffic Manager is still DNS, not a proxy.

## Why I wired it this way

I wanted push-style DNS updates inside each cloud and a single public entrypoint outside both clouds. `external-dns` fits the first part. Traffic Manager fits the second. That let me keep per-cluster ownership local while still having one hostname for users.

I started with weighted routing because I wanted room for a soft rollout and a clean failback story. If I want stricter failover later, I can swap the profile to Priority without changing much on the cluster side.

## Public failover procedure

1. Verify both cluster edge hosts resolve and answer `/healthz`.
2. Verify the public host resolves through Traffic Manager.
3. Take one ingress path down on purpose.
4. Wait for Traffic Manager to stop handing out the failed endpoint.
5. Watch new requests land on the surviving cluster.
6. Bring the failed side back and wait for weighted answers to show up again.

In practice I usually see failover land in about 30 to 60 seconds. The monitor runs every 10 seconds, I tolerate three failures, and I keep DNS TTL at 30 seconds. Client-side caching can still stretch that a bit, so I don't treat 30 seconds like a promise.

## One thing I had to keep straight

Traffic Manager health probes and the user-facing hostname both have to line up with the Istio `Gateway` hosts. If I leave the gateway on `api.platform.local` and forget to add the public hostname, the probe can be healthy with a custom `Host` header while real browser traffic still gets a 404. I hit that once and wrote it down so I don't repeat it.

## What I actually apply

- `routing/external-dns/values-gke.yaml`
- `routing/external-dns/values-aks.yaml`
- `routing/external-dns/clusterrole.yaml`
- `routing/traffic-manager/`
- `routing/health-checks/connectivity-check.yaml`

The helper scripts are the part I keep using after day one:

- `routing/scripts/dns-verify.sh`
- `routing/scripts/traffic-split-test.sh`
- `routing/scripts/test-failover.sh`
- `routing/health-checks/synthetic-monitor.sh`
