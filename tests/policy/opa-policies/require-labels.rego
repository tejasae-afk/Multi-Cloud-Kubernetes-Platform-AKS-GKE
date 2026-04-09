package main

import rego.v1

workload_labels := labels if {
  input.kind == "Pod"
  labels := object.get(input.metadata, "labels", {})
} else := labels if {
  labels := object.get(object.get(object.get(input.spec, "template", {}), "metadata", {}), "labels", {})
}

deny contains msg if {
  labels := workload_labels
  not labels.app
  msg := sprintf("%s/%s is missing the app label", [input.kind, input.metadata.name])
}

deny contains msg if {
  labels := workload_labels
  not labels.version
  msg := sprintf("%s/%s is missing the version label", [input.kind, input.metadata.name])
}
