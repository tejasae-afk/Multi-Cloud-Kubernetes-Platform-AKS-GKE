# helm

I kept the app chart as one umbrella release because I don't want three separate installs per cluster while I'm still moving fast. The subcharts stay in-tree under `charts/`, so I can change app code and chart wiring in one repo without a side trip to another chart registry.

I install it on GKE with `helm upgrade --install mc-k8s-app ./helm -n platform --create-namespace -f helm/values-gke.yaml`.
I install it on AKS with `helm upgrade --install mc-k8s-app ./helm -n platform --create-namespace -f helm/values-aks.yaml`.
