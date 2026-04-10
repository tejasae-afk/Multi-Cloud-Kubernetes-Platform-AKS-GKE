# switched to just halfway through, kept both

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

repo_root := justfile_directory()

default:
  @just --list

init tf_backend_bucket tf_backend_prefix="multi-cloud-k8s/dev":
  cd {{ repo_root }} && make init TF_BACKEND_BUCKET={{ tf_backend_bucket }} TF_BACKEND_PREFIX={{ tf_backend_prefix }}

plan-gke:
  cd {{ repo_root }} && make plan-gke

plan-aks:
  cd {{ repo_root }} && make plan-aks

apply-all:
  cd {{ repo_root }} && make apply-all

mesh gke_context aks_context:
  cd {{ repo_root }} && ./mesh/scripts/setup-mesh.sh --context-gke {{ gke_context }} --context-aks {{ aks_context }}

monitoring gke_context aks_context:
  cd {{ repo_root }} && ./monitoring/scripts/install-monitoring.sh --gke-context {{ gke_context }} --aks-context {{ aks_context }}

quick-test:
  cd {{ repo_root }} && ./scripts/quick-test.sh
