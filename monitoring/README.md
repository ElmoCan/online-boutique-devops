# Local Prometheus and Grafana

Installs the official `prometheus-community/kube-prometheus-stack` chart **93.1.0** into `monitoring`. The values pin one replica per component, 3-day Prometheus retention, and conservative resource requests and limits. Prometheus (5 GiB), Grafana (1 GiB), and Alertmanager (1 GiB) use OrbStack's `local-path` StorageClass.

The chart provides Prometheus, Grafana, Alertmanager, Prometheus Operator, node exporter, kube-state-metrics, and Kubernetes dashboards. Local overrides disable etcd, controller-manager, scheduler, and kube-proxy scraping because OrbStack's single-node k3s control plane does not expose those components as ordinary scrape targets. The API server, CoreDNS, kubelet/cAdvisor, node exporter, and kube-state-metrics remain monitored.

The chart's v0.95.1 Prometheus Operator and config-reloader images are published without ARM64 variants. On OrbStack's ARM64 node, run `./monitoring/pull-arm64-compat-images.sh` before Helm installation. It imports only these two pinned official images as AMD64 for OrbStack's emulation; the other stack images use their native ARM64 variants. This workaround is for local development only.

## Install

From the repository root, after adding the official Helm repository:

```sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
./monitoring/pull-arm64-compat-images.sh
kubectl apply -f monitoring/namespace.yaml
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 93.1.0 --namespace monitoring --values monitoring/values.yaml --wait --timeout 15m
kubectl apply -k monitoring/dashboards
kubectl rollout status deployment -n monitoring --timeout=5m
kubectl rollout status statefulset -n monitoring --timeout=5m
```

## Local Grafana access

```sh
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Open <http://localhost:3000>. The username is `admin`; the chart creates the password in a Kubernetes Secret rather than storing it in this repository. Retrieve it locally when needed with:

```sh
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 --decode; echo
```

The `Local Kubernetes Overview` dashboard is provisioned from `dashboards/local-kubernetes-overview.json`; the chart's default Kubernetes and node-exporter dashboards are enabled too. The custom dashboard covers node and pod CPU/memory, pod restarts, deployment availability, namespace usage, and container readiness. Open it at <http://localhost:3000/d/local-kubernetes-overview/local-kubernetes-overview>.

## Application metrics

The inspected Online Boutique source contains OpenTelemetry tracing instrumentation but no Prometheus client or `/metrics` handler. No application `ServiceMonitor` is added. Prometheus discovers 13 targets from the API server, CoreDNS, kubelet, node exporter, kube-state-metrics, and the monitoring stack. All targets report `up`. OrbStack's kubelet `/metrics/cadvisor` target responds, but it does not expose `container_cpu_usage_seconds_total` or `container_memory_working_set_bytes`; therefore pod and namespace actual-usage panels have no data on this local cluster. Node CPU/memory and kube-state metrics (restarts, readiness, deployment availability) are collected. These limitations are verified against Prometheus queries, rather than assumed from target health.

## Local limits

The OrbStack API reports 8 CPU and approximately 7.8 GiB allocatable memory. Existing application and system pods request about 1.37 CPU and 1.18 GiB. OrbStack has no Metrics API (`kubectl top` is unavailable). Prometheus reports the node at about 5% CPU and 43.5% memory used during the post-install check; pod-level usage is not exported by this kubelet/cAdvisor endpoint.
