# Cost optimization notes

This is the list I keep when the cloud bill starts feeling a little too real.

## Cheapest wins first

- move one or both node pools to spot / preemptible for non-critical dev hours
- scale both clusters down at night
- keep Grafana and central monitoring up, but shrink the worker floor when I'm not actively testing failover
- trim cross-cloud traffic by preferring local service endpoints when I'm not testing remote routing

## Ideas I still want to try

### Reserved or committed capacity

If I kept this running for months, I'd look at one-year commitments for the node sizes I already use. The floor is steady enough that it would probably pay off.

### Smaller monitoring footprint

Prometheus, Thanos Receive, and Grafana all sit on the GKE side today. I could squeeze that harder with a dedicated smaller node pool or shorter retention.

### Smarter traffic weighting

Right now I keep the platform split alive because I want both sides exercised. For pure cost control, I could bias the public edge harder toward one cloud and keep the other side warm but lighter.

### Private connectivity later

Private cross-cloud networking would cost money too, but it might be cheaper than letting a lot of service-to-service traffic ride public egress forever.

## Stuff I won't do yet

- scale to zero for the whole thing. I still want the platform available when I sit down at night.
- rip out the second cluster. That would beat the whole point of the project.
