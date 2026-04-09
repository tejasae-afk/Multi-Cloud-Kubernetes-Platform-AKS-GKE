package main

import rego.v1

pod_spec := spec if {
  input.kind == "Pod"
  spec := input.spec
} else := spec if {
  spec := object.get(object.get(input.spec, "template", {}), "spec", {})
}

deny contains msg if {
  spec := pod_spec
  container := spec.containers[_]
  object.get(object.get(container, "securityContext", {}), "privileged", false)
  msg := sprintf("%s/%s has a privileged container named %s", [input.kind, input.metadata.name, container.name])
}

deny contains msg if {
  spec := pod_spec
  container := object.get(spec, "initContainers", [])[_]
  object.get(object.get(container, "securityContext", {}), "privileged", false)
  msg := sprintf("%s/%s has a privileged init container named %s", [input.kind, input.metadata.name, container.name])
}
