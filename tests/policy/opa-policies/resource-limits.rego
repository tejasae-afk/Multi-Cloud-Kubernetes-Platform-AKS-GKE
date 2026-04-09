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
  not object.get(object.get(container, "resources", {}), "limits", {}).cpu
  msg := sprintf("%s/%s container %s is missing a cpu limit", [input.kind, input.metadata.name, container.name])
}

deny contains msg if {
  spec := pod_spec
  container := spec.containers[_]
  not object.get(object.get(container, "resources", {}), "limits", {}).memory
  msg := sprintf("%s/%s container %s is missing a memory limit", [input.kind, input.metadata.name, container.name])
}
