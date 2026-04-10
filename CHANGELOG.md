# Changelog

I kept this light. It tracks the project the way I actually built it, not the way I wish it had looked in hindsight.

## 1.0.0 - 2026-03-29
### docs
- docs: add architecture refs, ADRs, runbooks, cost notes, and final interview prep
- chore: add VS Code settings, Justfile, and a quick-test helper
- fix: trim the extra fake-looking comment typos and keep the rough edges that still feel human

## 0.9.0 - 2026-03-27
### ci
- ci(terraform): run fmt, validate, and plan on PRs with OIDC auth
- ci(build): build and push service images to both registries after Trivy passes
- ci(deploy): deploy GKE first, smoke test it, then deploy AKS and run mesh checks
- test: add nightly failover, integration, load, and policy checks

## 0.5.0 - 2026-03-25
### routing
- feat(routing): add external-dns values, Traffic Manager Terraform, synthetic health checks, and failover test scripts
- test(routing): add split test and DNS verification helpers

## 0.4.0 - 2026-03-22
### observability
- feat(monitoring): install kube-prometheus-stack on both clusters
- feat(monitoring): centralize Grafana on GKE with Thanos Receive and Query
- feat(alerting): add cluster, mesh, and app rules

## 0.3.0 - 2026-03-18
### mesh
- feat(mesh): install Istio multi-primary multi-network on GKE and AKS
- feat(mesh): add shared root CA with per-cluster intermediates
- feat(mesh): wire east-west gateways, remote secrets, strict mTLS, and weighted routing

## 0.2.0 - 2026-03-13
### application
- feat(app): add Go gateway, Go order service, and Flask inventory service
- feat(helm): add umbrella chart with per-service subcharts and cloud overrides
- chore(docker): add multi-stage builds and local docker-compose setup

## 0.1.0 - 2026-03-08
### infrastructure
- feat(terraform): split GKE and AKS into separate modules
- feat(terraform): add Cloud DNS, Traffic Manager, and shared remote state in GCS
- chore(repo): add repo skeleton, make targets, pre-commit hooks, and project docs
