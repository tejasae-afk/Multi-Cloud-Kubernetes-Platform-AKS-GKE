# Monthly cost estimate

I priced this as the always-on floor for the repo as it sits today: two 4 vCPU clusters, the mesh up full time, central monitoring on GKE, and public ingress on both clouds. I rounded the noisy stuff because DNS queries, load balancer data, and cross-cloud traffic swing a lot depending on how hard I beat on it that month.

## Assumptions

- 730 hours in a month
- GKE nodes on-demand in `us-central1`
- AKS nodes on-demand in `eastus`
- AKS stays on the Standard tier because that's how I declared it in Terraform
- GKE cluster management fee is offset by the current zonal free-tier credit
- light to moderate public traffic, not a real customer workload
- about 250 GB/month of cross-cloud traffic between app calls and metric shipping

## Rough breakdown

| Item | Qty | Rate | Est. monthly |
| --- | ---: | ---: | ---: |
| GKE `e2-standard-4` worker nodes | 2 | $0.1340/hour | $195.64 |
| AKS `Standard_D4s_v3` worker nodes | 2 | $0.1920/hour | $280.32 |
| AKS Standard tier control plane | 1 | $0.10/hour | $73.00 |
| GKE cluster management fee | 1 | covered by zonal free tier | $0.00 |
| GKE boot disks (`2 x 100GiB pd-balanced`) | 2 | rough | $20.00 |
| AKS OS disks (`2 x 128GiB Premium SSD`) | 2 | rough | $39.00 |
| Public load balancers (ingress + east-west on both clouds) | 4 | rough | $38.00 |
| DNS + Traffic Manager | 1 | rough | $7.00 |
| Cross-cloud egress | ~250 GB | rough | $25.00 |
| Monitoring PVC and odds and ends | 1 | rough | $12.00 |
| **Total** |  |  | **$689.96** |

I call it **about $690/month** because the variable pieces move around and I don't want to pretend the cents mean anything.

## What makes the number move

### Cross-cloud traffic

This is the sneaky one. If I hammer the mesh with load tests or let remote service calls dominate, the egress line climbs first.

### AKS pricing tier

If I dropped AKS to the Free tier for a pure dev setup, I'd shave roughly `$73/month` off the floor. I kept Standard in the Terraform because the uptime SLA felt more honest for how I talk about the project.

### Idle hours

This stack is up 24x7 in the estimate. If I scale it down at night and on weekdays when I'm not using it, the bill gets a lot friendlier.
