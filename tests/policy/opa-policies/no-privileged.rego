package main

import rego.v1

workload_kinds := {
  "Pod",
  "Deployment",
  "StatefulSet",
  "DaemonSet",
  "Job",
  "CronJob"
}

is_workload if workload_kinds[input.kind]

pod_metadata(obj) := metadata if {
  obj.kind == "Pod"
  metadata := obj.metadata
}

pod_metadata(obj) := metadata if {
  obj.kind in {"Deployment", "StatefulSet", "DaemonSet", "Job"}
  metadata := obj.spec.template.metadata
}

pod_metadata(obj) := metadata if {
  obj.kind == "CronJob"
  metadata := obj.spec.jobTemplate.spec.template.metadata
}

pod_spec(obj) := spec if {
  obj.kind == "Pod"
  spec := obj.spec
}

pod_spec(obj) := spec if {
  obj.kind in {"Deployment", "StatefulSet", "DaemonSet", "Job"}
  spec := obj.spec.template.spec
}

pod_spec(obj) := spec if {
  obj.kind == "CronJob"
  spec := obj.spec.jobTemplate.spec.template.spec
}

containers(obj)[container] if {
  spec := pod_spec(obj)
  some container in object.get(spec, "containers", [])
}

containers(obj)[container] if {
  spec := pod_spec(obj)
  some container in object.get(spec, "initContainers", [])
}

object_name(obj) := name if {
  name := obj.metadata.name
}

deny contains msg if {
  is_workload
  some container in containers(input)
  security_context := object.get(container, "securityContext", {})
  object.get(security_context, "privileged", false)
  msg := sprintf("%s/%s has privileged container %s", [input.kind, object_name(input), container.name])
}
