# AWS EKS monitoring deployment

This configuration reuses the repository's pinned `prometheus-community/kube-prometheus-stack` chart (`93.1.0`) and dashboard sidecar. It adds an internal OpenTelemetry Collector for the traces already emitted by Online Boutique. The Collector follows the OpenTelemetry Demo pattern of receiving OTLP spans and using the `span_metrics` connector to derive RED metrics; it does not persist raw spans. Sensitive attribute keys are removed/redacted before conversion.

The Collector image is pinned by digest from the Google Online Boutique v0.10.7 experimental Helm chart. Google's source remains unchanged. An opt-in Kustomize Component is prepared for the seven upstream-instrumented Deployments (`frontend`, `checkoutservice`, `productcatalogservice`, `recommendationservice`, `currencyservice`, `emailservice`, and `paymentservice`) to send OTLP gRPC to `otel-collector.monitoring.svc.cluster.local:4317`. It stays disabled until the Collector is installed and healthy, so the regular application rollout never points to a missing service. Other services are not changed.

## Apply sequence

1. Create `monitoring` namespace: `kubectl apply -f monitoring/aws/namespace.yaml`.
2. Install the pinned official chart: `helm repo add prometheus-community https://prometheus-community.github.io/helm-charts`; then `helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 93.1.0 --namespace monitoring --values monitoring/values.yaml --values monitoring/aws/values.yaml --wait --timeout 15m`.
3. Apply collector, dashboards, ServiceMonitor, and alert rules: `kubectl apply -k monitoring`. The chart must be installed first because it provides the Prometheus Operator CRDs.
4. The frontend HPA is isolated in `kubectl apply -k kubernetes/aws/autoscaling`; apply it only after Metrics Server is Ready and an administrator has applied the updated namespace Role in `kubernetes/aws/online-boutique/deployer-rbac.yaml`. The existing CodeBuild identity cannot self-grant this permission. The seven-service OTel patch is an opt-in Kustomize Component at `kubernetes/aws/online-boutique/components/otel`; add `components: - components/otel` to the app Kustomization only after the Collector is healthy, then deploy through the normal CI/CodeBuild path and wait for those Deployment rollouts.
5. Check `kubectl get pods -n monitoring`, Prometheus target `otel-collector`, and Grafana dashboard `Online Boutique Application`. Verify the generated `online_boutique_traces_span_metrics_*` series in Prometheus before relying on dashboard panels.

Grafana, Prometheus, Alertmanager, and Collector are ClusterIP only. Use `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80` for Grafana. The chart values disable PVCs, so Prometheus/Grafana/Alertmanager state is ephemeral and lost if pods are recreated. The custom alert rules detect unavailable Deployments and repeated container restarts; Alertmanager has no external notification receiver until one is configured with an owner-approved destination and secret.

## Deployment boundary

The existing private CodeBuild deployer is bound only to the `online-boutique` namespace. The kube-prometheus-stack chart creates cluster-scoped CRDs, RBAC, and admission resources, so that deployer cannot install it. The chart and Collector were prepared but not installed. Installing the chart requires a reviewed cluster-admin/platform deployment path; do not broaden the app deployer role to cluster-admin.

The upstream Online Boutique cart service supports Redis or Google Spanner and has no MySQL client path. This project therefore does not add an unused MySQL StatefulSet or an EBS-backed database. The current Redis service remains the cart store.

## Implementation references and validation

The Collector pipeline is patterned on the [OpenTelemetry Demo Collector configuration](https://github.com/open-telemetry/opentelemetry-demo/blob/main/src/otel-collector/otelcol-config.yml) and its use of the [`span_metrics` connector](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/connector/spanmetricsconnector). The Google Online Boutique source remains the workload and was not edited.

The pinned chart rendered locally with Helm 4.3.1: the configured result contained no PersistentVolumeClaim or Ingress resources. `kubectl kustomize monitoring`, the HPA overlay, the application overlay, and the opt-in seven-service Collector component all rendered locally. Terraform formatting and validation passed with backend initialization disabled. No live Kubernetes apply or Terraform apply was run. The ServiceMonitor, alert rules, generated metrics, and dashboard query results remain to be verified after an approved installation.
